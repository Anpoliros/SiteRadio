import SwiftUI
import WebKit

struct ArticleReaderView: View {
    let item: FeedItem
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appModel: AppModel
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = true
    @State private var webView: WKWebView?
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                }
                .accessibilityLabel("返回")
                
                Button {
                    // 滚动到顶部
                    scrollToTop()
                } label: {
                    Text(item.title)
                        .font(.system(size: 17, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(UIColor.separator)),
                alignment: .bottom
            )
            
            // WebView
            ZStack {
                WebView(
                    url: item.url,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    isLoading: $isLoading,
                    webView: $webView
                )
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            
            // 底部工具栏
            HStack(spacing: 0) {
                // 返回
                Button {
                    if webView?.canGoBack == true {
                        webView?.goBack()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity)
                }
                //.disabled(!canGoBack)
                //.foregroundStyle(canGoBack ? .primary : .secondary)
                .accessibilityLabel("后退")
                
                //Divider()
                Spacer()
                
                // 收藏
                Button {
                    appModel.toggleFavorite(item.id)
                } label: {
                    Image(systemName: appModel.isFavorite(item.id) ? "heart.fill" : "heart")
                        .font(.system(size: 20))
                        .foregroundStyle(appModel.isFavorite(item.id) ? .red : .primary)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(appModel.isFavorite(item.id) ? "取消收藏" : "收藏")
                
                Spacer()
                
                // 分享
                ShareLink(item: item.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("分享")
                
                Spacer()
                
                // 在Safari中打开
                Button {
                    UIApplication.shared.open(item.url)
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("在Safari中打开")
            }
            .frame(height: 50)
            .background(Color(UIColor.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(UIColor.separator)),
                alignment: .top
            )
        }
        .onAppear {
            // 进入时滚动到顶部
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                scrollToTop()
            }
        }
    }
    
    private func scrollToTop() {
        webView?.scrollView.setContentOffset(.zero, animated: true)
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var webView: WKWebView?
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        
        // 配置
        webView.allowsBackForwardNavigationGestures = true
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // 保存webView引用
        DispatchQueue.main.async {
            self.webView = webView
        }
        
        if webView.url == nil {
            let request = URLRequest(url: url)
            webView.load(request)
        }
        
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        
        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            // 等页面稳定后滚动到顶部
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                webView.scrollView.setContentOffset(.zero, animated: false)
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }
    }
}

