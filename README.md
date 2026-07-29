# Dodo Payments — Security & DevOps Engineer Assessment

Hardening the `ledger-api` payments microservice end-to-end — workload
hardening, secure delivery, zero-trust networking — then attacking it.

> **Status:** work in progress. This README is finalized last; each task
> folder has its own detailed README and live proof.

| Task | Folder | Summary |
|------|--------|---------|
| 1 — Deploy & Harden | [`task1-harden-workload/`](task1-harden-workload) | kind cluster, fully locked `securityContext`, least-priv SA/RBAC, Sealed Secrets, Kyverno + PSS admission guardrails |
| 2 — Secure CI/CD | [`task2-cicd-supply-chain/`](task2-cicd-supply-chain) | GitHub Actions build→scan→sign→deploy, cosign keyless + SLSA attest, ArgoCD GitOps |
| 3 — Zero-Trust Mesh | [`task3-istio-zero-trust/`](task3-istio-zero-trust) | Istio mTLS STRICT, identity-based AuthorizationPolicy, NetworkPolicy defence-in-depth |
| 4 — Recon & Pentest | [`task4-recon-pentest/`](task4-recon-pentest) | Passive OSINT on `dodopayments.tech`, black-box pentest of local `ledger-api`, CVSS report |

The hardened application lives in [`app/`](app); the original vulnerable app is
preserved under `task4-recon-pentest/pentest/target/` as the authorized test
target.
