#!/usr/bin/env python3
"""Ingest neo4j-graph.json into a local Neo4j 5 instance.

Usage:
    python3 ingest.py                         # default path, bolt://localhost:7687
    python3 ingest.py --input path/to/graph.json
    python3 ingest.py --uri bolt://host:7687 --user neo4j --password secret
    python3 ingest.py --wipe                  # clear all nodes/rels first
"""

import argparse
import json
import sys
from pathlib import Path

from neo4j import GraphDatabase

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_INPUT = REPO_ROOT / "context-graphs" / "neo4j-graph.json"

BATCH_SIZE = 500


def wipe(session) -> None:
    session.run("MATCH (n) DETACH DELETE n")
    print("wiped existing graph")


def create_constraints(session, labels: set[str]) -> None:
    for label in labels:
        session.run(
            f"CREATE CONSTRAINT {label.lower()}_id IF NOT EXISTS "
            f"FOR (n:{label}) REQUIRE n.id IS UNIQUE"
        )
    print(f"constraints ready for: {', '.join(sorted(labels))}")


def create_vector_indexes(session, labels: set[str], rel_types: set[str], dim: int) -> None:
    for label in labels:
        session.run(
            f"CREATE VECTOR INDEX {label.lower()}_embedding IF NOT EXISTS "
            f"FOR (n:{label}) ON (n.embedding) "
            f"OPTIONS {{indexConfig: {{`vector.dimensions`: {dim}, `vector.similarity_function`: 'cosine'}}}}"
        )
    for rel_type in rel_types:
        session.run(
            f"CREATE VECTOR INDEX {rel_type.lower()}_embedding IF NOT EXISTS "
            f"FOR ()-[r:{rel_type}]-() ON (r.embedding) "
            f"OPTIONS {{indexConfig: {{`vector.dimensions`: {dim}, `vector.similarity_function`: 'cosine'}}}}"
        )
    print(f"vector indexes ready (dim={dim})")


def ingest_nodes(session, nodes: list[dict]) -> int:
    total = 0
    for i in range(0, len(nodes), BATCH_SIZE):
        batch = nodes[i : i + BATCH_SIZE]
        # Each node has exactly one label; build per-label batches to use dynamic labels
        by_label: dict[str, list[dict]] = {}
        for node in batch:
            label = node["labels"][0]
            by_label.setdefault(label, []).append(
                {"id": node["id"], **node["properties"]}
            )

        for label, props_batch in by_label.items():
            session.run(
                f"UNWIND $batch AS props "
                f"MERGE (n:{label} {{id: props.id}}) "
                f"SET n += props",
                batch=props_batch,
            )
        total += len(batch)
        print(f"  nodes {total}/{len(nodes)}", end="\r")

    print(f"  nodes {len(nodes)}/{len(nodes)} done")
    return total


def ingest_relationships(session, rels: list[dict]) -> int:
    total = 0
    # Group by type so we can use dynamic rel types
    by_type: dict[str, list[dict]] = {}
    for rel in rels:
        by_type.setdefault(rel["type"], []).append(rel)

    for rel_type, typed_rels in by_type.items():
        for i in range(0, len(typed_rels), BATCH_SIZE):
            batch = [
                {
                    "id": r["id"],
                    "start": r["startNodeId"],
                    "end": r["endNodeId"],
                    **r["properties"],
                }
                for r in typed_rels[i : i + BATCH_SIZE]
            ]
            session.run(
                f"UNWIND $batch AS props "
                f"MATCH (a {{id: props.start}}), (b {{id: props.end}}) "
                f"MERGE (a)-[r:{rel_type} {{id: props.id}}]->(b) "
                f"SET r += props",
                batch=batch,
            )
            total += len(batch)
            print(f"  rels {total}/{len(rels)}", end="\r")

    print(f"  rels {len(rels)}/{len(rels)} done")
    return total


def ingest(graph_path: Path, uri: str, user: str, password: str, do_wipe: bool) -> None:
    print(f"loading {graph_path}...")
    data = json.loads(graph_path.read_text())
    nodes = data["nodes"]
    rels = data["relationships"]
    meta = data.get("meta", {})
    embedding_dim = meta.get("embedding_dim", 1536)

    labels = {node["labels"][0] for node in nodes}
    rel_types = {r["type"] for r in rels}
    print(f"nodes={len(nodes)}, rels={len(rels)}, labels={sorted(labels)}, embedding_dim={embedding_dim}")

    driver = GraphDatabase.driver(uri, auth=(user, password))
    driver.verify_connectivity()
    print(f"connected to {uri}")

    with driver.session() as session:
        if do_wipe:
            wipe(session)

        create_constraints(session, labels)

        print("ingesting nodes...")
        ingest_nodes(session, nodes)

        print("ingesting relationships...")
        ingest_relationships(session, rels)

        if embedding_dim:
            create_vector_indexes(session, labels, rel_types, embedding_dim)

    driver.close()
    print("done")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ingest neo4j-graph.json into Neo4j 5")
    parser.add_argument("--input", default=str(DEFAULT_INPUT), help="Path to neo4j-graph.json")
    parser.add_argument("--uri", default="bolt://localhost:7687")
    parser.add_argument("--user", default="neo4j")
    parser.add_argument("--password", default="password")
    parser.add_argument("--wipe", action="store_true", help="Delete all existing nodes and rels first")
    args = parser.parse_args()

    try:
        ingest(Path(args.input), args.uri, args.user, args.password, args.wipe)
    except KeyboardInterrupt:
        sys.exit(1)
