# Boot

Run a status check and report to Discord. Keep the output short. The user wants a quick glance, not a diagnostic dump.

1. Read `config.json`. If missing or empty, this is a **first boot**.
2. Run health checks with dependency chain (see below).
3. If first boot, use "First Boot" output.
4. If returning boot, use "Returning Boot" output.

## Health Checks

Run in order. If a check fails, **skip all checks that depend on it**.

1. `config.json` present and not empty.
2. `scouter-db.sh init` (idempotent).
3. `xurl auth status` — record whether bearer token is present.
   - If this fails, skip check 5 for the Twitter source (scanning requires auth).
4. Heartbeat: run `openclaw config get agents.list`, find this agent by `id`, read `.heartbeat.every`. Value `"0m"` or absent = disabled.
5. Source counts: count Twitter list, RSS, and Web sources from config.
6. `scouter-db.sh last-scan` and `scouter-db.sh pending`.

**Output rules:**
- Never include raw command output, error messages, or stack traces in the Discord message.
- If a check fails, report it in one short phrase (e.g. "Twitter: not authenticated").
- If a check was skipped because its parent failed, do not mention it at all.

## First Boot

Use when `config.json` is missing or empty. Post to Discord:

**Scouter online.** Intelligence radar and brand ghostwriter.

I monitor AI/tech sources on schedule, surface what matters, and draft Twitter/X posts in your voice. Nothing publishes without your sign-off.

**Current sources:**
[Read `config.json` sources. List each configured source with its schedule. If no sources configured, show "None configured yet."]
- Twitter: list `1234567890` (twice-daily)
- RSS: HackerNews Best (every-4h)
- Web: GitHub Trending (daily-at-10)

**Getting started:**

Tell me what to watch. For example:

> "Watch this X list: 1234567890"

Find the list ID in the URL: `x.com/i/lists/<THIS_NUMBER>`. The list must be **public** (bearer token auth only works with public lists).

> "Follow this blog: https://hnrss.org/best"

You can also say things like:
- "Start scanning" / "Go" — activate the heartbeat
- "What have you found?" — see pending drafts
- "Scan now" — trigger a scan immediately
- "How are things?" — current status and config

**Setup needed:**
[Only list items whose check failed. Omit this section entirely if all pass — end with "Ready to scan." instead.]
- Twitter: not authenticated. Run `./install.sh` on the host to set up your X bearer token, then `make restart`.
- Sources: no sources configured. See the examples above to get started.

## Returning Boot

Use when `config.json` exists and is not empty. Post to Discord:

Introduce yourself briefly, then show current status. Two lines max.

Examples:
- All OK: `Scouter online. Sources: list 12345 (auth OK), 1 RSS, 1 Web. Heartbeat: 1h. Pending: 3.`
- Twitter missing: `Scouter online. Twitter: not authenticated. Run `./install.sh` on the host. Sources: 1 RSS, 1 Web.`
- No sources: `Scouter online. No sources configured. Send `add list <id>` or `add feed <url>` to start.`

Do not add extra warning lines. Everything fits in the status line.

## Notes

Bearer Token auth (xurl) only works with **public** X lists. If a list returns "not found" at scan time, the list is likely private. Do not flag this during boot.
