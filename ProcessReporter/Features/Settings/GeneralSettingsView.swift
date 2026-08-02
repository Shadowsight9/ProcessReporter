import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @Bindable var store: PreferencesStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var importError: String?
    @State private var isImportingSettings = false
    @State private var isExportingSettings = false
    @State private var settingsBackupDocument = SettingsBackupDocument(data: Data())

    var body: some View {
        Form {
            Section("App") {
                Toggle("Enabled", isOn: Binding(
                    get: { store.isEnabled },
                    set: { val in store.setEnabled(val) }
                ))
                Toggle("Start at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: setLaunchAtLogin
                ))
                
            }

            Section("Power") {
                Toggle("Vibe Coding Mode", isOn: Binding(
                    get: { store.keepMacAwake },
                    set: { store.setKeepMacAwake($0) }
                ))
                Text("Keeps macOS awake for long-running tasks while still allowing the display to turn off normally. Closing a MacBook lid can still put it to sleep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Report") {
                HStack {
                    Text("Report Type")

                    Spacer()
                    reportTypeToggle(
                        "Process",
                        systemImage: "macwindow",
                        type: .process
                    )
                    reportTypeToggle(
                        "Media",
                        systemImage: "music.note.list",
                        type: .media
                    )
                }
                    
                Toggle("Report when application focused", isOn: Binding(
                    get: { store.reportOnFocusChange },
                    set: { store.setReportOnFocusChange($0) }
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


            
            HStack {
                Spacer()
                Button("Request Accessibility Permission") {
                    if ApplicationMonitor.shared.requestAccessibilityAuthorization() {
                        ToastManager.shared.success("Accessibility permission is already enabled.")
                    }
                }
                
                Button {
                    isImportingSettings = true
                } label: {
                    Label("Import Settings", systemImage: "square.and.arrow.down")
                }
                
                Button(action: exportSettings) {
                    Label("Export Settings", systemImage: "square.and.arrow.up")
                }
            }
            if let importError {
                Text(importError).foregroundStyle(.red)
            }
            
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(
            isPresented: $isImportingSettings,
            allowedContentTypes: [.propertyList],
            allowsMultipleSelection: false,
            onCompletion: handleImportResult
        )
        .fileExporter(
            isPresented: $isExportingSettings,
            document: settingsBackupDocument,
            contentType: .propertyList,
            defaultFilename: "StatusaData.plist",
            onCompletion: handleExportResult
        )
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

    private func reportTypeToggle(
        _ title: String,
        systemImage: String,
        type: Reporter.Types
    ) -> some View {
        Toggle(isOn: Binding(
            get: { store.enabledTypes.contains(type) },
            set: { val in store.setReportType(type, enabled: val) }
        )) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .controlSize(.large)
    }

    private func exportSettings() {
        do {
            settingsBackupDocument = SettingsBackupDocument(data: try store.exportSettingsData())
            isExportingSettings = true
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            _ = try store.importSettings(from: url)
            importError = nil
            ToastManager.shared.success("Import successfully")
        } catch {
            importError = error.localizedDescription
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        do {
            _ = try result.get()
            importError = nil
            ToastManager.shared.success("Export successfully")
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct SettingsBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.propertyList] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
