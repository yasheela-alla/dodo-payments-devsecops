#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:$PATH"
B=$(printf '\033[1;36m'); G=$(printf '\033[1;32m'); Y=$(printf '\033[1;33m'); X=$(printf '\033[0m')
h(){ echo; echo "${B}### $* ###${X}"; sleep 1; }

echo "${Y}Dodo Payments assessment — LIVE stack, captured $(date '+%Y-%m-%d %H:%M:%S %Z')${X}"

h "OrbStack is hosting the kind cluster (docker containers = k8s nodes)"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | grep -Ei 'dodo|NAME|vulntarget'
sleep 2

h "Cluster nodes (kind, Calico CNI)"
kubectl get nodes -o wide --no-headers | awk '{print $1, $2, $3, $5}'
sleep 2

h "Workload — payments namespace (PCI CDE), Istio-injected (2/2 = app + sidecar)"
kubectl get pods -n payments
sleep 2

h "The RUNNING image is the cosign-SIGNED GHCR digest (promoted by CI, deployed by ArgoCD)"
kubectl get deploy ledger-api -n payments -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
sleep 2

h "GitOps — ArgoCD owns the workload"
kubectl get application ledger-api -n argocd -o jsonpath='  sync={.status.sync.status}  health={.status.health.status}{"\n"}'
sleep 1

h "Platform controllers all live"
for ns in istio-system kyverno argocd; do printf "  %-14s %s pods Running\n" "$ns" "$(kubectl get pods -n $ns --no-headers 2>/dev/null | grep -c Running)"; done
kubectl get cpol --no-headers | awk '{print "  kyverno policy:", $1, "("$4")"}'
sleep 2

h "Service mesh — sidecars registered with istiod"
istioctl proxy-status 2>/dev/null | awk 'NR==1 || /payments/ {print "  "$1}' | head -5
echo "${G}=> full stack live and reproducible via scripts/bootstrap.sh${X}"
sleep 2
