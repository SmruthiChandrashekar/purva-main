#!/usr/bin/env bash
# Creates the website's home on Azure: a Static Web App (Free plan) in this project's
# resource group. Run from the repo root in Azure Cloud Shell, after deploy/azure.sh.
# Safe to rerun.
#
#   bash deploy/azure-frontend.sh             # create it (if missing) and print next steps
#   DRY_RUN=1 bash deploy/azure-frontend.sh   # print the commands, change nothing
#
# It never builds or uploads the website: GitHub Actions does that
# (.github/workflows/azure-frontend.yml), signing in with the same deploy identity as the
# backend. That identity already has Contributor on this group, which covers fetching the
# Static Web App's upload token at deploy time, so no token is stored anywhere.
#
# If .env.azure exists, the new address is added to FRONTEND_URL there (after the current
# one, so email links keep pointing at the old site until you switch). Rerun
# deploy/azure.sh afterwards so the backend accepts requests from the new address (CORS).
set -euo pipefail

APP_NAME="${APP_NAME:-purva-main}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-82aaf9d4-d161-4dab-8ecf-dff34de35353}"
RESOURCE_GROUP="${RESOURCE_GROUP:-$APP_NAME}"
SWA_NAME="${SWA_NAME:-$APP_NAME-web}"
# Static Web Apps can only be created in a few regions (westus2, centralus, eastus2,
# westeurope, eastasia). That is only where its settings live: the site itself is served
# from Microsoft's global edge, close to the visitor. East Asia is the nearest to India.
SWA_LOCATION="${SWA_LOCATION:-eastasia}"
ENV_FILE="${ENV_FILE:-.env.azure}"
REPO="${GITHUB_REPO:-SmruthiChandrashekar/purva-main}"

DRY_RUN="${DRY_RUN:-0}"
[ "$DRY_RUN" = "0" ] || DRY_RUN=1

say()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
run()  { printf '+'; printf ' %q' "$@"; printf '\n'; [ "$DRY_RUN" = "1" ] && return 0; "$@"; }
exists() { "$@" >/dev/null 2>&1; }

[ -f Dockerfile ] && [ -d frontend ] || die "run this from the repo root"
command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found. Use Azure Cloud Shell."
[ "$DRY_RUN" = "1" ] && echo "DRY RUN: nothing will be changed."

say "Subscription $SUBSCRIPTION_ID"
if [ "$(az account show --query id -o tsv 2>/dev/null || true)" != "$SUBSCRIPTION_ID" ]; then
  az account set --subscription "$SUBSCRIPTION_ID" 2>/dev/null \
    || [ "$DRY_RUN" = "1" ] || die "cannot select subscription $SUBSCRIPTION_ID (az login?)"
fi

say "Resource provider Microsoft.Web"
state="$(az provider show --namespace Microsoft.Web --query registrationState -o tsv 2>/dev/null || echo unknown)"
if [ "$state" = "Registered" ]; then
  echo "registered"
else
  run az provider register --namespace Microsoft.Web --wait
fi

say "Resource group $RESOURCE_GROUP"
if [ "$(az group exists -n "$RESOURCE_GROUP" 2>/dev/null || echo false)" = "true" ]; then
  echo "exists"
elif [ "$DRY_RUN" = "1" ]; then
  echo "(not found; it must exist: run deploy/azure.sh first)"
else
  die "resource group $RESOURCE_GROUP not found. Run deploy/azure.sh first."
fi

say "Static Web App $SWA_NAME (Free)"
if exists az staticwebapp show -n "$SWA_NAME" -g "$RESOURCE_GROUP"; then
  echo "exists"
else
  # No --source: the site is uploaded by our own workflow, not linked to GitHub by Azure
  if ! run az staticwebapp create -n "$SWA_NAME" -g "$RESOURCE_GROUP" -l "$SWA_LOCATION" \
       --sku Free --only-show-errors -o none; then
    # Azure sometimes reports an error although the resource was created
    exists az staticwebapp show -n "$SWA_NAME" -g "$RESOURCE_GROUP" \
      || die "creating the Static Web App failed. Rerun this script in a minute."
    warn "create reported an error, but the Static Web App exists; continuing"
  fi
fi

HOST="$(az staticwebapp show -n "$SWA_NAME" -g "$RESOURCE_GROUP" --query defaultHostname -o tsv 2>/dev/null || true)"
if [ -z "$HOST" ]; then
  [ "$DRY_RUN" = "1" ] || die "could not read the Static Web App's address"
  HOST="<name>.azurestaticapps.net"
fi
NEW_ORIGIN="https://$HOST"

# Add the new address to FRONTEND_URL in .env.azure (keeps the current first entry)
say "Backend setting FRONTEND_URL in $ENV_FILE"
if [ ! -f "$ENV_FILE" ]; then
  echo "$ENV_FILE not here. Add $NEW_ORIGIN to FRONTEND_URL yourself (see deploy/AZURE-WEBSITE.md)."
else
  line="$(grep -E '^[[:space:]]*(export[[:space:]]+)?FRONTEND_URL=' "$ENV_FILE" | tail -1 || true)"
  current="$(printf '%s' "${line#*=}" | tr -d '\r' | sed -E 's/^[[:space:]]*["'\'']?//; s/["'\'']?[[:space:]]*$//')"
  if [[ ",$current," == *",$NEW_ORIGIN,"* ]]; then
    echo "already includes $NEW_ORIGIN"
  else
    new_value="${current:+$current,}$NEW_ORIGIN"
    if [ "$DRY_RUN" = "1" ]; then
      echo "(would set FRONTEND_URL=\"$new_value\")"
    else
      tmp="$(mktemp)"
      grep -vE '^[[:space:]]*(export[[:space:]]+)?FRONTEND_URL=' "$ENV_FILE" > "$tmp" || true
      printf 'FRONTEND_URL="%s"\n' "$new_value" >> "$tmp"
      cat "$tmp" > "$ENV_FILE"   # keeps the file's mode (600)
      rm -f "$tmp"
      echo "FRONTEND_URL is now: $new_value"
    fi
    echo "Apply it to the backend: bash deploy/azure.sh"
  fi
fi

say "Done"
echo "Website address (empty until the first GitHub deploy): $NEW_ORIGIN"
echo
echo "Send this line to the repo owner. It switches on the website deploy:"
echo
echo "gh variable set AZURE_STATIC_WEB_APP --repo $REPO --body $SWA_NAME"
echo
echo "The repo owner also sets the website's VITE_* settings (bash deploy/vercel-env.sh prints"
echo "them from Vercel), then runs: gh workflow run azure-frontend.yml --repo $REPO"
echo "Full steps: deploy/AZURE-WEBSITE.md"
