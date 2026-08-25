from datetime import date, timedelta

from strands import tool

from .strapi_client import strapi_get


@tool
def get_expiring_items(days: int) -> list[dict]:
    """Get active Items whose expiryDate is within the next `days` days (includes any already overdue).

    Args:
        days: Look-ahead window in days from today.

    Returns:
        List of Strapi Item records (name, expiryDate, quantity, category, ...).
    """
    cutoff = (date.today() + timedelta(days=days)).isoformat()
    return strapi_get(
        "/api/items",
        params={
            "filters[status][$eq]": "active",
            "filters[expiryDate][$lte]": cutoff,
            "pagination[pageSize]": 100,
        },
    )
