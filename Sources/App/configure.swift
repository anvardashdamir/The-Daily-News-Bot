import Vapor
import Fluent
import FluentSQLiteDriver

struct SchedulerKey: StorageKey {
    typealias Value = Scheduler
}

public func configure(_ app: Application) async throws {
    // MARK: Database
    app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
    app.migrations.add(CreateSchema())
    app.migrations.add(AddArticleImageURL())
    try await app.autoMigrate()

    // MARK: Required environment variables
    guard let telegramToken = Environment.get("TELEGRAM_BOT_TOKEN"), !telegramToken.isEmpty else {
        app.logger.critical("Missing TELEGRAM_BOT_TOKEN environment variable. See .env.example.")
        fatalError("TELEGRAM_BOT_TOKEN is required")
    }
    // Optional: without it, NewsAPI-backed feeds are simply skipped and RSS feeds still work.
    let newsAPIKey = Environment.get("NEWS_API_KEY")
    let fetchInterval = UInt64(Environment.get("FETCH_INTERVAL_SECONDS") ?? "300") ?? 300

    // MARK: Routes
    try routes(app)

    // MARK: Seed default feeds on first run (only if the table is empty)
    try await seedDefaultFeedsIfNeeded(app: app)

    // MARK: Start background loops
    let scheduler = Scheduler(
        app: app,
        telegramToken: telegramToken,
        newsAPIKey: newsAPIKey,
        fetchIntervalSeconds: fetchInterval
    )
    app.storage[SchedulerKey.self] = scheduler
    scheduler.start()

    app.logger.info("The Daily News Bot configured. Fetch interval: \(fetchInterval)s. NewsAPI: \(newsAPIKey == nil ? "disabled" : "enabled").")
}

/// Seeds a starter set of RSS feeds so the bot has something to match against
/// immediately after first launch, without requiring manual /addfeed calls.
///
/// Deliberately includes outlets from *both* sides of each conflict the user
/// cares about (Russia/Ukraine, Israel/Iran, USA/Iran) rather than only Western
/// sources — so a user following "Ukraine" or "Iran" sees how each side reports
/// on itself, not just how outside media covers them. Display names are tagged
/// with [Country · state-run] or [Country · independent] so it's clear in /list
/// output what kind of outlet each article came from — that context matters
/// more here than for, say, a tech feed.
///
/// NOTE: RSS URLs on smaller/regional/state outlets drift more often than major
/// wire services. These were verified via web search at build time, but since
/// this sandbox has no Swift toolchain to test-run the bot, double check each
/// one resolves once you run this locally (curl <url> is enough) and swap out
/// any that 404 — see README for a troubleshooting note on this.
private func seedDefaultFeedsIfNeeded(app: Application) async throws {
    let count = try await Feed.query(on: app.db).count()
    guard count == 0 else { return }

    let defaults: [(String, String)] = [
        // General / wire services (baseline, minimal editorial framing)
        ("https://feeds.bbci.co.uk/news/world/rss.xml", "BBC World News [UK]"),

        // Russia – Ukraine
        ("https://tass.com/rss/v2.xml", "TASS [Russia · state-run]"),
        ("https://www.rt.com/rss/", "RT [Russia · state-run]"),
        ("https://meduza.io/rss/all", "Meduza [Russia · independent, operates in exile]"),
        ("https://www.themoscowtimes.com/rss/news", "The Moscow Times [Russia · independent]"),
        ("https://kyivindependent.com/feed/", "Kyiv Independent [Ukraine · independent]"),
        ("https://www.ukrinform.net/rss/rubric-polytics", "Ukrinform [Ukraine · state]"),

        // Israel – Iran
        ("https://www.timesofisrael.com/feed/", "Times of Israel [Israel · independent]"),
        ("https://www.jpost.com/rss/rssfeedsfrontpage.aspx", "Jerusalem Post [Israel · independent]"),
        ("https://www.presstv.ir/rss.xml", "Press TV [Iran · state-run]"),
        ("https://www.tehrantimes.com/rss", "Tehran Times [Iran · state-linked]"),

        // Tech (kept from original defaults, useful for the iOS/dev portfolio angle)
        ("https://techcrunch.com/feed/", "TechCrunch"),
        ("http://feeds.arstechnica.com/arstechnica/index", "Ars Technica"),
    ]
    for (url, name) in defaults {
        let feed = Feed(type: .rss, value: url, displayName: name)
        try await feed.save(on: app.db)
    }
    app.logger.info("Seeded \(defaults.count) default RSS feeds.")
}
