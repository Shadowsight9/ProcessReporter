import SwiftUI

@MainActor
final class StatusMenuStore: ObservableObject {
    static let shared = StatusMenuStore()

    enum ReporterStatus {
        case ready
        case syncing
        case offline
        case paused
        case partialError
        case error
    }

    @Published var status: ReporterStatus = .ready
    @Published var currentProcess = "No Process"
    @Published var currentMedia = "No Media"
    @Published var lastProcess = "N/A"
    @Published var lastMedia = "No Media"
    @Published var lastReportTime: Date?
    @Published var isEnabled = PreferencesDataModel.isEnabled.value
    @Published var enabledTypes = PreferencesDataModel.enabledTypes.value.types

    private var subscriptions: [RelaySubscription] = []

    private init() {
        subscriptions = [
            PreferencesDataModel.isEnabled.subscribeOnMain { [weak self] in self?.isEnabled = $0 },
            PreferencesDataModel.enabledTypes.subscribeOnMain { [weak self] in self?.enabledTypes = $0.types },
        ]
    }

    var systemImage: String {
        switch status {
        case .ready:
            return "icloud.fill"
        case .offline, .paused:
            return "icloud.slash.fill"
        case .syncing:
            return "arrow.trianglehead.2.clockwise.rotate.90.icloud.fill"
        case .partialError:
            return "exclamationmark.icloud"
        case .error:
            return "exclamationmark.icloud.fill"
        }
    }

    var statusDescription: String {
        switch status {
        case .ready:
            return "Ready"
        case .syncing:
            return "Syncing"
        case .offline:
            return "Offline"
        case .paused:
            return "Paused"
        case .partialError:
            return "Partial Error"
        case .error:
            return "Error"
        }
    }

    var lastReportSummary: String {
        let time = lastReportTime?.relativeTimeDescription() ?? "No report yet"
        return "\(lastProcess) / \(lastMedia) / \(time)"
    }

    var canSendNow: Bool {
        isEnabled && !enabledTypes.isEmpty
    }

    func refreshPreferences() {
        isEnabled = PreferencesDataModel.isEnabled.value
        enabledTypes = PreferencesDataModel.enabledTypes.value.types
    }

    func refreshCurrentState() {
        refreshPreferences()
        if let info = ApplicationMonitor.shared.getFocusedWindowInfo() {
            currentProcess = info.appName
        }
        Task {
            let info = try? await MediaInfoManager.getMediaInfoAsync(timeout: 1.0)
            if let info, let name = info.name {
                currentMedia = StatusMenuFormatter.mediaName(name, artist: info.artist, playing: info.playing)
            } else {
                currentMedia = "No Media"
            }
        }
    }

    func toggleEnabled() {
        PreferencesDataModel.isEnabled.accept(!PreferencesDataModel.isEnabled.value)
    }

    func toggleReportType(_ type: Reporter.Types) {
        var types = PreferencesDataModel.enabledTypes.value.types
        if types.contains(type) {
            types.remove(type)
        } else {
            types.insert(type)
        }
        PreferencesDataModel.enabledTypes.accept(.init(types: types))
    }

    func openSettings() {
        SettingsWindowPresenter.shared.showWindow()
    }

    func updateCurrentMedia(_ mediaInfo: MediaInfo?) {
        if let mediaInfo, let name = mediaInfo.name {
            currentMedia = StatusMenuFormatter.mediaName(name, artist: mediaInfo.artist, playing: mediaInfo.playing)
        } else {
            currentMedia = "No Media"
        }
    }

    func updateLastReport(_ report: ReportModel) {
        lastProcess = report.processName ?? "N/A"
        lastMedia = StatusMenuFormatter.mediaName(report.mediaName, artist: report.artist)
        lastReportTime = report.timeStamp
    }

    deinit {
        subscriptions.forEach { $0.dispose() }
    }
}

enum StatusMenuFormatter {
    static func mediaName(_ mediaName: String?, artist: String?, playing: Bool = true) -> String {
        guard let mediaName, !mediaName.isEmpty else {
            return "No Media"
        }

        let prefix = playing ? "Playing: " : "Paused: "
        let suffix = artist?.isEmpty == false ? " - \(artist!)" : ""

        return "\(prefix)\(mediaName)\(suffix)"
    }
}
