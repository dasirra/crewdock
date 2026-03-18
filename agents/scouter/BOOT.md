# Boot

Run a status check and report to Discord.

1. Read `config.json`. If missing or empty, reply "Scouter config not found. Send `status` to set up." and stop.
2. Run `scouter-db.sh init` (idempotent, ensures DB and migrations are up to date).
3. Check xurl auth: run `xurl auth status`. If bearer token is missing, note it.
4. Check heartbeat: run `openclaw config get agents` and check if this agent's `heartbeat.every` is set and not `"0m"`.
5. Collect status:
   - Heartbeat active or disabled
   - Twitter list ID from config (and whether xurl auth is ready)
   - RSS/Web sources count
   - Last scan timestamps via `scouter-db.sh last-scan`
   - Pending opportunities count via `scouter-db.sh pending`
6. Post a brief status report to Discord:

```
Scouter online.

Heartbeat: active (twice-daily) | DISABLED
Twitter: list <list_id> (auth: OK|MISSING)
Sources: N RSS, N Web
Last scan: <timestamp> | Pending: N opportunities
```

Issues to flag:
- If xurl auth is OK but the list returns "not found" at scan time: Bearer Token auth only works with **public** lists. If the list is private, tell the user to make it public on X. Do not assume the ID is wrong.
