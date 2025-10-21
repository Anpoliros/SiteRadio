import Foundation

struct FeedItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var url: URL
    var publishedAt: Date
    var summary: String?
    var content: String?
    var author: String?
    var source: String // 来源网站名称
    var sourceURL: URL
    var imageURL: URL?
    var tags: [String]
    
    init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        publishedAt: Date = Date(),
        summary: String? = nil,
        content: String? = nil,
        author: String? = nil,
        source: String,
        sourceURL: URL,
        imageURL: URL? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.publishedAt = publishedAt
        self.summary = summary
        self.content = content
        self.author = author
        self.source = source
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.tags = tags
    }
}

extension FeedItem {
    /// 从解析结果创建FeedItem
    static func from(parsedResult: ParsedArticle, sourceURL: URL) -> FeedItem {
        FeedItem(
            title: parsedResult.title,
            url: parsedResult.url ?? sourceURL,
            publishedAt: parsedResult.publishedAt ?? Date(),
            summary: parsedResult.summary,
            content: parsedResult.content,
            author: parsedResult.author,
            source: sourceURL.host() ?? "Unknown",
            sourceURL: sourceURL,
            imageURL: parsedResult.imageURL,
            tags: parsedResult.tags
        )
    }
}

