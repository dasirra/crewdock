# CrewDock

A self-hosted AI crew that runs 24/7 on your server. Four specialized agents working autonomously in Docker, built on [OpenClaw](https://github.com/openclaw/openclaw).

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-required-blue?logo=docker)](https://www.docker.com/)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-2026.3.13--1-purple)](https://github.com/openclaw/openclaw)

## Architecture

```mermaid
graph TB
    subgraph CrewDock ["CrewDock (Docker)"]
        GW[OpenClaw Gateway]

        GW --> Overlord["Overlord<br/><i>System Admin</i>"]
        GW --> Forge["Forge<br/><i>Dev Autopilot</i>"]
        GW --> Alfred["Alfred<br/><i>Personal Assistant</i>"]
        GW --> Scouter["Scouter<br/><i>Intel Radar</i>"]
    end

    Overlord -.-> |config management| GW
    Forge --> |worktrees + PRs| GitHub
    Alfred --> |read/write| Google["Google Workspace"]
    Scouter --> |monitor| Sources["RSS / Twitter / Web"]

    Discord <--> GW
```

## What is CrewDock

CrewDock turns a Docker host into a 24/7 AI operations center. It runs
[OpenClaw](https://github.com/openclaw/openclaw) as the gateway, adds four
specialized agents, and wires everything to Discord so you can monitor and
interact from your phone.

The agents run on cron schedules or on demand. Each one has its own workspace,
config, and database. You deploy once and they take it from there.
