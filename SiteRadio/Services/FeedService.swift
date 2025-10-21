import Foundation

/// 订阅源服务 - 协调抓取和解析流程
class FeedService {
    private let fetcher: FetcherService
    private let parser: ArticleParser
    
    init(fetcher: FetcherService = FetcherService(), parser: ArticleParser = DefaultHTMLParser()) {
        self.fetcher = fetcher
        self.parser = parser
    }
    
    /// 从订阅链接列表中抓取文章列表
    /// - Parameter links: 订阅链接列表
    /// - Returns: 抓取到的FeedItem数组，按发布时间倒序排列
    func fetchFeeds(from links: [SubscriptionLink]) async -> [FeedItem] {
        print("📡 开始抓取 \(links.count) 个订阅源...")
        
        // 提取所有URL
        let urls = links.compactMap { URL(string: $0.urlString) }
        
        guard !urls.isEmpty else {
            print("⚠️ 没有有效的URL")
            return []
        }
        
        // 批量抓取文章列表
        let extractedArticles = await fetcher.fetchArticleLists(from: urls)
        
        print("✅ 成功抓取 \(extractedArticles.count) 篇文章")
        
        // 转换为FeedItem
        var feedItems: [FeedItem] = []
        
        for article in extractedArticles {
            let feedItem = FeedItem(
                title: article.title,
                url: article.url,
                publishedAt: article.publishedAt ?? Date(),
                summary: article.summary,
                author: article.author,
                source: article.url.host() ?? "Unknown",
                sourceURL: article.url
            )
            feedItems.append(feedItem)
        }
        
        // 按发布时间倒序排列
        feedItems.sort { $0.publishedAt > $1.publishedAt }
        
        print("📝 共生成 \(feedItems.count) 条时间线项目")
        
        return feedItems
    }
    
    /// 从单个URL抓取文章
    /// - Parameter url: 要抓取的URL
    /// - Returns: 抓取到的FeedItem，如果失败返回nil
    func fetchFeed(from url: URL) async -> FeedItem? {
        guard let html = await fetcher.fetchHTML(from: url) else {
            return nil
        }
        
        guard let parsedArticle = parser.parse(html: html, from: url) else {
            return nil
        }
        
        return FeedItem.from(parsedResult: parsedArticle, sourceURL: url)
    }
    
    /// 从订阅组列表中抓取所有文章
    /// - Parameter groups: 订阅组列表
    /// - Returns: 抓取到的FeedItem数组，按发布时间倒序排列
    func fetchFeeds(from groups: [SubscriptionGroup]) async -> [FeedItem] {
        // 提取所有链接
        let allLinks = groups.flatMap { $0.links }
        
        return await fetchFeeds(from: allLinks)
    }
}

