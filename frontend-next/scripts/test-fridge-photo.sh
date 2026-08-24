#!/usr/bin/env bash
# Simulates the ESP32 POST to /api/fridge-photos before hardware arrives.
# Usage: ./scripts/test-fridge-photo.sh <image-path> [zoneId] [base-url]
set -euo pipefail

IMAGE="${1:?usage: test-fridge-photo.sh <image-path> [zoneId] [base-url]}"
ZONE_ID="${2:-z1}"
BASE_URL="${3:-http://localhost:3000}"

curl -sS -X POST "$BASE_URL/api/fridge-photos" \
  -F "image=@${IMAGE}" \
  -F "zoneId=${ZONE_ID}" \
  | python3 -m json.tool
