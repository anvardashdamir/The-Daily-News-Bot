import Fluent
import Vapor

/// A Telegram user who has interacted with the bot (via a private chat or by adding
/// the bot to a channel/group that then acts as the "chat" we push news to).
final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    /// Telegram's chat id. For a private chat this is the user's own id.
    /// For a channel, this is the channel's chat id (e.g. -100xxxxxxxxxx).
    @Field(key: "telegram_chat_id")
    var telegramChatID: Int64

    /// Optional friendly name / username, for display in logs only.
    @OptionalField(key: "username")
    var username: String?

    @Field(key: "is_active")
    var isActive: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Children(for: \.$user)
    var interests: [Interest]

    init() {}

    init(id: UUID? = nil, telegramChatID: Int64, username: String? = nil, isActive: Bool = true) {
        self.id = id
        self.telegramChatID = telegramChatID
        self.username = username
        self.isActive = isActive
    }
}
