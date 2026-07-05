import ServiceManagement
import SwiftUI

struct SettingsRootView: View {
    @StateObject private var store = PreferencesStore()

    var body: some View {
        TabView {
            GeneralSettingsView(store: store)
                .tabItem { Label("General", systemImage: "gear") }
            ShellIntegrationSettingsView(store: store)
                .tabItem { Label("Integration", systemImage: "terminal") }
            PreferencesFilterView()
                .tabItem { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
            MappingView()
                .tabItem { Label("Mapping", systemImage: "arrow.trianglehead.swap") }
            HistorySettingsView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .frame(minWidth: 720, minHeight: 460)
    }
}

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

struct ShellIntegrationSettingsView: View {
    @ObservedObject var store: PreferencesStore
    @State private var draft = PreferencesDataModel.shellIntegration.value
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("Shell") {
                Toggle("Enabled", isOn: $draft.isEnabled)
                TextField("Command", text: $draft.command, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.system(.body, design: .monospaced))
                Stepper(value: $draft.timeoutSeconds, in: 1...300) {
                    Text("Timeout: \(draft.timeoutSeconds)s")
                }
                Text("Runs locally with your user permissions. Imported commands stay disabled until enabled here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Actions") {
                HStack {
                    Button("Reset") { draft = store.shellIntegration }
                    Button("Save") { store.saveShell(draft) }
                        .keyboardShortcut(.defaultAction)
                    Button(isTesting ? "Testing..." : "Test") {
                        Task {
                            store.saveShell(draft)
                            isTesting = true
                            await store.testShell()
                            draft = store.shellIntegration
                            isTesting = false
                        }
                    }
                    .disabled(draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
                }
            }

            Section("Last Result") {
                LabeledContent("Exit Code", value: draft.lastExitCode.map(String.init) ?? "-")
                outputView(title: "Stdout", text: draft.lastStdout)
                outputView(title: "Stderr", text: draft.lastStderr)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onReceive(store.$shellIntegration) { draft = $0 }
    }

    private func outputView(title: String, text: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            ScrollView {
                Text(text.isEmpty ? "-" : text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(minHeight: 80, maxHeight: 120)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct HistorySettingsView: View {
    @State private var reports: [ReportValue] = []
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search by process or media name", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await loadReports() } }
                Button("Search") { Task { await loadReports() } }
                Button("Open Database Location", action: openDatabaseLocation)
                Button("Clear History", role: .destructive) {
                    Task {
                        try? await DataStore.shared.deleteAllReports()
                        await loadReports()
                    }
                }
            }

            List(reports, id: \.id) { report in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(report.processName ?? "-")
                            .font(.headline)
                        Spacer()
                        Text(report.timeStamp.formatted(date: .abbreviated, time: .standard))
                            .foregroundStyle(.secondary)
                    }
                    Text(report.mediaName ?? "-")
                        .foregroundStyle(.secondary)
                    if !report.integrations.isEmpty {
                        Text(report.integrations.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .task { await loadReports() }
        .onReceive(NotificationCenter.default.publisher(for: DataStore.changedNotification)) { _ in
            Task { await loadReports() }
        }
    }

    private func loadReports() async {
        reports = await DataStore.shared.fetchReports(
            searchText: searchText.isEmpty ? nil : searchText,
            offset: 0,
            limit: 50,
            ascending: false
        )
    }

    private func openDatabaseLocation() {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appSupportURL.appendingPathComponent(bundleID).path)
    }
}
