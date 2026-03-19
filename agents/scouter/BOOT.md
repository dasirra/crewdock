# Boot

Run a status check and report to Discord.

1. Read `config.json`. If missing or empty, this is a **first boot**.
2. Run health checks (all checks run regardless of boot type).
3. If first boot, use "First Boot" output.
4. If returning boot, use "Returning Boot" output.

## Health Checks

Run these in order. Record pass/fail for each.

1. `config.json` present and not empty.
2. `scouter-db.sh init` (idempotent, ensures DB and migrations are current).
3. `xurl auth status`. Record whether bearer token is present.
4. Heartbeat: run `openclaw config get agents.list`, parse the JSON array to find the entry matching this agent's `id`, then read `.heartbeat.every`. A value of `"0m"` or absent means disabled.
5. Source counts: count Twitter list, RSS, and Web sources from config.
6. `scouter-db.sh last-scan` and `scouter-db.sh pending`.

If a health check command itself fails (timeout, crash), report it as failed with the error output. Do not silently skip it.

## First Boot

Use this output when `config.json` is missing or empty.

Post to Discord:

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
[List only the items whose health check failed. If all pass, replace this section with: "Ready to scan."]
- Twitter: not authenticated. Run `make auth-xurl` on the host, then `make restart`.
- Sources: no sources configured. Send `config` to add feeds.

## Returning Boot

Use this output when `config.json` exists and is not empty.

Post to Discord:

Scouter online. Twitter: list <list_id> (auth OK|MISSING). Sources: N RSS, N Web. Heartbeat: <status>. Pending: N opportunities.

If any health check failed, append warnings below the status line. One line per warning.

## Notes

Bearer Token auth (xurl) only works with **public** X lists. If a list returns "not found" at scan time, the list is likely private. Do not flag this during boot since boot does not fetch the list.
