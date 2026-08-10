import Vapor
import Fluent
import Crypto

/// The heart of the bot: fetches all active Feeds, stores newly-seen Articles,
/// matches them against every user's Interests, and delivers matches via Telegram
/// — skipping anything already logged in DeliveryLog so nobody gets duplicates.
struct NewsFetcher {
    let app: Application
    let telegram: TelegramService
    let newsAPIKey: String?

    func runOnce(on db: Database) async {
        let feeds: [Feed]
        do {
            feeds = try await Feed.query(on: db).filter(\.$isActive == true).all()
        } catch {
            app.logger.error("Failed to load feeds: \(error)")
            return
        }

        var newArticles: [Article] = []

        for feed in feeds {
            let items: [ParsedFeedItem]
            switch feed.type {
            case .rss:
                items = await fetchRSS(url: feed.value)
            case .newsAPICategory:
                guard let newsAPIKey else { continue }
                let service = NewsAPIService(client: app.client, apiKey: newsAPIKey, logger: app.logger)
                items = await service.fetchTopHeadlines(category: feed.value)
            }

            for item in items {
                if let stored = await storeIfNew(item: item, sourceName: feed.displayName ?? feed.value, on: db) {
                    newArticles.append(stored)
                }
            }
        }

        guard !newArticles.isEmpty else {
            app.logger.info("News fetch cycle: no new articles.")
            return
        }
        app.logger.info("News fetch cycle: \(newArticles.count) new article(s). Matching against user interests...")

        await matchAndDeliver(articles: newArticles, on: db)
    }

    private func fetchRSS(url: String) async -> [ParsedFeedItem] {
        do {
            let response = try await app.client.get(URI(string: url))
            guard let buffer = response.body else { return [] }
            let data = Data(buffer: buffer)
            return RSSParser.parse(data: data)
        } catch {
            app.logger.error("Failed to fetch RSS feed \(url): \(error)")
            return []
        }
    }

    /// Inserts the article if we haven't seen this link before. Returns the
    /// stored Article on success, or nil if it was a duplicate (or failed).
    private func storeIfNew(item: ParsedFeedItem, sourceName: String, on db: Database) async -> Article? {
        let hash = SHA256.hash(data: Data(item.link.utf8)).map { String(format: "%02x", $0) }.joined()

        let existing = try? await Article.query(on: db).filter(\.$linkHash == hash).first()
        if existing != nil {
            return nil
        }

        let article = Article(
            title: item.title,
            summary: item.summary,
            link: item.link,
            linkHash: hash,
            sourceName: sourceName,
            imageURL: item.imageURL,
            publishedAt: item.publishedAt
        )
        do {
            try await article.save(on: db)
            return article
        } catch {
            // Likely a unique constraint race; treat as duplicate.
            return nil
        }
    }

    private func matchAndDeliver(articles: [Article], on db: Database) async {
        let users: [User]
        do {
            users = try await User.query(on: db)
                .filter(\.$isActive == true)
                .with(\.$interests)
                .all()
        } catch {
            app.logger.error("Failed to load users for matching: \(error)")
            return
        }

        for user in users {
            guard !user.interests.isEmpty else { continue }
            for article in articles {
                guard NewsMatcher.matches(article: article, interests: user.interests) else { continue }

                do {
                    guard let userID = user.id, let articleID = article.id else { continue }
                    let alreadySent = try await DeliveryLog.query(on: db)
                        .filter(\.$user.$id == userID)
                        .filter(\.$article.$id == articleID)
                        .first()
                    if alreadySent != nil { continue }

                    await deliver(article: article, to: user.telegramChatID)

                    let log = DeliveryLog(userID: userID, articleID: articleID)
                    try await log.save(on: db)
                } catch {
                    app.logger.error("Failed to deliver article \(article.id?.uuidString ?? "?") to user \(user.telegramChatID): \(error)")
                }
            }
        }
    }

    /// Sends the article as a photo (image + caption) when we have an image
    /// URL, falling back to a plain text message when we don't — or when the
    /// image fails to send (broken URL, host blocking Telegram's fetcher, etc.).
    private func deliver(article: Article, to chatID: Int64) async {
        let text = formatMessage(article)
        if let imageURL = article.imageURL, !imageURL.isEmpty {
            let sent = await telegram.sendPhoto(chatID: chatID, photoURL: imageURL, caption: text)
            if sent { return }
        }
        await telegram.sendMessage(chatID: chatID, text: text)
    }

    /// Title, summary, and source only — no raw link, per the current message
    /// design. If the image-fallback path (no imageURL) is used, this is sent
    /// as a plain sendMessage instead of a photo caption.
    private func formatMessage(_ article: Article) -> String {
        var text = "📰 <b>\(escapeHTML(article.title))</b>\n"
        if let summary = article.summary, !summary.isEmpty {
            let trimmed = summary.count > 300 ? String(summary.prefix(300)) + "…" : summary
            text += "\n\(escapeHTML(trimmed))\n"
        }
        if let source = article.sourceName {
            text += "\n<i>\(escapeHTML(source))</i>"
        }
        return text
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

enum NewsMatcher {
    /// Case-insensitive substring match of each interest keyword against the
    /// article's title + summary. Simple by design — easy to reason about and
    /// good enough for a v1; swap in a smarter matcher (stemming, NLP) later.
    static func matches(article: Article, interests: [Interest]) -> Bool {
        let haystack = ((article.title) + " " + (article.summary ?? "")).lowercased()
        for interest in interests {
            if haystack.contains(interest.keyword.lowercased()) {
                return true
            }
        }
        return false
    }
}
