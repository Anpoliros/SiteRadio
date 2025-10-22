import Foundation
import SwiftSoup

// MARK: - Apple Newsroom 专用解析器

/// Apple Newsroom 专用解析器
/// 域名: www.apple.com/newsroom/
struct AppleNewsroomParser: ArticleParserStrategy {
    var identifier: String { "AppleNewsroomParser" }
    var priority: Int { 100 }
    var domainPatterns: [String] { ["apple.com"] }
    
    func parse(html: String, url: URL) throws -> [ParsedArticle] {
        let doc = try SwiftSoup.parse(html, url.absoluteString)
        
        // Apple Newsroom 使用特定的 class 结构
        let articles = try doc.select(".tile, .newsroom-tile")
        
        guard !articles.isEmpty() else {
            return []
        }
        
        var results: [ParsedArticle] = []
        
        for article in articles.array() {
            guard let link = try? article.select("a.tile-link").first(),
                  let href = try? link.attr("href"),
                  let articleURL = URL(string: href, relativeTo: url)?.absoluteURL else {
                continue
            }
            
            let title = try article.select(".tile-headline").first()?.text() ?? "Untitled"
            let summary = try? article.select(".tile-description").first()?.text()
            let dateText = try? article.select(".date").first()?.text()
            let publishedAt = dateText.flatMap { DateParser.parse($0) }
            
            results.append(ParsedArticle(
                title: title,
                url: articleURL,
                publishedAt: publishedAt,
                summary: summary,
                author: "Apple Newsroom"
            ))
        }
        
        return results
    }
}

// MARK: - Medium 专用解析器

///// Medium 专用解析器
//struct MediumParser: ArticleParserStrategy {
//    var identifier: String { "MediumParser" }
//    var priority: Int { 100 }
//    var domainPatterns: [String] { ["medium.com", "*.medium.com"] }
//    
//    func parse(html: String, url: URL) throws -> [ParsedArticle] {
//        let doc = try SwiftSoup.parse(html, url.absoluteString)
//        
//        // Medium 使用 article 标签和特定的数据属性
//        let articles = try doc.select("article")
//        
//        var results: [ParsedArticle] = []
//        
//        for article in articles.array() {
//            // Medium 的链接通常在 h2 或 h3 内
//            guard let titleElement = try? article.select("h2, h3").first(),
//                  let link = try? titleElement.select("a").first(),
//                  let href = try? link.attr("href"),
//                  let articleURL = URL(string: href, relativeTo: url)?.absoluteURL else {
//                continue
//            }
//            
//            let title = try titleElement.text()
//            
//            // 提取副标题作为摘要
//            let summary = try? article.select("h3 + p, p").first()?.text()
//            
//            // 提取作者
//            let author = try? article.select("[data-testid='authorName']").first()?.text()
//                ?? article.select("a[rel='author']").first()?.text()
//            
//            // 提取日期
//            let dateElement = try? article.select("time").first()
//            let publishedAt = try? dateElement?.attr("datetime").flatMap { DateParser.parse($0) }
//            
//            results.append(ParsedArticle(
//                title: title,
//                url: articleURL,
//                publishedAt: publishedAt,
//                summary: summary,
//                author: author
//            ))
//        }
//        
//        return results
//    }
//}

// MARK: - Hacker News 专用解析器

/// Hacker News 专用解析器
struct HackerNewsParser: ArticleParserStrategy {
    var identifier: String { "HackerNewsParser" }
    var priority: Int { 100 }
    var domainPatterns: [String] { ["news.ycombinator.com"] }
    
    func parse(html: String, url: URL) throws -> [ParsedArticle] {
        let doc = try SwiftSoup.parse(html, url.absoluteString)
        
        // HN 使用表格布局
        let rows = try doc.select(".athing")
        
        var results: [ParsedArticle] = []
        
        for row in rows.array() {
            guard let titleCell = try? row.select(".titleline").first(),
                  let link = try? titleCell.select("a").first(),
                  let href = try? link.attr("href"),
                  !href.isEmpty else {
                continue
            }
            
            // HN 的链接可能是相对路径或外部链接
            let articleURL: URL?
            if href.hasPrefix("item?id=") {
                articleURL = URL(string: href, relativeTo: url)?.absoluteURL
            } else {
                articleURL = URL(string: href)
            }
            
            guard let finalURL = articleURL else { continue }
            
            let title = try link.text()
            
            // HN 的元信息在下一行
            let subtext = try? row.nextElementSibling()?.select(".subtext").first()
            let author = try? subtext?.select(".hnuser").first()?.text()
            let ageText = try? subtext?.select(".age").first()?.text()
            
            results.append(ParsedArticle(
                title: title,
                url: finalURL,
                publishedAt: nil, // HN 不提供精确时间戳
                summary: nil,
                author: author
            ))
        }
        
        return results
    }
}

// MARK: - WordPress 通用解析器

/// WordPress 标准主题解析器
struct WordPressParser: ArticleParserStrategy {
    var identifier: String { "WordPressParser" }
    var priority: Int { 5 } // 中等优先级
    var domainPatterns: [String] { [] } // 匹配所有，但通过检测 WordPress 特征来决定
    
    func parse(html: String, url: URL) throws -> [ParsedArticle] {
        let doc = try SwiftSoup.parse(html, url.absoluteString)
        
        // 检测 WordPress 特征
        let isWordPress = (try? doc.select("meta[name='generator']").first()?.attr("content").contains("WordPress")) ?? false
        
        guard isWordPress else {
            return [] // 不是 WordPress，让其他解析器处理
        }
        
        // WordPress 标准类名
        let articles = try doc.select(".post, .hentry, article")
        
        var results: [ParsedArticle] = []
        
        for article in articles.array() {
            guard let link = try? article.select(".entry-title a, h2 a, h1 a").first(),
                  let href = try? link.attr("href"),
                  let articleURL = URL(string: href, relativeTo: url)?.absoluteURL else {
                continue
            }
            
            let title = try link.text()
            let summary = try? article.select(".entry-summary, .entry-excerpt").first()?.text()
            let author = try? article.select(".author, .entry-author").first()?.text()
            
            let dateElement = try? article.select(".entry-date, time[datetime]").first()
            let publishedAt: Date?
            if let datetime = try? dateElement?.attr("datetime") {
                publishedAt = DateParser.parse(datetime)
            } else if let dateText = try? dateElement?.text() {
                publishedAt = DateParser.parse(dateText)
            } else {
                publishedAt = nil
            }
            
            results.append(ParsedArticle(
                title: title,
                url: articleURL,
                publishedAt: publishedAt,
                summary: summary,
                author: author
            ))
        }
        
        return results
    }
}

// MARK: - RSS Feed Alternative Parser

/// RSS Feed 备选解析器（当网站提供 RSS feed 时）
/// 注意：这个解析器实际上应该解析 XML 而不是 HTML
/// 这里仅作为示例展示如何扩展架构
struct RSSFeedParser: ArticleParserStrategy {
    var identifier: String { "RSSFeedParser" }
    var priority: Int { 50 }
    var domainPatterns: [String] { [] }
    
    func parse(html: String, url: URL) throws -> [ParsedArticle] {
        // 检测是否是 RSS/Atom feed
        guard html.contains("<rss") || html.contains("<feed") else {
            return []
        }
        
        let doc = try SwiftSoup.parse(html, url.absoluteString)
        
        // 尝试解析 RSS 2.0
        if let items = try? doc.select("item") {
            return try parseRSSItems(items.array(), baseURL: url)
        }
        
        // 尝试解析 Atom
        if let entries = try? doc.select("entry") {
            return try parseAtomEntries(entries.array(), baseURL: url)
        }
        
        return []
    }
    
    private func parseRSSItems(_ items: [Element], baseURL: URL) throws -> [ParsedArticle] {
        var results: [ParsedArticle] = []
        
        for item in items {
            guard let titleElement = try? item.select("title").first(),
                  let title = try? titleElement.text(),
                  let linkElement = try? item.select("link").first(),
                  let linkText = try? linkElement.text(),
                  let articleURL = URL(string: linkText) else {
                continue
            }
            
            let summary = try? item.select("description").first()?.text()
            let author = try? item.select("author, dc\\:creator").first()?.text()
            
            let pubDate = try? item.select("pubDate").first()?.text()
            let publishedAt = pubDate.flatMap { DateParser.parse($0) }
            
            results.append(ParsedArticle(
                title: title,
                url: articleURL,
                publishedAt: publishedAt,
                summary: summary,
                author: author
            ))
        }
        
        return results
    }
    
    private func parseAtomEntries(_ entries: [Element], baseURL: URL) throws -> [ParsedArticle] {
        var results: [ParsedArticle] = []
        
        for entry in entries {
            guard let titleElement = try? entry.select("title").first(),
                  let title = try? titleElement.text(),
                  let linkElement = try? entry.select("link[href]").first(),
                  let href = try? linkElement.attr("href"),
                  let articleURL = URL(string: href) else {
                continue
            }
            
            let summary = try? entry.select("summary, content").first()?.text()
            let author = try? entry.select("author name").first()?.text()
            
            let published = try? entry.select("published, updated").first()?.text()
            let publishedAt = published.flatMap { DateParser.parse($0) }
            
            results.append(ParsedArticle(
                title: title,
                url: articleURL,
                publishedAt: publishedAt,
                summary: summary,
                author: author
            ))
        }
        
        return results
    }
}

// MARK: - 使用示例

/*
 如何在 AppModel 中注册这些自定义解析器：
 
 let feedService = FeedService()
 
 // 注册全局解析器（按优先级自动排序）
 feedService.registerGlobalParser(AppleNewsroomParser())
 feedService.registerGlobalParser(MediumParser())
 feedService.registerGlobalParser(HackerNewsParser())
 feedService.registerGlobalParser(WordPressParser())
 feedService.registerGlobalParser(RSSFeedParser())
 
 // 为特定订阅源设置专用解析器
 if let appleLink = groups.first?.links.first(where: { $0.urlString.contains("apple.com") }) {
     feedService.setCustomParser(for: appleLink.id, parser: AppleNewsroomParser())
 }
 
 // 解析器会根据 priority 和 domainPatterns 自动选择最合适的
 */
