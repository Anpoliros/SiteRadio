import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var showGroupFilter = false
    @State private var selectedItem: FeedItem?

    var body: some View {
        NavigationStack {
            List(appModel.timelineItems) { item in
                FeedItemRow(item: item)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedItem = item
                    }
            }
            .refreshable {
                await appModel.refreshTimeline()
            }
            .overlay {
                if appModel.timelineItems.isEmpty && !appModel.isRefreshing {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("暂无内容")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("下拉刷新以获取最新内容")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .navigationTitle("时间线")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showGroupFilter = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text("分组")
                                .font(.caption)
                        }
                    }
                    .accessibilityLabel("选择分组")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if appModel.isRefreshing {
                        ProgressView()
                    } else {
                        Button {
                            Task {
                                await appModel.refreshTimeline()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("刷新")
                    }
                }
            }
            .sheet(isPresented: $showGroupFilter) {
                GroupFilterSheet()
            }
            .fullScreenCover(item: $selectedItem) { item in
                ArticleReaderView(item: item)
            }
        }
    }
}

private struct GroupFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appModel: AppModel
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("选择要显示的分组")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Section {
                    ForEach(appModel.groups) { group in
                        HStack {
                            Text(group.name)
                            Spacer()
                            if appModel.selectedGroupIds.contains(group.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appModel.toggleGroupSelection(group.id)
                        }
                    }
                }
                
                Section {
                    Button {
                        // 全选
                        appModel.selectedGroupIds = Set(appModel.groups.map { $0.id })
                    } label: {
                        Text("全选")
                    }
                    
                    Button {
                        // 全部取消
                        appModel.selectedGroupIds.removeAll()
                    } label: {
                        Text("全部取消")
                    }
                }
            }
            .navigationTitle("选择分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct FeedItemRow: View {
    let item: FeedItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 来源信息
            HStack {
                Text(item.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.publishedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 标题
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
            
            // 摘要
            if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            // 作者
            if let author = item.author, !author.isEmpty {
                Text("作者: \(author)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            // 标签
            if !item.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineView()
            .environmentObject(AppModel())
    }
}

