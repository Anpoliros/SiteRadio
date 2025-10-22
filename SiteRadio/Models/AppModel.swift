import Foundation

struct SubscriptionLink: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var urlString: String

    init(id: UUID = UUID(), title: String, urlString: String) {
        self.id = id
        self.title = title
        self.urlString = urlString
    }
}

struct SubscriptionGroup: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var links: [SubscriptionLink]

    init(id: UUID = UUID(), name: String, links: [SubscriptionLink] = []) {
        self.id = id
        self.name = name
        self.links = links
    }
}

final class AppModel: ObservableObject {
    @Published var timelineItems: [FeedItem] = []
    @Published var groups: [SubscriptionGroup] = []
    @Published var isRefreshing = false
    @Published var selectedGroupIds: Set<UUID> = []
    @Published var favoriteItems: Set<UUID> = []
    
    private let feedService = FeedService()

    init() {
        loadInitialData()
    }

    func loadInitialData() {
        groups = [
            SubscriptionGroup(name: "默认分组", links: [
//                SubscriptionLink(title: "Apple Newsroom", urlString: "https://www.apple.com/newsroom/"),
//                SubscriptionLink(title: "Swift.org", urlString: "https://www.swift.org/blog/"),
                SubscriptionLink(title: "Anpoliros", urlString: "https://anpoliros.fun/"),
                SubscriptionLink(title: "Solidot", urlString: "https://www.solidot.org"),
                SubscriptionLink(title: "HakuNews", urlString: "https://security.fudan.edu.cn/news/")
            ])
        ]

        // 初始化时间线为空，等待用户刷新
        timelineItems = []
        // 默认选择所有分组
        selectedGroupIds = Set(groups.map { $0.id })
    }
    
    /// 切换收藏状态
    func toggleFavorite(_ itemId: UUID) {
        if favoriteItems.contains(itemId) {
            favoriteItems.remove(itemId)
        } else {
            favoriteItems.insert(itemId)
        }
    }
    
    /// 检查是否已收藏
    func isFavorite(_ itemId: UUID) -> Bool {
        favoriteItems.contains(itemId)
    }

    func addGroup(named name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let newGroup = SubscriptionGroup(name: name)
        groups.append(newGroup)
        // 自动选中新分组
        selectedGroupIds.insert(newGroup.id)
    }

    func addLink(to groupId: UUID, title: String, urlString: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else { return }
        let link = SubscriptionLink(title: trimmedTitle.isEmpty ? trimmedUrl : trimmedTitle, urlString: trimmedUrl)
        groups[index].links.append(link)
    }
    
    /// 移动链接到另一个分组
    func moveLink(_ linkId: UUID, from sourceGroupId: UUID, to targetGroupId: UUID) {
        guard let sourceIndex = groups.firstIndex(where: { $0.id == sourceGroupId }),
              let targetIndex = groups.firstIndex(where: { $0.id == targetGroupId }),
              let linkIndex = groups[sourceIndex].links.firstIndex(where: { $0.id == linkId }) else {
            return
        }
        
        let link = groups[sourceIndex].links[linkIndex]
        groups[sourceIndex].links.remove(at: linkIndex)
        groups[targetIndex].links.append(link)
    }
    
    /// 切换分组的选中状态
    func toggleGroupSelection(_ groupId: UUID) {
        if selectedGroupIds.contains(groupId) {
            selectedGroupIds.remove(groupId)
        } else {
            selectedGroupIds.insert(groupId)
        }
    }
    
    /// 获取当前选中的分组
    var selectedGroups: [SubscriptionGroup] {
        groups.filter { selectedGroupIds.contains($0.id) }
    }
    
    /// 刷新时间线 - 从选中的订阅组抓取最新内容
    @MainActor
    func refreshTimeline() async {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        defer { isRefreshing = false }
        
        print("🔄 开始刷新时间线...")
        
        // 从选中的订阅组抓取内容
        let newItems = await feedService.fetchFeeds(from: selectedGroups)
        
        // 更新时间线
        timelineItems = newItems
        
        print("✅ 时间线刷新完成，共 \(newItems.count) 条内容")
    }
}

