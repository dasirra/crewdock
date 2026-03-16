# Build: Autonomous Spec-to-PR Pipeline

Execute an autonomous implementation pipeline from a spec or issue. Creates a worktree, plans, dispatches an agent team, simplifies, creates a PR, and cleans up.

**Prerequisite:** This command is designed for autonomous execution. It works best when Claude Code is running with `--dangerously-skip-permissions`. If you detect that tool calls are being blocked by permission prompts, stop and tell the user: "The /build command requires autonomous mode. Restart with: claude --dangerously-skip-permissions"

## Input: $ARGUMENTS

## Step 1: Resolve Input

Determine the input type and resolve the content:

- **If input looks like a file path** (contains `/` or ends in `.md`): read it with the Read tool. If the file does not exist, stop and report the error.
- **If input starts with `#` or is a bare number**: fetch the GitHub issue using `gh issue view <N> --json title,body,number` via Bash. If the command fails, stop and report the error.
- **If input matches `LIN-` followed by a number** (e.g., `LIN-123`): fetch the Linear issue using `mcp__linear-server__get_issue`. Extract title and description. If Linear MCP is not configured, stop and report: "Linear MCP server is not configured. Use a file path or GitHub issue instead."

Store the resolved content as SPEC_CONTENT and the source identifier as SPEC_ID (issue number, LIN id, or filename slug).

## Step 2: Create Worktree

Record the current branch name as BASE_BRANCH.

**Check preconditions:**
- Run `git status --porcelain`. If there are uncommitted changes, stop and tell the user: "Working tree has uncommitted changes. Please commit or stash before running /build."
- Run `git rev-parse --is-inside-work-tree`. If not inside a git repo, stop and report the error.

**Derive branch name** (slugify = lowercase, replace spaces/special chars with hyphens, strip consecutive hyphens, max 50 chars):
- GitHub issue `#N`: `build/N-<slugified-issue-title>`
- Linear issue `LIN-N`: `build/LIN-N-<slugified-issue-title>`
- Local file: `build/<filename-without-date-prefix-and-extension>` (strip leading `YYYY-MM-DD-` pattern)

**Check for branch name collision:**
- Run `git branch --list <branch-name>`. If it exists, append `-2` (or `-3`, etc.) until unique.

**Create the worktree:**
- Determine the project root: `git rev-parse --show-toplevel` -> PROJECT_ROOT
- Worktree path: `<PROJECT_ROOT>/../.worktree-<branch-slug>`
- Run: `git worktree add <worktree-path> -b <branch-name>`
- If the command fails, stop and report the error.

Store WORKTREE_PATH and BRANCH_NAME for later steps.

## Step 3: Generate Implementation Plan

All subsequent file operations must use absolute paths within WORKTREE_PATH (e.g., `<WORKTREE_PATH>/src/file.py`). All Bash commands must `cd <WORKTREE_PATH>` first.

Present the resolved spec content in the conversation, then invoke the Skill tool:
- `skill: "superpowers:writing-plans"`

The writing-plans skill will generate the plan. Ensure the plan:
- Defines tasks with explicit file/directory ownership
- Is written to `docs/superpowers/plans/` inside the worktree (do NOT commit the plan file separately)

After the plan is generated, validate it:
- Check each task for file ownership declarations
- If any files appear in multiple tasks, group those tasks into the same work stream (they must run on the same teammate, sequentially)
- Record the work streams and their task assignments

## Step 4: Create Agent Team and Execute

**Create the team:**
- Use TeamCreate to create a team named `build-<SPEC_ID>`
- Determine the number of teammates: one per independent work stream, maximum 5

**Spawn teammates:**
For each work stream, spawn a teammate with a prompt that includes:
- The worktree path: "Your working directory is WORKTREE_PATH. All file operations must happen there."
- Their assigned work stream and tasks
- Git instructions: "Stage only your own files with `git add <specific-files>`. Never use `git add .` or `git add -A`. If you encounter a git index lock error, wait 2 seconds and retry (max 3 retries). Commit with descriptive messages after completing each task. Do NOT commit any plan files from docs/superpowers/plans/."
- If the project has `.claude/agents/` definitions, reference the relevant specialist role

**Create tasks:**
- Use TaskCreate for each task from the plan
- Set `blockedBy` relationships for dependent tasks
- Teammates will self-claim available tasks

**Monitor:**
- Watch the shared task list for progress
- If all tasks are completed, proceed to Step 5
- If a teammate appears stuck (no progress for an extended period), send a message to check on them
- If a teammate fails, note the failure and continue with remaining work

## Step 5: Clean Up Team and Simplify

**Shut down teammates:**
- Ask each teammate to shut down
- Clean up the team

**Simplify:**
- Working from the worktree directory, invoke the Skill tool: `skill: "simplify"` to review all changed code for reuse, quality, and efficiency
- If the skill is not available (plugin not installed), skip this step
- If simplify produces changes, commit them with message: "refactor: simplify implementation"

## Step 6: Create Pull Request

**Push the branch:**
```bash
cd <WORKTREE_PATH> && git push -u origin <BRANCH_NAME>
```

**Create the PR:**
- **Title:** For issues, use the issue title prefixed with `feat:`, `fix:`, or `chore:` based on content. For local files, use the H1 heading from the spec with the same prefix convention.
- **Body:** Use this template:

```
## Summary
- <1-3 bullet points derived from the spec>

## Completed Tasks
- <list of completed tasks from the plan>

## Failures (if any)
- <list of any tasks that failed, with brief explanation>

---
Generated by `/build` from <source description>
```

Run:
```bash
gh pr create --draft --base <BASE_BRANCH> --title "<title>" --body "<body>"
```

If PR creation fails, stop and report the error. Do NOT remove the worktree so work is preserved.

Report the PR URL to the user.

## Step 7: Cleanup

Remove the worktree:
```bash
cd <PROJECT_ROOT> && git worktree remove <WORKTREE_PATH>
```

If cleanup fails, warn the user but do not treat it as an error.

**Final message:** "Build complete. PR created: <PR_URL>"
