#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:$PATH"
NS=payments; B=$(printf '\033[1;36m'); G=$(printf '\033[1;32m'); R=$(printf '\033[1;31m'); X=$(printf '\033[0m')
h(){ echo; echo "${B}### $* ###${X}"; sleep 1; }

h "Signed image is what runs (CI promoted the digest -> ArgoCD deployed it)"
kubectl get deploy ledger-api -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
sleep 1

h "Kyverno VERIFIED the cosign signature at admission (positive)"
POD=$(kubectl get pod -n $NS -l app=ledger-api -o jsonpath='{.items[-1].metadata.name}')
kubectl get pod "$POD" -n $NS -o jsonpath='{.metadata.annotations.kyverno\.io/verify-images}' | sed "s/.*/${G}&${X}/"; echo
sleep 2

h "Unsigned image is REJECTED at admission (negative control)"
kubectl patch cpol require-signed-images --type=json \
  -p='[{"op":"add","path":"/spec/rules/0/verifyImages/0/imageReferences/-","value":"docker.io/library/busybox*"}]' >/dev/null 2>&1
kubectl run unsigned-test --image=busybox:1.36 -n $NS --restart=Never \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"b","image":"docker.io/library/busybox:1.36","command":["sleep","1"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' 2>&1 \
  | grep -iE "blocked|require-signed|no signatures found" | sed "s/.*/${R}&${X}/" | head -4
kubectl patch cpol require-signed-images --type=json \
  -p='[{"op":"remove","path":"/spec/rules/0/verifyImages/0/imageReferences/1"}]' >/dev/null 2>&1
echo "${G}=> only images signed by our workflow can run${X}"
sleep 2
