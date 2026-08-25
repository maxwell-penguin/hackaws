import json
import os
from datetime import datetime, timezone

from strands import tool

LOG_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "agent.log")


@tool
def log_event(message: str, type: str) -> str:
    """Append one structured entry to the agent log for a separate API route to tail.

    Call this once per reasoning step and once per notification you draft — never batch
    several into one message. Suggested `type` values: "reasoning" for your prioritization
    reasoning, "unclear_confirmation" for a low-friction confirm-ask tied to an item from
    get_unclear_items, "restock_alert" for a confirmed expiring/depleted item notification,
    and "error" for a failure you want surfaced.

    Args:
        message: Plain-language text of the reasoning step or notification.
        type: Short label categorizing this entry.

    Returns:
        Confirmation string.
    """
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": message,
        "type": type,
    }
    with open(LOG_PATH, "a") as f:
        f.write(json.dumps(entry) + "\n")
    return "logged"
