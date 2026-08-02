import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class StatusMenuStore {
    static let shared = StatusMenuStore()

    enum DeliveryState: Equatable {
        case idle
        case sending
        case success
        case partialFailure
        case failure
    }

    enum ScreenState: Equatable {
        case on
        case off
    }

    private(set) var deliveryState: DeliveryState = .idle
    private(set) var screenState: ScreenState = .on
    private(set) var currentProcess = "No active application"
    private(set) var currentWindowTitle: String?
    private(set) var currentMedia = "Nothing playing"
    private(set) var lastProcess = "No application"
    private(set) var lastMedia = "No media"
    private(set) var lastReportTime: Date?
    private(set) var isEnabled = PreferencesDataModel.isEnabled.value
    private(set) var enabledTypes = PreferencesDataModel.enabledTypes.value.types
    private(set) var shellIntegration = PreferencesDataModel.shellIntegration.value
    private(set) var keepMacAwake = PreferencesDataModel.keepMacAwake.value
    private(set) var keepAwakeActive = KeepAwakeController.shared.isActive
    private(set) var keepAwakeError = KeepAwakeController.shared.lastError
    private(set) var accessibilityEnabled = ApplicationMonitor.shared.isAccessibilityEnabled()
    private(set) var isRefreshing = false

    private var subscriptions: [RelaySubscription] = []

    private init() {
        subscriptions = [
            PreferencesDataModel.isEnabled.subscribeOnMain { [weak self] in self?.isEnabled = $0 },
            PreferencesDataModel.enabledTypes.subscribeOnMain { [weak self] in self?.enabledTypes = $0.types },
            PreferencesDataModel.shellIntegration.subscribeOnMain { [weak self] in self?.shellIntegration = $0 },
            PreferencesDataModel.keepMacAwake.subscribeOnMain { [weak self] in
                self?.keepMacAwake = $0
                self?.refreshKeepAwakeState()
            },
        ]
    }

    var isReporting: Bool {
        isEnabled && !enabledTypes.isEmpty
    }

    var menuBarBadgeSymbol: String? {
        if screenState == .off {
            return "moon.fill"
        }
        if deliveryState == .sending {
            return "arrow.up.circle.fill"
        }
        if deliveryState == .partialFailure {
            return "exclamationmark.circle.fill"
        }
        if keepMacAwake {
            return "bolt.fill"
        }
        if shellIntegration.isEnabled {
            return "terminal.fill"
        }
        return nil
    }

    var currentProcessDetail: String {
        guard accessibilityEnabled else {
            return "Window title unavailable"
        }
        guard let currentWindowTitle, !currentWindowTitle.isEmpty else {
            return "No window title"
        }
        return currentWindowTitle
    }

    var lastDeliveryTitle: String {
        guard let lastReportTime else { return "No report sent yet" }
        return "Sent \(lastReportTime.relativeTimeDescription())"
    }

    var lastDeliveryDetail: String {
        "\(lastProcess) · \(lastMedia)"
    }

    var shellSummary: String {
        let config = shellIntegration.sanitized()
        guard config.isEnabled else { return "Shell integration disabled" }
        let slot = config.selectedSlot
        if let exitCode = slot.lastExitCode {
            return "Command \(slot.id + 1) · Exit \(exitCode)"
        }
        return "Command \(slot.id + 1) · Waiting for first run"
    }

    var keepAwakeDetail: String {
        guard keepMacAwake else { return "Allow normal system sleep" }
        if let error = keepAwakeError {
            return error
        }
        return keepAwakeActive
            ? "Mac stays awake; the display may sleep"
            : "Starting power assertions..."
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    func presentation(launch: StatusLaunchKind = .ready) -> StatusPresentation {
        StatusPresentation.make(
            launch: launch,
            reporting: isReporting,
            delivery: deliveryState.presentationKind,
            screen: screenState == .on ? .on : .off
        )
    }

    func refreshPreferences() {
        isEnabled = PreferencesDataModel.isEnabled.value
        enabledTypes = PreferencesDataModel.enabledTypes.value.types
        shellIntegration = PreferencesDataModel.shellIntegration.value
        keepMacAwake = PreferencesDataModel.keepMacAwake.value
    }

    func refreshCurrentState() {
        refreshPreferences()
        accessibilityEnabled = ApplicationMonitor.shared.isAccessibilityEnabled()
        if let info = ApplicationMonitor.shared.getFocusedWindowInfo() {
            currentProcess = info.appName
            currentWindowTitle = info.title
        } else if let app = NSWorkspace.shared.frontmostApplication {
            currentProcess = app.localizedName ?? "Unknown application"
            currentWindowTitle = nil
        }

        isRefreshing = true
        Task {
            let info = try? await MediaInfoManager.getMediaInfoAsync(timeout: 1.0)
            if let info, let name = info.name {
                currentMedia = StatusMenuFormatter.mediaName(name, artist: info.artist, playing: info.playing)
            } else {
                currentMedia = "Nothing playing"
            }
            isRefreshing = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        PreferencesDataModel.isEnabled.accept(enabled)
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

    func setKeepMacAwake(_ enabled: Bool) {
        PreferencesDataModel.keepMacAwake.accept(enabled)
        refreshKeepAwakeState()
    }

    func retryKeepAwake() {
        KeepAwakeController.shared.retry()
        refreshKeepAwakeState()
    }

    func turnDisplayOffNow() {
        KeepAwakeController.shared.turnDisplayOffNow()
    }

    func refreshKeepAwakeState() {
        keepAwakeActive = KeepAwakeController.shared.isActive
        keepAwakeError = KeepAwakeController.shared.lastError
    }

    func sendNow(using appModel: AppModel) {
        guard isReporting, deliveryState != .sending else { return }
        appModel.sendNow()
    }

    func openSettings() {
        SettingsWindowPresenter.shared.showWindow()
    }

    func updateDeliveryState(_ state: DeliveryState) {
        deliveryState = state
    }

    func updateScreenState(_ state: ScreenState) {
        screenState = state
    }

    func updateCurrentMedia(_ mediaInfo: MediaInfo?) {
        if let mediaInfo, let name = mediaInfo.name {
            currentMedia = StatusMenuFormatter.mediaName(name, artist: mediaInfo.artist, playing: mediaInfo.playing)
        } else {
            currentMedia = "Nothing playing"
        }
    }

    func updateCurrentProcess(_ info: FocusedWindowInfo) {
        currentProcess = info.appName
        currentWindowTitle = info.title
        accessibilityEnabled = ApplicationMonitor.shared.isAccessibilityEnabled()
    }

    func updateLastReport(_ report: ReportModel) {
        lastProcess = report.processName ?? "No application"
        lastMedia = StatusMenuFormatter.mediaName(report.mediaName, artist: report.artist)
        lastReportTime = report.timeStamp
    }

}

private extension StatusMenuStore.DeliveryState {
    var presentationKind: StatusDeliveryKind {
        switch self {
        case .idle:
            return .idle
        case .sending:
            return .sending
        case .success:
            return .success
        case .partialFailure:
            return .partialFailure
        case .failure:
            return .failure
        }
    }
}

enum StatusMenuFormatter {
    static func mediaName(_ mediaName: String?, artist: String?, playing: Bool = true) -> String {
        guard let mediaName, !mediaName.isEmpty else {
            return "No media"
        }

        let prefix = playing ? "" : "Paused · "
        let suffix = artist.flatMap { $0.isEmpty ? nil : " — \($0)" } ?? ""

        return "\(prefix)\(mediaName)\(suffix)"
    }
}
