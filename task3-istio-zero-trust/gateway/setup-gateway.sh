#!/usr/bin/env bash
# Bonus: expose ledger-api through the Istio ingress gateway with TLS termination.
# Self-signed cert for the demo; production would use cert-manager + a real CA.
set -euo pipefail
cd "$(dirname "$0")"
OSSL=$(ls /opt/homebrew/opt/openssl@3/bin/openssl 2>/dev/null || echo openssl)

# 1. self-signed cert for the gateway host
tmp=$(mktemp -d)
"$OSSL" req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout "$tmp/tls.key" -out "$tmp/tls.crt" \
  -subj "/CN=ledger.dodo.local/O=Dodo Payments Demo" \
  -addext "subjectAltName=DNS:ledger.dodo.local"

# 2. the ingress gateway reads gateway certs from istio-system
kubectl create secret tls ledger-tls --cert="$tmp/tls.crt" --key="$tmp/tls.key" \
  -n istio-system --dry-run=client -o yaml | kubectl apply -f -
rm -rf "$tmp"

# 3. Gateway + VirtualService
kubectl apply -f 40-gateway.yaml

cat <<'EOF'
Gateway ready. Test it:
  kubectl port-forward svc/istio-ingressgateway 8443:443 -n istio-system &
  curl -sk --resolve ledger.dodo.local:8443:127.0.0.1 https://ledger.dodo.local:8443/health
Expected: {"status":"ok"} — TLS terminates at the gateway, then in-mesh mTLS to ledger-api.
NOTE: ledger-api's AuthorizationPolicy must allow the gateway identity
  cluster.local/ns/istio-system/sa/istio-ingressgateway-service-account
(already added in ../manifests/11-authz-allow-reporting.yaml).
EOF
