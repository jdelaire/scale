import SwiftUI

struct ContentView: View {
    let model: AppModel

    var body: some View {
        TabView {
            DashboardView(model: model)
                .tabItem {
                    Label("Scale", systemImage: "scalemass")
                }

            HistoryView(model: model)
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            SettingsView(model: model)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }

        }
        .scaleTabShellStyle()
    }
}

private extension View {
    @ViewBuilder
    func scaleTabShellStyle() -> some View {
        if #available(iOS 26.0, *) {
            tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }
}
