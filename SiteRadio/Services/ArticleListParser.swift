import Foundation

/// 文章列表解析器 - 负责从HTML中提取文章列表
class ArticleListParser {
    private let strategy: FetchStrategy
    
    init(strategy: FetchStrategy = DefaultArticleListStrategy()) {
        self.strategy = strategy
    }
    
    /// 从HTML中提取文章列表
    /// - Parameters:
    ///   - html: 待解析的HTML字符串
    ///   - baseURL: 源URL，用于解析相对路径
    /// - Returns: 提取到的文章列表
    func extractArticles(from html: String, baseURL: URL) -> [ExtractedArticle] {
        return strategy.extractArticles(from: html, baseURL: baseURL)
    }
    
    /// 切换抓取策略
    /// - Parameter newStrategy: 新的抓取策略
    func switchStrategy(_ newStrategy: FetchStrategy) -> ArticleListParser {
        return ArticleListParser(strategy: newStrategy)
    }
}

