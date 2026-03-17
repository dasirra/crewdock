#!/usr/bin/env python3
"""gh-webhook-proxy.py — GitHub webhook HMAC validation proxy.

Validates X-Hub-Signature-256, filters to issues.opened events,
and forwards to OpenClaw gateway with Bearer token auth.

Run as a systemd service on the host. See docs/webhooks-setup.md.

Environment variables (required):
  GITHUB_WEBHOOK_SECRET  Shared secret set in GitHub webhook config
  HOOKS_TOKEN            Bearer token expected by OpenClaw hooks endpoint

Environment variables (optional):
  OPENCLAW_HOOKS_URL     Full URL of OpenClaw hooks endpoint
                         Default: http://127.0.0.1:18789/hooks/github
  PROXY_PORT             Port to listen on (default: 18791)
  PROXY_HOST             Host to bind to (default: 127.0.0.1)
"""
import hashlib
import hmac
import http.server
import json
import os
import sys
import urllib.error
import urllib.request

# --- Pure functions (testable without env vars) ---

def verify_signature(body: bytes, signature_header: str, secret: bytes) -> bool:
    """Return True if X-Hub-Signature-256 header matches body + secret."""
    if not signature_header or not signature_header.startswith("sha256="):
        return False
    mac = hmac.new(secret, body, hashlib.sha256)
    expected = "sha256=" + mac.hexdigest()
    return hmac.compare_digest(expected, signature_header)


def should_forward(event: str, action: str) -> bool:
    """Return True only for issues.opened events."""
    return event == "issues" and action == "opened"


# --- Configuration (loaded from env at startup) ---

GITHUB_WEBHOOK_SECRET: bytes = os.environ.get("GITHUB_WEBHOOK_SECRET", "").encode()
HOOKS_TOKEN: str = os.environ.get("HOOKS_TOKEN", "")
OPENCLAW_HOOKS_URL: str = os.environ.get(
    "OPENCLAW_HOOKS_URL", "http://127.0.0.1:18789/hooks/github"
)
PROXY_PORT: int = int(os.environ.get("PROXY_PORT", "18791"))
PROXY_HOST: str = os.environ.get("PROXY_HOST", "127.0.0.1")


class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        # Validate HMAC signature
        sig = self.headers.get("X-Hub-Signature-256", "")
        if not verify_signature(body, sig, GITHUB_WEBHOOK_SECRET):
            self._respond(401, b"Invalid signature")
            return

        # Parse payload
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            self._respond(400, b"Invalid JSON")
            return

        # Filter: only issues.opened
        event = self.headers.get("X-GitHub-Event", "")
        action = payload.get("action", "")
        if not should_forward(event, action):
            self._respond(200, b"Ignored")
            return

        # Forward to OpenClaw
        try:
            req = urllib.request.Request(
                OPENCLAW_HOOKS_URL,
                data=body,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {HOOKS_TOKEN}",
                    "X-GitHub-Event": event,
                },
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                self._respond(resp.status, resp.read())
        except urllib.error.URLError as e:
            print(f"[proxy] Upstream error: {e}", file=sys.stderr)
            self._respond(502, f"Upstream error: {e}".encode())

    def _respond(self, status: int, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # noqa: N802
        print(f"[proxy] {self.address_string()} {fmt % args}")


def main() -> None:
    if not GITHUB_WEBHOOK_SECRET:
        print("ERROR: GITHUB_WEBHOOK_SECRET is not set", file=sys.stderr)
        sys.exit(1)
    if not HOOKS_TOKEN:
        print("ERROR: HOOKS_TOKEN is not set", file=sys.stderr)
        sys.exit(1)

    server = http.server.HTTPServer((PROXY_HOST, PROXY_PORT), WebhookHandler)
    print(f"[proxy] Listening on {PROXY_HOST}:{PROXY_PORT}")
    print(f"[proxy] Forwarding issues.opened to {OPENCLAW_HOOKS_URL}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("[proxy] Shutting down.")


if __name__ == "__main__":
    main()
