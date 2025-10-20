import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var showAddActionSheet = false
    @State private var showAddGroupSheet = false
    @State private var showAddLinkSheet = false
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
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(link.title)
                                        Text(link.urlString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        selectedGroupIdForNewLink = group.id
                                        showAddLinkSheet = true
                                    } label: {
                                        Image(systemName: "plus.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("添加链接到该分组")
                                }
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


