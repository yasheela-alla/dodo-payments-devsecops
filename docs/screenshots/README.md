# Screenshots (web UIs & OrbStack)

Visual proof of the pieces that live in a browser / desktop app (the CLI demos
are terminal-recording GIFs in [`../recordings/`](../recordings)).

> Save each screenshot with the **exact filename** below into this folder, then
> `git add docs/screenshots && git commit -m "add UI screenshots" && git push`.
> The task READMEs already embed these paths.

## GitHub — CI/CD & supply chain (Task 2)
| File | Shows |
|------|-------|
| `github-actions-run.png` | Green pipeline run — *multi-arch build + promote signed digest*, `static-analysis` + `build-sign-attest` both ✓ |
| `github-code-scanning.png` | Security tab → Code scanning: SARIF alerts from Trivy + Semgrep surfaced on the repo |

## ArgoCD — GitOps (Task 2)
| File | Shows |
|------|-------|
| `argocd-apps.png` | `ledger-api` application card — **Healthy / Synced**, repo + path + `payments` ns |
| `argocd-tree.png` | Application resource tree — Deployment/Svc/SA/**SealedSecret**/Ingress/RBAC all synced, pods 2/2 |
| `argocd-network.png` | Application network view — localhost → ingress → `ledger-api` svc → pods (2/2), auto-sync enabled |

## OrbStack — the local cluster is real (Task 1)
| File | Shows |
|------|-------|
| `orbstack-containers.png` | Containers: `dodo-control-plane` + 2 workers (kind nodes) + `vulntarget` running |
| `orbstack-node-info.png` | Control-plane node — port-forwards 80/443/6443, `io.x-k8s.kind` labels |
| `orbstack-node-logs.png` | kind node boot logs (arm64, Debian trixie) |
| `orbstack-images.png` | Images: `ledger-api:0.1.0` (hardened) + `ledger-api:vuln` (pentest target) |
| `orbstack-networks.png` | The `kind` docker network |
| `orbstack-vulntarget.png` | Vulnerable pentest target — port `9090→8080` |
