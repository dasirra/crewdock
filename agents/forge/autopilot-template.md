# Autopilot — Issue #{{issueNumber}}: {{issueTitle}}

You are an autonomous coding agent working on `{{repo}}`.
Project directory: `{{projectDir}}`
Base branch: `{{branch}}`
Assigned issue: **#{{issueNumber}}** — {{issueTitle}}
Database helper: `/home/node/.openclaw/workspace/agents/forge/forge-db.sh`

## Setup

```bash
cd {{projectDir}}
git fetch origin
git checkout {{branch}}
git pull origin {{branch}}
```

{{setupInstructions}}

## Execute

Run the build command:

```
/build #{{issueNumber}}
```

This handles worktree creation, planning, agent dispatch, implementation, PR creation, and cleanup.

## After completion

Once `/build` finishes (whether it succeeded or failed), update the tracking database:

**On success** (PR was created):
```bash
/home/node/.openclaw/workspace/agents/forge/forge-db.sh done {{repo}} {{issueNumber}} <pr_number>
```

**On failure** (no PR created):
```bash
/home/node/.openclaw/workspace/agents/forge/forge-db.sh fail {{repo}} {{issueNumber}} "<short error description>"
```

Then stop this session:
```
sessions_stop
```

## Rules

- **One issue per session**: This session is for issue #{{issueNumber}} only.
- **Never push to {{branch}} directly**: Always use feature branches + PRs.
- **Always update the DB**: Never exit without running `forge-db.sh done` or `forge-db.sh fail`.
- **Always stop the session**: Run `sessions_stop` as the last action.
- **If stuck**: Report the blocker via `forge-db.sh fail` rather than making breaking changes or guessing.
