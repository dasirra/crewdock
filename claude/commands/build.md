# Build: Autonomous Spec-to-PR Pipeline

You are the team lead. Take an approved spec, decompose it into tasks, dispatch a team of agents to implement it, review the result, and open a PR. No human intervention after launch.

**Prerequisite:** This command requires autonomous execution. It works best when Claude Code is running with `--dangerously-skip-permissions`. If you detect that tool calls are being blocked by permission prompts, stop and tell the user: "The /build command requires autonomous mode. Restart with: claude --dangerously-skip-permissions"

## Input: $ARGUMENTS

## Step 1: Resolve Input

The input can be:

- **A file path** (contains `/` or ends in `.md`): read it with the Read tool.
- **A GitHub issue** (starts with `#` or is a bare number): fetch with `gh issue view <N> --json title,body,number,labels` via Bash.
- **Inline text** (anything else): treat the entire input string as the spec content directly.

If reading a file or fetching an issue fails, stop and report the error.

Store the resolved content as SPEC_CONTENT and derive SPEC_ID:
- GitHub issue: the issue number (e.g., `42`)
- File: the filename slug without date prefix or extension (strip leading `YYYY-MM-DD-`)
- Inline text: slugify the first 5 words (e.g., "add sqlite tracking for issues" becomes `add-sqlite-tracking-for`)

**Validate the spec has substance:**
The spec must contain concrete requirements: what to build, desired behavior, or acceptance criteria. If the input is too vague to decompose into tasks (e.g., "make it better", "improve performance"), stop and tell the user: "This input is too vague to build from. Run /brainstorm to turn it into a concrete spec first."

## Step 2: Create Worktree

Record the current branch name as BASE_BRANCH.

**Check preconditions:**
- Run `git status --porcelain`. If there are uncommitted changes, stop and tell the user: "Working tree has uncommitted changes. Please commit or stash before running /build."
- Run `git rev-parse --is-inside-work-tree`. If not inside a git repo, stop and report the error.

**Derive branch name** (slugify = lowercase, replace spaces/special chars with hyphens, strip consecutive hyphens, max 50 chars):
- GitHub issue `#N`: `build/N-<slugified-issue-title>`
- File or inline: `build/<SPEC_ID>`

**Check for branch name collision:**
- Run `git branch --list <branch-name>`. If it exists, append `-2` (or `-3`, etc.) until unique.

**Create the worktree:**
- Determine the project root: `git rev-parse --show-toplevel` -> PROJECT_ROOT
- Worktree path: `<PROJECT_ROOT>/../.worktree-<branch-slug>`
- Run: `git worktree add <worktree-path> -b <branch-name>`
- If the command fails, stop and report the error.

Store WORKTREE_PATH and BRANCH_NAME for later steps.

All subsequent file operations must use absolute paths within WORKTREE_PATH. All Bash commands must `cd <WORKTREE_PATH>` first.

## Step 3: Discover Project Agents and Decompose Spec

You are the team lead. This is YOUR job. First discover what specialist agents are available, then read the spec and the codebase, and produce the task breakdown.

**Discover project agents:**
- Glob for `.claude/agents/*.md` in the worktree
- If agent definitions exist, read each one and extract: `name` (from frontmatter), description, specialization, and tools available
- Build an AGENT_ROSTER: a list of available specialist agent types with their capabilities
- These agents are domain experts defined by the project. When spawning teammates, prefer matching a work stream to a specialist agent over using a generic `general-purpose` agent.
- If no `.claude/agents/` directory exists or it's empty, all teammates will be `general-purpose` agents.

**Explore the codebase:**
- Read the project's CLAUDE.md, README, or equivalent for conventions and structure
- Glob for files related to the spec's domain (e.g., if the spec mentions "auth", find existing auth files)
- Understand the existing patterns before deciding how to implement

**Decompose into tasks. For each task, define:**
- **Name**: short imperative (e.g., "Add SQLite migration for issue tracking")
- **Description**: what to implement, with enough detail that an agent can do it without asking questions. Include relevant spec excerpts inline so the agent has full context.
- **Acceptance criteria**: how the agent knows the task is done
- **Files**: which files this task creates or modifies (explicit ownership)
- **Dependencies**: which other tasks must complete first (by name)

**Group tasks into work streams:**
- Tasks that touch the same files MUST be in the same work stream (they run sequentially on one agent)
- Tasks with no file overlap are independent streams (they run in parallel on separate agents)
- Maximum 5 work streams (merge the smallest streams if you exceed this)

**Verify the decomposition:**
- Every file mentioned in the spec is owned by exactly one work stream
- No two work streams touch the same file
- The dependency graph has no cycles
- Each task is small enough for an agent to hold in context (if a task touches more than 5 files, consider splitting it)

Do NOT write the plan to a file. Keep it in your working memory for the next step.

## Step 4: Create Agent Team and Execute

**Create the team:**
- Use TeamCreate to create a team named `build-<SPEC_ID>`

**Create tasks:**
- Use TaskCreate for each task from your decomposition
- Include the full task description, acceptance criteria, and file ownership in each task's description
- Set `blockedBy` relationships matching your dependency graph

**Spawn teammates:**
For each work stream, spawn a teammate using the Agent tool with `team_name` set to the team name.

**Agent type selection per teammate:**
- If AGENT_ROSTER is not empty, match each work stream to the best-fit specialist agent by comparing the work stream's domain (files, layer, technology) to each agent's description and specialization.
  - Example: a work stream touching Firebase repositories matches a `backend` agent; a work stream creating widgets matches a `ui-dev` agent; a work stream writing tests matches a `testing` agent.
  - Set `subagent_type` to the agent's `name` from its frontmatter (e.g., `subagent_type: "backend"`).
  - If no specialist agent is a good fit for a work stream, use `general-purpose`.
- If AGENT_ROSTER is empty, use `general-purpose` for all teammates.
- NEVER use a specialist agent for the code review step (Step 6). The review agent is always `general-purpose` to avoid bias.

Each teammate's prompt must include:

```
You are implementing work stream [N]: [stream description].

## Your Working Directory
All file operations happen in: <WORKTREE_PATH>
All Bash commands start with: cd <WORKTREE_PATH>

## Full Spec
<Paste the ENTIRE SPEC_CONTENT here so the agent has full context of the feature being built>

## Your Tasks
<Full text of each task assigned to this work stream, in dependency order, with acceptance criteria>

## How to Work
1. Check TaskList for available tasks (unblocked, unowned)
2. Claim a task with TaskUpdate (set owner to your name)
3. Mark it in_progress
4. Implement exactly what the task specifies
5. Write tests if the task requires them
6. Self-review (see below)
7. Commit your work
8. Mark the task completed
9. Check TaskList again for next available task
10. When no tasks remain for you, report completion to the team lead

## Git Rules
- Stage only your own files: git add <specific-files>
- NEVER use git add . or git add -A
- If you encounter a git index lock error, wait 2 seconds and retry (max 3 retries)
- Commit with descriptive messages prefixed with feat:, fix:, or chore:
- One commit per task

## Self-Review Before Each Commit
Before committing, review your work:
- Did I implement everything the task specifies? Nothing more, nothing less?
- Are names clear and accurate?
- Did I follow existing patterns in the codebase?
- Do tests verify real behavior (not just mock behavior)?
- Is the code clean and would I be proud to submit this?
Fix any issues you find before committing.

## Escalation
Report one of these statuses per task:
- DONE: Task completed successfully
- DONE_WITH_CONCERNS: Completed but you have doubts. Describe them.
- BLOCKED: Cannot complete. Describe what's blocking you and what you tried.
- NEEDS_CONTEXT: Missing information. Describe exactly what you need.

If blocked or need context, send a message to the team lead. Do NOT guess or make assumptions.
It is always OK to stop and ask. Bad work is worse than no work.
```

**Monitor execution:**
- Watch the shared task list for progress
- If all tasks are completed, proceed to Step 5
- If a teammate sends BLOCKED or NEEDS_CONTEXT, assess and respond:
  - If it's a context problem: provide the missing information via SendMessage
  - If the task is too complex: break it into smaller tasks with TaskCreate
  - If the spec is ambiguous on this point: make a judgment call as team lead, document your decision in the message, and let the teammate proceed
- If a teammate appears stuck (no progress, no messages), send a check-in via SendMessage
- If a teammate fails repeatedly on a task, note the failure and continue with remaining work

## Step 5: Shut Down Team

Once all tasks are completed (or remaining tasks are marked as failed):
- Send shutdown requests to each teammate via SendMessage
- Wait for shutdown confirmations
- Use TeamDelete to clean up team resources

## Step 6: Code Review

Dispatch a single review agent (using the Agent tool, NOT as a teammate) to review the full diff:

```
Review the implementation in <WORKTREE_PATH>.

Run: cd <WORKTREE_PATH> && git diff <BASE_BRANCH>...HEAD

The spec being implemented:
<SPEC_CONTENT>

Check for:
1. **Spec compliance**: Does the code deliver what the spec requires? Anything missing?
2. **Cross-task integration**: Do the pieces from different agents fit together correctly?
3. **Correctness**: Obvious bugs, off-by-one errors, unhandled nulls?
4. **Security**: Injection, XSS, hardcoded secrets, unsafe operations?
5. **Code quality**: Dead code, unclear names, duplicated logic across files?

For each issue found, classify as:
- MUST_FIX: Bugs, security issues, or spec violations
- SHOULD_FIX: Quality issues that meaningfully hurt maintainability
- NIT: Style preferences (ignore these)

Report only MUST_FIX and SHOULD_FIX issues with:
- File and line
- What's wrong
- Suggested fix
```

**If MUST_FIX issues are found:**
- Dispatch a fix agent (Agent tool) to resolve them in the worktree
- The fix agent commits with message: `fix: address code review findings`
- Re-run the review agent to verify fixes (max 2 review cycles, then proceed with a note in the PR)

**If only SHOULD_FIX issues are found:**
- Dispatch a fix agent to resolve them
- Commit with message: `refactor: address code review findings`
- No re-review needed

**If no issues found:** proceed directly to Step 7.

## Step 7: Create Pull Request

**Push the branch:**
```bash
cd <WORKTREE_PATH> && git push -u origin <BRANCH_NAME>
```

**Create the PR as draft** (autonomous PRs need human review before merge):
- **Title:** For issues, use the issue title prefixed with `feat:`, `fix:`, or `chore:` based on content. For files/inline, use the H1 heading or first meaningful header from the spec with the same prefix convention.
- **Body:** Use this template:

```markdown
## Summary
<1-3 sentences: what was built and why, derived from the spec>

## Source
<Link to GitHub issue, or "Local spec: <filename>", or "Inline spec">

## What Changed
<Bulleted list of the concrete changes, grouped by area>

## Tasks
| Task | Status | Notes |
|------|--------|-------|
| <task name> | DONE / FAILED | <brief note if relevant> |

## Code Review
<Summary of review findings and fixes, or "Clean review, no issues found">

---
Built autonomously by `/build`
```

Run:
```bash
cd <WORKTREE_PATH> && gh pr create --draft --base <BASE_BRANCH> --title "<title>" --body "$(cat <<'EOF'
<body content>
EOF
)"
```

If PR creation fails, stop and report the error. Do NOT remove the worktree so work is preserved.

Report the PR URL to the user.

## Step 8: Cleanup

Remove the worktree:
```bash
cd <PROJECT_ROOT> && git worktree remove <WORKTREE_PATH>
```

If cleanup fails, warn the user but do not treat it as an error.

**Final message:** "Build complete. PR: <PR_URL>"
