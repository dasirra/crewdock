# Boot

Read `config.json` to determine boot type. If the file is missing or empty, run **First Boot**. If present and valid, run **Returning Boot**.

Run all health checks regardless of boot type. Collect results before producing output.

## Health Checks

Run these in order. If any check command fails, report it as failed with the error output. Do not skip checks.

1. **Config**: `config.json` present and not empty.
2. **Database**: `scouter-db.sh init` (idempotent, ensures DB and migrations are current).
3. **Twitter auth**: `xurl auth status`. Record whether bearer token is present.
4. **Heartbeat**: `openclaw config get agents.list`, find this agent's entry, read `.heartbeat.every`. Value `"0m"` or absent means disabled.
5. **Source counts**: count Twitter list, RSS, and Web sources from config.
6. **Scan state**: `scouter-db.sh last-scan` and `scouter-db.sh pending`.

## First Boot

When `config.json` is missing or empty.

Post to Discord:

**Scouter online.** Intelligence radar and brand ghostwriter.

I monitor Twitter/X lists, RSS feeds, and web sources for AI/tech content relevant to your brand. When I find something, I draft engagement posts in your voice for approval. Nothing publishes without your sign-off.

**What I can do:**
- Scan configured sources on a schedule or on demand
- Surface relevant content based on your keywords and interests
- Draft Twitter/X posts using your voice and templates

**Commands:** `status`, `scan`, `sources`, `config`

**Setup needed:**
Show only items whose health check failed. If all checks pass, show: "Ready to scan."

- Twitter auth not configured → run `make auth-xurl` on the host
- Sources not configured → send `config` to set up feeds and keywords

## Returning Boot

When `config.json` is present and valid.

Post a single status line to Discord:

```
Scouter online. Twitter: list <list_id> (auth OK|MISSING). Sources: N RSS, N Web. Heartbeat: active (<interval>)|disabled. Pending: N opportunities.
```

If any health check failed, append warnings below the status line.

## Notes

- Bearer Token auth (xurl) only works with **public** X lists. If a list returns "not found" at scan time, the list is likely private. Do not flag this during boot since boot does not fetch the list. Only flag it if a scan fails with this error.
