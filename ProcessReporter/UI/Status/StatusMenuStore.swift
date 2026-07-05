import SwiftUI

@MainActor
final class StatusMenuStore: ObservableObject {
    static let shared = StatusMenuStore()

    @Published var status: ReporterStatusItemManager.StatusItemIconStatus = .ready
    @Published var currentProcess = "No Process"
    @Published var currentMedia = "No Media"
    @Published var lastProcess = "N/A"
    @Published var lastMedia = "No Media"
    @Published var lastReportTime: Date?
    @Published var isEnabled = PreferencesDataModel.isEnabled.value
    @Published var enabledTypes = PreferencesDataModel.enabledTypes.value.types

    private init() {}

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
                currentMedia = formatMediaName(name, info.artist, playing: info.playing)
            }
        }
    }

    func toggleEnabled() {
        PreferencesDataModel.isEnabled.accept(!PreferencesDataModel.isEnabled.value)
        refreshPreferences()
    }

    func toggleReportType(_ type: Reporter.Types) {
        var types = PreferencesDataModel.enabledTypes.value.types
        if types.contains(type) {
            types.remove(type)
        } else {
            types.insert(type)
        }
        PreferencesDataModel.enabledTypes.accept(.init(types: types))
        refreshPreferences()
    }

    func requestAccessibilityPermission() {
        if ApplicationMonitor.shared.requestAccessibilityAuthorization() {
            ToastManager.shared.success("Accessibility permission is already enabled.")
        }
    }

    func openSettings() {
        SettingWindowManager.shared.showWindow()
    }

    func formatMediaName(_ mediaName: String?, _ artist: String?, playing: Bool = true) -> String {
        let prefix = playing ? "" : "Paused: "
        if let mediaName, let artist {
            return "\(prefix)\(mediaName) - \(artist)"
        }
        return prefix + (mediaName ?? "No Media")
    }
}
