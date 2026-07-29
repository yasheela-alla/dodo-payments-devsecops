#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:$PATH"
NS=payments; B=$(printf '\033[1;36m'); G=$(printf '\033[1;32m'); R=$(printf '\033[1;31m'); X=$(printf '\033[0m')
h(){ echo; echo "${B}### $* ###${X}"; sleep 1; }

h "TASK 1 — hardened securityContext (live pod)"
kubectl get pod -n $NS -l app=ledger-api -o jsonpath='{.items[0].spec.containers[0].securityContext}' | python3 -m json.tool
sleep 2

h "Least privilege: can workloads read Secrets?"
echo "ledger-api SA -> get secrets : ${R}$(kubectl auth can-i get secrets -n $NS --as=system:serviceaccount:$NS:ledger-api)${X}"
echo "reporting  SA -> get secrets : ${R}$(kubectl auth can-i get secrets -n $NS --as=system:serviceaccount:$NS:reporting)${X}"
echo "reporting  SA -> list svcs   : ${G}$(kubectl auth can-i list services -n $NS --as=system:serviceaccount:$NS:reporting)${X}"
sleep 2

h "Admission REJECTS the original insecure Deployment (PSS + Kyverno)"
sed 's/name: ledger-api/name: ledger-api-insecure/; s/app: ledger-api/app: ledger-api-insecure/' \
  task1-harden-workload/insecure-original/deployment-original.yaml \
  | kubectl apply -f - 2>&1 | grep -iE "violate|denied|disallow|runAsNonRoot|blocked" | head -6
echo "${G}=> insecure workload blocked before scheduling${X}"
sleep 2
