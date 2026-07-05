import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var store: PreferencesStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var importError: String?

    var body: some View {
        Form {
            Section("App") {
                Toggle("Enabled", isOn: Binding(
                    get: { store.isEnabled },
                    set: { store.setEnabled($0) }
                ))
                Toggle("Start at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: setLaunchAtLogin
                ))
                Button("Request Accessibility Permission") {
                    if ApplicationMonitor.shared.requestAccessibilityAuthorization() {
                        ToastManager.shared.success("Accessibility permission is already enabled.")
                    }
                }
            }

            Section("Report") {
                Toggle("Report when application focused", isOn: Binding(
                    get: { store.focusReport },
                    set: { store.setFocusReport($0) }
                ))
                Toggle("Ignore media reports with empty artist", isOn: Binding(
                    get: { store.ignoreNullArtist },
                    set: { store.setIgnoreNullArtist($0) }
                ))
                Picker("Send interval", selection: Binding(
                    get: { store.sendInterval },
                    set: { store.setSendInterval($0) }
                )) {
                    ForEach(SendInterval.allCases, id: \.self) { interval in
                        Text(interval.toString()).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Report Types") {
                Toggle("Process", isOn: Binding(
                    get: { store.enabledTypes.contains(.process) },
                    set: { store.setReportType(.process, enabled: $0) }
                ))
                Toggle("Media", isOn: Binding(
                    get: { store.enabledTypes.contains(.media) },
                    set: { store.setReportType(.media, enabled: $0) }
                ))
            }

            Section("Settings Backup") {
                HStack {
                    Button("Import Settings", action: importSettings)
                    Button("Export Settings", action: exportSettings)
                }
                if let importError {
                    Text(importError).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            importError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func exportSettings() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.exportSettings(to: url)
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.propertyList]
        panel.prompt = "Import"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                if try store.importSettings(from: url) {
                    importError = nil
                    ToastManager.shared.success("Import successfully")
                } else {
                    importError = "Invalid data format"
                }
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

