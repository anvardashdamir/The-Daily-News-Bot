import Fluent
import Vapor

/// Records that a given Article was already delivered to a given User, so the
/// scheduler never sends the same article twice to the same person.
final class DeliveryLog: Model, Content, @unchecked Sendable {
    static let schema = "delivery_logs"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Parent(key: "article_id")
    var article: Article

    @Timestamp(key: "sent_at", on: .create)
    var sentAt: Date?

    init() {}

    init(id: UUID? = nil, userID: User.IDValue, articleID: Article.IDValue) {
        self.id = id
        self.$user.id = userID
        self.$article.id = articleID
    }
}
