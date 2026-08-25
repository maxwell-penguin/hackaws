import os
import sys
import time
import traceback

from dotenv import load_dotenv
from strands import Agent
from strands.models.anthropic import AnthropicModel

from tools import (
    get_aging_produce,
    get_depleted_staples,
    get_expiring_items,
    get_unclear_items,
    log_event,
    suggest_recipe_for_item,
)

load_dotenv()

SYSTEM_PROMPT = """You are a fridge-monitoring agent. Each cycle you check current
fridge state in Strapi and decide what, if anything, is worth telling the user.

Every cycle, in this order:

1. Call get_expiring_items, get_depleted_staples, get_unclear_items, and
   get_aging_produce to gather the full current state. Always call all four — don't
   skip one because last cycle was empty.

2. Reason about what to prioritize when multiple signals fire at once. Use judgment
   rather than a rigid rule — e.g. an item expiring today is usually more urgent than a
   depleted staple, which is usually more urgent than aging/spoiled produce, which is
   usually more urgent than a merely unclear item, but let the specifics of what you
   found change that ordering when it makes sense. Call log_event once with
   type="reasoning" explaining in plain language what you're prioritizing this cycle and
   why, before drafting any notifications.

3. For every item from get_aging_produce, call suggest_recipe_for_item(item_name) to get
   a recipe built around that item and the current active inventory. Call log_event with
   type="reasoning" briefly noting what you decided for that item — which recipe you're
   going with, or that no usable recipe came back so you're falling back to a plain
   warning. Then call log_event with type="freshness_alert": if a recipe came back, name
   it in the message instead of a bare freshness warning — e.g. "Your spinach is
   starting to wilt. Want to try Garlic Butter Pasta tonight?" — otherwise fall back to a
   plain warning naming the item and its state.

4. For every item from get_unclear_items, call log_event with type="unclear_confirmation"
   and a short, low-friction message asking the user to physically check — e.g. "I
   couldn't clearly tell if the eggs are still there — can you check?". Word these as a
   request for a human to confirm, never as a confirmed alert — the vision system was not
   sure, so don't imply certainty.

5. For every confirmed item from get_expiring_items or get_depleted_staples, call
   log_event with type="restock_alert" and a short plain-text restock/notification
   message a person could act on directly.

6. If all four tools come back empty, still call log_event once with type="reasoning"
   saying there's nothing to report this cycle — don't stay silent.

Keep every message short, plain language, and specific to the item(s) involved.
"""


def build_agent() -> Agent:
    model = AnthropicModel(
        client_args={"api_key": os.environ["ANTHROPIC_API_KEY"]},
        model_id="claude-sonnet-4-6",
        max_tokens=2048,
    )
    return Agent(
        model=model,
        tools=[
            get_expiring_items,
            get_depleted_staples,
            get_unclear_items,
            get_aging_produce,
            suggest_recipe_for_item,
            log_event,
        ],
        system_prompt=SYSTEM_PROMPT,
    )


def main() -> None:
    if not os.environ.get("STRAPI_URL"):
        sys.exit("STRAPI_URL is not set")
    if not os.environ.get("ANTHROPIC_API_KEY"):
        sys.exit("ANTHROPIC_API_KEY is not set")

    interval = float(os.environ.get("AGENT_LOOP_INTERVAL_SECONDS", "20"))

    print(f"agent-service: looping every {interval}s, logging to agent.log — Ctrl+C to stop")
    try:
        while True:
            # Fresh agent per cycle: state lives in Strapi, not conversation history, so
            # each cycle should re-observe from scratch rather than accumulate context.
            agent = build_agent()
            try:
                agent("Check the current fridge state and act on it.")
            except Exception as exc:
                log_event(f"Cycle failed: {exc}", "error")
                traceback.print_exc()
            time.sleep(interval)
    except KeyboardInterrupt:
        print("\nagent-service: stopped")


if __name__ == "__main__":
    main()
