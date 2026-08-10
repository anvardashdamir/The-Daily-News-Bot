import Fluent

struct AddArticleImageURL: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("articles")
            .field("image_url", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("articles")
            .deleteField("image_url")
            .update()
    }
}
