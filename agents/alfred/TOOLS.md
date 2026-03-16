# TOOLS.md - Alfred

Environment-specific tool notes for Alfred.

## Google Workspace (GWS)

Alfred uses OpenClaw's built-in `gws` CLI for all Google Workspace operations. GWS is configured at the gateway level and available to all agents.

### Available commands

```bash
gws calendar list [--from DATE] [--to DATE]    # List events
gws calendar create                             # Create event (interactive)
gws gmail unread [--max N]                      # List unread emails
gws gmail read <message-id>                     # Read specific email
gws gmail send                                  # Compose and send email
gws tasks list [--status STATUS]                # List tasks
gws tasks create                                # Create task
gws tasks complete <task-id>                    # Mark task done
```

### Notes

- All date/time operations use the timezone from `config.json`.
- GWS commands return JSON. Parse the output for briefing composition.
- If a GWS command fails, include an error note in that briefing section instead of failing the entire briefing.

## Discord

Post briefings and read user commands via the gateway's Discord integration.
