import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var showAddActionSheet = false
    @State private var showAddGroupSheet = false
    @State private var showAddLinkSheet = false
    @State private var showLinkDetailSheet = false
    @State private var selectedLinkDetail: LinkDetailContext?
    @State private var selectedGroupIdForNewLink: UUID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(appModel.groups) { group in
                    Section(group.name) {
                        if group.links.isEmpty {
                            Text("暂无链接")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(group.links) { link in
                                LinkRow(
                                    link: link,
                                    groupId: group.id,
                                    onDetailTap: {
                                        selectedLinkDetail = LinkDetailContext(link: link, currentGroupId: group.id)
                                        showLinkDetailSheet = true
                                    },
                                    onDelete: {
                                        deleteLink(linkId: link.id, from: group.id)
                                    }
                                )
                            }
                            .onMove { source, destination in
                                moveLinkInGroup(groupId: group.id, from: source, to: destination)
                            }
                        }
                        Button {
                            selectedGroupIdForNewLink = group.id
                            showAddLinkSheet = true
                        } label: {
                            Label("添加链接", systemImage: "link.badge.plus")
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("订阅组")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddActionSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增分组或链接")
                }
            }
            .confirmationDialog("新增", isPresented: $showAddActionSheet, titleVisibility: .visible) {
                Button("新增分组") { showAddGroupSheet = true }
                Button("新增链接到分组") { showAddLinkSheet = true }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showAddGroupSheet) {
                AddGroupSheet { name in
                    appModel.addGroup(named: name)
                }
            }
            .sheet(isPresented: $showAddLinkSheet) {
                AddLinkSheet(groups: appModel.groups, preselectedGroupId: selectedGroupIdForNewLink) { groupId, title, url in
                    if let groupId { appModel.addLink(to: groupId, title: title, urlString: url) }
                }
            }
            .sheet(item: $selectedLinkDetail) { context in
                LinkDetailSheet(link: context.link, currentGroupId: context.currentGroupId) { newGroupId in
                    if newGroupId != context.currentGroupId {
                        appModel.moveLink(context.link.id, from: context.currentGroupId, to: newGroupId)
                    }
                }
            }
        }
    }
    
    private func moveLinkInGroup(groupId: UUID, from source: IndexSet, to destination: Int) {
        guard let groupIndex = appModel.groups.firstIndex(where: { $0.id == groupId }) else { return }
        appModel.groups[groupIndex].links.move(fromOffsets: source, toOffset: destination)
    }
    
    private func deleteLink(linkId: UUID, from groupId: UUID) {
        guard let groupIndex = appModel.groups.firstIndex(where: { $0.id == groupId }),
              let linkIndex = appModel.groups[groupIndex].links.firstIndex(where: { $0.id == linkId }) else {
            return
        }
        appModel.groups[groupIndex].links.remove(at: linkIndex)
    }
}

private struct LinkDetailContext: Identifiable {
    let id = UUID()
    let link: SubscriptionLink
    let currentGroupId: UUID
}

private struct LinkRow: View {
    let link: SubscriptionLink
    let groupId: UUID
    let onDetailTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(link.title)
                    .font(.headline)
                Text(link.urlString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                onDetailTap()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看详情")
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

private struct LinkDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appModel: AppModel
    let link: SubscriptionLink
    let currentGroupId: UUID
    let onMoveGroup: (UUID) -> Void
    
    @State private var selectedGroupId: UUID
    
    init(link: SubscriptionLink, currentGroupId: UUID, onMoveGroup: @escaping (UUID) -> Void) {
        self.link = link
        self.currentGroupId = currentGroupId
        self.onMoveGroup = onMoveGroup
        _selectedGroupId = State(initialValue: currentGroupId)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    Text(link.title)
                }
                Section("URL") {
                    Text(link.urlString)
                        .textSelection(.enabled)
                }
                Section("所在分组") {
                    Picker("分组", selection: $selectedGroupId) {
                        ForEach(appModel.groups) { group in
                            Text(group.name).tag(group.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section {
                    Button {
                        if let url = URL(string: link.urlString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("在浏览器中打开", systemImage: "safari")
                    }
                }
            }
            .navigationTitle("链接详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if selectedGroupId != currentGroupId {
                            onMoveGroup(selectedGroupId)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AddGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    var onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("分组名称", text: $name)
            }
            .navigationTitle("新增分组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct AddLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    var groups: [SubscriptionGroup]
    var preselectedGroupId: UUID?
    var onSave: (UUID?, String, String) -> Void

    @State private var selectedGroupId: UUID?
    @State private var title: String = ""
    @State private var url: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("分组", selection: Binding(get: {
                    selectedGroupId ?? preselectedGroupId ?? groups.first?.id
                }, set: { newValue in
                    selectedGroupId = newValue
                })) {
                    ForEach(groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                TextField("标题（可选）", text: $title)
                TextField("URL", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle("新增链接")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(selectedGroupId ?? preselectedGroupId ?? groups.first?.id, title, url)
                        dismiss()
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || groups.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct SubscriptionsView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionsView()
            .environmentObject(AppModel())
    }
}


