import Vapor
import Fluent

struct BotCommandHandler {
    let app: Application
    let telegram: TelegramService

    func handle(update: TelegramUpdate, on db: Database) async {
        guard let message = update.message, let text = message.text else { return }
        let chatID = message.chat.id
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = trimmed.split(separator: " ", maxSplits: 1)
        let command = parts.first.map(String.init)?.lowercased() ?? ""
        let argument = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : nil

        do {
            let user = try await findOrCreateUser(chatID: chatID, username: message.from?.username, on: db)

            switch command {
            case "/start":
                await telegram.sendMessage(chatID: chatID, text: Self.welcomeText)

            case "/help":
                await telegram.sendMessage(chatID: chatID, text: Self.helpText)

            case "/add":
                guard let keyword = argument, !keyword.isEmpty else {
                    await telegram.sendMessage(chatID: chatID, text: "Usage: /add <keyword>\nExample: /add Swift")
                    return
                }
                try await addInterest(keyword: keyword, to: user, on: db)
                await telegram.sendMessage(chatID: chatID, text: "✅ Added \"\(keyword)\" to your interests. You'll get news mentioning it as it comes in.")

            case "/remove":
                guard let keyword = argument, !keyword.isEmpty else {
                    await telegram.sendMessage(chatID: chatID, text: "Usage: /remove <keyword>")
                    return
                }
                try await removeInterest(keyword: keyword, from: user, on: db)
                await telegram.sendMessage(chatID: chatID, text: "🗑️ Removed \"\(keyword)\" from your interests.")

            case "/list":
                try await sendInterestList(to: user, on: db)

            case "/addfeed":
                guard let url = argument, !url.isEmpty else {
                    await telegram.sendMessage(chatID: chatID, text: "Usage: /addfeed <rss_url>")
                    return
                }
                try await addFeed(url: url, on: db)
                await telegram.sendMessage(chatID: chatID, text: "✅ Feed added. It'll be checked on the next fetch cycle.")

            case "/sources":
                try await sendSourceList(to: chatID, on: db)

            default:
                await telegram.sendMessage(chatID: chatID, text: "Unrecognized command. Send /help to see what I can do.")
            }
        } catch {
            app.logger.error("Error handling update for chat \(chatID): \(error)")
            await telegram.sendMessage(chatID: chatID, text: "Something went wrong handling that. Please try again.")
        }
    }

    private func findOrCreateUser(chatID: Int64, username: String?, on db: Database) async throws -> User {
        if let existing = try await User.query(on: db).filter(\.$telegramChatID == chatID).first() {
            return existing
        }
        let user = User(telegramChatID: chatID, username: username)
        try await user.save(on: db)
        return user
    }

    private func addInterest(keyword: String, to user: User, on db: Database) async throws {
        guard let userID = user.id else { return }
        let normalized = keyword.lowercased()
        let existing = try await Interest.query(on: db)
            .filter(\.$user.$id == userID)
            .filter(\.$keyword == normalized)
            .first()
        guard existing == nil else { return }
        let interest = Interest(userID: userID, keyword: normalized)
        try await interest.save(on: db)
    }

    private func removeInterest(keyword: String, from user: User, on db: Database) async throws {
        guard let userID = user.id else { return }
        let normalized = keyword.lowercased()
        try await Interest.query(on: db)
            .filter(\.$user.$id == userID)
            .filter(\.$keyword == normalized)
            .delete()
    }

    private func sendInterestList(to user: User, on db: Database) async throws {
        guard let userID = user.id else { return }
        let interests = try await Interest.query(on: db).filter(\.$user.$id == userID).all()
        if interests.isEmpty {
            await telegram.sendMessage(chatID: user.telegramChatID, text: "You have no interests yet. Add one with /add <keyword>.")
        } else {
            let list = interests.map { "• \($0.keyword)" }.joined(separator: "\n")
            await telegram.sendMessage(chatID: user.telegramChatID, text: "Your interests:\n\(list)")
        }
    }

    private func sendSourceList(to chatID: Int64, on db: Database) async throws {
        let feeds = try await Feed.query(on: db).filter(\.$isActive == true).all()
        if feeds.isEmpty {
            await telegram.sendMessage(chatID: chatID, text: "No active sources yet.")
            return
        }
        let list = feeds.map { "• \($0.displayName ?? $0.value)" }.joined(separator: "\n")
        await telegram.sendMessage(chatID: chatID, text: "Currently active sources:\n\(list)\n\nAdd your own with /addfeed <rss_url>.")
    }

    private func addFeed(url: String, on db: Database) async throws {
        let existing = try await Feed.query(on: db)
            .filter(\.$type == .rss)
            .filter(\.$value == url)
            .first()
        guard existing == nil else { return }
        let feed = Feed(type: .rss, value: url)
        try await feed.save(on: db)
    }

    static let welcomeText = """
    👋 Welcome! I send you news the moment it happens — matched to topics you choose, instead of you having to check a news app.

    Get started:
    /add <keyword> — follow a topic (e.g. /add Swift)
    /list — see your current topics
    /help — full command list
    """

    static let helpText = """
    Commands:
    /add <keyword> — follow a new topic
    /remove <keyword> — stop following a topic
    /list — show your current topics
    /addfeed <rss_url> — add an RSS feed to the pool of sources I check
    /sources — see which outlets I'm currently pulling from
    /help — this message
    """
}
