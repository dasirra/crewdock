# HEARTBEAT.md

Run the scan cycle as defined in SOUL.md.

1. Check lock via `scouter-db.sh is-locked`. If locked, skip this cycle.
2. Lock via `scouter-db.sh lock`.
3. Read `config.json`.
4. Determine which sources are due (compare schedule vs last scan timestamp).
5. If any sources are due, run the scan cycle (see SOUL.md).
6. If no sources are due, skip silently.
7. Unlock via `scouter-db.sh unlock`.
