"""ledger-api — hardened payments microservice.

Security posture (see task4-recon-pentest for the before/after):
  * /import   uses yaml.safe_load (no arbitrary object construction / RCE).
  * /fetch    validates scheme + resolves the host and refuses private,
              loopback, link-local and cloud-metadata ranges (SSRF defence),
              and does not follow redirects into those ranges.
  * /transactions requires a bearer token and never returns a full PAN;
              cardholder data is masked to the PCI-permitted first6/last4.
  * secrets   are read from the environment (populated by a Kubernetes
              Secret / SealedSecret), never hard-coded.
Served by gunicorn (see Dockerfile), not the Flask dev server.
"""
import hashlib
import hmac
import ipaddress
import os
import socket
from urllib.parse import urlsplit

import requests
import yaml
from flask import Flask, jsonify, request

app = Flask(__name__)

# --- configuration / secrets (injected via env from a k8s Secret) ----------
STRIPE_API_KEY = os.environ.get("STRIPE_API_KEY", "")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
# Token that callers must present to read cardholder-adjacent data.
API_TOKEN = os.environ.get("LEDGER_API_TOKEN", "")
# Salt for tokenisation so tokens are not a plain unsalted hash of the PAN.
TOKEN_SALT = os.environ.get("TOKEN_SALT", "")

FETCH_TIMEOUT = float(os.environ.get("FETCH_TIMEOUT", "5"))
FETCH_MAX_BYTES = 2048

LEDGER = [
    {"id": "txn_1001", "pan": "4242424242424242", "amount": 4200, "currency": "USD", "status": "captured"},
    {"id": "txn_1002", "pan": "5555555555554444", "amount": 1899, "currency": "EUR", "status": "refunded"},
]


def _authorized() -> bool:
    """Constant-time bearer-token check. Fails closed if no token configured."""
    if not API_TOKEN:
        return False
    auth = request.headers.get("Authorization", "")
    prefix = "Bearer "
    if not auth.startswith(prefix):
        return False
    return hmac.compare_digest(auth[len(prefix):], API_TOKEN)


def _mask_pan(pan: str) -> str:
    """PCI DSS: at most first6 + last4 may be displayed; mask the rest."""
    digits = "".join(c for c in pan if c.isdigit())
    if len(digits) < 10:
        return "*" * len(digits)
    return f"{digits[:6]}{'*' * (len(digits) - 10)}{digits[-4:]}"


def _is_public_host(host: str) -> bool:
    """Resolve host and require every A/AAAA record to be a global address.

    Blocks SSRF into loopback (127/8, ::1), private RFC1918, link-local
    (169.254/16 incl. 169.254.169.254 metadata), CGNAT, and reserved ranges.
    """
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return False
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if not ip.is_global or ip.is_multicast:
            return False
    return True


@app.route("/health")
def health():
    return jsonify(status="ok")


@app.route("/tokenize", methods=["POST"])
def tokenize():
    payload = request.get_json(silent=True) or {}
    pan = str(payload.get("pan", ""))
    if not pan.isdigit() or not (12 <= len(pan) <= 19):
        return jsonify(error="invalid pan"), 400
    digest = hashlib.sha256((TOKEN_SALT + pan).encode()).hexdigest()[:24]
    return jsonify(token="tok_" + digest, last4=pan[-4:])


@app.route("/transactions")
def transactions():
    if not _authorized():
        return jsonify(error="unauthorized"), 401
    masked = [{**t, "pan": _mask_pan(t["pan"])} for t in LEDGER]
    return jsonify(transactions=masked)


@app.route("/import", methods=["POST"])
def import_config():
    try:
        config = yaml.safe_load(request.data)
    except yaml.YAMLError as exc:
        return jsonify(error="invalid yaml", detail=str(exc)), 400
    return jsonify(loaded=str(config))


@app.route("/fetch")
def fetch():
    url = request.args.get("url", "")
    parts = urlsplit(url)
    if parts.scheme not in ("http", "https") or not parts.hostname:
        return jsonify(error="only http(s) urls are allowed"), 400
    if not _is_public_host(parts.hostname):
        return jsonify(error="refusing to fetch a non-public address"), 400
    try:
        resp = requests.get(url, timeout=FETCH_TIMEOUT, allow_redirects=False)
    except requests.RequestException as exc:
        return jsonify(error="fetch failed", detail=str(exc)), 502
    return jsonify(status_code=resp.status_code, body=resp.text[:FETCH_MAX_BYTES])


if __name__ == "__main__":
    # Dev-only entrypoint; production is served by gunicorn (see Dockerfile).
    app.run(host="127.0.0.1", port=8080)
