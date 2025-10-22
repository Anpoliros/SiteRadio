import Foundation

// MARK: - Data Models

/// 解析后的文章数据结构
struct ParsedArticle: Equatable {
    let title: String
    let url: URL
    let publishedAt: Date?
    let summary: String?
    let content: String?
    let author: String?
    let imageURL: URL?
    let tags: [String]
    
    init(
        title: String,
        url: URL,
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

// MARK: - Network Layer Protocol

/// HTML 抓取协议 - 负责网络请求
protocol HTMLFetcher {
    /// 从指定 URL 抓取 HTML 内容
    /// - Parameter url: 目标 URL
    /// - Returns: HTML 字符串
    /// - Throws: 网络错误或解码错误
    func fetch(url: URL) async throws -> String
}

// MARK: - Parser Layer Protocol

/// 文章解析策略协议 - 使用 SwiftSoup 解析 HTML
protocol ArticleParserStrategy {
    /// 解析器的唯一标识符（用于日志和调试）
    var identifier: String { get }
    
    /// 解析器适用的域名模式（可选，用于自动匹配）
    /// 例如：["example.com", "*.blog.com"]
    var domainPatterns: [String] { get }
    
    /// 解析器优先级（数字越大优先级越高，默认为 0）
    var priority: Int { get }
    
    /// 从 HTML 中解析文章列表
    /// - Parameters:
    ///   - html: 待解析的 HTML 字符串
    ///   - url: 源 URL（用于解析相对路径）
    /// - Returns: 解析到的文章数组（空数组表示不适用或无内容）
    /// - Throws: 解析错误
    func parse(html: String, url: URL) throws -> [ParsedArticle]
}

// MARK: - Default Protocol Implementations

extension ArticleParserStrategy {
    var domainPatterns: [String] { [] }
    var priority: Int { 0 }
}

// MARK: - Parser Error Types

enum ParserError: LocalizedError {
    case invalidHTML
    case noArticlesFound
    case missingRequiredField(String)
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .invalidHTML:
            return "HTML 格式无效或已损坏"
        case .noArticlesFound:
            return "未找到任何文章"
        case .missingRequiredField(let field):
            return "缺少必需字段: \(field)"
        case .unsupportedFormat:
            return "不支持的网站格式"
        }
    }
}

// MARK: - Utility Extensions

extension ArticleParserStrategy {
    /// 检查 URL 是否匹配此解析器的域名模式
    func matches(url: URL) -> Bool {
        guard !domainPatterns.isEmpty else { return true } // 空模式匹配所有
        guard let host = url.host() else { return false }
        
        return domainPatterns.contains { pattern in
            if pattern.hasPrefix("*.") {
                let suffix = pattern.dropFirst(2)
                return host.hasSuffix(String(suffix))
            } else {
                return host == pattern || host.hasSuffix(".\(pattern)")
            }
        }
    }
}
