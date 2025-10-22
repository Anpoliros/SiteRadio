import Foundation
import SwiftSoup

/// 默认通用解析器 - 适用于大多数标准博客和新闻网站
/// 解析策略:提取页面中的 <article> 元素
struct DefaultParser: ArticleParserStrategy {
    
    var identifier: String { "DefaultParser" }
    var priority: Int { 0 } // 最低优先级,作为兜底方案
    
    func parse(html: String, url: URL) throws -> [ParsedArticle] {
        let doc = try SwiftSoup.parse(html, url.absoluteString)
        let articles = try doc.select("article")
        
        guard !articles.isEmpty() else {
            // 如果没有 article 标签,尝试其他常见容器
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
        
        // 最后的尝试:查找包含标题和链接的容器
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
        
        // 如果没有找到标题元素,尝试从链接文本提取
        if let link = try? element.select("a[href]").first(),
           let text = try? link.text().trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        
        return "Untitled"
    }
    
    private func extractURL(from element: Element, base: URL) throws -> URL? {
        // 优先级:
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
        
        // 跳过过小的元素(可能不是完整文章)
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
        
        // 1. 尝试相对时间(如 "2 hours ago", "3 days ago")
        if let date = parseRelativeDate(trimmed) {
            return date
        }
        
        // 2. 尝试 ISO8601 及其变体
        if let date = parseISO8601(trimmed) {
            return date
        }
        
        // 3. 尝试 RFC 2822 (Email/RSS 常用格式)
        if let date = parseRFC2822(trimmed) {
            return date
        }
        
        // 4. 提取并清理日期字符串(移除多余文本)
        let cleaned = cleanDateString(trimmed)
        
        // 5. 尝试标准格式
        if let date = parseStandardFormats(cleaned) {
            return date
        }
        
        // 6. 尝试带时区的格式
        if let date = parseWithTimezone(cleaned) {
            return date
        }
        
        // 7. 尝试中文日期格式
        if let date = parseChineseDate(cleaned) {
            return date
        }
        
        // 8. 尝试模糊匹配(提取数字和月份)
        if let date = parseFuzzyDate(cleaned) {
            return date
        }
        
        return nil
    }
    
    // MARK: - Relative Date Parsing
    
    private static func parseRelativeDate(_ string: String) -> Date? {
        let lowercased = string.lowercased()
        let now = Date()
        
        // 匹配 "X time_unit ago" 格式
        let patterns: [(pattern: String, unit: Calendar.Component)] = [
            (#"(\d+)\s*seconds?\s+ago"#, .second),
            (#"(\d+)\s*minutes?\s+ago"#, .minute),
            (#"(\d+)\s*hours?\s+ago"#, .hour),
            (#"(\d+)\s*days?\s+ago"#, .day),
            (#"(\d+)\s*weeks?\s+ago"#, .weekOfYear),
            (#"(\d+)\s*months?\s+ago"#, .month),
            (#"(\d+)\s*years?\s+ago"#, .year)
        ]
        
        for (pattern, unit) in patterns {
            if let range = lowercased.range(of: pattern, options: .regularExpression),
               let match = lowercased[range].firstMatch(of: /(\d+)/),
               let value = Int(match.1) {
                return Calendar.current.date(byAdding: unit, value: -value, to: now)
            }
        }
        
        // 特殊词汇
        if lowercased.contains("just now") || lowercased.contains("刚刚") {
            return now
        }
        if lowercased.contains("yesterday") || lowercased.contains("昨天") {
            return Calendar.current.date(byAdding: .day, value: -1, to: now)
        }
        if lowercased.contains("today") || lowercased.contains("今天") {
            return now
        }
        
        return nil
    }
    
    // MARK: - ISO8601 Parsing
    
    private static func parseISO8601(_ string: String) -> Date? {
        let iso8601Formatter = ISO8601DateFormatter()
        
        // 标准 ISO8601
        if let date = iso8601Formatter.date(from: string) {
            return date
        }
        
        // 带毫秒的 ISO8601
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: string) {
            return date
        }
        
        return nil
    }
    
    // MARK: - RFC 2822 Parsing
    
    private static func parseRFC2822(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        
        if let date = formatter.date(from: string) {
            return date
        }
        
        // 无时区版本
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss"
        return formatter.date(from: string)
    }
    
    // MARK: - Standard Formats Parsing
    
    private static func parseStandardFormats(_ string: String) -> Date? {
        let formats = [
            // ISO 风格
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            
            // 斜杠分隔
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "yyyy/MM/dd",
            "MM/dd/yyyy",
            "dd/MM/yyyy",
            
            // 点分隔
            "yyyy.MM.dd HH:mm:ss",
            "yyyy.MM.dd HH:mm",
            "yyyy.MM.dd",
            "dd.MM.yyyy",
            
            // 月份名称(英文)
            "MMM d, yyyy HH:mm:ss",
            "MMM d, yyyy HH:mm",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "d MMM yyyy",
            "d MMMM yyyy",
            
            // 月份名称(英文,逆序)
            "yyyy, MMMM d",
            "yyyy, MMM d",
            
            // 无分隔符
            "yyyyMMdd",
            "yyyyMMddHHmmss"
        ]
        
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            
            if let date = formatter.date(from: string) {
                return date
            }
        }
        
        return nil
    }
    
    // MARK: - Timezone Formats Parsing
    
    private static func parseWithTimezone(_ string: String) -> Date? {
        let formatsWithTimezone = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss ZZZZ",
            "MMM d, yyyy HH:mm:ss Z",
            "MMMM d, yyyy HH:mm:ss Z"
        ]
        
        for format in formatsWithTimezone {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            
            if let date = formatter.date(from: string) {
                return date
            }
        }
        
        return nil
    }
    
    // MARK: - Chinese Date Parsing
    
    private static func parseChineseDate(_ string: String) -> Date? {
        let formats = [
            "yyyy年MM月dd日 HH:mm:ss",
            "yyyy年MM月dd日 HH:mm",
            "yyyy年MM月dd日",
            "yyyy年M月d日",
            "M月d日",
            "MM-dd HH:mm"
        ]
        
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            
            if let date = formatter.date(from: string) {
                return date
            }
        }
        
        return nil
    }
    
    // MARK: - Fuzzy Date Parsing
    
    private static func parseFuzzyDate(_ string: String) -> Date? {
        // 提取年月日时分秒
        let yearPattern = #"(19|20)\d{2}"#
        let monthPattern = #"\b(0?[1-9]|1[0-2])\b"#
        let dayPattern = #"\b(0?[1-9]|[12]\d|3[01])\b"#
        
        guard let yearRange = string.range(of: yearPattern, options: .regularExpression),
              let year = Int(string[yearRange]) else {
            return nil
        }
        
        // 在年份之后查找月份和日期
        let afterYear = String(string[yearRange.upperBound...])
        
        guard let monthRange = afterYear.range(of: monthPattern, options: .regularExpression),
              let month = Int(afterYear[monthRange]) else {
            return nil
        }
        
        let afterMonth = String(afterYear[monthRange.upperBound...])
        
        guard let dayRange = afterMonth.range(of: dayPattern, options: .regularExpression),
              let day = Int(afterMonth[dayRange]) else {
            return nil
        }
        
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        
        return Calendar.current.date(from: components)
    }
    
    // MARK: - String Cleaning
    
    private static func cleanDateString(_ string: String) -> String {
        var cleaned = string
        
        // 移除常见的前缀/后缀
        let prefixes = ["Published:", "Updated:", "Posted:", "Date:", "发布于:", "更新于:", "时间:"]
        for prefix in prefixes {
            if let range = cleaned.range(of: prefix, options: .caseInsensitive) {
                cleaned = String(cleaned[range.upperBound...])
            }
        }
        
        // 移除 HTML 实体
        cleaned = cleaned
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&mdash;", with: "-")
        
        // 规范化空白字符
        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 移除尾部的时区缩写(如 "PST", "EST")如果已有数字时区
        if cleaned.contains("+") || cleaned.contains("-") {
            cleaned = cleaned.replacingOccurrences(
                of: #"\s+[A-Z]{3,4}$"#,
                with: "",
                options: .regularExpression
            )
        }
        
        return cleaned
    }
}
