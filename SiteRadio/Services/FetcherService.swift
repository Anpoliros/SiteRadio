import Foundation

/// 网络抓取服务 - 负责从URL获取HTML内容
class FetcherService {
    private let session: URLSession
    private let timeout: TimeInterval
    private let listParser: ArticleListParser
    
    init(timeout: TimeInterval = 10.0, listParser: ArticleListParser = ArticleListParser()) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ]
        
        self.session = URLSession(configuration: config)
        self.timeout = timeout
        self.listParser = listParser
    }
    
    /// 从指定URL获取HTML内容
    /// - Parameter url: 要抓取的URL
    /// - Returns: HTML字符串，如果失败返回nil
    func fetchHTML(from url: URL) async -> String? {
        do {
            let (data, response) = try await session.data(from: url)
            
            // 检查HTTP响应状态
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("❌ HTTP Error: \(httpResponse.statusCode) for \(url)")
                    return nil
                }
                
                // 检查Content-Type
                if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
                   !contentType.contains("text/html") {
                    print("⚠️ Unexpected Content-Type: \(contentType) for \(url)")
                }
            }
            
            // 尝试检测编码
            let encoding = detectEncoding(from: data, response: response)
            
            // 转换为字符串
            if let htmlString = String(data: data, encoding: encoding) {
                return htmlString
            } else {
                print("❌ Failed to decode HTML from \(url)")
                return nil
            }
            
        } catch {
            print("❌ Fetch error for \(url): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 批量抓取多个URL
    /// - Parameter urls: 要抓取的URL数组
    /// - Returns: URL到HTML的字典映射
    func fetchMultiple(urls: [URL]) async -> [URL: String] {
        await withTaskGroup(of: (URL, String?).self) { group in
            for url in urls {
                group.addTask {
                    let html = await self.fetchHTML(from: url)
                    return (url, html)
                }
            }
            
            var results: [URL: String] = [:]
            for await (url, html) in group {
                if let html = html {
                    results[url] = html
                }
            }
            
            return results
        }
    }
    
    /// 从URL抓取文章列表
    /// - Parameter url: 要抓取的URL
    /// - Returns: 提取到的文章列表
    func fetchArticleList(from url: URL) async -> [ExtractedArticle] {
        guard let html = await fetchHTML(from: url) else {
            print("❌ 无法获取HTML: \(url)")
            return []
        }
        
        let articles = listParser.extractArticles(from: html, baseURL: url)
        print("📋 从 \(url) 提取到 \(articles.count) 篇文章")
        
        return articles
    }
    
    /// 批量抓取多个URL的文章列表
    /// - Parameter urls: 要抓取的URL数组
    /// - Returns: 所有提取到的文章列表
    func fetchArticleLists(from urls: [URL]) async -> [ExtractedArticle] {
        await withTaskGroup(of: [ExtractedArticle].self) { group in
            for url in urls {
                group.addTask {
                    await self.fetchArticleList(from: url)
                }
            }
            
            var allArticles: [ExtractedArticle] = []
            for await articles in group {
                allArticles.append(contentsOf: articles)
            }
            
            return allArticles
        }
    }
    
    // MARK: - Private Methods
    
    private func detectEncoding(from data: Data, response: URLResponse) -> String.Encoding {
        // 1. 尝试从HTTP响应头获取
        if let httpResponse = response as? HTTPURLResponse,
           let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           let encoding = parseEncoding(from: contentType) {
            return encoding
        }
        
        // 2. 尝试从HTML meta标签获取
        if let htmlString = String(data: data, encoding: .utf8),
           let encoding = parseEncodingFromHTML(htmlString) {
            return encoding
        }
        
        // 3. 尝试BOM检测
        if let encoding = detectBOM(from: data) {
            return encoding
        }
        
        // 4. 默认使用UTF-8
        return .utf8
    }
    
    private func parseEncoding(from contentType: String) -> String.Encoding? {
        let pattern = #"charset=([^;\s]+)"#
        if let range = contentType.range(of: pattern, options: .regularExpression) {
            let encodingString = String(contentType[range])
                .replacingOccurrences(of: "charset=", with: "")
                .uppercased()
            
            return encodingFromString(encodingString)
        }
        return nil
    }
    
    private func parseEncodingFromHTML(_ html: String) -> String.Encoding? {
        // 匹配 <meta charset="...">
        if let range = html.range(of: #"<meta[^>]*charset=["']([^"']+)["']"#, options: .regularExpression) {
            let match = String(html[range])
            if let encodingRange = match.range(of: #"charset="[^"]+""#, options: .regularExpression) {
                let encodingString = String(match[encodingRange])
                    .replacingOccurrences(of: #"charset=""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #""$"#, with: "", options: .regularExpression)
                    .uppercased()
                
                return encodingFromString(encodingString)
            }
        }
        
        // 匹配 <meta http-equiv="Content-Type" content="...charset=...">
        if let range = html.range(of: #"<meta[^>]*http-equiv=["']Content-Type["'][^>]*content=["'][^"']*charset=([^"';]+)"#, options: .regularExpression) {
            let match = String(html[range])
            if let charsetRange = match.range(of: #"charset=[^"';]+"#, options: .regularExpression) {
                let encodingString = String(match[charsetRange])
                    .replacingOccurrences(of: "charset=", with: "")
                    .uppercased()
                
                return encodingFromString(encodingString)
            }
        }
        
        return nil
    }
    
    private func detectBOM(from data: Data) -> String.Encoding? {
        guard data.count >= 3 else { return nil }
        
        let bytes = data.prefix(3)
        
        // UTF-8 BOM: EF BB BF
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return .utf8
        }
        
        // UTF-16 BE BOM: FE FF
        if data.count >= 2 && data.prefix(2).starts(with: [0xFE, 0xFF]) {
            return .utf16BigEndian
        }
        
        // UTF-16 LE BOM: FF FE
        if data.count >= 2 && data.prefix(2).starts(with: [0xFF, 0xFE]) {
            return .utf16LittleEndian
        }
        
        return nil
    }
    
    private func encodingFromString(_ encodingString: String) -> String.Encoding? {
        switch encodingString.uppercased() {
        case "UTF-8", "UTF8":
            return .utf8
        case "UTF-16", "UTF16":
            return .utf16
        case "UTF-32", "UTF32":
            return .utf32
        case "ISO-8859-1", "ISO8859-1", "LATIN1":
            return .isoLatin1
        case "GB2312", "GBK", "GB18030":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        case "BIG5":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        default:
            return nil
        }
    }
}

