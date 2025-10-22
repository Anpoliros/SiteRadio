
import Foundation
import SwiftSoup

/// 默认通用解析器 - 适用于大多数标准博客和新闻网站
/// 解析策略：提取页面中的 <article> 元素
struct DefaultParser: ArticleParserStrategy {
    
    var identifier: String { "DefaultParser" }
    var priority: Int { 0 } // 最低优先级，作为兜底方案
    
    func parse(html: String, url: URL) throws -> [ParsedArticle] {
        let doc = try SwiftSoup.parse(html, url.absoluteString)
        let articles = try doc.select("article")
        
        guard !articles.isEmpty() else {
            // 如果没有 article 标签，尝试其他常见容器
            return try parseAlternativeStructures(doc: doc, url: url)
        }
        
        var results: [ParsedArticle] = []
        
        for article in articles.array() {
            // 跳过明显的导航或侧边栏元素
            if try shouldSkipElement(article) {
                continue
            }
            
            guard let articleURL = try extractURL(from: article, base: url) else {
                continue
            }
            
            let title = try extractTitle(from: article)
            let publishedAt = try extractPublishedDate(from: article)
            let summary = try extractSummary(from: article)
            let author = try extractAuthor(from: article)
            
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
    
    // MARK: - Alternative Structures
    
    private func parseAlternativeStructures(doc: Document, url: URL) throws -> [ParsedArticle] {
        // 尝试常见的列表容器
        let selectors = [
            ".post, .entry",           // WordPress 常用类名
            ".article-item, .news-item", // 新闻网站
            "main article, main .post", // 在 main 标签内
            "[itemtype*='Article']"     // Schema.org 标记
        ]
        
        for selector in selectors {
            let elements = try doc.select(selector)
            if !elements.isEmpty() {
                return try parseElements(elements.array(), baseURL: url)
            }
        }
        
        // 最后的尝试：查找包含标题和链接的容器
        return try parseFallback(doc: doc, url: url)
    }
    
    private func parseElements(_ elements: [Element], baseURL: URL) throws -> [ParsedArticle] {
        var results: [ParsedArticle] = []
        
        for element in elements {
            if try shouldSkipElement(element) {
                continue
            }
            
            guard let articleURL = try extractURL(from: element, base: baseURL) else {
                continue
            }
            
            let title = try extractTitle(from: element)
            let publishedAt = try extractPublishedDate(from: element)
            let summary = try extractSummary(from: element)
            let author = try extractAuthor(from: element)
            
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
    
    private func parseFallback(doc: Document, url: URL) throws -> [ParsedArticle] {
        // 查找所有带标题的链接
        let links = try doc.select("a[href]")
        var results: [ParsedArticle] = []
        
        for link in links.array() {
            // 必须有实质性文本
            let text = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 10 else { continue }
            
            guard let href = try? link.attr("href"),
                  !href.isEmpty,
                  let articleURL = URL(string: href, relativeTo: url)?.absoluteURL else {
                continue
            }
            
            // 跳过导航链接
            if isNavigationLink(articleURL, baseURL: url) {
                continue
            }
            
            results.append(ParsedArticle(
                title: text,
                url: articleURL,
                publishedAt: nil,
                summary: nil,
                author: nil
            ))
        }
        
        return results
    }
    
    // MARK: - Extraction Methods
    
    private func extractTitle(from element: Element) throws -> String {
        // 按优先级尝试不同的标题选择器
        let selectors = ["h1", "h2", "h3", ".title", ".headline", "[itemprop='headline']"]
        
        for selector in selectors {
            if let titleElement = try? element.select(selector).first(),
               let text = try? titleElement.text().trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return text
            }
        }
        
        // 如果没有找到标题元素，尝试从链接文本提取
        if let link = try? element.select("a[href]").first(),
           let text = try? link.text().trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        
        return "Untitled"
    }
    
    private func extractURL(from element: Element, base: URL) throws -> URL? {
        // 优先级：
        // 1. .entry-link (Hugo/Theme 特定)
        // 2. title/heading 内的链接
        // 3. 第一个有效链接
        
        // 1. .entry-link
        if let link = try? element.select("a.entry-link").first(),
           let href = try? link.attr("href"),
           !href.isEmpty {
            return URL(string: href, relativeTo: base)?.absoluteURL
        }
        
        // 2. 标题内的链接
        let headingSelectors = ["h1 a", "h2 a", "h3 a", ".title a", ".headline a"]
        for selector in headingSelectors {
            if let link = try? element.select(selector).first(),
               let href = try? link.attr("href"),
               !href.isEmpty {
                return URL(string: href, relativeTo: base)?.absoluteURL
            }
        }
        
        // 3. 第一个有效链接
        if let link = try? element.select("a[href]").first(),
           let href = try? link.attr("href"),
           !href.isEmpty,
           let url = URL(string: href, relativeTo: base)?.absoluteURL,
           !isNavigationLink(url, baseURL: base) {
            return url
        }
        
        return nil
    }
    
    private func extractPublishedDate(from element: Element) throws -> Date? {
        // 1. <time datetime="...">
        if let time = try? element.select("time[datetime]").first(),
           let datetime = try? time.attr("datetime"),
           !datetime.isEmpty {
            return DateParser.parse(datetime)
        }
        
        // 2. Schema.org itemprop
        if let dateElement = try? element.select("[itemprop='datePublished']").first(),
           let dateString = try? dateElement.attr("content").isEmpty ? dateElement.text() : dateElement.attr("content") {
            return DateParser.parse(dateString)
        }
        
        // 3. 常见的日期类名
        let dateSelectors = [".date", ".published", ".post-date", ".entry-date", "time"]
        for selector in dateSelectors {
            if let dateElement = try? element.select(selector).first() {
                // 先尝试 title 属性
                if let title = try? dateElement.attr("title"), !title.isEmpty {
                    if let date = DateParser.parse(title) {
                        return date
                    }
                }
                // 再尝试文本内容
                if let text = try? dateElement.text(), !text.isEmpty {
                    if let date = DateParser.parse(text) {
                        return date
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractSummary(from element: Element) throws -> String? {
        // 1. Meta description / itemprop
        if let desc = try? element.select("[itemprop='description']").first(),
           let text = try? desc.text().trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return String(text.prefix(300))
        }
        
        // 2. 常见的摘要类名
        let summarySelectors = [".summary", ".excerpt", ".description", ".entry-content p", "p"]
        for selector in summarySelectors {
            if let summaryElement = try? element.select(selector).first(),
               let text = try? summaryElement.text().trimmingCharacters(in: .whitespacesAndNewlines),
               text.count >= 20 {
                return String(text.prefix(300))
            }
        }
        
        return nil
    }
    
    private func extractAuthor(from element: Element) throws -> String? {
        // 1. Schema.org
        if let author = try? element.select("[itemprop='author'], [rel='author']").first(),
           let text = try? author.text().trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        
        // 2. 常见类名
        let authorSelectors = [".author", ".byline", ".entry-author", ".post-author"]
        for selector in authorSelectors {
            if let authorElement = try? element.select(selector).first(),
               let text = try? authorElement.text().trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty && text.count < 100 {
                return text
            }
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func shouldSkipElement(_ element: Element) throws -> Bool {
        // 跳过导航、侧边栏等元素
        let skipClasses = ["nav", "navigation", "sidebar", "footer", "header", "menu", "widget"]
        
        if let className = try? element.className() {
            for skip in skipClasses {
                if className.lowercased().contains(skip) {
                    return true
                }
            }
        }
        
        // 跳过过小的元素（可能不是完整文章）
        if let text = try? element.text(),
           text.count < 30 {
            return true
        }
        
        return false
    }
    
    private func isNavigationLink(_ url: URL, baseURL: URL) -> Bool {
        let path = url.path.lowercased()
        
        // 跳过常见的导航路径
        let navPaths = ["/tag/", "/category/", "/page/", "/author/", "/archive/", "#"]
        for navPath in navPaths {
            if path.contains(navPath) || url.absoluteString.contains(navPath) {
                return true
            }
        }
        
        // 跳过分页链接
        if path.contains("page=") || path.hasSuffix("/") && path != "/" {
            return true
        }
        
        return false
    }
}

// MARK: - Date Parser Utility

struct DateParser {
    static func parse(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 尝试 ISO8601
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: trimmed) {
            return date
        }
        
        // 尝试常见格式
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "d MMM yyyy",
            "d MMMM yyyy",
            "yyyy/MM/dd",
            "MM/dd/yyyy"
        ]
        
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        
        return nil
    }
    
}
