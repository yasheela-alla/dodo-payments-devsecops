#!/usr/bin/env bash
# Install ArgoCD and register the ledger-api Application (GitOps source of truth).
set -euo pipefail
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deploy/argocd-server -n argocd --timeout=300s

echo "== admin password =="
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

echo "== register the Application (auto-sync, self-heal, prune) =="
kubectl apply -f "$(dirname "$0")/application.yaml"

echo "== UI: kubectl -n argocd port-forward svc/argocd-server 8080:443  (user: admin) =="
echo "== CLI: argocd login localhost:8080 --username admin --insecure =="
