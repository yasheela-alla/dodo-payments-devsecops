# PCI DSS v4.0 — control mapping

The brief frames `ledger-api` as **in PCI DSS scope with an audit coming**. This
maps the controls built in Tasks 1–3 to the PCI DSS requirements they support,
with evidence pointers. Scope: the technical controls a Security/DevOps engineer
owns (not the full programme — policy/《Req 9 physical》/Req 12 are org-level).

> Honest framing: this is a **local demonstration** of the control *mechanisms*.
> Production would add KMS encryption-at-rest, centralised audit logging, and a
> formal token vault — called out per row and in the [threat model](THREAT-MODEL.md).

| PCI DSS req | Intent | How this repo addresses it | Evidence |
|-------------|--------|----------------------------|----------|
| **1** — Network security controls | Segment the CDE; restrict connectivity | Calico **NetworkPolicy** default-deny + explicit allows; Istio mesh boundary; the `payments` ns *is* the CDE (labelled) | `task3-istio-zero-trust/manifests/30-networkpolicy.yaml`; `PROOF.txt` |
| **2** — Secure configurations | No insecure defaults | non-root, read-only FS, drop-ALL-caps, seccomp `RuntimeDefault`; **PSS restricted**; Kyverno rejects root/`:latest`/unsigned | `task1-harden-workload/` (manifests + policies + `PROOF.txt`) |
| **3.3 / 3.4** — Protect stored account data | Mask PAN; don't store what you needn't | `/transactions` **masks PAN** to first6/last4 and requires auth; tokenisation is salted/irreversible | `app/app.py`; retest in Task 4 report |
| **3 / 8.6** — Protect secrets | No cleartext keys | **Sealed Secrets** (ciphertext only in git); `gitleaks` gate; SA token not mounted | `task1-.../manifests/40-sealed-secret.yaml`; `task2-.../scan-evidence/` |
| **4** — Encrypt transmission of CHD | Strong crypto in transit | **Istio mTLS STRICT** for every hop inside the CDE; plaintext refused | `task3-.../00-peerauthentication-strict.yaml`; `PROOF.txt` |
| **6.2 / 6.3** — Secure software & change control | Find & fix vulns; controlled change | CI gates: **Semgrep (SAST) + Trivy (deps+image CVE) + gitleaks**; **GitOps (ArgoCD)** as the sole change path with drift self-heal | `.github/workflows/ci.yml`; `task2-.../` |
| **6.3.3 / supply chain** | Trusted, verifiable artifacts | **cosign keyless signing + SLSA provenance + SBOM**; **Kyverno verifies the signature at admission** (unsigned rejected) | `task2-.../proof/`; `SIGNED-IMAGE-ADMISSION-PROOF.txt` |
| **7** — Least privilege / need-to-know | Restrict access | Dedicated least-priv **ServiceAccount** (no token, no RBAC); scoped neighbour Role (no secrets); **persona RBAC** (dev/operator/admin); mesh **AuthorizationPolicy** by identity | `task1-.../20-serviceaccount.yaml`, `21-rbac-*`, `rbac-personas/`; `task3-.../11-authz-*` |
| **8** — Identify & authenticate | Unique IDs, no shared accounts | Default SA dropped; unique SAs; **SPIFFE workload identities** issued/rotated by istiod | `task1-.../serviceaccount`, `task3-.../README.md` (cert issuance/rotation) |
| **10** — Log & monitor | Audit trail | cosign signatures in **Rekor transparency log**; GitOps git history as change record | `task2-.../proof/cosign-verify.txt` · *(prod: enable K8s API audit + central logging)* |
| **11.3 / 11.4** — Test security | Regular pen-testing & scanning | Full black-box **pen test** (Task 4) with CVSS + retest; continuous scanning in CI | `task4-recon-pentest/report/` |

## Reachability / scope-reduction note
Because the mesh + NetworkPolicy enforce **default-deny** around the CDE, systems
outside `payments` cannot reach cardholder data paths — supporting PCI **scope
reduction** (fewer systems in scope = smaller audit surface).
