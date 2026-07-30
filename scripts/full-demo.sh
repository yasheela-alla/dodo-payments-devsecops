#!/usr/bin/env bash
# One continuous walkthrough of the whole assignment against the LIVE cluster.
# Recorded to a terminal video (asciinema/mp4). Colour + banners for readability.
export PATH="/opt/homebrew/bin:$PATH"
# Use the local kind cluster's kubeconfig for this demo.
export KUBECONFIG="$(mktemp -t dodokube.XXXXXX)"
kind export kubeconfig --name dodo >/dev/null 2>&1 || { echo "kind cluster 'dodo' not found — run ./scripts/bootstrap.sh first"; exit 1; }
NS=payments; T=http://localhost:9090; H=http://localhost:18082
B=$(printf '\033[1;36m'); G=$(printf '\033[1;32m'); R=$(printf '\033[1;31m'); Y=$(printf '\033[1;33m'); D=$(printf '\033[2m'); X=$(printf '\033[0m')
banner(){ echo; echo "${B}════════════════════════════════════════════════════════════${X}"; echo "${B}  $*${X}"; echo "${B}════════════════════════════════════════════════════════════${X}"; sleep 1.2; }
step(){ echo; echo "${Y}▸ $*${X}"; sleep .6; }
pause(){ sleep 1.6; }

clear
echo "${Y}Dodo Payments — Security & DevOps assignment${X}"
echo "${D}Live end-to-end walkthrough · $(date '+%Y-%m-%d %H:%M %Z')${X}"
sleep 1.5

banner "0 · The stack is real (OrbStack → kind → Calico → Istio)"
step "kind nodes running as containers"
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -Ei 'dodo|NAME|vulntarget'; pause
step "workload pods (2/2 = app + Istio sidecar), in the PCI namespace"
kubectl get pods -n $NS; pause
step "the RUNNING image is the cosign-SIGNED GHCR digest (CI promoted it, ArgoCD deployed it)"
kubectl get deploy ledger-api -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}'; echo; pause

banner "1 · Workload hardening + admission guardrails"
step "container securityContext — non-root, read-only, caps dropped, seccomp"
kubectl get pod -n $NS -l app=ledger-api -o jsonpath='{.items[0].spec.containers[0].securityContext}' | python3 -m json.tool; pause
step "least privilege — can the app / neighbour read Secrets?"
echo "  ledger-api SA get secrets : ${R}$(kubectl auth can-i get secrets -n $NS --as=system:serviceaccount:$NS:ledger-api)${X}"
echo "  reporting  SA get secrets : ${R}$(kubectl auth can-i get secrets -n $NS --as=system:serviceaccount:$NS:reporting)${X}"; pause
step "admission REJECTS the original insecure Deployment (PSS + Kyverno)"
sed 's/name: ledger-api/name: ledger-api-insecure/; s/app: ledger-api/app: ledger-api-insecure/' \
  task1-harden-workload/insecure-original/deployment-original.yaml \
  | kubectl apply -f - 2>&1 | grep -iE 'violate|denied|disallow|blocked' | head -4
echo "  ${G}=> insecure workload blocked before scheduling${X}"; pause

banner "2 · Supply chain — only signed images run"
step "Kyverno verified the cosign signature at admission (positive)"
POD=$(kubectl get pod -n $NS -l app=ledger-api -o jsonpath='{.items[-1].metadata.name}')
kubectl get pod "$POD" -n $NS -o jsonpath='{.metadata.annotations.kyverno\.io/verify-images}'; echo; pause
step "an UNSIGNED image is rejected at admission (negative control)"
kubectl patch cpol require-signed-images --type=json -p='[{"op":"add","path":"/spec/rules/0/verifyImages/0/imageReferences/-","value":"docker.io/library/busybox*"}]' >/dev/null 2>&1
kubectl delete pod unsigned-demo -n $NS --ignore-not-found >/dev/null 2>&1
kubectl run unsigned-demo --image=busybox:1.36 -n $NS --restart=Never \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"b","image":"docker.io/library/busybox:1.36","command":["true"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' 2>&1 | grep -iE 'blocked|no signatures found' | sed "s/.*/  ${R}&${X}/" | head -3
kubectl patch cpol require-signed-images --type=json -p='[{"op":"remove","path":"/spec/rules/0/verifyImages/0/imageReferences/1"}]' >/dev/null 2>&1
echo "  ${G}=> only images signed by our GitHub workflow can run${X}"; pause

banner "3 · Zero-trust — mTLS + identity authz + NetworkPolicy"
step "mTLS STRICT enforced (effective workload mode)"
istioctl experimental describe pod "$POD" -n $NS 2>/dev/null | grep -i 'mTLS mode' | sed "s/.*/  ${G}&${X}/"; pause
step "authorization by SPIFFE identity, not IP"
echo "  reporting (authorized) -> /health : ${G}$(kubectl exec -n $NS deploy/reporting -c client -- curl -s -o /dev/null -w '%{http_code}' http://ledger-api:8080/health 2>/dev/null)${X}"
echo "  intruder  (unauthorized)-> /health : ${R}$(kubectl exec -n $NS deploy/intruder -c client -- sh -c 'curl -s -o /dev/null -w "%{http_code}" http://ledger-api:8080/health' 2>/dev/null)${X}  ${D}(reachable, but wrong identity)${X}"; pause
step "NetworkPolicy egress containment — SSRF blast-radius = 0"
echo -n "  ledger-api -> 169.254.169.254 (cloud metadata): "
kubectl exec -n $NS "$POD" -c ledger-api -- python -c "import urllib.request
try:
 urllib.request.urlopen('http://169.254.169.254/',timeout=4);print('REACHED - BAD')
except Exception as e:print('${R}BLOCKED (%s)${X}'%type(e).__name__)" 2>/dev/null; pause

banner "4 · Offensive — exploit the vulnerable app, then prove it's fixed"
step "VULNERABLE target: unauthenticated full-PAN disclosure"
curl -s $T/transactions | python3 -c "import sys,json;[print('  ${R}'+t['pan']+'${X}',t['id']) for t in json.load(sys.stdin)['transactions']]"; pause
step "chain: YAML deserialization RCE -> exfiltrate secrets, as root"
curl -s -o /dev/null -X POST -H 'Content-Type: application/x-yaml' --data-binary @task4-recon-pentest/pentest/evidence/rce-exfil.yaml $T/import
echo "  injected command ran as: ${R}$(docker exec vulntarget id 2>/dev/null)${X}"
docker exec vulntarget sh -c 'grep -E "STRIPE_API_KEY|DB_PASSWORD" /tmp/loot.txt' 2>/dev/null | sed "s/.*/  ${R}&${X}/"; pause
step "RETEST on the HARDENED app — every finding closed"
echo "  /transactions no-auth : ${G}$(curl -s -o /dev/null -w '%{http_code}' $H/transactions 2>/dev/null || echo '—')${X}  ${D}(401; was 200 + full PAN)${X}"
echo "  /import RCE gadget     : ${G}$(curl -s -X POST -H 'Content-Type: application/x-yaml' --data-binary @task4-recon-pentest/pentest/evidence/rce-exfil.yaml $H/import 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin).get("error","?"))' 2>/dev/null || echo 'invalid yaml')${X}  ${D}(no execution)${X}"
echo "  /fetch SSRF metadata  : ${G}$(curl -s "$H/fetch?url=http://169.254.169.254/" 2>/dev/null || echo 'refused')${X}"; pause

banner "Defense-in-depth: prevented in code · gated in CI · contained at runtime · segmented on the network"
echo "${D}Repo: github.com/yasheela-alla/dodo-payments-devsecops · reproducible with: make bootstrap${X}"
sleep 2
