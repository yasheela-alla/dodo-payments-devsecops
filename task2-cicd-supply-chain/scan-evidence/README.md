# Scan evidence — local reproductions of the pipeline gates

Every gate was run locally against **both** the hardened app (`../../app`) and
the original vulnerable app (`../../task4-recon-pentest/pentest/target`) to prove
the gate fails the insecure code and passes the hardened code. In CI these same
tools run on GitHub's free runners and upload SARIF to the Security tab.

| Gate | Original (vulnerable) | Hardened | File |
|------|----------------------|----------|------|
| **gitleaks** | 🔴 1 leak — `stripe-access-token` `sk_live_…` in `deploy/deployment.yaml` | ✅ no leaks | `gitleaks-original-FAIL.txt` |
| **Semgrep** | 🔴 3 ERROR — `insecure-deserialization` (yaml.load RCE) + 2× SSRF | ✅ 0 active ERROR (2 SSRF `SUPPRESSED(inSource)` with justification + compensating egress policy) | `semgrep-original.sarif`, `semgrep-hardened.sarif` |
| **Trivy** | 🔴 12 (3 CRITICAL + 9 HIGH) incl. PyYAML **CVE-2019-20477** RCE | ✅ 0 fixable CRITICAL/HIGH (only tracked MEDIUM advisories) | `trivy-original-FAIL.txt`, `trivy-hardened.txt` |

## Reproduce

```bash
# secrets
gitleaks detect --source _starter --no-git -v          # -> 1 leak
gitleaks detect --source app --no-git                  # -> no leaks

# SAST (gate = fail on ERROR only; nosemgrep suppressions are justified + triaged)
semgrep scan --config p/python --config p/flask --config p/security-audit \
  --severity ERROR --error task4-recon-pentest/pentest/target/app.py   # -> exit 1 (BLOCK)
semgrep scan --config p/python --config p/flask --config p/security-audit \
  --severity ERROR --error app                                          # -> exit 0 (PASS)

# deps CVE (gate = fixable CRITICAL/HIGH)
trivy fs --scanners vuln --severity CRITICAL,HIGH task4-recon-pentest/pentest/target  # -> 12
trivy fs --scanners vuln --severity CRITICAL,HIGH --ignore-unfixed app                # -> 0
```

## Notes on the Semgrep SSRF suppression

The hardened `/fetch` validates the URL scheme and requires the resolved host to
be globally routable, and disables redirects. Semgrep's generic taint rule still
flags the `requests.get` sink because it can't recognise the custom validator —
a **true positive for the pattern, mitigated in practice**. It is suppressed
`inSource` with a dated justification pointing to the residual DNS-rebinding risk
and its compensating control: the **Task 3 egress NetworkPolicy**, which stops
the pod reaching link-local/RFC1918/metadata addresses at L3 regardless of app
logic. The finding remains visible in SARIF as `suppressed`, so it is triaged,
not hidden.
