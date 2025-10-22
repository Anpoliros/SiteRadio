import Foundation

/// 解析服务 - 管理解析策略并路由到合适的解析器
final class ParseService {
    
    // MARK: - Properties
    
    /// 全局默认解析器（按优先级排序）
    private var globalParsers: [ArticleParserStrategy]
    
    /// 链接特定的解析器映射 (LinkID -> Parsers)
    private var linkSpecificParsers: [UUID: [ArticleParserStrategy]] = [:]
    
    /// 域名到解析器的缓存映射 (用于性能优化)
    private var domainCache: [String: [ArticleParserStrategy]] = [:]
    
    // MARK: - Initialization
    
    init(defaultParsers: [ArticleParserStrategy] = [
        CustomParser1(),
        DefaultParser()
    ]) {
        self.globalParsers = defaultParsers.sorted { $0.priority > $1.priority }
    }
    
    // MARK: - Parser Registration
    
    /// 注册全局解析器
    /// - Parameter parser: 要注册的解析器
    func registerGlobalParser(_ parser: ArticleParserStrategy) {
        globalParsers.append(parser)
        globalParsers.sort { $0.priority > $1.priority }
        clearDomainCache()
    }
    
    /// 批量注册全局解析器
    func registerGlobalParsers(_ parsers: [ArticleParserStrategy]) {
        globalParsers.append(contentsOf: parsers)
        globalParsers.sort { $0.priority > $1.priority }
        clearDomainCache()
    }
    
    /// 为特定链接设置专用解析器（覆盖全局）
    /// - Parameters:
    ///   - linkId: 订阅链接 ID
    ///   - parsers: 解析器数组（按优先级排序）
    func setParsers(for linkId: UUID, parsers: [ArticleParserStrategy]) {
        linkSpecificParsers[linkId] = parsers.sorted { $0.priority > $1.priority }
    }
    
    /// 为特定链接追加解析器
    func appendParser(for linkId: UUID, parser: ArticleParserStrategy) {
        var existing = linkSpecificParsers[linkId] ?? []
        existing.append(parser)
        linkSpecificParsers[linkId] = existing.sorted { $0.priority > $1.priority }
    }
    
    /// 移除特定链接的自定义解析器（回退到全局）
    func clearParsers(for linkId: UUID) {
        linkSpecificParsers.removeValue(forKey: linkId)
    }
    
    // MARK: - Parsing
    
    /// 解析单个链接的内容
    /// - Parameters:
    ///   - link: 订阅链接
    ///   - html: HTML 内容
    ///   - url: 源 URL
    /// - Returns: 解析到的文章数组
    func parse(link: SubscriptionLink, html: String, url: URL) -> [ParsedArticle] {
        let parsers = getParsers(for: link, url: url)
        var allArticles: [ParsedArticle] = []
        var parseErrors: [(String, Error)] = []
        
        for parser in parsers {
            do {
                let articles = try parser.parse(html: html, url: url)
                if !articles.isEmpty {
                    print("✅ [\(parser.identifier)] 成功解析 \(articles.count) 篇文章")
                    allArticles.append(contentsOf: articles)
                } else {
                    print("⚠️ [\(parser.identifier)] 未找到文章")
                }
            } catch {
                parseErrors.append((parser.identifier, error))
                print("❌ [\(parser.identifier)] 解析失败: \(error.localizedDescription)")
            }
        }
        
        // 如果所有解析器都失败，记录详细错误
        if allArticles.isEmpty && !parseErrors.isEmpty {
            print("🚨 所有解析器均失败:")
            parseErrors.forEach { identifier, error in
                print("   - \(identifier): \(error)")
            }
        }
        
        return deduplicateArticles(allArticles)
    }
    
    /// 批量解析多个链接
    func parseBatch(
        links: [(link: SubscriptionLink, html: String, url: URL)]
    ) -> [ParsedArticle] {
        var allArticles: [ParsedArticle] = []
        
        for item in links {
            let articles = parse(link: item.link, html: item.html, url: item.url)
            allArticles.append(contentsOf: articles)
        }
        
        return deduplicateArticles(allArticles)
    }
    
    // MARK: - Parser Selection
    
    /// 获取适用于特定链接的解析器列表
    private func getParsers(for link: SubscriptionLink, url: URL) -> [ArticleParserStrategy] {
        // 1. 优先使用链接特定的解析器
        if let linkParsers = linkSpecificParsers[link.id], !linkParsers.isEmpty {
            return linkParsers
        }
        
        // 2. 检查域名缓存
        if let host = url.host(), let cached = domainCache[host] {
            return cached
        }
        
        // 3. 从全局解析器中筛选匹配的
        let matchedParsers = globalParsers.filter { $0.matches(url: url) }
        
        // 4. 如果有特定匹配，使用它们；否则使用所有全局解析器
        let selectedParsers = matchedParsers.isEmpty ? globalParsers : matchedParsers
        
        // 5. 缓存结果
        if let host = url.host() {
            domainCache[host] = selectedParsers
        }
        
        return selectedParsers
    }
    
    // MARK: - Utilities
    
    /// 去重文章（基于 URL）
    private func deduplicateArticles(_ articles: [ParsedArticle]) -> [ParsedArticle] {
        var seen: Set<URL> = []
        var unique: [ParsedArticle] = []
        
        for article in articles {
            // URL 是必需字段，不是可选值
            if !seen.contains(article.url) {
                seen.insert(article.url)
                unique.append(article)
            }
        }
        
        return unique
    }
    
    /// 清空域名缓存
    private func clearDomainCache() {
        domainCache.removeAll()
    }
    
    // MARK: - Introspection
    
    /// 获取所有已注册的全局解析器
    func listGlobalParsers() -> [String] {
        globalParsers.map { "\($0.identifier) (priority: \($0.priority))" }
    }
    
    /// 获取特定链接的解析器配置
    func listParsers(for linkId: UUID) -> [String]? {
        linkSpecificParsers[linkId]?.map {
            "\($0.identifier) (priority: \($0.priority))"
        }
    }
    
    /// 获取适用于特定 URL 的解析器
    func debugParsers(for url: URL) -> [String] {
        globalParsers
            .filter { $0.matches(url: url) }
            .map { "\($0.identifier) (priority: \($0.priority))" }
    }
}
