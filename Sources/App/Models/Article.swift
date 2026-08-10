import Fluent
import Vapor

/// A news item pulled from a Feed. `linkHash` is a SHA256 of the canonical link
/// and is unique, so re-fetching the same feed never creates duplicates.
final class Article: Model, Content, @unchecked Sendable {
    static let schema = "articles"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "title")
    var title: String

    @OptionalField(key: "summary")
    var summary: String?

    @Field(key: "link")
    var link: String

    @Field(key: "link_hash")
    var linkHash: String

    @OptionalField(key: "source_name")
    var sourceName: String?

    /// URL of the article's lead image, if the feed provided one (RSS
    /// <enclosure>/<media:content>, or NewsAPI's urlToImage). Optional — plenty
    /// of feeds don't include one, in which case we fall back to a text-only
    /// message (see NewsFetcher.deliver).
    @OptionalField(key: "image_url")
    var imageURL: String?

    @OptionalField(key: "published_at")
    var publishedAt: Date?

    @Timestamp(key: "fetched_at", on: .create)
    var fetchedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        title: String,
        summary: String? = nil,
        link: String,
        linkHash: String,
        sourceName: String? = nil,
        imageURL: String? = nil,
        publishedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.link = link
        self.linkHash = linkHash
        self.sourceName = sourceName
        self.imageURL = imageURL
        self.publishedAt = publishedAt
    }
}
