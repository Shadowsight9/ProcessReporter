import SwiftUI

struct SettingsRootView: View {
    @StateObject private var store = PreferencesStore()

    var body: some View {
        TabView {
            GeneralSettingsView(store: store)
                .tabItem { Label("General", systemImage: "gear") }
            ShellIntegrationSettingsView(store: store)
                .tabItem { Label("Integration", systemImage: "terminal") }
            PreferencesFilterView(store: store)
                .tabItem { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
            MappingSettingsView(store: store)
                .tabItem { Label("Mapping", systemImage: "arrow.trianglehead.swap") }
            HistorySettingsView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .frame(minWidth: 720, minHeight: 460)
    }
}
