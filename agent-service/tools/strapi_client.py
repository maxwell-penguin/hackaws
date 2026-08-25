import os

import requests


def strapi_get(path: str, params: dict) -> list[dict]:
    """GET a Strapi content-api endpoint and return its `data` list."""
    strapi_url = os.environ["STRAPI_URL"]
    headers = {}
    token = os.environ.get("STRAPI_API_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"

    response = requests.get(f"{strapi_url}{path}", params=params, headers=headers, timeout=10)
    response.raise_for_status()
    return response.json()["data"]
