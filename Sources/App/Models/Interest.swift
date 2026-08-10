import Fluent
import Vapor

/// A single keyword/topic a user wants to follow, e.g. "AI", "Swift", "Baku".
/// Matching against incoming articles is a case-insensitive substring check
/// against the article's title + summary (see NewsMatcher).
final class Interest: Model, Content, @unchecked Sendable {
    static let schema = "interests"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "keyword")
    var keyword: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, userID: User.IDValue, keyword: String) {
        self.id = id
        self.$user.id = userID
        self.keyword = keyword
    }
}
