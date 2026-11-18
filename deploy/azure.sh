#!/usr/bin/env bash
# Setup and settings changes for the backend on Azure Container Apps.
# Run from the repo root in Azure Cloud Shell (Bash). Safe to rerun at any time; rerun it
# if Azure answers InternalServerError.
#
#   bash deploy/azure.sh             # create what's missing, apply .env.azure
#   DRY_RUN=1 bash deploy/azure.sh   # print the commands (secrets masked), change nothing
#
# This project's own resource group holds the registry, the app and (via
# github-setup.sh) the deploy identity. The Container Apps ENVIRONMENT is shared: the
# subscription (free trial) allows only one, so the app joins the existing one. This
# script only reads that environment; it never creates or changes it. Settings
# (secrets, env vars) belong to the app, not the environment, so they can't clash with
# other apps in it. See "What is shared" in deploy/AZURE.md.
# It never builds images: GitHub Actions builds and pushes them (.github/workflows/azure.yml).
# A new app starts on a placeholder image until the first GitHub deploy.
# Settings come from .env.azure (write it with deploy/render-env.sh). See deploy/AZURE.md.
set -euo pipefail

# ---------------------------------------------------------------------------
# Names: all derived from APP_NAME, each overridable
# ---------------------------------------------------------------------------
APP_NAME="${APP_NAME:-purva-main}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-82aaf9d4-d161-4dab-8ecf-dff34de35353}"
LOCATION="${LOCATION:-centralindia}"
RESOURCE_GROUP="${RESOURCE_GROUP:-$APP_NAME}"
ACR_NAME="${ACR_NAME:-$(printf '%s' "$APP_NAME" | tr -cd 'a-zA-Z0-9' | tr 'A-Z' 'a-z')${SUBSCRIPTION_ID:0:8}}"
# Shared Container Apps environment (read only; the subscription allows just one)
ENV_NAME="${ENV_NAME:-purva-bot-env}"
ENV_RESOURCE_GROUP="${ENV_RESOURCE_GROUP:-purva-bot}"
ENV_FILE="${ENV_FILE:-.env.azure}"
PLACEHOLDER_IMAGE="${PLACEHOLDER_IMAGE:-docker.io/nginxinc/nginx-unprivileged:alpine}"

# Port: the app reads $PORT; the placeholder (nginx-unprivileged) listens on 8080 too.
TARGET_PORT=8080

# Sizing (see deploy/AZURE.md, "Size and cost"):
#  - 0.25 vCPU / 0.5Gi: measured ~210 MiB in use, about 1% of a core when idle.
#  - min 1: the SLA monitor runs inside the app every 5 minutes; it must not sleep.
#  - max 1: phone OTP codes live in memory, and a second copy would run the SLA
#    monitor twice (double escalations and emails).
CPU="${CPU:-0.25}"
MEMORY="${MEMORY:-0.5Gi}"
MIN_REPLICAS="${MIN_REPLICAS:-1}"
MAX_REPLICAS="${MAX_REPLICAS:-1}"

DRY_RUN="${DRY_RUN:-0}"
[ "$DRY_RUN" = "0" ] || DRY_RUN=1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
say()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

SECRET_NAMES=()   # filled from .env.azure; their values are masked when printed

is_secret_name() {
  local n
  for n in ${SECRET_NAMES[@]+"${SECRET_NAMES[@]}"}; do
    [ "$n" = "$1" ] && return 0
  done
  return 1
}

# Print a command, masking "<secret-name>=<value>" arguments.
show_cmd() {
  local out="+" a
  for a in "$@"; do
    if [[ "$a" == *=* ]] && is_secret_name "${a%%=*}"; then
      a="${a%%=*}=****"
    fi
    out+=" $(printf '%q' "$a")"
  done
  printf '%s\n' "$out"
}

# Run a command that changes something (only printed in DRY_RUN).
run() {
  show_cmd "$@"
  [ "$DRY_RUN" = "1" ] && return 0
  "$@"
}

# Read-only lookup. In DRY_RUN a failed lookup gives a placeholder instead of stopping.
lookup() {
  local placeholder="$1"; shift
  local out
  if out="$("$@" 2>/dev/null)" && [ -n "$out" ]; then
    printf '%s' "$out"
  elif [ "$DRY_RUN" = "1" ]; then
    printf '%s' "$placeholder"
  else
    die "lookup failed: $*"
  fi
}

# Does a resource exist? (read-only; false if the lookup fails)
exists() { "$@" >/dev/null 2>&1; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
[ -f Dockerfile ] && [ -f backend/main.py ] || die "run this from the repo root (where the Dockerfile is)"
[ -f "$ENV_FILE" ] || die "$ENV_FILE not found. Write it with deploy/render-env.sh (see deploy/AZURE.md)."
command -v az >/dev/null 2>&1 || die "Azure CLI (az) not found. Use Azure Cloud Shell."
[[ "$ACR_NAME" =~ ^[a-z0-9]{5,50}$ ]] || die "registry name '$ACR_NAME' must be 5-50 lower-case letters/digits"
if git rev-parse --git-dir >/dev/null 2>&1 && git ls-files --error-unmatch "$ENV_FILE" >/dev/null 2>&1; then
  die "$ENV_FILE is tracked by git. Remove it from the repo first: git rm --cached $ENV_FILE"
fi

# ---------------------------------------------------------------------------
# Read .env.azure
#   KEY=value, "export KEY=value", one pair of quotes stripped, \r stripped,
#   blank lines and # comments skipped. A key given twice: the last one wins.
# ---------------------------------------------------------------------------
KEYS=(); VALUES=()
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  line="${line//$'\r'/}"
  line="$(trim "$line")"
  [ -z "$line" ] && continue
  [[ "$line" == \#* ]] && continue
  if [[ "$line" == export[[:space:]]* ]]; then
    line="$(trim "${line#export}")"
  fi
  if [[ "$line" != *=* ]]; then
    warn "$ENV_FILE line $lineno has no '=', skipped"
    continue
  fi
  key="$(trim "${line%%=*}")"
  val="$(trim "${line#*=}")"
  if [ "${#val}" -ge 2 ]; then
    first="${val:0:1}"; last="${val: -1}"
    if { [ "$first" = '"' ] && [ "$last" = '"' ]; } || { [ "$first" = "'" ] && [ "$last" = "'" ]; }; then
      val="${val:1:${#val}-2}"
    fi
  fi
  if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    warn "$ENV_FILE line $lineno: '$key' is not a valid variable name, skipped"
    continue
  fi
  if [ "$key" = "PORT" ]; then
    warn "PORT in $ENV_FILE is ignored; the app always gets PORT=$TARGET_PORT"
    continue
  fi
  if [ -z "$val" ]; then
    warn "$key is empty in $ENV_FILE, skipped (Container Apps secrets cannot be empty)"
    continue
  fi
  replaced=0
  for i in ${KEYS[@]+"${!KEYS[@]}"}; do
    if [ "${KEYS[$i]}" = "$key" ]; then VALUES[$i]="$val"; replaced=1; fi
  done
  if [ "$replaced" = "0" ]; then KEYS+=("$key"); VALUES+=("$val"); fi
done < "$ENV_FILE"

[ "${#KEYS[@]}" -gt 0 ] || die "$ENV_FILE has no settings"

for k in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY; do
  found=0
  for key in "${KEYS[@]}"; do [ "$key" = "$k" ] && found=1; done
  [ "$found" = "1" ] || warn "$k is not in $ENV_FILE; the backend will not start without it"
done

SECRET_ARGS=(); ENV_ARGS=()
for i in "${!KEYS[@]}"; do
  key="${KEYS[$i]}"
  # Secret name: lower case, _ -> -, only [a-z0-9-], must start and end alphanumeric
  name="$(printf '%s' "$key" | tr 'A-Z_' 'a-z-' | tr -cd 'a-z0-9-')"
  while [[ "$name" == -* ]]; do name="${name#-}"; done
  while [[ "$name" == *- ]]; do name="${name%-}"; done
  [ -n "$name" ] || die "cannot make a secret name from '$key'"
  if is_secret_name "$name"; then
    die "two settings map to the same secret name '$name' (from '$key'); rename one"
  fi
  SECRET_NAMES+=("$name")
  SECRET_ARGS+=("$name=${VALUES[$i]}")
  ENV_ARGS+=("$key=secretref:$name")
done
ENV_ARGS+=("PORT=$TARGET_PORT")

echo "Settings from $ENV_FILE (${#KEYS[@]}): ${KEYS[*]}"
echo "App $APP_NAME | group $RESOURCE_GROUP | registry $ACR_NAME | $LOCATION"
echo "Shared environment $ENV_NAME (group $ENV_RESOURCE_GROUP): only read, never changed"
[ "$DRY_RUN" = "1" ] && echo "DRY RUN: nothing will be changed."

# ---------------------------------------------------------------------------
# Subscription, CLI extension, providers
# ---------------------------------------------------------------------------
say "Subscription $SUBSCRIPTION_ID"
current_sub="$(az account show --query id -o tsv 2>/dev/null || true)"
if [ "$current_sub" != "$SUBSCRIPTION_ID" ]; then
  # Only selects the subscription in this shell's CLI; changes nothing in Azure
  az account set --subscription "$SUBSCRIPTION_ID" 2>/dev/null \
    || [ "$DRY_RUN" = "1" ] || die "cannot select subscription $SUBSCRIPTION_ID (az login?)"
fi

say "Azure CLI extension and resource providers"
run az extension add --name containerapp --upgrade --only-show-errors
for ns in Microsoft.App Microsoft.OperationalInsights Microsoft.ContainerRegistry; do
  state="$(lookup "unknown" az provider show --namespace "$ns" --query registrationState -o tsv)"
  if [ "$state" = "Registered" ]; then
    echo "$ns: registered"
  else
    run az provider register --namespace "$ns" --wait
  fi
done

# ---------------------------------------------------------------------------
# This project's resource group, registry and environment
# ---------------------------------------------------------------------------
say "Resource group $RESOURCE_GROUP"
if [ "$(lookup "false" az group exists -n "$RESOURCE_GROUP")" = "true" ]; then
  echo "exists"
else
  run az group create -n "$RESOURCE_GROUP" -l "$LOCATION" --only-show-errors -o none
fi

say "Container registry $ACR_NAME (Basic)"
if exists az acr show -n "$ACR_NAME" -g "$RESOURCE_GROUP"; then
  echo "exists"
else
  available="$(lookup "true" az acr check-name -n "$ACR_NAME" --query nameAvailable -o tsv)"
  [ "$available" = "true" ] || die "registry name $ACR_NAME is taken outside this project. Rerun with ACR_NAME=<other name>."
  run az acr create -n "$ACR_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" --sku Basic \
    --admin-enabled false --only-show-errors -o none
fi
ACR_SERVER="$ACR_NAME.azurecr.io"

say "Shared Container Apps environment $ENV_NAME (in $ENV_RESOURCE_GROUP, read only)"
ENV_ID="$(lookup "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$ENV_RESOURCE_GROUP/providers/Microsoft.App/managedEnvironments/$ENV_NAME" \
  az containerapp env show -n "$ENV_NAME" -g "$ENV_RESOURCE_GROUP" --query id -o tsv)"
echo "$ENV_ID"

# App names must be unique inside an environment. Stop if another project already uses ours.
other_rgs="$(az containerapp list --environment "$ENV_ID" --query "[?name=='$APP_NAME'].resourceGroup" -o tsv 2>/dev/null || true)"
for rg in $other_rgs; do
  if [ "$(printf '%s' "$rg" | tr 'A-Z' 'a-z')" != "$(printf '%s' "$RESOURCE_GROUP" | tr 'A-Z' 'a-z')" ]; then
    die "an app named '$APP_NAME' already exists in $ENV_NAME (resource group $rg). Rerun with APP_NAME=<other name>."
  fi
done
echo "App name '$APP_NAME' is free in this environment (or already ours)"

# ---------------------------------------------------------------------------
# The app
# ---------------------------------------------------------------------------
say "Container app $APP_NAME"
APP_EXISTED=0
if exists az containerapp show -n "$APP_NAME" -g "$RESOURCE_GROUP"; then
  APP_EXISTED=1
  echo "exists: settings will be updated, the running image is kept"
else
  create_cmd=(az containerapp create
    --name "$APP_NAME"
    --resource-group "$RESOURCE_GROUP"
    --environment "$ENV_ID"
    --image "$PLACEHOLDER_IMAGE"
    --ingress external
    --target-port "$TARGET_PORT"
    --cpu "$CPU" --memory "$MEMORY"
    --min-replicas "$MIN_REPLICAS" --max-replicas "$MAX_REPLICAS"
    --secrets "${SECRET_ARGS[@]}"
    --env-vars "${ENV_ARGS[@]}"
    --only-show-errors -o none)
  if ! run "${create_cmd[@]}"; then
    # Azure sometimes answers InternalServerError although the app was created
    if exists az containerapp show -n "$APP_NAME" -g "$RESOURCE_GROUP"; then
      warn "create reported an error, but the app exists; continuing"
    else
      die "creating the app failed. Rerun this script in a minute."
    fi
  fi
fi

# Every run: the app's own identity, its pull access to this project's registry,
# and the registry setting. (Also repairs a half-finished earlier run.)
say "Image pull access: app identity -> registry $ACR_NAME"
run az containerapp identity assign -n "$APP_NAME" -g "$RESOURCE_GROUP" --system-assigned \
  --only-show-errors -o none
PRINCIPAL_ID="$(lookup "<app-principal-id>" az containerapp identity show -n "$APP_NAME" -g "$RESOURCE_GROUP" --query principalId -o tsv)"
ACR_ID="$(lookup "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_NAME" \
  az acr show -n "$ACR_NAME" -g "$RESOURCE_GROUP" --query id -o tsv)"

has_acrpull="$(az role assignment list --assignee "$PRINCIPAL_ID" --role AcrPull --scope "$ACR_ID" \
  --query "length(@)" -o tsv 2>/dev/null || echo 0)"
if [ "$has_acrpull" != "0" ] && [ -n "$has_acrpull" ]; then
  echo "AcrPull: already granted"
else
  granted=0
  for attempt in 1 2 3 4 5 6; do
    if run az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
         --role AcrPull --scope "$ACR_ID" --only-show-errors -o none; then
      granted=1; break
    fi
    echo "AcrPull not granted yet (new identities take a moment), retry $attempt in 20s..."
    sleep 20
  done
  [ "$granted" = "1" ] || die "could not grant AcrPull. Rerun this script in a few minutes."
fi
run az containerapp registry set -n "$APP_NAME" -g "$RESOURCE_GROUP" \
  --server "$ACR_SERVER" --identity system --only-show-errors -o none

# Settings on an existing app: keep the image GitHub deployed, change only settings.
if [ "$APP_EXISTED" = "1" ]; then
  say "Apply settings from $ENV_FILE"
  run az containerapp secret set -n "$APP_NAME" -g "$RESOURCE_GROUP" \
    --secrets "${SECRET_ARGS[@]}" --only-show-errors -o none
  # A new revision suffix makes the app restart even when only secret values changed
  run az containerapp update -n "$APP_NAME" -g "$RESOURCE_GROUP" \
    --cpu "$CPU" --memory "$MEMORY" \
    --min-replicas "$MIN_REPLICAS" --max-replicas "$MAX_REPLICAS" \
    --revision-suffix "cfg$(date -u +%m%d%H%M%S)" \
    --replace-env-vars "${ENV_ARGS[@]}" \
    --only-show-errors -o none
fi

if [ "$DRY_RUN" = "1" ]; then
  say "Dry run finished. Nothing was changed."
  exit 0
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
FQDN="$(lookup "" az containerapp show -n "$APP_NAME" -g "$RESOURCE_GROUP" --query properties.configuration.ingress.fqdn -o tsv)"
IMAGE_NOW="$(lookup "" az containerapp show -n "$APP_NAME" -g "$RESOURCE_GROUP" --query "properties.template.containers[0].image" -o tsv)"
URL="https://$FQDN"

# Earlier attempts to create a separate environment may have left empty Log Analytics
# workspaces in this group. They aren't used; point them out (never deleted automatically).
leftovers="$(az monitor log-analytics workspace list -g "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true)"
if [ -n "$leftovers" ]; then
  echo
  echo "Unused log workspace(s) in $RESOURCE_GROUP from earlier attempts (safe to delete):"
  for ws in $leftovers; do
    echo "  az monitor log-analytics workspace delete -g $RESOURCE_GROUP -n $ws --yes"
  done
fi

say "Done"
echo "App address: $URL"
echo "Registry:    $ACR_NAME  ($ACR_SERVER)"
echo "Image:       $IMAGE_NOW"
if [ "$IMAGE_NOW" = "$PLACEHOLDER_IMAGE" ]; then
  echo "Status:      still on the PLACEHOLDER image. The real app arrives with the first"
  echo "             GitHub deploy (run deploy/github-setup.sh, then see deploy/AZURE.md)."
else
  reply=""
  for _ in $(seq 1 30); do   # up to ~5 minutes for the new revision
    if reply="$(curl -fsS --max-time 10 "$URL/health" 2>/dev/null)"; then break; fi
    reply=""; sleep 10
  done
  if [ -n "$reply" ]; then
    echo "Health:      $reply"
  else
    echo "Health:      no answer yet. Logs: az containerapp logs show -n $APP_NAME -g $RESOURCE_GROUP --tail 100"
    exit 1
  fi
fi
