#!/usr/bin/env bash
# secrets.env (gitignored) -> namespaced CrowdSec and Traefik SealedSecrets (commit output)
#
# Needs: kubeseal.
# Online (default): fetches the public cert from the sealed-secrets controller.
# Offline: SEALED_SECRETS_CERT=/path/to/pub-cert.pem ./scripts/seal-secrets.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="${ENV_FILE:-secrets.env}"
OUT="base/crowdsec-extras/crowdsec-keys.sealedsecret.yaml"
CONTROLLER_NAME="${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets-controller}"
CONTROLLER_NS="${SEALED_SECRETS_CONTROLLER_NAMESPACE:-kube-system}"
CERT="${SEALED_SECRETS_CERT:-}"

command -v kubeseal >/dev/null || { echo "kubeseal not found in PATH" >&2; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "$ENV_FILE not found. Copy secrets.env.example to $ENV_FILE and fill it in." >&2; exit 1; }

# Parse KEY=value lines without sourcing the file (values are never evaluated).
get() {
  local v
  v="$(grep -E "^$1=" "$ENV_FILE" | tail -n1 | cut -d= -f2- || true)"
  v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  printf '%s' "$v"
}

BOUNCER_KEY_TRAEFIK="$(get BOUNCER_KEY_TRAEFIK)"
BOUNCER_KEY_FIREWALL="$(get BOUNCER_KEY_FIREWALL)"

[[ -n "$BOUNCER_KEY_TRAEFIK" ]] || { echo "BOUNCER_KEY_TRAEFIK is empty in $ENV_FILE" >&2; exit 1; }
[[ -n "$BOUNCER_KEY_FIREWALL" ]] || { echo "BOUNCER_KEY_FIREWALL is empty in $ENV_FILE" >&2; exit 1; }

args=(--format yaml)
if [[ -n "$CERT" ]]; then
  args+=(--cert "$CERT")
else
  args+=(--controller-name "$CONTROLLER_NAME" --controller-namespace "$CONTROLLER_NS")
fi

seal_secret() {
  local name="$1"
  local namespace="$2"
  local data="$3"

  cat <<YAML | kubeseal "${args[@]}"
apiVersion: v1
kind: Secret
metadata:
  name: $name
  namespace: $namespace
type: Opaque
data:
$(printf '%s' "$data")
YAML
}

{
  seal_secret crowdsec-keys crowdsec "  BOUNCER_KEY_TRAEFIK: $(printf '%s' "$BOUNCER_KEY_TRAEFIK" | base64 | tr -d '\n')
  BOUNCER_KEY_FIREWALL: $(printf '%s' "$BOUNCER_KEY_FIREWALL" | base64 | tr -d '\n')"
  printf '%s\n' '---'
  # The Traefik chart mounts Secrets from its own kube-system namespace.
  seal_secret crowdsec-bouncer-key kube-system "  BOUNCER_KEY_traefik: $(printf '%s' "$BOUNCER_KEY_TRAEFIK" | base64 | tr -d '\n')"
} > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"

echo "Wrote $OUT -- commit it. (secrets.env stays local.)"
