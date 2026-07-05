import Combine
import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var isEnabled = PreferencesDataModel.isEnabled.value
    @Published var reportOnFocusChange = PreferencesDataModel.reportOnFocusChange.value
    @Published var sendInterval = PreferencesDataModel.sendInterval.value
    @Published var enabledTypes = PreferencesDataModel.enabledTypes.value.types
    @Published var ignoreNullArtist = PreferencesDataModel.ignoreNullArtist.value
    @Published var shellIntegration = PreferencesDataModel.shellIntegration.value
    @Published var mappings = PreferencesDataModel.mappingList.value
    @Published var filteredProcesses = PreferencesDataModel.filteredProcesses.value
    @Published var filteredMediaProcesses = PreferencesDataModel.filteredMediaProcesses.value

    private var subscriptions: [RelaySubscription] = []

    init() {
        subscriptions = [
            PreferencesDataModel.isEnabled.subscribeOnMain { [weak self] in self?.isEnabled = $0 },
            PreferencesDataModel.reportOnFocusChange.subscribeOnMain { [weak self] in self?.reportOnFocusChange = $0 },
            PreferencesDataModel.sendInterval.subscribeOnMain { [weak self] in self?.sendInterval = $0 },
            PreferencesDataModel.enabledTypes.subscribeOnMain { [weak self] in self?.enabledTypes = $0.types },
            PreferencesDataModel.ignoreNullArtist.subscribeOnMain { [weak self] in self?.ignoreNullArtist = $0 },
            PreferencesDataModel.shellIntegration.subscribeOnMain { [weak self] in self?.shellIntegration = $0 },
            PreferencesDataModel.mappingList.subscribeOnMain { [weak self] in self?.mappings = $0 },
            PreferencesDataModel.filteredProcesses.subscribeOnMain { [weak self] in self?.filteredProcesses = $0 },
            PreferencesDataModel.filteredMediaProcesses.subscribeOnMain { [weak self] in self?.filteredMediaProcesses = $0 },
        ]
    }

    func setEnabled(_ value: Bool) {
        PreferencesDataModel.isEnabled.accept(value)
    }

    func setReportOnFocusChange(_ value: Bool) {
        PreferencesDataModel.reportOnFocusChange.accept(value)
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
        PreferencesDataModel.mappingList.accept(mappings + [.init(type: type, from: from, to: to)])
    }

    func editMapping(type: PreferencesDataModel.MappingType, from: String, to: String, index: Int) {
        PreferencesDataModel.mappingList.accept(mappings.enumerated().map { i, item in
            i == index ? .init(type: type, from: from, to: to) : item
        })
    }

    func removeMappings(_ mappings: [PreferencesDataModel.Mapping]) {
        PreferencesDataModel.mappingList.accept(self.mappings.filter { item in
            !mappings.contains(where: { $0 == item })
        })
    }

    func exportSettings(to directoryURL: URL) throws {
        let data = try exportSettingsData()
        let fileURL = directoryURL.appendingPathComponent("ProcessReporterData.plist")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try data.write(to: fileURL, options: [.atomic])
    }

    func exportSettingsData() throws -> Data {
        guard let data = PreferencesDataModel.exportToPlist() else {
            throw PreferencesStoreError.exportFailed
        }
        return data
    }

    func importSettings(from fileURL: URL) throws -> Bool {
        let needsSecurityScope = fileURL.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: fileURL)
        return try importSettings(data)
    }

    func importSettings(_ data: Data) throws -> Bool {
        guard PreferencesDataModel.importFromPlist(data: data) else {
            throw PreferencesStoreError.invalidImportData
        }
        return true
    }

    deinit {
        subscriptions.forEach { $0.dispose() }
    }
}

enum PreferencesStoreError: LocalizedError {
    case exportFailed
    case invalidImportData

    var errorDescription: String? {
        switch self {
        case .exportFailed:
            return "Unable to export settings."
        case .invalidImportData:
            return "Invalid settings backup file."
        }
    }
}
