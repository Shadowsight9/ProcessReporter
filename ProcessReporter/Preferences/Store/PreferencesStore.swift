import AppKit
import Combine
import RxSwift

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var isEnabled = PreferencesDataModel.isEnabled.value
    @Published var focusReport = PreferencesDataModel.focusReport.value
    @Published var sendInterval = PreferencesDataModel.sendInterval.value
    @Published var enabledTypes = PreferencesDataModel.enabledTypes.value.types
    @Published var ignoreNullArtist = PreferencesDataModel.ignoreNullArtist.value
    @Published var shellIntegration = PreferencesDataModel.shellIntegration.value

    private let disposeBag = DisposeBag()

    init() {
        PreferencesDataModel.isEnabled
            .subscribe(onNext: { [weak self] in self?.isEnabled = $0 })
            .disposed(by: disposeBag)
        PreferencesDataModel.focusReport
            .subscribe(onNext: { [weak self] in self?.focusReport = $0 })
            .disposed(by: disposeBag)
        PreferencesDataModel.sendInterval
            .subscribe(onNext: { [weak self] in self?.sendInterval = $0 })
            .disposed(by: disposeBag)
        PreferencesDataModel.enabledTypes
            .subscribe(onNext: { [weak self] in self?.enabledTypes = $0.types })
            .disposed(by: disposeBag)
        PreferencesDataModel.ignoreNullArtist
            .subscribe(onNext: { [weak self] in self?.ignoreNullArtist = $0 })
            .disposed(by: disposeBag)
        PreferencesDataModel.shellIntegration
            .subscribe(onNext: { [weak self] in self?.shellIntegration = $0 })
            .disposed(by: disposeBag)
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
}
