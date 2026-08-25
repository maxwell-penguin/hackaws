from strands import tool

from .strapi_client import strapi_get


@tool
def get_depleted_staples() -> list[dict]:
    """Get staple Items (isStaple=true) that are currently marked depleted.

    Returns:
        List of Strapi Item records.
    """
    return strapi_get(
        "/api/items",
        params={
            "filters[isStaple][$eq]": "true",
            "filters[status][$eq]": "depleted",
            "pagination[pageSize]": 100,
        },
    )
