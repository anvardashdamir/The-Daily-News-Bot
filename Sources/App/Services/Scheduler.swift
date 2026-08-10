import Vapor
import Fluent

/// Owns the two long-running background loops the bot needs:
///  1. Telegram long-polling — receives /add, /remove, /list, /addfeed etc. in near
///     real time (Telegram holds the connection open up to `timeout` seconds).
///  2. Periodic news fetch — every `fetchIntervalSeconds`, pulls all feeds, stores
///     new articles, and pushes matches to interested users.
/// Both run as detached Tasks started from configure.swift and simply loop until
/// the app shuts down.
final class Scheduler: @unchecked Sendable {
    let app: Application
    let telegram: TelegramService
    let commandHandler: BotCommandHandler
    let newsFetcher: NewsFetcher
    let fetchIntervalSeconds: UInt64

    private var pollingTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?

    init(app: Application, telegramToken: String, newsAPIKey: String?, fetchIntervalSeconds: UInt64) {
        self.app = app
        self.telegram = TelegramService(client: app.client, token: telegramToken, logger: app.logger)
        self.commandHandler = BotCommandHandler(app: app, telegram: telegram)
        self.newsFetcher = NewsFetcher(app: app, telegram: telegram, newsAPIKey: newsAPIKey)
        self.fetchIntervalSeconds = fetchIntervalSeconds
    }

    func start() {
        pollingTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
        fetchTask = Task { [weak self] in
            await self?.runFetchLoop()
        }
    }

    func shutdown() {
        pollingTask?.cancel()
        fetchTask?.cancel()
    }

    private func runPollingLoop() async {
        var offset: Int64?
        app.logger.info("Telegram long-polling loop started.")
        while !Task.isCancelled {
            do {
                let updates = try await telegram.getUpdates(offset: offset)
                for update in updates {
                    await commandHandler.handle(update: update, on: app.db)
                    offset = update.updateID + 1
                }
            } catch {
                app.logger.error("Polling error: \(error). Retrying in 5s.")
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func runFetchLoop() async {
        app.logger.info("News fetch loop started (every \(fetchIntervalSeconds)s).")
        while !Task.isCancelled {
            await newsFetcher.runOnce(on: app.db)
            try? await Task.sleep(for: .seconds(fetchIntervalSeconds))
        }
    }
}
