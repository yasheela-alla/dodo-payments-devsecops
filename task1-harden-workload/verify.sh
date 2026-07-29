#!/usr/bin/env bash
# Task 1 verification — proves the hardening controls are live.
set -uo pipefail
NS=payments
line(){ printf '\n=== %s ===\n' "$1"; }

line "pods"
kubectl get pods -n $NS -o wide

line "container securityContext (ledger-api)"
kubectl get pod -n $NS -l app=ledger-api -o jsonpath='{.items[0].spec.containers[0].securityContext}' | python3 -m json.tool

line "ServiceAccount token NOT mounted"
kubectl get pod -n $NS -l app=ledger-api -o jsonpath='{.items[0].spec.automountServiceAccountToken}{"\n"}'

line "secret comes from SealedSecret (no inline values)"
kubectl get sealedsecret,secret ledger-api-secrets -n $NS
kubectl get deploy ledger-api -n $NS -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.valueFrom.secretKeyRef.name}{"\n"}{end}'

line "RBAC least privilege"
echo "ledger-api can get secrets: $(kubectl auth can-i get secrets -n $NS --as=system:serviceaccount:$NS:ledger-api)"
echo "reporting  can get secrets: $(kubectl auth can-i get secrets -n $NS --as=system:serviceaccount:$NS:reporting)"
echo "reporting  can list svcs  : $(kubectl auth can-i list services -n $NS --as=system:serviceaccount:$NS:reporting)"

line "API auth + PAN masking"
echo "/transactions no-token HTTP: $(kubectl exec -n $NS deploy/reporting -- curl -s -o /dev/null -w '%{http_code}' http://ledger-api:8080/transactions)"
echo "(supply LEDGER_API_TOKEN to see masked PANs: 424242******4242)"

line "Kyverno policies (Enforce)"
kubectl get cpol
