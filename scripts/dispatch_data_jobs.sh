#!/bin/bash
set -euo pipefail

# --- Core Parameters ---
BASE_DIR="/opt/homelab-iac"
RUNNER_ENV="${BASE_DIR}/services/core/gha-runners/.env"
REPO="rajivghandi767/homelab-iac"
WORKFLOW_FILE="deploy-orchestrator.yml"
REF="main"

umask 077

log_event() {
    local LEVEL="$1"
    local MESSAGE="$2"
    local TIMESTAMP
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"timestamp\": \"$TIMESTAMP\", \"level\": \"$LEVEL\", \"service\": \"data_dispatch_job\", \"message\": \"$MESSAGE\"}"
}

if [ ! -f "$RUNNER_ENV" ]; then
    log_event "FATAL" "Missing runner environment file at $RUNNER_ENV"
    exit 1
fi

log_event "INFO" "Minting short-lived GitHub App installation token and dispatching $WORKFLOW_FILE (MODE=data-only)..."

RUNNER_ENV="$RUNNER_ENV" REPO="$REPO" WORKFLOW_FILE="$WORKFLOW_FILE" REF="$REF" /usr/bin/python3 - << 'PY'
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone


def log(level: str, msg: str) -> None:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(json.dumps({"timestamp": ts, "level": level, "service": "data_dispatch_job", "message": msg}), flush=True)


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def parse_runner_env(path: str) -> tuple[str, str]:
    raw = open(path, "r", encoding="utf-8").read()
    app_id_match = re.search(r"^APP_ID=['\"]?([^'\"\s]+)['\"]?", raw, re.MULTILINE)
    if not app_id_match:
        raise RuntimeError("APP_ID not found in runner .env")
    app_id = app_id_match.group(1).strip()

    key_match = re.search(
        r"(-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----)",
        raw,
        re.DOTALL,
    )
    if not key_match:
        raise RuntimeError("APP_PRIVATE_KEY PEM block not found in runner .env")
    pem = key_match.group(1).replace("\\n", "\n").strip() + "\n"
    return app_id, pem


def mint_jwt(app_id: str, pem: str) -> str:
    now = int(time.time())
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode("utf-8"))
    payload = b64url(
        json.dumps({"iat": now - 60, "exp": now + 540, "iss": app_id}, separators=(",", ":")).encode("utf-8")
    )
    signing_input = f"{header}.{payload}".encode("ascii")
    # Pass PEM via an in-memory pipe descriptor so the key never touches disk
    r_fd, w_fd = os.pipe()
    try:
        os.write(w_fd, pem.encode("utf-8"))
        os.close(w_fd)
        w_fd = -1
        proc = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", f"/dev/fd/{r_fd}"],
            input=signing_input,
             pass_fds=(r_fd,),
            capture_output=True,
            check=True,
        )
    finally:
        if w_fd != -1:
            os.close(w_fd)
        os.close(r_fd)
    sig = b64url(proc.stdout)
    return f"{header}.{payload}.{sig}"


def api_request(url: str, token: str, method: str = "GET", body: dict | None = None) -> dict | None:
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "homelab-iac-pi-dispatcher",
    }
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=15) as resp:
        raw = resp.read()
        return json.loads(raw.decode("utf-8")) if raw else None


def main() -> int:
    env_path = os.environ["RUNNER_ENV"]
    repo = os.environ["REPO"]
    workflow = os.environ["WORKFLOW_FILE"]
    ref = os.environ["REF"]

    app_id, pem = parse_runner_env(env_path)
    jwt_token = mint_jwt(app_id, pem)

    inst = api_request(f"https://api.github.com/repos/{repo}/installation", jwt_token)
    inst_id = inst["id"]
    tok_resp = api_request(f"https://api.github.com/app/installations/{inst_id}/access_tokens", jwt_token, method="POST")
    inst_token = tok_resp["token"]

    dispatch_url = f"https://api.github.com/repos/{repo}/actions/workflows/{workflow}/dispatches"
    payload = {"ref": ref, "inputs": {"MODE": "data-only", "TARGET_APP": "all"}}

    delay = 5
    for attempt in range(1, 5):
        try:
            api_request(dispatch_url, inst_token, method="POST", body=payload)
            log("INFO", f"Successfully dispatched {workflow} on {repo} (ref={ref}, MODE=data-only).")
            return 0
        except urllib.error.HTTPError as exc:
            err_body = exc.read().decode("utf-8", errors="replace")
            log("WARN", f"Attempt {attempt}/4 failed with HTTP {exc.code}: {err_body}")
        except Exception as exc:
            log("WARN", f"Attempt {attempt}/4 failed: {exc}")
        if attempt < 4:
            time.sleep(delay)
            delay *= 2

    log("ERROR", f"Exhausted retries dispatching {workflow} on {repo}.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
PY
