import Foundation

/// 解析器返回的文章数据结构
struct ParsedArticle {
    let title: String
    let url: URL?
    let publishedAt: Date?
    let summary: String?
    let content: String?
    let author: String?
    let imageURL: URL?
    let tags: [String]
    
    init(
        title: String,
        url: URL? = nil,
        publishedAt: Date? = nil,
        summary: String? = nil,
        content: String? = nil,
        author: String? = nil,
        imageURL: URL? = nil,
        tags: [String] = []
    ) {
        self.title = title
        self.url = url
        self.publishedAt = publishedAt
        self.summary = summary
        self.content = content
        self.author = author
        self.imageURL = imageURL
        self.tags = tags
    }
}

