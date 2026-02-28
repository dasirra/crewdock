#!/usr/bin/env python3
"""
Claude Dev Orchestrator
Polls GitHub issues and runs Claude Code autonomously for each one.
"""

import asyncio
import json
import logging
import os
import re
import signal
import subprocess
import sys
from datetime import datetime, date, time as dtime
from pathlib import Path
from zoneinfo import ZoneInfo

import requests

# ── Paths ──────────────────────────────────────────────────────────────────
CONFIG_PATH  = Path(os.environ.get("DEV_CONFIG_PATH",  "/config/dev-config.json"))
STATE_PATH   = Path(os.environ.get("DEV_STATE_PATH",   "/state/jobs.json"))
PROJECTS_DIR = Path(os.environ.get("PROJECTS_DIR",     "/projects"))
LOGS_DIR     = Path(os.environ.get("LOGS_DIR",         "/state/logs"))

# ── Env ────────────────────────────────────────────────────────────────────
GITHUB_TOKEN   = os.environ.get("GITHUB_TOKEN", "")
OPENCLAW_URL   = os.environ.get("OPENCLAW_URL", "http://localhost:18789")
OPENCLAW_TOKEN = os.environ.get("OPENCLAW_GATEWAY_TOKEN", "")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    stream=sys.stdout,
)
log = logging.getLogger("claude-dev")

# Active jobs: { "repo#number": {process, pid, started_at, log_file, log_handle, repo, number, title} }
_active_jobs: dict = {}

DEFAULT_PROMPT = """\
You are an autonomous software engineer working on a GitHub issue.

Repository : {repo}  (already cloned at {repo_path})
Base branch: {branch}
Issue #{number}: {title}

Description:
{body}

Instructions:
1. Create a git worktree for a new branch `issue-{number}` based on `{branch}`.
2. Implement the changes required by the issue.
3. Write or update tests as needed.
4. Commit the changes with a descriptive message referencing issue #{number}.
5. Open a Pull Request targeting `{branch}`.

Work autonomously using your tools (Bash, Read, Write, Edit, Agent).
"""


# ── State ──────────────────────────────────────────────────────────────────

def load_state() -> dict:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    if STATE_PATH.exists():
        return json.loads(STATE_PATH.read_text())
    return {"daily": {}}


def save_state(state: dict):
    STATE_PATH.write_text(json.dumps(state, indent=2, default=str))


def today_key(timezone: str) -> str:
    return datetime.now(ZoneInfo(timezone)).date().isoformat()


def day_state(state: dict, tz: str) -> dict:
    """Return (and initialise) the state bucket for today."""
    key = today_key(tz)
    state["daily"].setdefault(key, {"cost_usd": 0.0, "processed": []})
    return state["daily"][key]


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        log.error(f"Config not found: {CONFIG_PATH}")
        sys.exit(1)
    return json.loads(CONFIG_PATH.read_text())


# ── Time windows ───────────────────────────────────────────────────────────

DAY_MAP = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}


def is_within_window(windows: list, timezone: str) -> bool:
    tz  = ZoneInfo(timezone)
    now = datetime.now(tz)
    wd  = now.weekday()

    for w in windows:
        # Parse days: "mon-fri" or "sat,sun"
        days_str = w["days"]
        if "-" in days_str:
            a, b = days_str.split("-")
            active = set(range(DAY_MAP[a], DAY_MAP[b] + 1))
        else:
            active = {DAY_MAP[d.strip()] for d in days_str.split(",")}

        if wd not in active:
            continue

        t_from = dtime(*map(int, w["from"].split(":")))
        t_to   = dtime(*map(int, w["to"].split(":")))
        t_now  = now.time().replace(second=0, microsecond=0)

        # Overnight window e.g. 22:00 → 07:00
        if t_from > t_to:
            if t_now >= t_from or t_now < t_to:
                return True
        else:
            if t_from <= t_now < t_to:
                return True

    return False


# ── GitHub ─────────────────────────────────────────────────────────────────

def fetch_open_issues(repo: str, labels: list) -> list:
    params = {"state": "open", "per_page": 20}
    if labels:
        params["labels"] = ",".join(labels)

    resp = requests.get(
        f"https://api.github.com/repos/{repo}/issues",
        headers={
            "Authorization": f"Bearer {GITHUB_TOKEN}",
            "Accept": "application/vnd.github+json",
        },
        params=params,
        timeout=15,
    )
    resp.raise_for_status()
    return [i for i in resp.json() if "pull_request" not in i]


# ── Notifications ──────────────────────────────────────────────────────────

def notify(event: str, text: str, config: dict):
    notif = config.get("notifications", {})
    if not notif.get("telegram", False):
        return
    if event not in notif.get("events", []):
        return

    # OpenClaw HTTP API — adjust the endpoint if needed.
    # The gateway exposes an API at OPENCLAW_URL (default http://localhost:18789).
    # Check your OpenClaw docs / Control UI for the correct message endpoint.
    endpoint = f"{OPENCLAW_URL}/api/v1/message"
    try:
        r = requests.post(
            endpoint,
            json={"text": text, "channel": "telegram"},
            headers={"Authorization": f"Bearer {OPENCLAW_TOKEN}"},
            timeout=5,
        )
        if r.status_code not in (200, 201, 204):
            log.warning(f"Notification failed {r.status_code}: {r.text[:200]}")
    except Exception as e:
        log.warning(f"Notification error: {e}")


# ── Jobs ───────────────────────────────────────────────────────────────────

def issue_key(repo: str, number: int) -> str:
    return f"{repo}#{number}"


async def start_job(issue: dict, project: dict, config: dict):
    repo    = project["repo"]
    number  = issue["number"]
    key     = issue_key(repo, number)
    limits  = config.get("limits", {})
    claude  = config.get("claude", {})

    # Clone or fetch repo
    repo_name = repo.split("/")[1]
    repo_dir  = PROJECTS_DIR / repo_name
    PROJECTS_DIR.mkdir(parents=True, exist_ok=True)

    if not repo_dir.exists():
        log.info(f"Cloning {repo}...")
        clone_url = f"https://oauth2:{GITHUB_TOKEN}@github.com/{repo}.git"
        r = subprocess.run(["git", "clone", clone_url, str(repo_dir)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            log.error(f"Clone failed: {r.stderr}")
            return
    else:
        subprocess.run(["git", "-C", str(repo_dir), "fetch", "origin"],
                       capture_output=True)

    # Build prompt
    template = claude.get("issue_prompt_template", DEFAULT_PROMPT)
    prompt = template.format(
        repo=repo,
        number=number,
        title=issue["title"],
        body=issue.get("body") or "(no description)",
        branch=project.get("branch", "main"),
        repo_path=str(repo_dir),
    )

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    log_path = LOGS_DIR / f"{repo_name}-{number}.log"
    log_handle = open(log_path, "w")

    max_turns = limits.get("max_turns_per_issue", 50)
    base_cmd  = claude.get("command", "claude --dangerously-skip-permissions")
    cmd = base_cmd.split() + ["--max-turns", str(max_turns), "-p", prompt]

    log.info(f"Starting job {key} (max_turns={max_turns})")

    process = await asyncio.create_subprocess_exec(
        *cmd,
        cwd=str(repo_dir),
        stdout=log_handle,
        stderr=asyncio.subprocess.STDOUT,
        env={**os.environ, "HOME": str(Path.home()), "TERM": "dumb"},
    )

    _active_jobs[key] = {
        "process":    process,
        "pid":        process.pid,
        "started_at": datetime.now().isoformat(),
        "log_path":   str(log_path),
        "log_handle": log_handle,
        "repo":       repo,
        "number":     number,
        "title":      issue["title"],
    }

    notify("start", f"Starting #{number}: {issue['title']}\nRepo: {repo}", config)


async def check_completed_jobs(state: dict, config: dict):
    tz      = config.get("schedule", {}).get("timezone", "UTC")
    day     = day_state(state, tz)
    done    = []

    for key, job in _active_jobs.items():
        if job["process"].returncode is None:
            continue  # still running

        done.append(key)
        job["log_handle"].close()
        exit_code = job["process"].returncode

        # Parse cost from log output
        cost = 0.0
        try:
            log_text = Path(job["log_path"]).read_text()
            m = re.search(r"Total cost:\s+\$?([\d.]+)", log_text)
            if m:
                cost = float(m.group(1))
        except Exception:
            pass

        day["cost_usd"] += cost
        if key not in day["processed"]:
            day["processed"].append(key)

        status = "success" if exit_code == 0 else f"error (exit {exit_code})"
        icon   = "✅" if exit_code == 0 else "❌"

        log.info(f"Job done: {key} | {status} | cost=${cost:.2f}")
        notify(
            "complete" if exit_code == 0 else "error",
            f"{icon} #{job['number']}: {job['title']}\n"
            f"Repo: {job['repo']}\n"
            f"Status: {status} | Cost: ${cost:.2f}",
            config,
        )

    for key in done:
        del _active_jobs[key]


# ── Main loop ──────────────────────────────────────────────────────────────

async def sleep_interruptible(seconds: float, shutdown: asyncio.Event):
    """Sleep for `seconds` or until shutdown is set."""
    try:
        await asyncio.wait_for(shutdown.wait(), timeout=seconds)
    except asyncio.TimeoutError:
        pass


async def main():
    log.info("Claude Dev Orchestrator starting")

    shutdown = asyncio.Event()
    loop     = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, shutdown.set)

    state = load_state()

    while not shutdown.is_set():
        try:
            config   = load_config()
            limits   = config.get("limits", {})
            schedule = config.get("schedule", {})
            tz       = schedule.get("timezone", "UTC")

            poll_secs = limits.get("poll_interval_minutes", 15) * 60

            # Always check for completed jobs first
            await check_completed_jobs(state, config)
            save_state(state)

            # Outside active window → short sleep, try again
            if not is_within_window(schedule.get("windows", []), tz):
                log.debug("Outside active window")
                await sleep_interruptible(60, shutdown)
                continue

            # Daily cost limit
            day         = day_state(state, tz)
            max_cost    = limits.get("max_cost_per_day_usd", 10.0)
            if day["cost_usd"] >= max_cost:
                log.warning(f"Daily cost limit reached: ${day['cost_usd']:.2f} / ${max_cost:.2f}")
                notify("quota_warning",
                       f"Daily cost limit reached: ${day['cost_usd']:.2f}", config)
                await sleep_interruptible(300, shutdown)
                continue

            # Fill available parallel slots
            parallel_limit  = limits.get("parallel_issues", 2)
            available_slots = parallel_limit - len(_active_jobs)

            if available_slots > 0:
                for project in config.get("projects", []):
                    if available_slots <= 0:
                        break
                    try:
                        issues = fetch_open_issues(project["repo"],
                                                   project.get("labels", []))
                    except Exception as e:
                        log.error(f"GitHub error for {project['repo']}: {e}")
                        continue

                    for issue in issues:
                        if available_slots <= 0:
                            break
                        key = issue_key(project["repo"], issue["number"])
                        if key in _active_jobs or key in day["processed"]:
                            continue
                        await start_job(issue, project, config)
                        available_slots -= 1

        except Exception as e:
            log.error(f"Loop error: {e}", exc_info=True)

        await sleep_interruptible(poll_secs, shutdown)

    # Graceful shutdown: wait up to 30 s per job
    if _active_jobs:
        log.info(f"Waiting for {len(_active_jobs)} active job(s)…")
        for job in _active_jobs.values():
            try:
                await asyncio.wait_for(job["process"].wait(), timeout=30)
            except asyncio.TimeoutError:
                job["process"].terminate()

    save_state(state)
    log.info("Orchestrator stopped")


if __name__ == "__main__":
    asyncio.run(main())
