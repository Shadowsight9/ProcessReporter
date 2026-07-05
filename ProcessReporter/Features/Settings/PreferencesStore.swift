import AppKit
import Combine

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var isEnabled = PreferencesDataModel.isEnabled.value
    @Published var focusReport = PreferencesDataModel.focusReport.value
    @Published var sendInterval = PreferencesDataModel.sendInterval.value
    @Published var enabledTypes = PreferencesDataModel.enabledTypes.value.types
    @Published var ignoreNullArtist = PreferencesDataModel.ignoreNullArtist.value
    @Published var shellIntegration = PreferencesDataModel.shellIntegration.value
    @Published var mappings = PreferencesDataModel.mappingList.value.getList()
    @Published var filteredProcesses = PreferencesDataModel.filteredProcesses.value
    @Published var filteredMediaProcesses = PreferencesDataModel.filteredMediaProcesses.value

    private var subscriptions: [RelaySubscription] = []

    init() {
        subscriptions = [
            PreferencesDataModel.isEnabled.subscribeOnMain { [weak self] in self?.isEnabled = $0 },
            PreferencesDataModel.focusReport.subscribeOnMain { [weak self] in self?.focusReport = $0 },
            PreferencesDataModel.sendInterval.subscribeOnMain { [weak self] in self?.sendInterval = $0 },
            PreferencesDataModel.enabledTypes.subscribeOnMain { [weak self] in self?.enabledTypes = $0.types },
            PreferencesDataModel.ignoreNullArtist.subscribeOnMain { [weak self] in self?.ignoreNullArtist = $0 },
            PreferencesDataModel.shellIntegration.subscribeOnMain { [weak self] in self?.shellIntegration = $0 },
            PreferencesDataModel.mappingList.subscribeOnMain { [weak self] in self?.mappings = $0.getList() },
            PreferencesDataModel.filteredProcesses.subscribeOnMain { [weak self] in self?.filteredProcesses = $0 },
            PreferencesDataModel.filteredMediaProcesses.subscribeOnMain { [weak self] in self?.filteredMediaProcesses = $0 },
        ]
    }

    func setEnabled(_ value: Bool) {
        PreferencesDataModel.isEnabled.accept(value)
    }

    func setFocusReport(_ value: Bool) {
        PreferencesDataModel.focusReport.accept(value)
    }

    func setSendInterval(_ value: SendInterval) {
        PreferencesDataModel.sendInterval.accept(value)
    }

    func setIgnoreNullArtist(_ value: Bool) {
        PreferencesDataModel.ignoreNullArtist.accept(value)
    }

    func setReportType(_ type: Reporter.Types, enabled: Bool) {
        var types = PreferencesDataModel.enabledTypes.value.types
        if enabled {
            types.insert(type)
        } else {
            types.remove(type)
        }
        PreferencesDataModel.enabledTypes.accept(.init(types: types))
    }

    func saveShell(_ integration: ShellIntegration) {
        var sanitized = integration
        sanitized.timeoutSeconds = max(sanitized.timeoutSeconds, 1)
        PreferencesDataModel.shellIntegration.accept(sanitized)
    }

    func testShell() async {
        let report = ReportModel(
            windowInfo: ApplicationMonitor.shared.getFocusedWindowInfo(),
            integrations: [],
            mediaInfo: try? await MediaInfoManager.getMediaInfoAsync(timeout: 1.0)
        )
        _ = await ShellReporterExtension.send(data: report, requireEnabled: false)
    }

    func saveFilteredProcesses(_ appIDs: [String]) {
        PreferencesDataModel.filteredProcesses.accept(appIDs)
    }

    func saveFilteredMediaProcesses(_ appIDs: [String]) {
        PreferencesDataModel.filteredMediaProcesses.accept(appIDs)
    }

    func addMapping(type: PreferencesDataModel.MappingType, from: String, to: String) {
        PreferencesDataModel.mappingList.value.addMapping(.init(type: type, from: from, to: to))
    }

    func editMapping(type: PreferencesDataModel.MappingType, from: String, to: String, index: Int) {
        PreferencesDataModel.mappingList.value.editMapping(.init(type: type, from: from, to: to), for: index)
    }

    func removeMappings(_ mappings: [PreferencesDataModel.Mapping]) {
        PreferencesDataModel.mappingList.value.removeMapping(mappings)
    }

    func exportSettings(to directoryURL: URL) throws {
        guard let data = PreferencesDataModel.exportToPlist() else { return }
        let fileURL = directoryURL.appendingPathComponent("ProcessReporterData.plist")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try data.write(to: fileURL, options: [.atomic])
    }

    func importSettings(from fileURL: URL) throws -> Bool {
        let data = try Data(contentsOf: fileURL)
        return PreferencesDataModel.importFromPlist(data: data)
    }

    deinit {
        subscriptions.forEach { $0.dispose() }
    }
}
