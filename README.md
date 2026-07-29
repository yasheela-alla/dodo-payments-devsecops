# Dodo Payments — Security & DevOps Engineer Assessment

Harden the `ledger-api` payments microservice end-to-end — **workload
hardening → secure delivery → zero-trust networking** — then **attack it** and
prove the controls hold.

> **The through-line:** the *same* service is hardened in Tasks 1–3 and attacked
> in Task 4. Every Task-4 finding maps back to the exact control from Tasks 1–3
> that prevents, gates, or contains it (Task 4 report §7). Defence-in-depth is
> the theme; each control is demonstrated *enforcing*, not just present.

Everything runs **locally and free**: `kind` + Calico + Istio + GitHub Actions +
GHCR. No cloud account required.

---

## Repository map

| Task | Folder | What's proven |
|------|--------|---------------|
| **1 — Deploy & Harden** | [`task1-harden-workload/`](task1-harden-workload) | non-root + read-only + drop-ALL-caps + seccomp; dedicated least-priv SA (no token/RBAC); **Sealed Secrets** (no plaintext in git); **Kyverno + PSS restricted** reject the insecure Deployment; persona RBAC |
| **2 — Secure CI/CD** | [`task2-cicd-supply-chain/`](task2-cicd-supply-chain) | GH Actions: gitleaks → Semgrep → Trivy → build → image-scan → push → **cosign keyless sign + SLSA provenance + SBOM** → verify; SARIF to Security tab; **ArgoCD** GitOps drift self-heal; documented fail policy; local scan evidence (gates fail the vulnerable app, pass the hardened one) |
| **3 — Zero-Trust Mesh** | [`task3-istio-zero-trust/`](task3-istio-zero-trust) | Istio **mTLS STRICT** (plaintext refused); **default-deny AuthorizationPolicy** + identity allow (reporting=200, intruder=403); **Calico NetworkPolicy** egress containment → SSRF blast-radius = 0 |
| **4 — Recon & Pentest** | [`task4-recon-pentest/`](task4-recon-pentest) · [**report**](task4-recon-pentest/report/Dodo-Payments-Security-Assessment.md) | passive OSINT of `dodopayments.tech` (112 subdomains, exposed admin consoles); black-box pentest of local `ledger-api` — **RCE(9.8)/PAN/SSRF** chained to secret exfil, CVSS + PoC + retest |

The hardened application is in [`app/`](app); the original vulnerable app is
preserved at [`task4-recon-pentest/pentest/target/`](task4-recon-pentest/pentest/target) as the authorized test target.

---

## Architecture

```mermaid
flowchart TB
  subgraph DEV["Secure delivery — Task 2"]
    GH["GitHub Actions<br/>gitleaks → Semgrep → Trivy"]
    SIGN["build → cosign keyless sign<br/>+ SLSA provenance + SBOM"]
    GHCR[("GHCR<br/>signed image")]
    ARGO["ArgoCD (GitOps)<br/>auto-sync · self-heal"]
    GH --> SIGN --> GHCR --> ARGO
  end

  subgraph CL["kind cluster (Calico CNI)"]
    subgraph ADM["Admission — Task 1"]
      KY["Kyverno: no-root · no-latest · require-signed"]
      PSS["PSS: restricted"]
    end
    subgraph NS["namespace payments  (PCI CDE)  — Istio mesh, mTLS STRICT — Task 3"]
      direction LR
      REP["reporting<br/>(SA identity)"] -->|"mTLS + authz ALLOW"| LED["ledger-api<br/>non-root · ro-rootfs · caps=drop ALL"]
      INT["intruder<br/>(SA identity)"] -.->|"mTLS + authz DENY 403"| LED
      LED -->|"egress: DNS+istiod only<br/>(NetworkPolicy)"| X(("✗ metadata /<br/>internal / internet"))
      SS["SealedSecret → Secret"] -->|secretKeyRef| LED
      ING["Ingress"] --> LED
    end
    ARGO --> ADM
  end

  ATT["Task 4 attacker<br/>RCE · PAN · SSRF"] -.->|"blocked / contained by<br/>the controls above"| NS
```

**Layered controls (defence-in-depth):**
- **Admission** (Kyverno + PSS) — rejects root/`:latest`/unsigned before scheduling.
- **Workload** (securityContext, least-priv SA, Sealed Secrets) — minimises blast radius.
- **Supply chain** (scan-gate + keyless signature) — only vetted, signed images run.
- **Mesh** (mTLS + identity authz) — encrypted, identity-based, default-deny.
- **Network** (Calico NetworkPolicy) — kernel-level floor + egress containment.

---

## Quick start

```bash
# one command: cluster + Calico + Sealed Secrets + Kyverno + ingress + Istio +
# build/deploy the hardened workload + zero-trust policies
./scripts/bootstrap.sh

# verify each task
./task1-harden-workload/verify.sh      # hardening + admission + RBAC
./task3-istio-zero-trust/verify.sh     # mTLS + identity authz + NetworkPolicy

# Task 2 GitOps drift demo (after ArgoCD is registered)
./task2-cicd-supply-chain/argocd/setup.sh && ./task2-cicd-supply-chain/drift-demo.sh
```

**Tooling:** kind, kubectl, helm, docker, Calico, Istio (+CNI), Kyverno,
Sealed Secrets, ArgoCD, cosign, trivy, gitleaks, semgrep. Cluster config:
[`task1-harden-workload/cluster/kind-config.yaml`](task1-harden-workload/cluster/kind-config.yaml).

---

## Notable engineering decisions

- **Fixed the app, not just the deployment.** Shipping a known-RCE payments
  service while calling it "production-grade" is indefensible, so `app/` fixes
  the code (`safe_load`, SSRF guard, auth + PAN masking, current deps) *and* the
  platform hardens around it.
- **Istio CNI plugin** so injected sidecars satisfy **PSS restricted** (the
  default `NET_ADMIN` init container would be rejected).
- **Calico**, because kind's default `kindnet` doesn't enforce NetworkPolicy —
  the segmentation had to *actually enforce*, and it's proven doing so.
- **Guardrails scoped to workload namespaces**, excluding platform namespaces
  (CNI/mesh/controllers legitimately need privilege) — learned by watching my
  own policy correctly block the Istio CNI DaemonSet.
- **Honest SAST triage:** the hardened `/fetch` still trips Semgrep's generic
  SSRF taint rule; it's suppressed *in source with a dated justification* and a
  compensating egress NetworkPolicy — visible in SARIF as `suppressed`, not hidden.

---

## Live proofs

Local proofs (cluster enforcement, scan gates, mesh policies, pentest PoCs) are
captured in each task's `PROOF.txt` / `evidence/`. The GitHub-hosted proofs are live:

- **CI pipeline (green):** https://github.com/yasheela-alla/dodo-payments-devsecops/actions
- **Signed image (GHCR):** https://github.com/yasheela-alla/dodo-payments-devsecops/pkgs/container/ledger-api
- **`cosign verify`** (workflow OIDC identity + Rekor): [`task2-cicd-supply-chain/proof/cosign-verify.txt`](task2-cicd-supply-chain/proof/cosign-verify.txt)
- **SARIF in Security tab:** `semgrep`, `trivy-deps`, `trivy-image`
- **ArgoCD drift → self-heal:** [`task2-cicd-supply-chain/argocd/DRIFT-SELFHEAL-PROOF.txt`](task2-cicd-supply-chain/argocd/DRIFT-SELFHEAL-PROOF.txt)
- **Closed supply-chain loop** — CI signs → promotes digest to git → ArgoCD deploys → **Kyverno verifies the signature at admission** (unsigned rejected): [`task2-cicd-supply-chain/proof/SIGNED-IMAGE-ADMISSION-PROOF.txt`](task2-cicd-supply-chain/proof/SIGNED-IMAGE-ADMISSION-PROOF.txt)
- **Live canary** (VirtualService/DestinationRule weighted routing, 90/10→50/50): [`task3-istio-zero-trust/canary/CANARY-PROOF.txt`](task3-istio-zero-trust/canary/CANARY-PROOF.txt)
- **Pentest report** also as [HTML](task4-recon-pentest/report/Dodo-Payments-Security-Assessment.html) / [PDF](task4-recon-pentest/report/Dodo-Payments-Security-Assessment.pdf)
- **Terminal recordings (GIFs)** of every live demo: [`docs/recordings/`](docs/recordings) — hardening, zero-trust, supply-chain, pentest+retest
- **UI screenshots** (GitHub Actions/Security, ArgoCD, OrbStack): [`docs/screenshots/`](docs/screenshots)
