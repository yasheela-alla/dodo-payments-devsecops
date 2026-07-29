#!/usr/bin/env bash
# Demonstrates ArgoCD drift detection + self-heal.
# Precondition: the ledger-api Application is Synced/Healthy.
set -uo pipefail
NS=payments
echo "== git desired state: replicas =="
grep -A1 '^spec:' task1-harden-workload/manifests/30-deployment.yaml | grep replicas

echo; echo "== BEFORE: live replicas =="
kubectl get deploy ledger-api -n $NS -o jsonpath='{.spec.replicas}{"\n"}'

echo; echo "== INTRODUCE DRIFT: scale to 5 by hand (simulating a rogue kubectl edit) =="
kubectl scale deploy/ledger-api -n $NS --replicas=5
kubectl get deploy ledger-api -n $NS -o jsonpath='drifted to {.spec.replicas}{"\n"}'

echo; echo "== ArgoCD detects OutOfSync + self-heals =="
argocd app get ledger-api --refresh -o wide 2>/dev/null | grep -E "Sync Status|Health Status" || true
echo "waiting for self-heal..."
for i in $(seq 1 24); do
  r=$(kubectl get deploy ledger-api -n $NS -o jsonpath='{.spec.replicas}')
  [ "$r" = "2" ] && { echo "self-healed back to $r replicas after ~$((i*5))s"; break; }
  sleep 5
done

echo; echo "== AFTER: live replicas (should match git = 2) =="
kubectl get deploy ledger-api -n $NS -o jsonpath='{.spec.replicas}{"\n"}'
