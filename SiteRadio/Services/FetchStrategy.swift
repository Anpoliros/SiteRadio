import Foundation

/// 抓取策略协议 - 定义如何从HTML中提取文章列表
protocol FetchStrategy {
    /// 从HTML中提取文章列表
    /// - Parameters:
    ///   - html: 待解析的HTML字符串
    ///   - baseURL: 源URL，用于解析相对路径
    /// - Returns: 提取到的文章列表
    func extractArticles(from html: String, baseURL: URL) -> [ExtractedArticle]
}

/// 提取到的文章信息（仅包含URL和标题）
struct ExtractedArticle {
    let title: String
    let url: URL
    let publishedAt: Date?
    let summary: String?
    let author: String?
}

/// 默认抓取策略 - 匹配 <article> 标签
struct DefaultArticleListStrategy: FetchStrategy {
    func extractArticles(from html: String, baseURL: URL) -> [ExtractedArticle] {
        var articles: [ExtractedArticle] = []
        
        // 匹配所有 <article> 标签
        let pattern = #"<article[^>]*>([\s\S]*?)</article>"#
        var searchRange = html.startIndex..<html.endIndex
        
        while let articleRange = html.range(of: pattern, options: .regularExpression, range: searchRange) {
            let articleHTML = String(html[articleRange])
            
            // 提取标题
            let title = extractTitle(from: articleHTML) ?? "Untitled"
            
            // 提取链接
            guard let url = extractURL(from: articleHTML, baseURL: baseURL) else {
                searchRange = articleRange.upperBound..<html.endIndex
                continue
            }
            
            // 提取发布日期
            let publishedAt = extractPublishedDate(from: articleHTML)
            
            // 提取摘要
            let summary = extractSummary(from: articleHTML)
            
            // 提取作者
            let author = extractAuthor(from: articleHTML)
            
            articles.append(ExtractedArticle(
                title: title,
                url: url,
                publishedAt: publishedAt,
                summary: summary,
                author: author
            ))
            
            searchRange = articleRange.upperBound..<html.endIndex
        }
        
        return articles
    }
    
    // MARK: - Private Extraction Methods
    
    private func extractTitle(from html: String) -> String? {
        // 尝试匹配 <h1>, <h2>, <h3> 标签
        let headerPatterns = [
            #"<h1[^>]*>([^<]+)</h1>"#,
            #"<h2[^>]*>([^<]+)</h2>"#,
            #"<h3[^>]*>([^<]+)</h3>"#
        ]
        
        for pattern in headerPatterns {
            if let range = html.range(of: pattern, options: .regularExpression) {
                let match = String(html[range])
                if let contentRange = match.range(of: #">[^<]+<"#, options: .regularExpression) {
                    let content = String(match[contentRange])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "><"))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty {
                        return content
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractURL(from html: String, baseURL: URL) -> URL? {
        // 优先匹配 <a> 标签中的 href
        if let linkRange = html.range(of: #"<a[^>]*href=["']([^"']+)["']"#, options: .regularExpression) {
            let linkMatch = String(html[linkRange])
            if let hrefRange = linkMatch.range(of: #"href="[^"]+""#, options: .regularExpression) {
                let hrefString = String(linkMatch[hrefRange])
                    .replacingOccurrences(of: #"href=""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #""$"#, with: "", options: .regularExpression)
                
                if let url = URL(string: hrefString) {
                    return url
                } else if let url = URL(string: hrefString, relativeTo: baseURL) {
                    return url
                }
            }
        }
        
        return nil
    }
    
    private func extractPublishedDate(from html: String) -> Date? {
        // 尝试匹配 <time> 标签
        if let timeRange = html.range(of: #"<time[^>]*datetime=["']([^"']+)["']"#, options: .regularExpression) {
            let timeMatch = String(html[timeRange])
            if let dateRange = timeMatch.range(of: #"datetime="[^"]+""#, options: .regularExpression) {
                let dateString = String(timeMatch[dateRange])
                    .replacingOccurrences(of: #"datetime=""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #""$"#, with: "", options: .regularExpression)
                
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
        }
        
        // 尝试匹配 title 属性中的日期
        if let titleRange = html.range(of: #"title=['"]([^'"]*[\d]{4}[\s-][\d]{1,2}[\s-][\d]{1,2}[^'"]*)['"]"#, options: .regularExpression) {
            let titleMatch = String(html[titleRange])
            if let dateRange = titleMatch.range(of: #"title="[^"]+""#, options: .regularExpression) {
                let dateString = String(titleMatch[dateRange])
                    .replacingOccurrences(of: #"title=""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #""$"#, with: "", options: .regularExpression)
                
                // 尝试多种日期格式
                let formatters = [
                    createDateFormatter(format: "yyyy-MM-dd HH:mm:ss Z"),
                    createDateFormatter(format: "yyyy-MM-dd HH:mm:ss"),
                    createDateFormatter(format: "yyyy-MM-dd"),
                    createDateFormatter(format: "MMMM dd, yyyy")
                ]
                
                for formatter in formatters {
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractSummary(from html: String) -> String? {
        // 尝试匹配 <p> 标签作为摘要
        if let pRange = html.range(of: #"<p[^>]*>([^<]{20,200})"#, options: .regularExpression) {
            let pMatch = String(html[pRange])
            if let contentRange = pMatch.range(of: #">[^<]+"#, options: .regularExpression) {
                let content = String(pMatch[contentRange])
                    .replacingOccurrences(of: ">", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                return content.isEmpty ? nil : String(content.prefix(200))
            }
        }
        
        return nil
    }
    
    private func extractAuthor(from html: String) -> String? {
        // 尝试匹配 <span> 或 <footer> 中的作者信息
        if let authorRange = html.range(of: #"<span[^>]*>([A-Za-z][A-Za-z0-9\s]+)</span>"#, options: .regularExpression) {
            let authorMatch = String(html[authorRange])
            if let contentRange = authorMatch.range(of: #">[^<]+<"#, options: .regularExpression) {
                let content = String(authorMatch[contentRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "><"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty && content.count < 50 {
                    return content
                }
            }
        }
        
        return nil
    }
    
    private func createDateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

