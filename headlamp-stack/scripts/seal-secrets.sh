#!/usr/bin/env bash
# secrets.env (gitignored)  ->  manifests/oauth2-proxy-credentials.sealedsecret.yaml (commit this)
#
# Needs: kubeseal (and openssl only if COOKIE_SECRET is empty).
# Online (default): fetches the public cert from the sealed-secrets controller.
# Offline: SEALED_SECRETS_CERT=/path/to/pub-cert.pem ./scripts/seal-secrets.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="${ENV_FILE:-secrets.env}"
OUT="manifests/oauth2-proxy-credentials.sealedsecret.yaml"
SECRET_NAME="oauth2-proxy-credentials"   # must match config.existingSecret in oauth2-proxy/values.yaml
SECRET_NS="oauth2-proxy"
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

GITHUB_CLIENT_SECRET="$(get GITHUB_CLIENT_SECRET)"
COOKIE_SECRET="$(get COOKIE_SECRET)"

[[ -n "$GITHUB_CLIENT_SECRET" ]] || { echo "GITHUB_CLIENT_SECRET is empty in $ENV_FILE" >&2; exit 1; }

if [[ -z "$COOKIE_SECRET" ]]; then
  COOKIE_SECRET="$(openssl rand -hex 16)"          # 32 chars
  tmp="$(mktemp)"
  { grep -v '^COOKIE_SECRET=' "$ENV_FILE" || true; echo "COOKIE_SECRET=$COOKIE_SECRET"; } > "$tmp"
  cat "$tmp" > "$ENV_FILE"; rm -f "$tmp"
  echo "Generated COOKIE_SECRET and saved it to $ENV_FILE"
fi
case "${#COOKIE_SECRET}" in 16|24|32) ;; *) echo "COOKIE_SECRET must be 16, 24 or 32 characters (got ${#COOKIE_SECRET})" >&2; exit 1;; esac

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

args=(--format yaml)
if [[ -n "$CERT" ]]; then
  args+=(--cert "$CERT")
else
  args+=(--controller-name "$CONTROLLER_NAME" --controller-namespace "$CONTROLLER_NS")
fi

cat <<YAML | kubeseal "${args[@]}" > "$OUT.tmp"
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $SECRET_NS
type: Opaque
data:
  client-secret: $(b64 "$GITHUB_CLIENT_SECRET")
  cookie-secret: $(b64 "$COOKIE_SECRET")
YAML
mv "$OUT.tmp" "$OUT"

echo "Wrote $OUT -- commit it. (secrets.env stays local.)"
