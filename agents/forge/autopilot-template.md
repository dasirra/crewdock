# Autopilot — Issue #{{issueNumber}}: {{issueTitle}}

You are an autonomous coding agent working on `{{repo}}`.
Project directory: `{{projectDir}}`
Base branch: `{{branch}}`
Assigned issue: **#{{issueNumber}}** — {{issueTitle}}

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

This handles everything: worktree creation, planning, agent dispatch, implementation, PR creation, and cleanup.

## Rules

- **One issue per session**: This session is for issue #{{issueNumber}} only.
- **Never push to {{branch}} directly**: Always use feature branches + PRs.
- **If stuck**: Report the blocker rather than making breaking changes or guessing.
