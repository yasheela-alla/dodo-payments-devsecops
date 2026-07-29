# Screenshots (web UIs & OrbStack)

Visual proof of the pieces that live in a browser / desktop app (the CLI demos
are terminal-recording GIFs in [`../recordings/`](../recordings)).

## GitHub — CI/CD & supply chain (Task 2)
| File | Shows |
|------|-------|
| `github-actions-run.png` | Green pipeline run — *multi-arch build + promote signed digest*, `static-analysis` + `build-sign-attest` both ✓ |
| `github-code-scanning.png` | Security tab → Code scanning: 221 SARIF alerts from Trivy + Semgrep surfaced on the repo |

## ArgoCD — GitOps (Task 2)
| File | Shows |
|------|-------|
| `argocd-apps.png` | `ledger-api` application card — **Status: ♥ Healthy ✓ Synced**, repo + `main` + path `task1-harden-workload/manifests` + ns `payments` |

## OrbStack — the local cluster is real (Task 1)
| File | Shows |
|------|-------|
| `orbstack-containers.png` | Containers: `dodo-control-plane` + 2 workers (kind nodes) + `vulntarget` running |
| `orbstack-node-logs.png` | kind node boot log — detects docker/arm64, Debian trixie, starts kubelet |

> The built `ledger-api` images (hardened `0.1.0` + pentest `:vuln`) are shown in
> the [`docker images` GIF](../recordings/images.gif) and the
> [`live-stack` recording](../recordings/live-stack.gif).
