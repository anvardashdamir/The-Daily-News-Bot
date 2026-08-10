import Foundation

struct ParsedFeedItem {
    let title: String
    let link: String
    let summary: String?
    let publishedAt: Date?
    let imageURL: String?
}

/// Parses both RSS 2.0 (<item>) and Atom (<entry>) feeds without any third-party
/// dependency. Written by hand against the two formats' common fields; feeds that
/// use unusual extensions may lose optional fields (summary/date) but title+link
/// extraction is robust since those two elements are near-universal.
final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [ParsedFeedItem] = []

    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentSummary = ""
    private var currentDateString = ""
    private var currentAtomLinkHref: String?
    private var currentImageURL: String?
    private var insideItem = false

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",      // RFC 822 (RSS pubDate)
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",       // ISO8601 (Atom)
            "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        ]
        return formats.map { fmt in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            return df
        }
    }()

    static func parse(data: Data) -> [ParsedFeedItem] {
        let parser = RSSParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.items
    }

    private static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        for formatter in dateFormatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "item" || elementName == "entry" {
            insideItem = true
            currentTitle = ""
            currentLink = ""
            currentSummary = ""
            currentDateString = ""
            currentAtomLinkHref = nil
            currentImageURL = nil
        }
        // Atom links are attributes on a self-closing <link href="..."/> element.
        if insideItem, elementName == "link", let href = attributeDict["href"] {
            let rel = attributeDict["rel"]
            if rel == nil || rel == "alternate" {
                currentAtomLinkHref = href
            }
        }
        // Images show up in a few different, non-standard ways across feeds.
        // Check each; first one found wins (order = rough reliability).
        guard insideItem, currentImageURL == nil else { return }
        if elementName == "enclosure", let url = attributeDict["url"],
           (attributeDict["type"] ?? "").hasPrefix("image") {
            currentImageURL = url
        } else if elementName == "media:content" || elementName == "media:thumbnail",
                  let url = attributeDict["url"] {
            currentImageURL = url
        } else if elementName == "itunes:image", let href = attributeDict["href"] {
            currentImageURL = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        case "description", "summary", "content":
            currentSummary += string
        case "pubDate", "published", "updated":
            currentDateString += string
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "item" || elementName == "entry" {
            let link = currentAtomLinkHref ?? currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !link.isEmpty {
                let summary = currentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                // Some feeds embed the image as an <img> tag inside the
                // (HTML-escaped) description rather than a dedicated element —
                // fall back to scraping that if nothing else was found.
                let image = currentImageURL ?? Self.extractImgSrc(from: summary)
                items.append(ParsedFeedItem(
                    title: Self.decodeHTMLEntities(title),
                    link: link,
                    summary: summary.isEmpty ? nil : Self.decodeHTMLEntities(Self.stripHTMLTags(summary)),
                    publishedAt: Self.parseDate(currentDateString),
                    imageURL: image
                ))
            }
            insideItem = false
        }
        currentElement = ""
    }

    /// Pulls the first `<img src="...">` out of an HTML-ish summary string,
    /// used as a fallback when a feed doesn't provide a dedicated image tag.
    private static func extractImgSrc(from html: String) -> String? {
        guard let range = html.range(of: #"<img[^>]+src=["']([^"']+)["']"#, options: .regularExpression) else {
            return nil
        }
        let match = String(html[range])
        guard let srcRange = match.range(of: #"src=["']([^"']+)["']"#, options: .regularExpression) else {
            return nil
        }
        let srcAttr = String(match[srcRange])
        return srcAttr
            .replacingOccurrences(of: "src=", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    /// Strips HTML tags from a summary so it reads as plain text in a Telegram
    /// caption instead of showing raw markup like <p> or <a href=...>.
    private static func stripHTMLTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Handles the common HTML entities that show up in feed titles/summaries
    /// (feeds are technically XML, but many providers embed HTML-escaped text).
    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}
