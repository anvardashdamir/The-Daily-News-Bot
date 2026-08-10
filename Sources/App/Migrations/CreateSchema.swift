import Fluent

struct CreateSchema: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .id()
            .field("telegram_chat_id", .int64, .required)
            .field("username", .string)
            .field("is_active", .bool, .required, .sql(.default(true)))
            .field("created_at", .datetime)
            .unique(on: "telegram_chat_id")
            .create()

        try await database.schema("interests")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("keyword", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "user_id", "keyword")
            .create()

        try await database.schema("feeds")
            .id()
            .field("type", .string, .required)
            .field("value", .string, .required)
            .field("display_name", .string)
            .field("is_active", .bool, .required, .sql(.default(true)))
            .field("created_at", .datetime)
            .unique(on: "type", "value")
            .create()

        try await database.schema("articles")
            .id()
            .field("title", .string, .required)
            .field("summary", .string)
            .field("link", .string, .required)
            .field("link_hash", .string, .required)
            .field("source_name", .string)
            .field("published_at", .datetime)
            .field("fetched_at", .datetime)
            .unique(on: "link_hash")
            .create()

        try await database.schema("delivery_logs")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("article_id", .uuid, .required, .references("articles", "id", onDelete: .cascade))
            .field("sent_at", .datetime)
            .unique(on: "user_id", "article_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("delivery_logs").delete()
        try await database.schema("articles").delete()
        try await database.schema("feeds").delete()
        try await database.schema("interests").delete()
        try await database.schema("users").delete()
    }
}
