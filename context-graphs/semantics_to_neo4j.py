#!/usr/bin/env python3
"""Convert semantics.json (edge-first, embedded nodes) to neo4j-graph.json (deduplicated nodes + relationships).

Usage:
    python3 semantics_to_neo4j.py                          # no embeddings
    python3 semantics_to_neo4j.py --embed                  # embed with OpenAI (needs OPENAI_API_KEY)
    python3 semantics_to_neo4j.py --embed --model local    # embed with sentence-transformers (offline)
    python3 semantics_to_neo4j.py input.json output.json   # custom paths

Service grouping:
    If service.json exists in the repo root, a Service node is created and every
    knowledge node receives a BELONGS_TO edge pointing to it.  Each node also gets
    a flat `service` property for queries that don't want to traverse the edge.
"""

import argparse
import json
import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_INPUT = REPO_ROOT / "semantics.json"
DEFAULT_OUTPUT = REPO_ROOT / "context-graphs" / "neo4j-graph.json"
SERVICE_MANIFEST = REPO_ROOT / "service.json"

NODE_FIELDS_BY_TYPE = {
    "Decision": {"label", "scope", "trigger", "rationale", "alternatives", "confidence", "uncertainty", "created_at"},
    "Constraint": {"label", "scope", "description", "source", "hard", "symptom", "created_at"},
    "Insight": {"label", "scope", "body", "failure_without", "created_at"},
    "Signal": {"label", "scope", "observation", "appears_to_mean", "actually_means", "conditions", "evidence", "created_at"},
}

NODE_TEXT_FIELDS = {
    "Decision": ["label", "trigger", "rationale"],
    "Constraint": ["label", "description", "symptom"],
    "Insight": ["label", "body", "failure_without"],
    "Signal": ["label", "observation", "actually_means"],
}


def node_text(raw: dict) -> str:
    """Compose the text to embed for a node — type-aware, structured."""
    node_type = raw["type"]
    fields = NODE_TEXT_FIELDS.get(node_type, ["label"])
    parts = [f"[{node_type}]"]
    for f in fields:
        val = raw.get(f)
        if val:
            parts.append(val)
    if node_type == "Decision" and raw.get("alternatives"):
        for alt in raw["alternatives"]:
            if isinstance(alt, dict):
                parts.append(f"Rejected: {alt.get('option', '')} — {alt.get('rejected_because', '')}")
    return " | ".join(parts)


def relationship_text(entry: dict) -> str:
    """Compose the text to embed for a relationship — edge_context + endpoint labels."""
    from_label = entry["from"].get("label", "")
    to_label = entry["to"].get("label", "")
    edge_ctx = entry.get("properties", {}).get("edge_context", "")
    return f"{from_label} —[{entry['rel']}]→ {to_label} | {edge_ctx}"


# --- Embedding backends ---

def embed_openai(texts: list[str], model: str = "text-embedding-3-small") -> list[list[float]]:
    from openai import OpenAI
    client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])
    resp = client.embeddings.create(input=texts, model=model)
    return [item.embedding for item in resp.data]


def embed_local(texts: list[str], model_name: str = "all-MiniLM-L6-v2") -> list[list[float]]:
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer(model_name)
    return model.encode(texts, show_progress_bar=True).tolist()


EMBED_BACKENDS = {
    "openai": embed_openai,
    "local": embed_local,
}


# --- Service manifest ---

SERVICE_NODE_FIELDS = {"label", "repo", "description", "tech_stack", "domain", "platform", "created_at"}


def load_service(path: Path) -> dict | None:
    """Return parsed service.json, or None if the file does not exist."""
    if not path.exists():
        return None
    return json.loads(path.read_text())


def build_service_node(manifest: dict) -> dict:
    props = {k: v for k, v in manifest.items() if k in SERVICE_NODE_FIELDS and v is not None}
    if isinstance(props.get("tech_stack"), list):
        props["tech_stack"] = json.dumps(props["tech_stack"])
    return {"id": manifest["id"], "labels": ["Service"], "properties": props}


def build_belongs_to_rels(node_ids: list[str], service_id: str, created_at: str) -> list[dict]:
    return [
        {
            "id": f"rel-{nid.replace(':', '-')}-BELONGS_TO-{service_id.replace(':', '-')}",
            "type": "BELONGS_TO",
            "startNodeId": nid,
            "endNodeId": service_id,
            "properties": {"created_at": created_at, "inferred": True},
        }
        for nid in node_ids
    ]


# --- Core conversion ---

def extract_node(raw: dict) -> dict:
    node_type = raw["type"]
    allowed = NODE_FIELDS_BY_TYPE.get(node_type, set())
    props = {k: v for k, v in raw.items() if k in allowed and v is not None}

    if "alternatives" in props and isinstance(props["alternatives"], list):
        props["alternatives"] = json.dumps(props["alternatives"])

    return {
        "id": raw["id"],
        "labels": [node_type],
        "properties": props,
    }


def extract_relationship(entry: dict) -> dict:
    props = dict(entry.get("properties", {}))
    props["created_at"] = entry.get("created_at", "")
    return {
        "id": entry["id"],
        "type": entry["rel"],
        "startNodeId": entry["from"]["id"],
        "endNodeId": entry["to"]["id"],
        "properties": props,
    }


def convert(
    input_path: Path,
    output_path: Path,
    embed_backend: str | None = None,
    service_path: Path = SERVICE_MANIFEST,
) -> dict:
    entries = json.loads(input_path.read_text())

    nodes: dict[str, dict] = {}
    node_texts: dict[str, str] = {}
    relationships: list[dict] = []
    rel_texts: list[str] = []

    for entry in entries:
        for side in ("from", "to"):
            raw = entry[side]
            nid = raw["id"]
            nodes[nid] = extract_node(raw)
            node_texts[nid] = node_text(raw)

        relationships.append(extract_relationship(entry))
        rel_texts.append(relationship_text(entry))

    if embed_backend:
        embed_fn = EMBED_BACKENDS[embed_backend]

        all_texts = list(node_texts.values()) + rel_texts
        print(f"embedding {len(all_texts)} texts with {embed_backend}...")
        all_embeddings = embed_fn(all_texts)

        node_embeddings = all_embeddings[:len(node_texts)]
        rel_embeddings = all_embeddings[len(node_texts):]

        for (nid, node), emb in zip(nodes.items(), node_embeddings):
            node["properties"]["embedding"] = emb

        for rel, emb in zip(relationships, rel_embeddings):
            rel["properties"]["embedding"] = emb

        dim = len(all_embeddings[0])
        print(f"embedded {len(all_embeddings)} items, dimension={dim}")

    # --- Service grouping ---
    service_manifest = load_service(service_path)
    if service_manifest:
        service_id = service_manifest["id"]
        service_node = build_service_node(service_manifest)
        nodes[service_id] = service_node

        knowledge_node_ids = [nid for nid in nodes if nid != service_id]
        for nid in knowledge_node_ids:
            nodes[nid]["properties"]["service"] = service_id

        relationships.extend(
            build_belongs_to_rels(
                knowledge_node_ids,
                service_id,
                service_manifest.get("created_at", ""),
            )
        )
        print(f"service: {service_id} ({len(knowledge_node_ids)} BELONGS_TO edges added)")
    else:
        print("no service.json found — skipping service grouping")

    graph = {
        "nodes": list(nodes.values()),
        "relationships": relationships,
    }

    if embed_backend:
        graph["meta"] = {
            "embedding_model": "text-embedding-3-small" if embed_backend == "openai" else "all-MiniLM-L6-v2",
            "embedding_dim": len(all_embeddings[0]),
        }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(graph, indent=2) + "\n")

    print(f"nodes: {len(graph['nodes'])}, relationships: {len(graph['relationships'])}")
    print(f"written to {output_path}")
    return graph


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert semantics.json to neo4j-graph.json")
    parser.add_argument("input", nargs="?", default=str(DEFAULT_INPUT))
    parser.add_argument("output", nargs="?", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--embed", action="store_true", help="Generate vector embeddings")
    parser.add_argument("--model", choices=["openai", "local"], default="openai",
                        help="Embedding backend: openai (needs OPENAI_API_KEY) or local (sentence-transformers)")
    args = parser.parse_args()

    convert(Path(args.input), Path(args.output), embed_backend=args.model if args.embed else None)
