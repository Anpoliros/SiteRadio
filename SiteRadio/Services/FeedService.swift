import Foundation

/// 订阅服务 - 协调网络抓取和内容解析
final class FeedService {
    
    // MARK: - Properties
    
    private let fetcher: HTMLFetcher
    private let parseService: ParseService
    
    // MARK: - Initialization
    
    init(
        fetcher: HTMLFetcher = FetcherService(),
        parseService: ParseService = ParseService()
    ) {
        self.fetcher = fetcher
        self.parseService = parseService
    }
    
    // MARK: - Public API
    
    /// 从订阅链接列表抓取并解析文章
    /// - Parameter links: 订阅链接数组
    /// - Returns: FeedItem 数组，按发布时间倒序排列
    func fetchFeeds(from links: [SubscriptionLink]) async -> [FeedItem] {
        guard !links.isEmpty else {
            print("⚠️ 无订阅链接")
            return []
        }
        
        print("📡 开始抓取 \(links.count) 个订阅源...")
        let startTime = Date()
        
        var allFeedItems: [FeedItem] = []
        var successCount = 0
        var failureCount = 0
        
        await withTaskGroup(of: FetchResult.self) { group in
            for link in links {
                guard let url = URL(string: link.urlString) else {
                    print("❌ 无效的 URL: \(link.urlString)")
                    failureCount += 1
                    continue
                }
                
                group.addTask {
                    await self.fetchAndParse(link: link, url: url)
                }
            }
            
            for await result in group {
                switch result {
                case .success(let items):
                    allFeedItems.append(contentsOf: items)
                    successCount += 1
                case .failure(let error):
                    print("❌ \(error)")
                    failureCount += 1
                }
            }
        }
        
        // 按发布时间倒序排列
        allFeedItems.sort { $0.publishedAt > $1.publishedAt }
        
        let duration = Date().timeIntervalSince(startTime)
        print("✅ 抓取完成: 成功 \(successCount)/\(links.count), 失败 \(failureCount), 共 \(allFeedItems.count) 篇文章, 耗时 \(String(format: "%.2f", duration))s")
        
        return allFeedItems
    }
    
    /// 从订阅组列表抓取文章
    /// - Parameter groups: 订阅组数组
    /// - Returns: FeedItem 数组
    func fetchFeeds(from groups: [SubscriptionGroup]) async -> [FeedItem] {
        let allLinks = groups.flatMap { $0.links }
        return await fetchFeeds(from: allLinks)
    }
    
    /// 刷新单个订阅源
    /// - Parameter link: 订阅链接
    /// - Returns: FeedItem 数组
    func refreshFeed(for link: SubscriptionLink) async throws -> [FeedItem] {
        guard let url = URL(string: link.urlString) else {
            throw FeedServiceError.invalidURL(link.urlString)
        }
        
        let result = await fetchAndParse(link: link, url: url)
        
        switch result {
        case .success(let items):
            return items
        case .failure(let error):
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchAndParse(link: SubscriptionLink, url: URL) async -> FetchResult {
        do {
            // 1. 抓取 HTML
            let html = try await fetcher.fetch(url: url)
            
            // 2. 解析文章
            let parsedArticles = parseService.parse(link: link, html: html, url: url)
            
            guard !parsedArticles.isEmpty else {
                return .failure(.noArticlesFound(url))
            }
            
            // 3. 转换为 FeedItem
            let feedItems = parsedArticles.map { article in
                FeedItem(
                    title: article.title,
                    url: article.url,
                    publishedAt: article.publishedAt ?? Date(),
                    summary: article.summary,
                    author: article.author,
                    source: url.host() ?? "Unknown",
                    sourceURL: url
                )
            }
            
            print("✅ [\(link.title.isEmpty ? url.host() ?? "Unknown" : link.title)] \(feedItems.count) 篇文章")
            
            return .success(feedItems)
            
        } catch let error as FetcherError {
            return .failure(.fetcherError(url, error))
        } catch let error as ParserError {
            return .failure(.parserError(url, error))
        } catch {
            return .failure(.unknownError(url, error))
        }
    }
    
    // MARK: - Parser Configuration
    
    /// 为特定链接设置自定义解析器
    func setCustomParser(for linkId: UUID, parser: ArticleParserStrategy) {
        parseService.setParsers(for: linkId, parsers: [parser])
    }
    
    /// 注册全局解析器
    func registerGlobalParser(_ parser: ArticleParserStrategy) {
        parseService.registerGlobalParser(parser)
    }
}

// MARK: - Supporting Types

private enum FetchResult {
    case success([FeedItem])
    case failure(FeedServiceError)
}

enum FeedServiceError: LocalizedError {
    case invalidURL(String)
    case fetcherError(URL, FetcherError)
    case parserError(URL, ParserError)
    case noArticlesFound(URL)
    case unknownError(URL, Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let urlString):
            return "无效的 URL: \(urlString)"
        case .fetcherError(let url, let error):
            return "[\(url.host() ?? "")] 抓取失败: \(error.localizedDescription)"
        case .parserError(let url, let error):
            return "[\(url.host() ?? "")] 解析失败: \(error.localizedDescription)"
        case .noArticlesFound(let url):
            return "[\(url.host() ?? "")] 未找到文章"
        case .unknownError(let url, let error):
            return "[\(url.host() ?? "")] 未知错误: \(error.localizedDescription)"
        }
    }
}
