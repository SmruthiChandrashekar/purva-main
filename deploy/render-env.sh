#!/usr/bin/env bash
# Writes .env.azure from the backend's current settings on Render, so nobody has to
# type them. Run from the repo root in Azure Cloud Shell:
#
#   read -rs RENDER_API_KEY && export RENDER_API_KEY     # paste the key, press Enter
#   bash deploy/render-env.sh
#
# RENDER_API_KEY: Render → Account settings → API keys (Bearer key with read access).
# RENDER_SERVICE: the Render service name (default: the name in render.yaml).
# Values are never printed. The file is written with mode 600 and is git-ignored.
#
# Left out on purpose:
#   PORT, PYTHON_VERSION, RENDER_*      Render-only; Azure sets its own PORT
#   SUPER_ADMIN_*, SEED_ADMIN_PASSWORD  one-time admin setup, not used by the running app
#   empty values, multi-line values     (Container Apps secrets can't be empty; add
#                                        multi-line ones by hand if there are any)
# Variables from Render "environment groups" linked to the service are not returned by
# Render's API; add those by hand.
set -euo pipefail

RENDER_SERVICE="${RENDER_SERVICE:-puravankara-grm-backend}"
RENDER_API_BASE="${RENDER_API_BASE:-https://api.render.com/v1}"
OUT="${ENV_FILE:-.env.azure}"
EXCLUDE_KEYS="${EXCLUDE_KEYS:-PORT PYTHON_VERSION SUPER_ADMIN_EMAIL SUPER_ADMIN_PASSWORD SEED_ADMIN_PASSWORD}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -n "${RENDER_API_KEY:-}" ] || die "RENDER_API_KEY is not set. Run: read -rs RENDER_API_KEY && export RENDER_API_KEY"
command -v jq   >/dev/null 2>&1 || die "jq not found"
command -v curl >/dev/null 2>&1 || die "curl not found"

umask 077
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# GET a Render API path; prints the body on success. On anything that is not a JSON
# array, prints Render's own message (never the key) and stops.
render_get() {
  local path="$1" body="$TMP_DIR/body" code
  code="$(curl -sS -o "$body" -w '%{http_code}' \
    -H "Authorization: Bearer $RENDER_API_KEY" -H "Accept: application/json" \
    "$RENDER_API_BASE$path")" || die "could not reach $RENDER_API_BASE"
  if ! jq -e 'type == "array"' "$body" >/dev/null 2>&1; then
    local msg
    msg="$(jq -r 'if type == "object" then (.message // .error // tostring) else tostring end' "$body" 2>/dev/null \
           || head -c 500 "$body")"
    die "Render answered HTTP $code: ${msg:-<empty reply>}"
  fi
  cat "$body"
}

# 1. Find the service ID
echo "Looking up Render service '$RENDER_SERVICE'..."
services="$(render_get "/services?name=$(jq -rn --arg s "$RENDER_SERVICE" '$s|@uri')&limit=100")"
SERVICE_ID="$(jq -r --arg n "$RENDER_SERVICE" '[.[] | .service | select(.name == $n)] | .[0].id // empty' <<< "$services")"
if [ -z "$SERVICE_ID" ]; then
  all="$(render_get "/services?limit=100")"
  echo "Services this key can see:" >&2
  jq -r '.[] | .service | "  \(.name)  (\(.type))"' <<< "$all" >&2
  die "no service named '$RENDER_SERVICE'. Rerun with RENDER_SERVICE=<name>."
fi
echo "Found $SERVICE_ID"

# 2. Read all env vars, following the cursor until an empty page
vars="$TMP_DIR/vars.json"
echo '[]' > "$vars"
cursor=""
for _ in $(seq 1 50); do
  path="/services/$SERVICE_ID/env-vars?limit=100"
  [ -n "$cursor" ] && path="$path&cursor=$(jq -rn --arg c "$cursor" '$c|@uri')"
  page="$(render_get "$path")"
  [ "$(jq 'length' <<< "$page")" -eq 0 ] && break
  jq -s '.[0] + [.[1][] | .envVar]' "$vars" - <<< "$page" > "$vars.new" && mv "$vars.new" "$vars"
  next="$(jq -r '.[-1].cursor // empty' <<< "$page")"
  [ -z "$next" ] || [ "$next" = "$cursor" ] && break
  cursor="$next"
done

# 3. Filter and write KEY="value" lines (azure.sh strips one pair of surrounding quotes,
#    so every value comes through exactly, including spaces and quotes inside it)
excl_json="$(printf '%s\n' $EXCLUDE_KEYS | jq -R . | jq -s .)"
filter='
  map(select(.key != null))
  | group_by(.key) | map(.[-1])
  | map(. + {why:
      (if (.key | IN($excl[])) or (.key | startswith("RENDER")) then "Render-only / one-time"
       elif (.value // "") == "" then "empty"
       elif (.value | test("[\r\n]")) then "multi-line"
       else null end)})'
jq --argjson excl "$excl_json" "$filter" "$vars" > "$TMP_DIR/sorted.json"

if [ -e "$OUT" ]; then
  cp -p "$OUT" "$OUT.bak"
  echo "Existing $OUT saved as $OUT.bak"
fi
{
  echo "# Written by deploy/render-env.sh from Render service $RENDER_SERVICE ($SERVICE_ID) on $(date -u +%Y-%m-%dT%H:%MZ)."
  echo "# Every value becomes a Container Apps secret. Edit freely, then: bash deploy/azure.sh"
  jq -r '.[] | select(.why == null) | "\(.key)=\"\(.value)\""' "$TMP_DIR/sorted.json"
} > "$TMP_DIR/out"
mv "$TMP_DIR/out" "$OUT"
chmod 600 "$OUT"

kept="$(jq -r '[.[] | select(.why == null) | .key] | join(" ")' "$TMP_DIR/sorted.json")"
skipped="$(jq -r '[.[] | select(.why != null) | "\(.key) (\(.why))"] | join(", ")' "$TMP_DIR/sorted.json")"
echo
echo "Wrote $OUT (mode 600) with $(jq '[.[] | select(.why == null)] | length' "$TMP_DIR/sorted.json") settings:"
echo "  $kept"
[ -n "$skipped" ] && echo "Left out: $skipped"
echo
echo "Check it (values are visible): nano $OUT"
echo "Next: bash deploy/azure.sh"
