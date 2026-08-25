import os

import requests
from strands import tool

from .strapi_client import strapi_get


@tool
def suggest_recipe_for_item(item_name: str) -> dict:
    """Get quick recipe suggestions built around one aging/spoiled produce item, using
    what's already in the active inventory.

    Call this once per item from get_aging_produce, before drafting its notification, so
    the notification can name a specific recipe instead of a bare freshness warning.

    Args:
        item_name: Name of the aging/spoiled item to build a recipe suggestion around.

    Returns:
        {"recipes": [{"name", "usesExpiring", "missingIngredients"}, ...]}. Empty
        "recipes" if the recipe service couldn't be reached — fall back to a plain
        freshness warning for that item in that case.
    """
    base_url = os.environ.get("NEXT_APP_BASE_URL", "http://localhost:3000")
    active_inventory = [
        item["name"]
        for item in strapi_get(
            "/api/items",
            params={"filters[status][$eq]": "active", "pagination[pageSize]": 100},
        )
    ]

    try:
        response = requests.post(
            f"{base_url}/api/recipe-suggestions",
            json={"expiringItems": [item_name], "activeInventory": active_inventory},
            timeout=30,
        )
        response.raise_for_status()
        return response.json()
    except requests.RequestException as exc:
        return {"recipes": [], "error": str(exc)}
