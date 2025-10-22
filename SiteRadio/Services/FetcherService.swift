import Foundation

/// 网络抓取服务 - 专注于从 URL 获取 HTML 内容
final class FetcherService: HTMLFetcher {
    
    // MARK: - Properties
    
    private let session: URLSession
    private let timeout: TimeInterval
    
    // MARK: - Initialization
    
    init(timeout: TimeInterval = 10.0) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept-Encoding": "gzip, deflate, br"
        ]
        
        self.session = URLSession(configuration: config)
        self.timeout = timeout
    }
    
    // MARK: - HTMLFetcher Protocol
    
    func fetch(url: URL) async throws -> String {
        do {
            let (data, response) = try await session.data(from: url)
            
            // 验证 HTTP 响应
            try validateResponse(response, for: url)
            
            // 检测并解码
            let encoding = detectEncoding(from: data, response: response)
            guard let html = String(data: data, encoding: encoding) else {
                throw FetcherError.decodingFailed(url, encoding)
            }
            
            return html
            
        } catch let error as FetcherError {
            throw error
        } catch {
            throw FetcherError.networkError(url, error)
        }
    }
    
    // MARK: - Batch Fetching
    
    /// 批量抓取多个 URL（并发）
    /// - Parameter urls: URL 数组
    /// - Returns: 成功抓取的结果字典 (URL -> HTML)
    func fetchBatch(_ urls: [URL]) async -> [URL: Result<String, Error>] {
        await withTaskGroup(of: (URL, Result<String, Error>).self) { group in
            for url in urls {
                group.addTask {
                    do {
                        let html = try await self.fetch(url: url)
                        return (url, .success(html))
                    } catch {
                        return (url, .failure(error))
                    }
                }
            }
            
            var results: [URL: Result<String, Error>] = [:]
            for await (url, result) in group {
                results[url] = result
            }
            
            return results
        }
    }
    
    // MARK: - Private Methods
    
    private func validateResponse(_ response: URLResponse, for url: URL) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetcherError.invalidResponse(url)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw FetcherError.httpError(url, httpResponse.statusCode)
        }
        
        // 检查 Content-Type（警告而非错误）
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           !contentType.contains("text/html") && !contentType.contains("application/xhtml") {
            print("⚠️ 意外的 Content-Type: \(contentType) for \(url)")
        }
    }
    
    // MARK: - Encoding Detection
    
    private func detectEncoding(from data: Data, response: URLResponse) -> String.Encoding {
        // 1. HTTP 响应头
        if let httpResponse = response as? HTTPURLResponse,
           let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           let encoding = parseEncodingFromContentType(contentType) {
            return encoding
        }
        
        // 2. BOM 检测
        if let encoding = detectBOM(from: data) {
            return encoding
        }
        
        // 3. HTML meta 标签
        if let tempString = String(data: data.prefix(2048), encoding: .utf8),
           let encoding = parseEncodingFromHTML(tempString) {
            return encoding
        }
        
        // 4. 默认 UTF-8
        return .utf8
    }
    
    private func parseEncodingFromContentType(_ contentType: String) -> String.Encoding? {
        guard let range = contentType.range(of: #"charset=([^;\s]+)"#, options: .regularExpression) else {
            return nil
        }
        
        let charsetString = String(contentType[range])
            .replacingOccurrences(of: "charset=", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return encodingFromString(charsetString)
    }
    
    private func detectBOM(from data: Data) -> String.Encoding? {
        guard data.count >= 2 else { return nil }
        
        let prefix = data.prefix(4)
        
        // UTF-8 BOM: EF BB BF
        if prefix.starts(with: [0xEF, 0xBB, 0xBF]) {
            return .utf8
        }
        
        // UTF-16 BE: FE FF
        if prefix.starts(with: [0xFE, 0xFF]) {
            return .utf16BigEndian
        }
        
        // UTF-16 LE: FF FE
        if prefix.starts(with: [0xFF, 0xFE]) {
            return .utf16LittleEndian
        }
        
        return nil
    }
    
    private func parseEncodingFromHTML(_ html: String) -> String.Encoding? {
        // <meta charset="...">
        if let range = html.range(of: #"<meta[^>]+charset=["']?([^"'\s>]+)"#, options: .regularExpression) {
            let match = String(html[range])
            if let charsetRange = match.range(of: #"charset=["']?([^"'\s>]+)"#, options: .regularExpression) {
                let charset = String(match[charsetRange])
                    .replacingOccurrences(of: #"charset=["']?"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"["']?"#, with: "", options: .regularExpression)
                return encodingFromString(charset)
            }
        }
        
        // <meta http-equiv="Content-Type" content="...charset=...">
        if let range = html.range(of: #"<meta[^>]+http-equiv=["']Content-Type["'][^>]+content=[^>]+charset=([^"'\s;>]+)"#, options: .regularExpression) {
            let match = String(html[range])
            if let charsetRange = match.range(of: #"charset=([^"'\s;>]+)"#, options: .regularExpression) {
                let charset = String(match[charsetRange])
                    .replacingOccurrences(of: "charset=", with: "")
                return encodingFromString(charset)
            }
        }
        
        return nil
    }
    
    private func encodingFromString(_ string: String) -> String.Encoding? {
        let normalized = string.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch normalized {
        case "UTF-8", "UTF8":
            return .utf8
        case "UTF-16", "UTF16":
            return .utf16
        case "UTF-32", "UTF32":
            return .utf32
        case "ISO-8859-1", "ISO8859-1", "LATIN1":
            return .isoLatin1
        case "GB2312", "GBK", "GB18030":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        case "BIG5", "BIG-5":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue)))
        default:
            return nil
        }
    }
}

// MARK: - Error Types

enum FetcherError: LocalizedError {
    case networkError(URL, Error)
    case httpError(URL, Int)
    case invalidResponse(URL)
    case decodingFailed(URL, String.Encoding)
    case timeout(URL)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let url, let error):
            return "网络错误 (\(url.host ?? "")): \(error.localizedDescription)"
        case .httpError(let url, let code):
            return "HTTP \(code) 错误 (\(url.host ?? ""))"
        case .invalidResponse(let url):
            return "无效的响应 (\(url.host ?? ""))"
        case .decodingFailed(let url, let encoding):
            return "解码失败 (\(url.host ?? ""), 编码: \(encoding))"
        case .timeout(let url):
            return "请求超时 (\(url.host ?? ""))"
        }
    }
}
