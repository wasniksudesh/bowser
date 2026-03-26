"""
HackerNews Plugin - V1
Provides skills for fetching YC/Show HN launch products and describing them
"""

import time
from typing import Any, Dict
from datetime import datetime, timezone

from app.models.agent_schemas import Plugin, Skill, AuthRequirement, DataPacket


async def _fetch_launches(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    Fetch today's Show HN / Launch YC posts from the HackerNews API.
    Filters to only include today's posts to avoid repeats.
    """
    try:
        import httpx

        raw_max = params.get("max_items", 15)
        try:
            max_items = int(raw_max) if raw_max not in (None, "") else 15
        except (ValueError, TypeError):
            max_items = 15
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get("https://hacker-news.firebaseio.com/v0/showstories.json")
            resp.raise_for_status()
            story_ids = resp.json()[:50]

            items = []
            for story_id in story_ids:
                if len(items) >= max_items:
                    break
                try:
                    item_resp = await client.get(f"https://hacker-news.firebaseio.com/v0/item/{story_id}.json")
                    item_resp.raise_for_status()
                    item = item_resp.json()
                    if not item:
                        continue

                    item_time = datetime.fromtimestamp(item.get("time", 0), tz=timezone.utc)
                    item_date = item_time.strftime("%Y-%m-%d")
                    if item_date != today:
                        continue

                    title = item.get("title", "")
                    is_launch = any(kw in title.lower() for kw in ["show hn", "launch yc", "yc ", "launch hn"])
                    if not is_launch and "show" not in title.lower():
                        continue

                    url = item.get("url", f"https://news.ycombinator.com/item?id={story_id}")
                    items.append({
                        "title": title,
                        "url": url,
                        "hn_id": str(story_id),
                        "score": item.get("score", 0),
                        "by": item.get("by", ""),
                        "time": item_time.isoformat(),
                    })
                except Exception:
                    continue

            if not items:
                return DataPacket(
                    schema_def={"title": "string", "url": "string", "hn_id": "string", "score": "number", "by": "string"},
                    rows=[{"title": "No Show HN posts found for today", "url": "", "hn_id": "", "score": 0, "by": ""}]
                )

            return DataPacket(
                schema_def={"title": "string", "url": "string", "hn_id": "string", "score": "number", "by": "string"},
                rows=items
            )
    except Exception as e:
        return DataPacket.error(str(e), code="HN_FETCH_ERROR")


async def _describe_product(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    Given a product title and URL, generate a short description using LLM + web context.
    """
    try:
        from app.services.ai_agent import get_ai_agent

        title = params.get("title", "")
        url = params.get("url", "")

        ai_agent = await get_ai_agent()

        prompt = f"""Describe this product/project in 2-3 sentences. Be concise and factual.

Title: {title}
URL: {url}

Return a JSON object with:
- "description": 2-3 sentence description
- "image": a relevant image URL if you can find one, or empty string

Return ONLY valid JSON, no markdown."""

        result = await ai_agent.execute_task(
            prompt,
            context={"mode": "json_mode", "enable_web_search": True},
            use_tools=True
        )

        import json
        # extract_task returns a dict {"success": bool, "output": str}
        if isinstance(result, dict):
            result_text = result.get("output", "")
        else:
            result_text = str(result)
        result_text = result_text.strip()
        if result_text.startswith("```"):
            lines = result_text.split("\n")
            lines = [l for l in lines if not l.strip().startswith("```")]
            result_text = "\n".join(lines)

        try:
            parsed = json.loads(result_text)
            description = parsed.get("description", result_text[:200])
            image = parsed.get("image", "")
        except json.JSONDecodeError:
            description = result_text[:200]
            image = ""

        return DataPacket(
            schema_def={"title": "string", "url": "string", "description": "string", "image": "string"},
            rows=[{
                "title": title,
                "url": url,
                "description": description,
                "image": image
            }]
        )
    except Exception as e:
        return DataPacket.error(str(e), code="DESCRIBE_ERROR")


def get_hackernews_plugin() -> Plugin:
    """Returns the HackerNews plugin with all skills."""
    return Plugin(
        plugin_id="hackernews",
        name="HackerNews Plugin",
        version="1.0.0",
        description="Skills for fetching and analyzing HackerNews Show HN / YC Launch products",
        auth_requirements=[],
        skills=[
            Skill(
                skill_id="fetchLaunches",
                name="Fetch HN Launches",
                description="Fetch today's Show HN and YC launch products from HackerNews. Returns only today's posts to avoid duplicates.",
                input_schema={
                    "type": "object",
                    "properties": {
                        "max_items": {
                            "type": "integer",
                            "description": "Maximum number of items to fetch (default 15)",
                            "default": 15
                        }
                    }
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "title": {"type": "string"},
                        "url": {"type": "string"},
                        "hn_id": {"type": "string"},
                        "score": {"type": "number"},
                        "by": {"type": "string"}
                    }
                },
                output_type="table",
                execution_type="sdk",
                execute=_fetch_launches,
                domains=["hackernews", "news", "yc", "startups"],
                verbs=["fetch", "get", "list", "find"],
                nouns=["launches", "products", "startups", "show_hn"],
                output_types=["table", "list", "carousel"]
            ),
            Skill(
                skill_id="describeProduct",
                name="Describe Product",
                description="Generate a brief description and find an image for a product given its title and URL.",
                input_schema={
                    "type": "object",
                    "properties": {
                        "title": {"type": "string", "description": "Product title"},
                        "url": {"type": "string", "description": "Product URL"}
                    },
                    "required": ["title", "url"]
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "title": {"type": "string"},
                        "url": {"type": "string"},
                        "description": {"type": "string"},
                        "image": {"type": "string"}
                    }
                },
                output_type="text",
                execution_type="sdk",
                execute=_describe_product,
                domains=["hackernews", "web", "analysis"],
                verbs=["describe", "analyze", "summarize"],
                nouns=["product", "startup", "project", "description"],
                output_types=["text", "textBlock", "custom"]
            )
        ]
    )
