# Threat Model — `ledger-api` (PCI cardholder-data environment)

STRIDE model for the payments microservice and the platform around it. Each
threat lists the **control** that addresses it (with where it lives in this
repo) and the **honest residual risk**. This is the defender's-eye companion to
the attacker's-eye [pen-test report](../task4-recon-pentest/report/Dodo-Payments-Security-Assessment.md).

## Assets & trust boundaries
- **Primary asset:** cardholder data (PANs) and the payment-processor / DB
  credentials.
- **Trust boundaries:** internet → ingress; ingress → mesh; workload → workload
  (mesh mTLS); pod → Kubernetes API; CI → registry → cluster (supply chain);
  git → cluster (GitOps).
- **In-scope namespace = the CDE** (`payments`, labelled `dodo.payments/pci-scope=cde`).

## STRIDE

| # | Threat (STRIDE) | Scenario | Control (where) | Residual risk |
|---|-----------------|----------|-----------------|---------------|
| S | **Spoofing** | A compromised/rogue pod impersonates `reporting` to read `ledger-api` | mTLS STRICT + `AuthorizationPolicy` keyed on SPIFFE identity, not IP — proven `reporting=200 / intruder=403` (T3) | Trust root is istiod's self-signed CA; production should chain to an enterprise/`cert-manager` intermediate |
| T | **Tampering** (supply chain) | Attacker pushes a backdoored image / swaps the running image | cosign **keyless signature** + **Kyverno `require-signed-images`** verifies at admission (unsigned → rejected, proven); digest pinned in git, promoted by CI (T1/T2) | Git commits are not signed — an attacker with repo write could alter manifests; add branch protection + commit signing |
| T | **Tampering** (runtime) | Someone `kubectl edit`s the live workload | `readOnlyRootFilesystem`; **ArgoCD self-heal** reverts drift to git (proven 5→2 in ~10s) (T1/T2) | selfHeal interval is seconds — a very short-lived change could act before revert |
| R | **Repudiation** | "Who deployed / signed this?" | GitOps git history is the audit trail; cosign signature + **Rekor transparency log** record the signer identity + time (T2) | K8s API audit logging not configured in this local demo (would be enabled in prod) |
| I | **Information disclosure** (PAN) | Anon user reads full card numbers | Auth required + **PAN masked** to first6/last4 (fixes F2); mesh authz gates the endpoint (T1/T3) | Tokenisation is HMAC-salted here; a production system should use a random-mapped token vault |
| I | **Information disclosure** (secrets) | Secrets in git / readable by a popped pod | **Sealed Secrets** (only ciphertext in git); SA token **not mounted** + zero RBAC so a popped `ledger-api` can't read Secrets via the API; `gitleaks` gate blocks re-commit (T1/T2) | Unsealed Secret is standard base64 in etcd; prod should add KMS encryption-at-rest or External Secrets + Vault |
| I | **Information disclosure** (SSRF) | `/fetch` pivots to internal/metadata | App validates scheme + resolves host + blocks private ranges + no redirects (fixes F3); **egress NetworkPolicy** contains blast-radius to zero at L3 (T1/T3) | App-level DNS-rebinding TOCTOU exists — *the egress NetworkPolicy is the compensating control* (proven: metadata + external blocked) |
| D | **Denial of service** | Resource exhaustion / crash loop | CPU/memory **requests+limits**, liveness/readiness probes, ≥2 replicas (T1) | No app-layer rate limiting; add an Istio `EnvoyFilter`/local-rate-limit and HPA in prod |
| E | **Elevation of privilege** (breakout) | RCE → container/host escape | non-root uid 10001, `readOnlyRootFilesystem`, **drop ALL caps**, seccomp `RuntimeDefault`, no privilege escalation, **PSS restricted** + Kyverno reject root (T1) | Shared kernel — a kernel 0-day could still escape; gVisor/Kata would harden further |
| E | **Elevation of privilege** (RCE) | YAML deserialization → code exec | `yaml.safe_load` (fixes F1); Semgrep gate blocks re-introduction; *even if it recurred*, the securityContext above contains it (T1/T2/T4) | Defence-in-depth: prevented in code, gated in CI, contained at runtime |

## What the layers catch that the others don't
- **Kill the app-code bug** (safe_load, auth, SSRF guard) — stops the vulnerability.
- **Gate it in CI** (Semgrep/Trivy/gitleaks + signing) — stops it re-entering the pipeline.
- **Contain it at runtime** (non-root/read-only/caps/seccomp) — limits blast radius if it recurs.
- **Segment the network** (mTLS authz + NetworkPolicy) — stops lateral movement & egress even if the workload is popped.
No single layer is trusted; a finding must defeat all of them.
