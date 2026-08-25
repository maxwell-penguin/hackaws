from strands import tool

from .strapi_client import strapi_get


@tool
def get_unclear_items() -> list[dict]:
    """Get Items whose visionConfidence is "unclear" — the last photo couldn't confirm their state.

    Returns:
        List of Strapi Item records.
    """
    return strapi_get(
        "/api/items",
        params={
            "filters[visionConfidence][$eq]": "unclear",
            "pagination[pageSize]": 100,
        },
    )
