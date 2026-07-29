#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:$PATH"
NS=payments; B=$(printf '\033[1;36m'); G=$(printf '\033[1;32m'); R=$(printf '\033[1;31m'); X=$(printf '\033[0m')
h(){ echo; echo "${B}### $* ###${X}"; sleep 1; }
LP=$(kubectl get pod -n $NS -l app=ledger-api -o jsonpath='{.items[0].metadata.name}')

h "TASK 3 — mTLS STRICT (Istio)"
kubectl get peerauthentication -n $NS
istioctl experimental describe pod "$LP" -n $NS 2>/dev/null | grep -iE "mTLS mode" | sed "s/.*/${G}&${X}/"
sleep 2

h "Identity-based AuthorizationPolicy (default-deny + allow by SPIFFE)"
echo "reporting SA (authorized) -> /health : ${G}$(kubectl exec -n $NS deploy/reporting -c client -- curl -s -o /dev/null -w '%{http_code}' http://ledger-api:8080/health 2>/dev/null)${X}"
echo "intruder  SA (unauthorized)-> /health : ${R}$(kubectl exec -n $NS deploy/intruder -c client -- sh -c 'curl -s -o /dev/null -w "%{http_code}" http://ledger-api:8080/health' 2>/dev/null)${X}  (403 = denied by identity)"
sleep 2

h "NetworkPolicy egress containment — SSRF blast-radius = 0"
echo -n "ledger-api -> 169.254.169.254 (cloud metadata): "
kubectl exec -n $NS "$LP" -c ledger-api -- python -c "import urllib.request
try:
 urllib.request.urlopen('http://169.254.169.254/',timeout=4);print('REACHED - BAD')
except Exception as e:print('${R}BLOCKED (%s)${X}'%type(e).__name__)" 2>/dev/null
sleep 2
