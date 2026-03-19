# Boot

Run a status check and report to Discord.

1. Read `config.json`. If missing or empty, this is a **first boot**.
2. Run health checks (all checks run regardless of boot type).
3. If first boot, use "First Boot" output.
4. If returning boot, use "Returning Boot" output.

## Health Checks

Run these in order. Record pass/fail for each.

1. `config.json` present and not empty.
2. GWS skill available: run `npx skills list | grep googleworkspace`.
3. GWS credentials: check if `~/.config/gws/credentials.json` exists.
4. Heartbeat: run `openclaw config get agents.list`, parse the JSON array to find the entry matching this agent's `id`, then read `.heartbeat.every`. A value of `"0m"` or absent means disabled.
5. Briefing config: read `briefing.enabled` and `briefing.cron` from `config.json`.

If a health check command itself fails (timeout, crash), report it as failed with the error output. Do not silently skip it.

## First Boot

Use this output when `config.json` is missing or empty.

Post to Discord:

**Alfred online.** Your personal assistant.

I keep an eye on your Google Workspace so you don't have to: email, calendar, and tasks. I can send you a daily briefing so you start each day with a clear picture.

**What I can do:**
- Daily briefing: calendar events, unread emails, pending tasks
- Read and search your Gmail
- Check and create calendar events
- Manage your Google Tasks

**Commands:**
- `briefing` — get your briefing now
- `emails` — recent unread emails
- `calendar` — today's schedule
- `tasks` — pending tasks
- `config` — view/modify settings

**Setup needed:**
[List only the items whose health check failed. If all pass, replace this section with: "Ready. Next briefing at <time>."]
- Google Workspace: not authenticated. Run `make auth-gws` on the host, then `make restart`.
- Briefing: not scheduled. Send me a message with your preferred time (e.g. "briefing at 8:00") and I'll set it up.

## Returning Boot

Use this output when `config.json` exists and is not empty.

Post to Discord:

Alfred online. GWS: OK. Briefing: daily at <time>. Unread: N emails. Today: N events.

If any health check failed, append warnings below the status line. One line per warning.

## Notes

SOUL.md contains interactive onboarding (asks user for briefing time on first interactive message). This BOOT.md does not replace that. BOOT.md informs the user that briefing can be configured; SOUL.md handles the interactive setup when the user responds.
