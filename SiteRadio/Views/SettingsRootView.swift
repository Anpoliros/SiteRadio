import SwiftUI

struct SettingsRootView: View {
    @AppStorage("enableNotifications") private var enableNotifications: Bool = false
    @AppStorage("openLinksInApp") private var openLinksInApp: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("常规") {
                    Toggle("通知", isOn: $enableNotifications)
                    Toggle("在应用内打开链接", isOn: $openLinksInApp)
                }
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://example.com")!) {
                        Label("项目主页", systemImage: "link")
                    }
                }
            }
            .navigationTitle("设置")
        }
    }
}

struct SettingsRootView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsRootView()
    }
}


