# The Daily News Bot

A Telegram bot, written in **Swift (Vapor)**, that pushes news to you the moment
it happens — matched to topics you choose — instead of you having to open a news
app and scroll to find what matters.

## Why

Most news apps are pull-based: you open the app, browse, hope you didn't miss
anything. This bot flips that — you tell it what you care about once, and it
messages you as soon as something matching shows up.

It's also deliberately **multi-sided** on default sources. See `/sources` in
the bot, or `seedDefaultFeedsIfNeeded` in `configure.swift`.
The goal is to let you see how each side frames its own story, not to endorse
any of them.

## Features

- Users pick their own keywords/topics — no shared feed, everyone gets their
  own personalized stream
- Push delivery: a background loop polls all sources and forwards new matches
  immediately, no polling required on the user's end
- Mix of RSS feeds and NewsAPI categories as sources — anyone can add an RSS
  feed via `/addfeed`
- No public URL needed — uses Telegram long-polling, so it runs entirely
  locally
- SQLite storage (via Fluent) — zero external DB setup

## Bot commands

| Command | What it does |
|---|---|
| `/start` | Registers you and shows a welcome message |
| `/add <keyword>` | Follow a topic, e.g. `/add Swift` |
| `/remove <keyword>` | Stop following a topic |
| `/list` | Show your current topics |
| `/addfeed <rss_url>` | Add an RSS feed to the shared pool of sources |
| `/sources` | See every active source currently being checked |
| `/help` | Show all commands |

## Architecture

```
Sources/App/
├── entrypoint.swift        # @main entry point
├── configure.swift         # DB setup, migrations, env vars, default feed seeding
├── routes.swift            # health check endpoint
├── Models/
│   ├── User.swift          # a Telegram chat (person or channel)
│   ├── Interest.swift      # a keyword a user follows
│   ├── Feed.swift          # an RSS feed or NewsAPI category (shared, global)
│   ├── Article.swift       # a fetched news item, deduplicated by link hash
│   └── DeliveryLog.swift   # tracks what's already been sent to whom
├── Migrations/
│   └── CreateSchema.swift
└── Services/
    ├── TelegramService.swift    # sendMessage + long-polling getUpdates
    ├── RSSParser.swift          # hand-written RSS/Atom parser (no 3rd-party dep)
    ├── NewsAPIService.swift     # NewsAPI.org top-headlines client
    ├── NewsFetcher.swift        # fetch → store → match → deliver pipeline
    ├── BotCommandHandler.swift  # parses & responds to /commands
    └── Scheduler.swift          # owns the two background loops
```

Two background loops run for the app's lifetime:
1. **Telegram long-poll loop** — receives commands in near real time.
2. **News fetch loop** — every `FETCH_INTERVAL_SECONDS`, pulls all active
   feeds, stores new articles (deduplicated by a hash of the article link),
   matches them against every user's keywords, and sends matches via Telegram.

Matching is currently a case-insensitive substring check of each keyword
against the article's title + summary — simple, predictable, and a reasonable
v1. Swapping in something smarter (stemming, embeddings) later is a clean,
isolated change in `NewsMatcher`.

## Setup

### Requirements
- Swift 5.9+ (macOS 13+ or Linux)
- A Telegram bot token from [@BotFather](https://t.me/BotFather)
- (Optional) A free [NewsAPI.org](https://newsapi.org) API key

### 1. Create your bot
Message [@BotFather](https://t.me/BotFather) on Telegram, run `/newbot`,
follow the prompts, and copy the token it gives you.

### 2. Configure environment
```bash
cp .env.example .env
# edit .env and paste in your TELEGRAM_BOT_TOKEN
```

### 3. Build & run
```bash
swift build
swift run
```

On first run, the bot seeds a starter set of RSS feeds (see `configure.swift`)
and creates `db.sqlite` in the project root automatically.

### 4. Try it
Open a chat with your bot on Telegram and send `/start`.

## Using the bot on Telegram

Once it's running, everything happens inside a normal Telegram chat with your
bot — no separate app or website involved.

1. Open Telegram and search for your bot by the **username** you gave it in
   BotFather (e.g. `@cnvr_news_bot`), not its display name.
2. Send `/start` — you'll get a welcome message and you're registered.
3. Follow a topic with `/add <keyword>`, e.g.:
   ```
   /add SpaceX
   /add Swift
   /add Ukraine
   ```
   Add as many separate keywords as you want — each is tracked independently,
   and any article matching *any* of them gets sent to you.
4. Check what you're following anytime with `/list`, or drop one with
   `/remove <keyword>`.
5. See exactly which outlets are feeding the bot with `/sources`, or add your
   own with `/addfeed <rss_url>`.
6. Sit back — matching articles arrive as a photo + caption (or plain text if
   no image is available) as soon as the next fetch cycle finds them.

The bot only responds while the program is actively running (`swift run` in a
terminal, or deployed somewhere always-on — see Roadmap). If your Mac sleeps
or the terminal is closed, the bot goes quiet until it's started again.

### Troubleshooting
- **No messages arriving:** check the bot's console logs — a feed URL may have
  changed. Verify with `curl <feed_url>` and swap it via `/addfeed` (and
  removing the old one from the DB) if it's dead. RSS URLs on smaller/regional
  outlets drift more than major wire services.
- **NewsAPI 426/429 errors:** you've hit the free-tier daily cap. Either raise
  `FETCH_INTERVAL_SECONDS` or drop NewsAPI categories and rely on RSS only.

## Roadmap ideas
- Smarter matching (stemming / basic NLP instead of substring match)
- Digest mode (batched summary instead of one message per article)
- Deploy guide (Docker + a small VPS or Railway/Render)

## License
MIT — do whatever you'd like with it.
