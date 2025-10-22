import Foundation
import SwiftSoup

/// 自定义解析器示例 - 针对特定网站结构优化
/// 适用于使用 .post-entry 类的网站（如某些 Hugo 主题）
struct CustomParser1: ArticleParserStrategy {
    
    var identifier: String { "CustomParser1" }
    var priority: Int { 10 } // 高优先级
    
    // 可以指定特定域名，留空则匹配所有
    var domainPatterns: [String] { [] }
    
    func parse(html: String, url: URL) throws -> [ParsedArticle] {
        let doc = try SwiftSoup.parse(html, url.absoluteString)
        
        // 查找特定结构的 article 元素
        let articles = try doc.select("article.post-entry, article.entry")
        
        guard !articles.isEmpty() else {
            // 如果没有找到，返回空数组让其他解析器尝试
            return []
        }
        
        var results: [ParsedArticle] = []
        
        for article in articles.array() {
            do {
                let parsed = try parseArticleElement(article, baseURL: url)
                results.append(parsed)
            } catch {
                // 单个文章解析失败不影响其他文章
                print("⚠️ [CustomParser1] 跳过无效文章: \(error)")
                continue
            }
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    private func parseArticleElement(_ article: Element, baseURL: URL) throws -> ParsedArticle {
        // 提取标题
        let title = try extractTitle(from: article)
        
        // 提取链接（必需）
        guard let articleURL = try extractURL(from: article, base: baseURL) else {
            throw ParserError.missingRequiredField("url")
        }
        
        // 提取可选字段
        let publishedAt = try? extractPublishedDate(from: article)
        let summary = try? extractSummary(from: article)
        let author = try? extractAuthor(from: article)
        
        return ParsedArticle(
            title: title,
            url: articleURL,
            publishedAt: publishedAt,
            summary: summary,
            content: nil,
            author: author,
            imageURL: nil,
            tags: []
        )
    }
    
    private func extractTitle(from article: Element) throws -> String {
        // 尝试多个可能的标题选择器
        let selectors = [
            "h1",
            "h2",
            ".entry-hint-parent",
            ".entry-title",
            ".post-title"
        ]
        
        for selector in selectors {
            if let titleElement = try? article.select(selector).first(),
               let text = try? titleElement.text().trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return text
            }
        }
        
        // 如果找不到标题，尝试从链接提取
        if let link = try? article.select("a.entry-link").first(),
           let text = try? link.text().trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        
        return "Untitled"
    }
    
    private func extractURL(from article: Element, base: URL) throws -> URL? {
        // 优先级：
        // 1. a.entry-link
        // 2. h1/h2 内的链接
        // 3. 第一个有效链接
        
        let linkSelectors = [
            "a.entry-link",
            "h1 a[href]",
            "h2 a[href]",
            "a[href]"
        ]
        
        for selector in linkSelectors {
            if let link = try? article.select(selector).first(),
               let href = try? link.attr("href"),
               !href.isEmpty {
                return URL(string: href, relativeTo: base)?.absoluteURL
            }
        }
        
        return nil
    }
    
    private func extractPublishedDate(from article: Element) throws -> Date? {
        // 1. 尝试 footer 中的 span[title] (常见于某些主题)
        if let span = try? article.select("footer span[title]").first(),
           let titleAttr = try? span.attr("title"),
           !titleAttr.isEmpty {
            if let date = DateParser.parse(titleAttr) {
                return date
            }
        }
        
        // 2. 标准 <time> 标签
        if let time = try? article.select("time[datetime]").first(),
           let datetime = try? time.attr("datetime") {
            return DateParser.parse(datetime)
        }
        
        // 3. 日期类名
        if let dateElement = try? article.select(".date, .published, .post-date").first() {
            if let title = try? dateElement.attr("title"), !title.isEmpty {
                return DateParser.parse(title)
            }
            if let text = try? dateElement.text() {
                return DateParser.parse(text)
            }
        }
        
        return nil
    }
    
    private func extractSummary(from article: Element) throws -> String? {
        // 尝试多个可能的摘要位置
        let summarySelectors = [
            ".entry-content p",
            ".entry-summary",
            ".post-excerpt",
            "p"
        ]
        
        for selector in summarySelectors {
            if let summaryElement = try? article.select(selector).first(),
               let text = try? summaryElement.text().trimmingCharacters(in: .whitespacesAndNewlines),
               text.count >= 20 {
                return String(text.prefix(300))
            }
        }
        
        return nil
    }
    
    private func extractAuthor(from article: Element) throws -> String? {
        // 尝试多个可能的作者位置
        let authorSelectors = [
            ".entry-footer",
            ".author",
            ".byline",
            "footer .author-name",
            "[rel='author']"
        ]
        
        for selector in authorSelectors {
            if let authorElement = try? article.select(selector).first(),
               let text = try? authorElement.text().trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty && text.count < 100 {
                // 清理常见的前缀
                let cleaned = text
                    .replacingOccurrences(of: "By ", with: "")
                    .replacingOccurrences(of: "Author: ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                return cleaned
            }
        }
        
        return nil
    }
}
