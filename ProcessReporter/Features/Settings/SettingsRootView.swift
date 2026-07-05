import SwiftUI

struct SettingsRootView: View {
    @StateObject private var store = PreferencesStore()

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsView(store: store)
            }
            Tab("Integration", systemImage: "terminal") {
                ShellIntegrationSettingsView(store: store)
            }
            Tab("Filter", systemImage: "line.3.horizontal.decrease.circle") {
                PreferencesFilterView(store: store)
            }
            Tab("Mapping", systemImage: "arrow.trianglehead.swap") {
                MappingSettingsView(store: store)
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                HistorySettingsView()
            }
        }
        .frame(minWidth: 720, minHeight: 460)
    }
}
