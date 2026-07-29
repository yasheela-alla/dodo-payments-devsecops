#!/usr/bin/env bash
# Live canary proof: apply the split, send N requests through the mesh, count
# how many hit v1 vs v2, then shift the weights and show the split move.
set -uo pipefail
NS=canary-demo
kubectl apply -f "$(dirname "$0")/demo.yaml"
kubectl rollout status deploy/echo-v1 -n $NS --timeout=120s
kubectl rollout status deploy/echo-v2 -n $NS --timeout=120s
# in-mesh client (PSS-restricted) that curls the Service repeatedly
run_traffic() {
  local n=$1
  kubectl run canary-client -n $NS --image=curlimages/curl:8.11.1 --restart=Never --rm -i --quiet \
    --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"c","image":"curlimages/curl:8.11.1","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"command":["sh","-c","for i in $(seq 1 '"$n"'); do curl -s http://echo.canary-demo.svc.cluster.local:8080/; done"]}]}}' 2>/dev/null \
    | sort | uniq -c
}
echo "=== 90/10 split — 50 requests ==="
run_traffic 50
echo
echo "=== shift to 50/50 (progress the canary) ==="
kubectl patch virtualservice echo -n $NS --type=json \
  -p='[{"op":"replace","path":"/spec/http/0/route/0/weight","value":50},{"op":"replace","path":"/spec/http/0/route/1/weight","value":50}]'
sleep 3
echo "=== 50/50 split — 50 requests ==="
run_traffic 50
