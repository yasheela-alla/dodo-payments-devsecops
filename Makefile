# Dodo Payments assessment — one-command UX.
# Everything runs locally & free (kind + Calico + Istio + GHCR). No cloud account.
.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help bootstrap verify verify-hardening verify-zerotrust demo-canary demo-drift pentest retest argocd-ui clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	 awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Stand up the whole stack (kind+Calico+SealedSecrets+Kyverno+ingress+Istio+workload+mesh)
	./scripts/bootstrap.sh

verify: verify-hardening verify-zerotrust ## Run all verification suites

verify-hardening: ## Task 1 — securityContext, RBAC, Sealed Secrets, admission guardrails
	./task1-harden-workload/verify.sh

verify-zerotrust: ## Task 3 — mTLS STRICT, identity authz (200 vs 403), NetworkPolicy egress
	ISTIOCTL=istioctl ./task3-istio-zero-trust/verify.sh

demo-drift: ## Task 2 — ArgoCD drift -> self-heal
	./task2-cicd-supply-chain/drift-demo.sh

demo-canary: ## Task 3 — canary weighted routing (90/10 -> 50/50)
	./task3-istio-zero-trust/canary/demo.sh

pentest: ## Task 4 — build + run the vulnerable target locally on :9090 (authorized target)
	docker build -t ledger-api:vuln task4-recon-pentest/pentest/target
	docker rm -f vulntarget 2>/dev/null || true
	docker run -d --name vulntarget -p 9090:8080 \
	  -e STRIPE_API_KEY=sk_live_EXAMPLE -e DB_PASSWORD=example ledger-api:vuln
	@echo "target up: http://localhost:9090  (see report Part B for PoCs)"

retest: ## Task 4 — prove the findings are closed on the hardened app
	docker rm -f hardened 2>/dev/null || true
	docker run -d --name hardened -p 18082:8080 -e LEDGER_API_TOKEN=t -e TOKEN_SALT=s ledger-api:0.1.0
	@sleep 3
	@echo "no-auth /transactions -> $$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18082/transactions) (expect 401)"
	@curl -s "http://localhost:18082/fetch?url=http://169.254.169.254/" ; echo

argocd-ui: ## Port-forward the ArgoCD UI (https://localhost:8080)
	@echo "user: admin   password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
	kubectl port-forward svc/argocd-server 8080:443 --namespace argocd

clean: ## Tear everything down
	kind delete cluster --name dodo || true
	docker rm -f vulntarget hardened internal-svc 2>/dev/null || true
