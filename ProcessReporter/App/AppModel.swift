import Observation

/// Owns the app-wide services that must only exist after startup succeeds.
/// Keeping startup here makes the SwiftUI entry point declarative and easy to inspect.
@MainActor
@Observable
final class AppModel {
    enum LaunchState: Equatable {
        case starting
        case ready
        case failed(message: String)
    }

    static let shared = AppModel()

    private(set) var launchState: LaunchState = .starting
    private(set) var reporter: Reporter?
    private var launchTask: Task<Void, Never>?
    private var subscriptions: [RelaySubscription] = []

    private init() {
        subscriptions = [
            PreferencesDataModel.keepMacAwake.subscribeOnMain { enabled in
                KeepAwakeController.shared.setEnabled(enabled)
            }
        ]
    }

    func start() {
        guard launchTask == nil, launchState == .starting else { return }

        launchTask = Task {
            do {
                try await DataStore.shared.initialize()
                guard !Task.isCancelled else { return }
                reporter = Reporter()
                launchState = .ready
            } catch {
                launchState = .failed(message: error.localizedDescription)
            }
            launchTask = nil
        }
    }

    func sendNow() {
        reporter?.sendNow()
    }

    func clearReporterCaches() {
        reporter?.clearCaches()
    }

    func handleWakeFromSleep() {
        reporter?.handleWakeFromSleep()
        KeepAwakeController.shared.restoreIfNeeded()
    }

    func stopPowerAssertions() {
        KeepAwakeController.shared.stopForTermination()
    }

    var launchKind: StatusLaunchKind {
        switch launchState {
        case .starting:
            return .starting
        case .ready:
            return .ready
        case .failed:
            return .failed
        }
    }
}
