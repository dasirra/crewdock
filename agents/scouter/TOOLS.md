# TOOLS.md - Scouter

Environment-specific tool notes for Scouter.

## xurl CLI (Twitter/X API v2)

[xurl](https://github.com/xdevplatform/xurl) is installed in the Docker image. Auth is managed via `xurl auth` and stored in `~/.xurl/`.

### Reading from an X List

The only Twitter endpoint Scouter uses. Reads recent tweets from a predefined X List.

```bash
xurl "/2/lists/<list_id>/tweets?max_results=10&tweet.fields=created_at,author_id,text&expansions=author_id&user.fields=username,name"
```

Response includes `data[]` (tweets) and `includes.users[]` (author info). Each tweet has `id`, `text`, `created_at`, `author_id`. Expansion resolves `author_id` to username/name.

### Auth and list visibility

xurl uses a **Bearer Token** (app-only auth). This only grants access to **public** lists and tweets. Private or protected lists return a "not found" error even if the list ID is correct.

If the user's list is private, they have two options:
1. Make the list public on X (simplest).
2. Switch to OAuth 2.0 User Context auth (complex, requires user login flow).

On "list not found" errors, suggest checking list visibility before assuming the ID is wrong.

### Cost control

Twitter API uses consumption-based billing:
- **Tweet read**: $0.005 per tweet returned
- **User lookup**: $0.010 per user (avoid; use `expansions=author_id` instead)
- **List read**: $0.005 per item

Budget: $5 credit. At 10 tweets x 2 scans/day = $0.10/day (~50 days).

**Rules:**
- Always set `max_results=10` (or the value from config.json).
- Never use search endpoints, keyword queries, or mentions.
- Never call user lookup separately; use tweet expansions to get author info.
- On any API error, skip Twitter for this cycle. Do not retry.

### Shortcut commands (reference only)

These are available but NOT used in scan cycles:
- `xurl search "query" -n 10` — search recent tweets (costs $0.005/tweet)
- `xurl user <username>` — lookup user profile (costs $0.010/user)
- `xurl read <tweet_id>` — read a single tweet (costs $0.005)

## HTTP tools

Use the gateway's HTTP tool to fetch RSS feeds.

### RSS parsing
Fetch the URL, then parse the XML response:
- Atom feeds: look for `<entry>` elements with `<title>`, `<link>`, `<published>`
- RSS 2.0 feeds: look for `<item>` elements with `<title>`, `<link>`, `<pubDate>`

## Web sources (HTTP fetch)

Use the gateway's HTTP tool (or `web_fetch`) to fetch web pages. Most pages Scouter monitors (e.g., GitHub Trending) are server-side rendered and do not require a browser.

Parse the HTML response to extract relevant items (trending repos, headlines, etc.). Each page may need different selectors or patterns.

## scouter-db.sh

SQLite helper at `$HOME/.openclaw/workspace/agents/scouter/scouter-db.sh`.
Run with no args to see all available commands.

## Discord

Post reports and read user commands via the gateway's Discord integration.
Scouter's channel: **The Watchtower**.
