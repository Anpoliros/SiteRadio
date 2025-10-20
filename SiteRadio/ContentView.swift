import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TimelineView()
                .tabItem {
                    Label("时间线", systemImage: "clock")
                }

            SubscriptionsView()
                .tabItem {
                    Label("订阅组", systemImage: "tray.full")
                }

            SettingsRootView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppModel())
    }
}


