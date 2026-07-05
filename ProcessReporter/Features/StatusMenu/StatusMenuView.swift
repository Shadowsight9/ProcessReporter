import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var store = StatusMenuStore.shared

    var body: some View {
        VStack {
            Section("Status") {
                Label(
                    "\(store.statusDescription) - \(store.canSendNow ? "Reporting enabled" : "Reporting paused")",
                    systemImage: store.canSendNow ? "checkmark.circle.fill" : "pause.circle.fill"
                )
                    .foregroundStyle(.primary)
                Label(store.currentProcess, systemImage: "macwindow")
                Label(store.currentMedia, systemImage: "music.note")
                Label(store.lastReportSummary, systemImage: "clock.arrow.circlepath")
            }


            Divider()

            Button {
                store.openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()
            
            Toggle(isOn: Binding(
                get: { store.isEnabled },
                set: { _ in store.toggleEnabled() }
            )) {
                Label("Reporting", systemImage: store.isEnabled ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
            }

            Toggle(isOn: Binding(
                get: { store.enabledTypes.contains(.media) },
                set: { _ in store.toggleReportType(.media) }
            )) {
                Label("Report Media", systemImage: "play.rectangle")
            }
            .disabled(!store.isEnabled)
            
            Toggle(isOn: Binding(
                get: { store.enabledTypes.contains(.process) },
                set: { _ in store.toggleReportType(.process) }
            )) {
                Label("Report Process", systemImage: "app.connected.to.app.below.fill")
            }
            .disabled(!store.isEnabled)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear {
            store.refreshCurrentState()
        }
    }
}
