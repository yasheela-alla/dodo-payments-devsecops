# Task 3 — Service Mesh & Zero-Trust (Istio)

Identity-based zero-trust between `ledger-api` and its neighbour, with a
Kubernetes NetworkPolicy layer underneath for defence-in-depth.

> **Design note — Istio CNI + PSS restricted.** The `payments` namespace enforces
> Pod Security Standards `restricted`, which forbids the `NET_ADMIN` init
> container Istio uses by default to program iptables. So Istio is installed with
> the **CNI plugin**, which moves that setup out of the pod — sidecars inject as
> fully `restricted`-compliant pods (Istio 1.30 native/restartable-init sidecars).
> The cluster runs **Calico** (kind's default kindnet does not enforce
> NetworkPolicy) so the L3/L4 layer genuinely enforces.

## Layout
```
task3-istio-zero-trust/
├── manifests/                       # applied by scripts/bootstrap.sh
│   ├── 00-peerauthentication-strict.yaml   # mTLS STRICT
│   ├── 10-authz-default-deny.yaml           # empty-spec = deny all
│   ├── 11-authz-allow-reporting.yaml        # allow by SPIFFE identity
│   ├── 20-intruder.yaml                     # unauthorized workload (negative test)
│   └── 30-networkpolicy.yaml                # Calico default-deny + explicit allows
├── gateway/40-gateway.yaml          # bonus: ingress gateway + TLS termination
├── canary/50-canary.yaml            # bonus: canary via VirtualService/DestinationRule
├── verify.sh                        # all proofs
└── PROOF.txt                        # captured output
```

## Verified (see `PROOF.txt`)

| Control | Proof |
|---------|-------|
| **mTLS STRICT** | `PeerAuthentication` mode `STRICT`; `istioctl x describe pod` → **`Workload mTLS mode: STRICT`** and the inbound Envoy listener shows **`requireClientCertificate: true`**; a **non-mesh plaintext** request to `:8080` returns HTTP `000` (connection reset — mTLS required). *(The assignment names `istioctl authn tls-check`, which was **removed** in modern Istio — 1.30 here; the two commands above are its current equivalents.)* |
| **Identity authz — allowed** | `reporting` SA → `/health` = **200** |
| **Identity authz — denied** | `intruder` SA (network-reachable, in-mesh) → **403** — reachability ≠ authorization |
| **NetworkPolicy egress** | `ledger-api` → `169.254.169.254` and → `1.1.1.1` both **time out** (blocked) — SSRF blast-radius = 0 |
| **NetworkPolicy L4** | unlabeled pod → `ledger-api` blocked at L4 (`000`) |

## Certificate issuance, rotation & trust root

- **Trust root:** on install, `istiod` becomes the mesh CA. Its self-signed root
  key/cert is the trust anchor for the whole mesh (replaceable with an
  enterprise intermediate / `cert-manager` for production).
- **Issuance:** each workload's `istio-proxy` generates a private key in-memory
  and sends a CSR to `istiod` over the node's xDS channel. `istiod` validates the
  pod's Kubernetes **ServiceAccount token** (bound to the pod), then issues an
  X.509 SVID whose SAN encodes the SPIFFE identity
  `spiffe://cluster.local/ns/payments/sa/<sa>`.
- **Rotation:** certs are short-lived (~24h by default) and the agent rotates
  them automatically at ~half-life — no downtime, no secrets stored on disk.
- **Authorization** keys on that SPIFFE identity (the SAN), *not* on IP — which
  is exactly why the `intruder` is denied even though it can reach the service.

## What each layer catches that the other doesn't

| Layer | Enforces | Catches | Blind spot |
|-------|----------|---------|------------|
| **Istio AuthorizationPolicy** (L7, per-request, identity) | who (SPIFFE) may call what path/method | a valid-mTLS but unauthorized workload; per-endpoint rules | only sees traffic that transits the sidecar; says nothing about egress to the internet; useless if the sidecar is bypassed |
| **Kubernetes NetworkPolicy** (L3/L4, Calico, kernel) | which pods/namespaces may talk on which ports; **egress** | raw TCP, sidecar-bypass, and a compromised `ledger-api` trying to reach metadata/internal/external (SSRF containment) | no per-request/identity awareness; coarser than L7 |

Together: the mesh gives cryptographic **identity** and fine-grained L7 authz;
NetworkPolicy gives an **identity-independent kernel-level floor** that still
holds if the mesh is bypassed and bounds the egress blast radius. Neither alone
is sufficient; layered, a finding must defeat both.

## Bonus

- **Ingress Gateway + TLS** — `gateway/40-gateway.yaml` terminates external TLS
  at the Istio ingress gateway for `ledger.dodo.local`, forces HTTPS, and routes
  to the workload over in-mesh mTLS. (Create the `ledger-tls` secret first, see
  the file header.)
- **Canary / blue-green** — `canary/50-canary.yaml`: `DestinationRule` subsets
  `v1/v2` + `VirtualService` weights (90/10). Shift weights to progress the
  canary; pin 100/0 ↔ 0/100 for blue-green. mTLS preserved via
  `ISTIO_MUTUAL`.

## PCI CDE boundary

The `payments` namespace *is* the cardholder-data environment (labelled
`dodo.payments/pci-scope=cde`). The mesh boundary + default-deny authz + egress
NetworkPolicy give the **segmentation and least-connectivity** PCI DSS Req 1
expects around the CDE, and mTLS gives **encryption of cardholder data in
transit** (Req 4) for every hop inside it — enforced by identity, not trusting
the network.
