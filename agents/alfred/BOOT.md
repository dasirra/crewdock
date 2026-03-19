# Boot

Run a status check and report to Discord. Keep the output short. The user wants a quick glance, not a diagnostic dump.

1. Read `config.json`. If missing or empty, this is a **first boot**.
2. Run health checks with dependency chain (see below).
3. If first boot, use "First Boot" output.
4. If returning boot, use "Returning Boot" output.

## Health Checks

Run in order. If a check fails, **skip all checks that depend on it**.

1. `config.json` present and not empty.
2. GWS credentials: check if `~/.config/gws/credentials.json` exists.
   - If this fails, skip checks 3 and 4 (they require GWS auth).
3. Unread email count: `gws gmail users messages list --params '{"userId":"me","q":"is:unread","maxResults":100}'` — count results.
4. Today's event count: `gws calendar events list` for today — count results.
5. Heartbeat: run `openclaw config get agents.list`, find this agent by `id`, read `.heartbeat.every`. Value `"0m"` or absent = disabled.
6. Briefing config: read `briefing.enabled` and `briefing.cron` from `config.json`.

**Output rules:**
- Never include raw command output, error messages, or stack traces in the Discord message.
- If a check fails, report it in one short phrase (e.g. "GWS: not configured").
- If a check was skipped because its parent failed, do not mention it at all.

## First Boot

Use when `config.json` is missing or empty. Post to Discord:

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
[Only list items whose check failed. Omit this section entirely if all pass — end with "Ready. Next briefing at <time>." instead.]
- Google Workspace: not configured. Run `make auth-gws` on the host, then `make restart`.
- Briefing: not scheduled. Send me your preferred time (e.g. "briefing at 8:00").

## Returning Boot

Use when `config.json` exists and is not empty. Post to Discord:

**One line only.** Include only the fields you could actually check. Omit fields whose checks were skipped.

Examples:
- All OK: `Alfred online. Briefing: daily at 08:00. Unread: 5. Today: 3 events.`
- GWS missing: `Alfred online. GWS: not configured. Run `make auth-gws` on the host, then `make restart`.`
- GWS OK but no briefing: `Alfred online. Unread: 5. Today: 3 events. Briefing: not scheduled.`

Do not add extra warning lines. Everything fits in the status line.

## Notes

SOUL.md contains interactive onboarding (asks user for briefing time on first message). This BOOT.md does not replace that.
