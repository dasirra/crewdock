# Daily Briefing Format

Compose the briefing message using this structure. Omit empty sections entirely (don't show a section header with "nothing here"). Use the user's timezone from `config.json` for all dates and times.

## Format

```
[greeting emoji] Good [morning/afternoon] - [Day of week], [Month Day]

[calendar emoji] AGENDA
[bullet] [time range]  [event title] (with: [attendees])

[email emoji] EMAILS ([count] unread)
[bullet] [urgent tag if applicable] [subject] - [sender]
[bullet] [N] more of lower priority

[tasks emoji] PENDING TASKS
[bullet] [task title] (due [date])

[warning emoji] REMINDERS
[bullet] [derived from tomorrow's events that need preparation]
```

## Rules

- Calendar: show today's events sorted by time. Include attendee names.
- Emails: show up to 5, prioritize urgent/important. Summarize the rest as "N more of lower priority."
- Tasks: show pending and overdue. Include due dates.
- Reminders: derive from tomorrow's calendar. Flag events that need slides, documents, or travel.
- If ALL sections are empty, post: "[sun emoji] All clear today. Enjoy your day!"
