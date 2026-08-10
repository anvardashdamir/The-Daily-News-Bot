import Vapor

/// Thin client for https://newsapi.org's top-headlines endpoint.
/// Free tier: 100 requests/day, so the scheduler's poll interval should be
/// set conservatively (see Scheduler.swift) if NewsAPI categories are in use.
struct NewsAPIService {
    let client: Client
    let apiKey: String
    let logger: Logger

    /// Fetches top headlines for a category like "technology", "business", etc.
    func fetchTopHeadlines(category: String, country: String = "us") async -> [ParsedFeedItem] {
        let uri = URI(string: "https://newsapi.org/v2/top-headlines?category=\(category)&country=\(country)&pageSize=20")
        do {
            let response = try await client.get(uri) { req in
                req.headers.add(name: "X-Api-Key", value: apiKey)
            }
            guard response.status == .ok else {
                logger.warning("NewsAPI request failed with status \(response.status) for category \(category)")
                return []
            }
            let decoded = try response.content.decode(NewsAPIResponse.self)
            return decoded.articles.compactMap { article in
                guard let title = article.title, let url = article.url else { return nil }
                return ParsedFeedItem(
                    title: title,
                    link: url,
                    summary: article.description,
                    publishedAt: article.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) },
                    imageURL: article.urlToImage
                )
            }
        } catch {
            logger.error("NewsAPI fetch error for category \(category): \(error)")
            return []
        }
    }
}

private struct NewsAPIResponse: Content {
    let status: String
    let articles: [NewsAPIArticle]
}

private struct NewsAPIArticle: Content {
    let title: String?
    let description: String?
    let url: String?
    let publishedAt: String?
    let urlToImage: String?
}
