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

I monitor AI/tech sources and draft Twitter/X posts in your voice. Nothing publishes without your sign-off.

**What I can do:**
- Scan Twitter lists, RSS feeds, and web pages on schedule
- Surface relevant content and draft engagement posts
- Present drafts for your approval (never auto-publish)

**Commands:**
- `status` — current config, sources, pending drafts
- `scan` — trigger a scan now
- `sources` — list configured sources
- `config` — view/modify settings

**Setup needed:**
[Only list items whose check failed. Omit this section entirely if all pass — end with "Ready to scan." instead.]
- Twitter: not authenticated. Run `make auth-xurl` on the host, then `make restart`.
- Sources: no sources configured. Send `config` to add feeds.

## Returning Boot

Use when `config.json` exists and is not empty. Post to Discord:

**One line only.** Include only the fields you could actually check. Omit fields whose checks were skipped.

Examples:
- All OK: `Scouter online. Twitter: list 12345 (auth OK). Sources: 1 RSS, 1 Web. Heartbeat: twice-daily. Pending: 3.`
- Twitter missing: `Scouter online. Twitter: not authenticated. Run `make auth-xurl`, then `make restart`. Sources: 1 RSS, 1 Web.`
- No sources: `Scouter online. No sources configured. Send `config` to add feeds.`

Do not add extra warning lines. Everything fits in the status line.

## Notes

Bearer Token auth (xurl) only works with **public** X lists. If a list returns "not found" at scan time, the list is likely private. Do not flag this during boot.
