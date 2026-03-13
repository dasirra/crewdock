# TOOLS.md - Scouter

Environment-specific tool notes for Scouter.

## xurl CLI (Twitter/X API v2)

[xurl](https://github.com/xdevplatform/xurl) is installed in the Docker image at `/usr/local/bin/xurl`.

### Key endpoints

**List tweets:**
```bash
xurl api get /2/lists/:list_id/tweets \
  --query "tweet.fields=created_at,author_id,text" \
  --query "max_results=20"
```

**Search recent tweets:**
```bash
xurl api get /2/tweets/search/recent \
  --query "query=<keyword>" \
  --query "tweet.fields=created_at,author_id,text" \
  --query "max_results=20"
```

**User mentions:**
```bash
xurl api get /2/users/:user_id/mentions \
  --query "tweet.fields=created_at,author_id,text" \
  --query "max_results=20"
```

### Rate limits
Rate limits are per-app, not per-endpoint. If xurl returns HTTP 429, skip Twitter for this cycle and note it in the Discord report. Do not retry.

### Auth
xurl manages its own auth via `xurl auth`. Tokens are stored in `~/.xurl/`. Auth must be configured during initial setup (not automated).

## HTTP tools

Use the gateway's HTTP tool to fetch RSS feeds.

### RSS parsing
Fetch the URL, then parse the XML response:
- Atom feeds: look for `<entry>` elements with `<title>`, `<link>`, `<published>`
- RSS 2.0 feeds: look for `<item>` elements with `<title>`, `<link>`, `<pubDate>`

## Browser tool

Use the gateway's browser tool for pages that require JavaScript rendering (e.g., GitHub Trending).

Extract relevant items from the rendered DOM. Each page may need different selectors.

## scouter-db.sh

SQLite helper at `$HOME/.openclaw/workspace/agents/scouter/scouter-db.sh`.
Run with no args to see all available commands.

## Discord

Post reports and read user commands via the gateway's Discord integration.
Scouter's channel: **The Watchtower**.
