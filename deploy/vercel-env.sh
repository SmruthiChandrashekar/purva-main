#!/usr/bin/env bash
# Prints the website's current settings on Vercel (the VITE_* variables used by the
# Production build) as `gh variable set` lines for the repo owner. The website's Azure
# deploy (.github/workflows/azure-frontend.yml) reads them from GitHub Actions variables.
#
# These values are built into the public website anyway (the Supabase URL and its
# public "anon" key, the backend address, two switches), so they are not secrets and
# are safe to print and to store as plain Actions variables.
#
#   read -rs VERCEL_TOKEN && export VERCEL_TOKEN     # Vercel → Account Settings → Tokens
#   bash deploy/vercel-env.sh
#
# VERCEL_PROJECT: project name (default purva-main). VERCEL_TEAM_ID: only if the project
# belongs to a Vercel team. Needs curl and jq (both in Cloud Shell and on most Macs).
set -euo pipefail

VERCEL_PROJECT="${VERCEL_PROJECT:-purva-main}"
VERCEL_API_BASE="${VERCEL_API_BASE:-https://api.vercel.com}"
REPO="${GITHUB_REPO:-SmruthiChandrashekar/purva-main}"
REQUIRED="VITE_SUPABASE_URL VITE_SUPABASE_ANON_KEY VITE_API_BASE_URL"
KNOWN="VITE_SUPABASE_URL VITE_SUPABASE_ANON_KEY VITE_API_BASE_URL VITE_REQUIRE_PHONE_OTP VITE_INTERNAL_EMAIL_DOMAIN"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -n "${VERCEL_TOKEN:-}" ] || die "VERCEL_TOKEN is not set. Run: read -rs VERCEL_TOKEN && export VERCEL_TOKEN"
command -v jq   >/dev/null 2>&1 || die "jq not found"
command -v curl >/dev/null 2>&1 || die "curl not found"

TMP_DIR="$(mktemp -d)"; trap 'rm -rf "$TMP_DIR"' EXIT
body="$TMP_DIR/body"

query="decrypt=true"
[ -n "${VERCEL_TEAM_ID:-}" ] && query="$query&teamId=$(jq -rn --arg t "$VERCEL_TEAM_ID" '$t|@uri')"
project_uri="$(jq -rn --arg p "$VERCEL_PROJECT" '$p|@uri')"

echo "Reading settings of Vercel project '$VERCEL_PROJECT'..." >&2
code="$(curl -sS -o "$body" -w '%{http_code}' -H "Authorization: Bearer $VERCEL_TOKEN" \
  "$VERCEL_API_BASE/v10/projects/$project_uri/env?$query")" || die "could not reach $VERCEL_API_BASE"
if ! jq -e 'type == "object" and (.envs | type == "array")' "$body" >/dev/null 2>&1; then
  msg="$(jq -r '.error.message // .message // tostring' "$body" 2>/dev/null || head -c 500 "$body")"
  die "Vercel answered HTTP $code: ${msg:-<empty reply>}"
fi

# VITE_* variables that apply to Production (target may be a list or a single string)
jq '[.envs[]
     | select(.key | startswith("VITE_"))
     | select((.target | if type == "array" then . else [.] end) | index("production"))
     | {key, value: (.value // ""), readable: ((.decrypted == true) or (.type == "plain"))}]
    | group_by(.key) | map(.[-1])' "$body" > "$TMP_DIR/vite.json"

echo >&2
echo "Send these lines to the repo owner (values are public, not secrets):"
echo
jq -r --arg repo "$REPO" '.[] | select(.readable and .value != "")
  | "gh variable set \(.key) --repo \($repo) --body \(.value | @sh)"' "$TMP_DIR/vite.json"
echo

missing=""
for k in $REQUIRED; do
  jq -e --arg k "$k" 'any(.[]; .key == $k and .readable and .value != "")' "$TMP_DIR/vite.json" >/dev/null \
    || missing="$missing $k"
done
unreadable="$(jq -r '[.[] | select(.readable | not) | .key] | join(" ")' "$TMP_DIR/vite.json")"
[ -n "$unreadable" ] && echo "Marked 'sensitive' on Vercel, so they can't be read back; copy by hand: $unreadable" >&2
[ -n "$missing" ] && echo "MISSING (the website needs these):$missing" >&2
others="$(jq -r --arg known "$KNOWN" '[.[] | .key | select(. as $k | ($known | split(" ") | index($k)) | not)] | join(" ")' "$TMP_DIR/vite.json")"
[ -n "$others" ] && echo "Not used by the website code, skip unless you know better: $others" >&2
echo "Check VITE_API_BASE_URL is the Azure backend address (no trailing slash)." >&2
[ -z "$missing" ]
