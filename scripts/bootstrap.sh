#!/usr/bin/env bash
# One-command reproducible stack for the whole assignment.
#   Cluster (kind, Calico) -> controllers -> Istio -> workload -> mesh policies.
# Idempotent-ish: safe to re-run; recreates the cluster.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

CALICO_VER=v3.28.2
SEALED_VER=v0.38.4

echo "==> [1/9] kind cluster (default CNI disabled)"
kind delete cluster --name dodo 2>/dev/null || true
kind create cluster --name dodo --config task1-harden-workload/cluster/kind-config.yaml

echo "==> [2/9] Calico (NetworkPolicy enforcement)"
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VER}/manifests/calico.yaml"
kubectl wait --for=condition=Ready nodes --all --timeout=180s
# kind nodes share a flat L2 network; IPIP/VXLAN encapsulation is unneeded and
# its MTU overhead drops pod->apiserver TLS handshakes. Disable encapsulation.
kubectl patch ippool default-ipv4-ippool --type=merge \
  -p '{"spec":{"ipipMode":"Never","vxlanMode":"Never"}}'
kubectl rollout restart daemonset/calico-node -n kube-system
kubectl rollout status daemonset/calico-node -n kube-system --timeout=120s

echo "==> [3/9] Sealed Secrets controller"
kubectl apply -f "https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_VER}/controller.yaml"
kubectl rollout status deploy/sealed-secrets-controller -n kube-system --timeout=180s

echo "==> [4/9] Kyverno + ingress-nginx"
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace --wait
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "==> [5/9] Istio + CNI (PSS-restricted compatible)"
istioctl install -y --set profile=default \
  --set components.cni.enabled=true \
  --set values.cni.cniBinDir=/opt/cni/bin \
  --set values.cni.cniConfDir=/etc/cni/net.d

echo "==> [6/9] Build + load the hardened image"
docker build -t ledger-api:0.1.0 app
kind load docker-image ledger-api:0.1.0 --name dodo

echo "==> [7/9] Kyverno guardrails"
kubectl apply -f task1-harden-workload/policies/

echo "==> [8/9] Workload + secrets (re-seal against THIS cluster's key)"
kubectl apply -f task1-harden-workload/manifests/00-namespace.yaml
# regenerate the SealedSecret for this cluster; plaintext is piped, never on disk
kubectl create secret generic ledger-api-secrets -n payments \
  --from-literal=STRIPE_API_KEY="sk_test_$(openssl rand -hex 16)" \
  --from-literal=DB_PASSWORD="$(openssl rand -base64 18)" \
  --from-literal=LEDGER_API_TOKEN="$(openssl rand -hex 24)" \
  --from-literal=TOKEN_SALT="$(openssl rand -hex 16)" \
  --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets-controller \
      --controller-namespace kube-system --format yaml \
  > task1-harden-workload/manifests/40-sealed-secret.yaml
kubectl apply -f task1-harden-workload/manifests/
kubectl apply -f task1-harden-workload/rbac-personas/personas.yaml

echo "==> [9/9] Enable mesh injection + apply zero-trust policies"
kubectl label namespace payments istio-injection=enabled --overwrite
kubectl rollout restart deploy/ledger-api deploy/reporting -n payments
kubectl rollout status deploy/ledger-api -n payments --timeout=120s
kubectl apply -f task3-istio-zero-trust/manifests/

echo "==> done. Verify: ./task1-harden-workload/verify.sh  &&  ./task3-istio-zero-trust/verify.sh"
