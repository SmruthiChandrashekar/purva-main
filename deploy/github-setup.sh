#!/usr/bin/env bash
# One-time setup so GitHub Actions can deploy on every push to main, with no secrets.
# Run in Azure Cloud Shell from the repo root, AFTER `bash deploy/azure.sh`.
# Safe to rerun: it reuses what already exists.
#
# In this project's own resource group it creates:
#   - a user-assigned managed identity <app>-github
#   - federated credentials that trust GitHub Actions runs on main of this repo, for both
#     forms GitHub may put in the token's subject:
#       repo:<owner>/<repo>:ref:refs/heads/main
#       repo:<owner>@<ownerId>/<repo>@<repoId>:ref:refs/heads/main
# and grants that identity only:
#   - Contributor on this project's resource group (it holds only this project)
#   - AcrPush on this project's registry
# At the end it prints four `gh variable set` lines for the repo owner.
set -euo pipefail

APP_NAME="${APP_NAME:-purva-main}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-82aaf9d4-d161-4dab-8ecf-dff34de35353}"
LOCATION="${LOCATION:-centralindia}"
RESOURCE_GROUP="${RESOURCE_GROUP:-$APP_NAME}"
ACR_NAME="${ACR_NAME:-$(printf '%s' "$APP_NAME" | tr -cd 'a-zA-Z0-9' | tr 'A-Z' 'a-z')${SUBSCRIPTION_ID:0:8}}"
IDENTITY="${IDENTITY:-$APP_NAME-github}"
ISSUER="https://token.actions.githubusercontent.com"
AUDIENCE="api://AzureADTokenExchange"
BRANCH="main"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '\n==> %s\n' "$*"; }

command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found. Use Azure Cloud Shell."

# --- GitHub repo: owner/name, and the numeric IDs for the second subject form ---
REPO="${GITHUB_REPO:-}"
if [ -z "$REPO" ]; then
  remote="$(git remote get-url origin 2>/dev/null || true)"
  [ -n "$remote" ] || die "no git remote found; run from the clone, or set GITHUB_REPO=owner/repo"
  REPO="$(printf '%s' "$remote" | sed -E 's#^(https://[^/]*github\.com/|git@github\.com:|ssh://git@github\.com/)##; s#\.git$##; s#/$##')"
fi
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "could not work out owner/repo (got '$REPO'); set GITHUB_REPO=owner/repo"
OWNER="${REPO%%/*}"; NAME="${REPO#*/}"

OWNER_ID="${GITHUB_OWNER_ID:-}"; REPO_ID="${GITHUB_REPO_ID:-}"
if [ -z "$OWNER_ID" ] || [ -z "$REPO_ID" ]; then
  command -v gh >/dev/null 2>&1 || die "gh not found; set GITHUB_OWNER_ID and GITHUB_REPO_ID"
  ids="$(gh api "repos/$REPO" --jq '"\(.owner.id) \(.id)"')" || die "gh api repos/$REPO failed (run: gh auth login)"
  read -r OWNER_ID REPO_ID <<< "$ids"
fi
[[ "$OWNER_ID" =~ ^[0-9]+$ && "$REPO_ID" =~ ^[0-9]+$ ]] || die "bad GitHub IDs: owner '$OWNER_ID', repo '$REPO_ID'"

SUBJECT_NAME="repo:$OWNER/$NAME:ref:refs/heads/$BRANCH"
SUBJECT_IDS="repo:$OWNER@$OWNER_ID/$NAME@$REPO_ID:ref:refs/heads/$BRANCH"

# --- Azure ---
say "Subscription $SUBSCRIPTION_ID"
az account set --subscription "$SUBSCRIPTION_ID" || die "cannot select subscription (az login?)"
TENANT_ID="$(az account show --query tenantId -o tsv)"

[ "$(az group exists -n "$RESOURCE_GROUP")" = "true" ] || die "resource group $RESOURCE_GROUP not found. Run deploy/azure.sh first."
RG_ID="$(az group show -n "$RESOURCE_GROUP" --query id -o tsv)"
ACR_ID="$(az acr show -n "$ACR_NAME" -g "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null)" \
  || die "registry $ACR_NAME not found in $RESOURCE_GROUP. Run deploy/azure.sh first."
echo "Repo:     $REPO (branch $BRANCH, owner id $OWNER_ID, repo id $REPO_ID)"
echo "Group:    $RG_ID"
echo "Registry: $ACR_NAME"

say "Managed identity $IDENTITY in $RESOURCE_GROUP"
if az identity show -n "$IDENTITY" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  echo "exists"
else
  az identity create -n "$IDENTITY" -g "$RESOURCE_GROUP" -l "$LOCATION" -o none
  echo "created"
fi
CLIENT_ID="$(az identity show -n "$IDENTITY" -g "$RESOURCE_GROUP" --query clientId -o tsv)"
PRINCIPAL_ID="$(az identity show -n "$IDENTITY" -g "$RESOURCE_GROUP" --query principalId -o tsv)"

# Create or correct one federated credential
federate() {
  local fc="$1" subject="$2" current
  current="$(az identity federated-credential show --name "$fc" --identity-name "$IDENTITY" \
    -g "$RESOURCE_GROUP" --query subject -o tsv 2>/dev/null || true)"
  if [ "$current" = "$subject" ]; then
    echo "$fc: exists ($subject)"
  elif [ -n "$current" ]; then
    az identity federated-credential update --name "$fc" --identity-name "$IDENTITY" -g "$RESOURCE_GROUP" \
      --issuer "$ISSUER" --subject "$subject" --audiences "$AUDIENCE" -o none
    echo "$fc: updated to $subject"
  else
    az identity federated-credential create --name "$fc" --identity-name "$IDENTITY" -g "$RESOURCE_GROUP" \
      --issuer "$ISSUER" --subject "$subject" --audiences "$AUDIENCE" -o none
    echo "$fc: created ($subject)"
  fi
}

say "Federated credentials (GitHub Actions on $BRANCH)"
federate "github-$BRANCH"     "$SUBJECT_NAME"
federate "github-$BRANCH-ids" "$SUBJECT_IDS"

ERR_FILE="$(mktemp)"
trap 'rm -f "$ERR_FILE"' EXIT

# Grant a role at a scope unless already granted. Retries, because a new identity can
# take a minute or two to become visible.
grant() {
  local role="$1" scope="$2" label="$3" attempt
  if [ "$(az role assignment list --assignee "$PRINCIPAL_ID" --role "$role" --scope "$scope" \
          --query "length(@)" -o tsv 2>/dev/null || echo 0)" != "0" ]; then
    echo "$role on $label: already granted"
    return 0
  fi
  for attempt in 1 2 3 4 5 6; do
    if az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
         --role "$role" --scope "$scope" -o none 2>"$ERR_FILE"; then
      echo "$role on $label: granted"
      return 0
    fi
    if grep -qi "already exists" "$ERR_FILE"; then
      echo "$role on $label: already granted"
      return 0
    fi
    echo "$role on $label: not yet (attempt $attempt), retrying in 20s..."
    sleep 20
  done
  cat "$ERR_FILE" >&2
  die "could not grant $role on $label"
}

say "Roles for $IDENTITY (this project only)"
grant "Contributor" "$RG_ID"  "resource group $RESOURCE_GROUP"
grant "AcrPush"     "$ACR_ID" "registry $ACR_NAME"

say "Done. Send these four lines to the repo owner ($OWNER):"
echo
echo "gh variable set AZURE_CLIENT_ID --repo $REPO --body $CLIENT_ID"
echo "gh variable set AZURE_TENANT_ID --repo $REPO --body $TENANT_ID"
echo "gh variable set AZURE_SUBSCRIPTION_ID --repo $REPO --body $SUBSCRIPTION_ID"
echo "gh variable set AZURE_ACR --repo $REPO --body $ACR_NAME"
echo
echo "These are IDs, not secrets. Then the first deploy:"
echo "gh workflow run azure.yml --repo $REPO"
