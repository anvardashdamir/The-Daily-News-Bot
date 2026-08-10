import Fluent
import Vapor

enum FeedType: String, Codable, Sendable {
    case rss
    case newsAPICategory = "newsapi_category"
}

/// A source of news the bot polls periodically. Feeds are shared/global — any user
/// can add one via /addfeed, and it becomes available to match against everyone's
/// interests. This keeps fetching efficient (each feed is fetched once, not once
/// per user).
final class Feed: Model, Content, @unchecked Sendable {
    static let schema = "feeds"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "type")
    var type: FeedType

    /// For .rss: the feed URL. For .newsAPICategory: the category name
    /// (business, entertainment, general, health, science, sports, technology).
    @Field(key: "value")
    var value: String

    @OptionalField(key: "display_name")
    var displayName: String?

    @Field(key: "is_active")
    var isActive: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, type: FeedType, value: String, displayName: String? = nil, isActive: Bool = true) {
        self.id = id
        self.type = type
        self.value = value
        self.displayName = displayName
        self.isActive = isActive
    }
}
