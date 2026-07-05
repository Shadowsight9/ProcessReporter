import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var store = StatusMenuStore.shared

    var body: some View {
        VStack {
            Section("Current Process") {
                Text(store.currentProcess)
            }

            Section("Current Media") {
                Text(store.currentMedia)
            }

            Section("Last Send") {
                Text(store.lastProcess)
                Text(store.lastMedia)
                Text(store.lastReportTime?.relativeTimeDescription() ?? "No report yet")
            }

            Divider()

            Button(store.isEnabled ? "Disable Reporting" : "Enable Reporting") {
                store.toggleEnabled()
            }
            Button("Request Accessibility Permission") {
                store.requestAccessibilityPermission()
            }
            Button("Settings") {
                store.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Toggle("Media", isOn: Binding(
                get: { store.enabledTypes.contains(.media) },
                set: { _ in store.toggleReportType(.media) }
            ))
            Toggle("Process", isOn: Binding(
                get: { store.enabledTypes.contains(.process) },
                set: { _ in store.toggleReportType(.process) }
            ))

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear {
            store.refreshCurrentState()
        }
    }
}
