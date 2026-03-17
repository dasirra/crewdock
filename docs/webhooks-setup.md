# GitHub Webhooks Setup

Enables Forge to react to new GitHub issues in real-time instead of waiting for the heartbeat.

## Architecture

```
GitHub → Tailscale Funnel (/hooks/) → HMAC proxy :18791 → OpenClaw :18789/hooks/github → Forge
```

The HMAC proxy (`scripts/gh-webhook-proxy.py`) runs as a systemd service on the **host** (not inside Docker). It:
- Validates `X-Hub-Signature-256` HMAC from GitHub
- Filters to `issues.opened` events only
- Forwards to OpenClaw with Bearer token auth

## Prerequisites

- Tailscale with Funnel enabled on the NAS host
- Python 3 on the host
- A GitHub PAT with `admin:repo_hook` scope (for webhook lifecycle management)

## Step 1: Generate secrets

```bash
# Bearer token for OpenClaw hooks auth (can reuse OPENCLAW_GATEWAY_TOKEN)
openssl rand -hex 32   # → HOOKS_TOKEN

# Shared secret for GitHub HMAC validation
openssl rand -hex 32   # → GITHUB_WEBHOOK_SECRET
```

## Step 2: Configure .env

Add to your `.env` file:

```bash
WEBHOOK_URL=https://<your-tailscale-hostname>/hooks/github
HOOKS_TOKEN=<generated above>
GITHUB_WEBHOOK_SECRET=<generated above>
```

## Step 3: Install the HMAC proxy on the host

Copy the proxy script to the host:

```bash
sudo cp scripts/gh-webhook-proxy.py /usr/local/bin/gh-webhook-proxy.py
sudo chmod +x /usr/local/bin/gh-webhook-proxy.py
```

Create a systemd service file at `/etc/systemd/system/gh-webhook-proxy.service`:

```ini
[Unit]
Description=GitHub Webhook HMAC Proxy for OpenClaw
After=network.target

[Service]
Type=simple
User=<your-user>
Environment=GITHUB_WEBHOOK_SECRET=<your-secret>
Environment=HOOKS_TOKEN=<your-token>
Environment=OPENCLAW_HOOKS_URL=http://127.0.0.1:18789/hooks/github
Environment=PROXY_PORT=18791
# Uncomment if Tailscale Funnel needs to reach the proxy from a different interface:
# Environment=PROXY_HOST=0.0.0.0
ExecStart=/usr/bin/python3 /usr/local/bin/gh-webhook-proxy.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable gh-webhook-proxy
sudo systemctl start gh-webhook-proxy
sudo systemctl status gh-webhook-proxy
```

## Step 4: Configure Tailscale Funnel

Expose only port 18791 (where the HMAC proxy listens) publicly:

```bash
tailscale funnel --bg 18791
```

Verify your Funnel URL:

```bash
tailscale funnel status
# Should show: https://<hostname>.ts.net -> http://127.0.0.1:18791
```

## Step 5: Rebuild and restart OpenClaw

```bash
make up
```

The `init.d/10-hooks.sh` script configures the hooks route automatically on startup (requires `HOOKS_TOKEN` to be set).

## Step 6: Register webhook with GitHub repos

In Forge (via Telegram/Discord):

```
add <owner/repo>
```

This adds the repo to Forge's config and (when `WEBHOOK_URL` is set) automatically creates the GitHub webhook.

Or manually via `gh`:

```bash
gh api repos/<owner>/<repo>/hooks --method POST \
  --field name=web \
  --field active=true \
  --field "events[]=issues" \
  --field "config[url]=https://<hostname>.ts.net/hooks/github" \
  --field "config[content_type]=json" \
  --field "config[secret]=<GITHUB_WEBHOOK_SECRET>"
```

## Verification

Check proxy logs:

```bash
sudo journalctl -u gh-webhook-proxy -f
```

Check OpenClaw logs:

```bash
make logs
```

A new issue on a tracked repo should trigger a Forge ACP session within seconds.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| 401 from proxy | Mismatched `GITHUB_WEBHOOK_SECRET` |
| 502 from proxy | OpenClaw not running or wrong `OPENCLAW_HOOKS_URL` |
| No Forge session spawned | Issue failed selection filters (check SQLite state, concurrency, labels) |
| Funnel not reachable | `tailscale funnel status`, check firewall |
