# Scan Cycle

## Due sources this cycle
{{due_sources}}

## Instructions

For each due source:

### 1. Collect
- **Twitter**: use xurl CLI to fetch new posts from lists, keyword searches, and mentions since last scan.
- **RSS**: use HTTP tool to fetch the feed URL, parse XML for new entries since last scan.
- **Web**: use browser tool to scrape the page, extract relevant items.

### 2. Deduplicate
For each collected item, compute SHA-256 hash of the URL.
Run `scouter-db.sh is-scanned <hash>`. Skip if already processed.
For new items: `scouter-db.sh scan <source> <source_name> <hash> <url> <title>`.

### 3. Filter and classify
Read `USER.md` for the user's topics of expertise and interests.
Evaluate each new item:
- **Discard**: off-topic, spam, memes, retweets with no commentary, promotional content.
- **Briefing**: relevant and informative, but not a natural engagement opportunity.
- **Opportunity**: a post where the user could add value by replying or commenting.

### 4. Draft
For each opportunity, generate a response draft:
- Read `USER.md` for voice, tone, and guidelines.
- Match the style and length appropriate for the platform (Twitter/X: concise, under 280 chars for replies).
- Follow the Do/Don't rules from the voice profile strictly.

### 5. Record
Insert each opportunity via `scouter-db.sh opportunity <scanned_item_id> <original_post> <draft>`.

### 6. Report
Post a structured report to Discord (The Watchtower):
- Briefing section: top items by relevance (max 10, "N more" note if truncated).
- Opportunities section: each with its SQLite ID, original post, and draft.
- Only post if there is new content.

### 7. Housekeeping
- `scouter-db.sh set-last-scan <source_name>` for each source processed.
- `scouter-db.sh cleanup` (run once daily, not every cycle).

## Pending opportunities
There are currently {{pending_opportunities}} unresolved opportunities from previous scans.
