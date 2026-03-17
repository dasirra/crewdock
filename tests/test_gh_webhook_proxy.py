"""Tests for gh-webhook-proxy.py — HMAC signature validation."""
import hashlib
import hmac
import sys
import os
import unittest

# Add scripts/ to path so we can import the module
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))

# Set required env vars before importing (module reads them at import time)
os.environ.setdefault("GITHUB_WEBHOOK_SECRET", "test-secret")
os.environ.setdefault("HOOKS_TOKEN", "test-token")

import gh_webhook_proxy as proxy


def _make_sig(body: bytes, secret: str = "test-secret") -> str:
    mac = hmac.new(secret.encode(), body, hashlib.sha256)
    return "sha256=" + mac.hexdigest()


class TestVerifySignature(unittest.TestCase):
    def test_valid_signature(self):
        body = b'{"action":"opened"}'
        sig = _make_sig(body)
        self.assertTrue(proxy.verify_signature(body, sig, b"test-secret"))

    def test_invalid_hex(self):
        body = b'{"action":"opened"}'
        self.assertFalse(proxy.verify_signature(body, "sha256=deadbeef", b"test-secret"))

    def test_missing_prefix(self):
        body = b'{"action":"opened"}'
        sig = _make_sig(body).replace("sha256=", "md5=")
        self.assertFalse(proxy.verify_signature(body, sig, b"test-secret"))

    def test_empty_header(self):
        self.assertFalse(proxy.verify_signature(b"body", "", b"test-secret"))

    def test_wrong_secret(self):
        body = b'{"action":"opened"}'
        sig = _make_sig(body, "wrong-secret")
        self.assertFalse(proxy.verify_signature(body, sig, b"test-secret"))


class TestIsIssuesOpened(unittest.TestCase):
    def test_issues_opened(self):
        self.assertTrue(proxy.is_issues_opened("issues", "opened"))

    def test_issues_closed(self):
        self.assertFalse(proxy.is_issues_opened("issues", "closed"))

    def test_pull_request(self):
        self.assertFalse(proxy.is_issues_opened("pull_request", "opened"))

    def test_push(self):
        self.assertFalse(proxy.is_issues_opened("push", ""))


if __name__ == "__main__":
    unittest.main()
