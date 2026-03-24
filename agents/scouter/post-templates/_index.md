# Post Templates

Reference for draft generation. Select the template that matches the content type, then read its file for the exact structure.

## Available Templates

| Template | File | Description |
|---|---|---|
| `library-review` | `library-review.md` | Comment on a GitHub repo or open-source project |
| `reply` | `reply.md` | Respond to someone's tweet |
| `quote-tweet` | `quote-tweet.md` | Cite a tweet adding your own take |
| `original-take` | `original-take.md` | Personal opinion on a topic or trend |
| `thread` | `thread.md` | Multi-tweet thread on a topic |
| `news-commentary` | `news-commentary.md` | React to a news item or announcement |
| `resource-share` | `resource-share.md` | Share a useful article, paper, or tool |
| `build-log` | `build-log.md` | Show something you're building or learning |

## Behavioral Categories

| Category | Types | Requirement |
|---|---|---|
| **Link-first** | library-review, news-commentary, resource-share | Visit URL, read content, understand context before drafting |
| **Context-first** | reply, quote-tweet | Original tweet/post is required as context |
| **Standalone** | original-take, thread, build-log | No external source needed |

## Template Selection

**During scan cycles:**
- Tweet from someone -> `reply` or `quote-tweet`
- Link to a GitHub repo -> `library-review`
- Link to an article or announcement -> `news-commentary` or `resource-share`
- Recurring topic trend across multiple briefing items -> `original-take` or `thread`

**During interactive commands:**
- `analyze [url]` -> detect URL type (GitHub repo, article, tweet) and select matching template
- `write about [topic]` -> `original-take` by default, `thread` if the topic needs multiple points
- User can force a type: `write thread about [topic]`, `analyze [url] as resource-share`
