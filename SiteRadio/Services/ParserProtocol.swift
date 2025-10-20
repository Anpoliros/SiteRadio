import Foundation

/// 文章解析器协议 - 定义统一的解析接口
protocol ArticleParser {
    /// 解析HTML内容，返回文章信息
    /// - Parameter html: 待解析的HTML字符串
    /// - Parameter url: 源URL，用于解析相对路径
    /// - Returns: 解析后的文章信息，如果解析失败返回nil
    func parse(html: String, from url: URL) -> ParsedArticle?
}

/// 默认HTML解析器 - 使用简单的正则和字符串匹配
struct DefaultHTMLParser: ArticleParser {
    func parse(html: String, from url: URL) -> ParsedArticle? {
        // 提取标题
        let title = extractTitle(from: html) ?? "Untitled"
        
        // 提取摘要
        let summary = extractSummary(from: html)
        
        // 提取内容
        let content = extractContent(from: html)
        
        // 提取作者
        let author = extractAuthor(from: html)
        
        // 提取发布日期
        let publishedAt = extractPublishedDate(from: html)
        
        // 提取图片
        let imageURL = extractImageURL(from: html, baseURL: url)
        
        // 提取标签
        let tags = extractTags(from: html)
        
        return ParsedArticle(
            title: title,
            url: url,
            publishedAt: publishedAt,
            summary: summary,
            content: content,
            author: author,
            imageURL: imageURL,
            tags: tags
        )
    }
    
    // MARK: - Private Extraction Methods
    
    private func extractTitle(from html: String) -> String? {
        // 尝试匹配 <title> 标签
        if let titleRange = html.range(of: #"<title[^>]*>([^<]+)</title>"#, options: .regularExpression) {
            let titleMatch = html[titleRange]
            if let contentRange = titleMatch.range(of: #">[^<]+<"#, options: .regularExpression) {
                let content = String(titleMatch[contentRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "><"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return content.isEmpty ? nil : content
            }
        }
        
        // 尝试匹配 <h1> 标签
        if let h1Range = html.range(of: #"<h1[^>]*>([^<]+)</h1>"#, options: .regularExpression) {
            let h1Match = html[h1Range]
            if let contentRange = h1Match.range(of: #">[^<]+<"#, options: .regularExpression) {
                let content = String(h1Match[contentRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "><"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return content.isEmpty ? nil : content
            }
        }
        
        return nil
    }
    
    private func extractSummary(from html: String) -> String? {
        // 尝试匹配 <meta name="description"> 标签
        if let descRange = html.range(of: #"<meta[^>]*name=["']description["'][^>]*content=["']([^"']+)["']"#, options: .regularExpression) {
            let descMatch = html[descRange]
            if let contentRange = descMatch.range(of: #"content=\"[^\"]+\""#, options: .regularExpression) {
                let content = String(descMatch[contentRange])
                .replacingOccurrences(of: #"content=\""#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\"$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return content.isEmpty ? nil : content
            }
        }
        
        // 尝试匹配 <p> 标签作为摘要
        if let pRange = html.range(of: #"<p[^>]*>([^<]{50,200})"#, options: .regularExpression) {
            let pMatch = html[pRange]
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
    
    private func extractContent(from html: String) -> String? {
        // 尝试匹配 <article> 或 <main> 标签
        let articlePatterns = [
            #"<article[^>]*>([\s\S]{100,5000})</article>"#,
            #"<main[^>]*>([\s\S]{100,5000})</main>"#,
            #"<div[^>]*class=["'][^"']*content[^"']*["'][^>]*>([\s\S]{100,5000})</div>"#
        ]
        
        for pattern in articlePatterns {
            if let contentRange = html.range(of: pattern, options: .regularExpression) {
                let content = String(html[contentRange])
                let cleaned = cleanHTML(content)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        
        return nil
    }
    
    private func extractAuthor(from html: String) -> String? {
        // 尝试匹配 <meta name="author"> 标签
        if let authorRange = html.range(of: #"<meta[^>]*name=["']author["'][^>]*content=["']([^"']+)["']"#, options: .regularExpression) {
            let authorMatch = html[authorRange]
            if let contentRange = authorMatch.range(of: #"content=\"[^\"]+\""#, options: .regularExpression) {
                let content = String(authorMatch[contentRange])
                    .replacingOccurrences(of: #"content=\""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\"$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return content.isEmpty ? nil : content
            }
        }
        
        return nil
    }
    
    private func extractPublishedDate(from html: String) -> Date? {
        // 尝试匹配 <time> 标签
        if let timeRange = html.range(of: #"<time[^>]*datetime=["']([^"']+)["']"#, options: .regularExpression) {
            let timeMatch = html[timeRange]
            if let dateRange = timeMatch.range(of: #"datetime=\"[^\"]+\""#, options: .regularExpression) {
                let dateString = String(timeMatch[dateRange])
                    .replacingOccurrences(of: #"datetime=\""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\"$"#, with: "", options: .regularExpression)
                
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
        }
        
        // 尝试匹配 <meta property="article:published_time">
        if let metaRange = html.range(of: #"<meta[^>]*property=["']article:published_time["'][^>]*content=["']([^"']+)["']"#, options: .regularExpression) {
            let metaMatch = html[metaRange]
            if let contentRange = metaMatch.range(of: #"content=\"[^\"]+\""#, options: .regularExpression) {
                let dateString = String(metaMatch[contentRange])
                    .replacingOccurrences(of: #"content=\""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\"$"#, with: "", options: .regularExpression)
                
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
        }
        
        return nil
    }
    
    private func extractImageURL(from html: String, baseURL: URL) -> URL? {
        // 尝试匹配 <meta property="og:image">
        if let ogImageRange = html.range(of: #"<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']"#, options: .regularExpression) {
            let ogImageMatch = html[ogImageRange]
            if let contentRange = ogImageMatch.range(of: #"content=\"[^\"]+\""#, options: .regularExpression) {
                let imageString = String(ogImageMatch[contentRange])
                    .replacingOccurrences(of: #"content=\""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\"$"#, with: "", options: .regularExpression)
                
                if let url = URL(string: imageString) {
                    return url
                } else if let url = URL(string: imageString, relativeTo: baseURL) {
                    return url
                }
            }
        }
        
        // 尝试匹配第一个 <img> 标签
        if let imgRange = html.range(of: #"<img[^>]*src=["']([^"']+)["']"#, options: .regularExpression) {
            let imgMatch = html[imgRange]
            if let srcRange = imgMatch.range(of: #"src=\"[^\"]+\""#, options: .regularExpression) {
                let imageString = String(imgMatch[srcRange])
                    .replacingOccurrences(of: #"src=\""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\"$"#, with: "", options: .regularExpression)
                
                if let url = URL(string: imageString) {
                    return url
                } else if let url = URL(string: imageString, relativeTo: baseURL) {
                    return url
                }
            }
        }
        
        return nil
    }
    
    private func extractTags(from html: String) -> [String] {
        var tags: [String] = []
        
        // 尝试匹配 <meta property="article:tag">
        let pattern = #"<meta[^>]*property=["']article:tag["'][^>]*content=["']([^"']+)["']"#
        var searchRange = html.startIndex..<html.endIndex
        
        while let tagRange = html.range(of: pattern, options: .regularExpression, range: searchRange) {
            let tagMatch = html[tagRange]
            if let contentRange = tagMatch.range(of: #"content=\"[^\"]+\""#, options: .regularExpression) {
                let tagString = String(tagMatch[contentRange])
                    .replacingOccurrences(of: #"content=\""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\"$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !tagString.isEmpty {
                    tags.append(tagString)
                }
            }
            
            searchRange = tagRange.upperBound..<html.endIndex
        }
        
        return tags
    }
    
    private func cleanHTML(_ html: String) -> String {
        var cleaned = html
        
        // 移除HTML标签
        cleaned = cleaned.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        
        // 移除多余的空白
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        // 移除HTML实体
        cleaned = cleaned.replacingOccurrences(of: "&nbsp;", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        cleaned = cleaned.replacingOccurrences(of: "&lt;", with: "<")
        cleaned = cleaned.replacingOccurrences(of: "&gt;", with: ">")
        cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&apos;", with: "'")
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

