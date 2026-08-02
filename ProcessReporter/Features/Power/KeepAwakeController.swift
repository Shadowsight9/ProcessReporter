import Foundation
import IOKit.pwr_mgt
import Observation
import os

/// Keeps macOS awake without holding a display-sleep assertion.
///
/// This is a focused adaptation of the IOKit assertion approach used by the
/// MIT-licensed caffeinate-disablesleep project by Demiao Chen:
/// https://github.com/demiaochen/caffeinate-disablesleep
@MainActor
@Observable
final class KeepAwakeController {
    static let shared = KeepAwakeController()

    private(set) var isActive = false
    private(set) var lastError: String?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ProcessReporter",
        category: "KeepAwake"
    )
    private var assertionIDs: [IOPMAssertionID] = []
    private var requestedEnabled = false

    private init() {}

    func setEnabled(_ enabled: Bool) {
        requestedEnabled = enabled
        enabled ? start() : stop()
    }

    func retry() {
        guard requestedEnabled else { return }
        start()
    }

    func turnDisplayOffNow() {
        guard requestedEnabled, isActive else { return }

        Task {
            let result = await Task.detached(priority: .utility) {
                let process = Process()
                process.executableURL = URL(
                    fileURLWithPath: KeepAwakeConfiguration.displaySleepExecutable
                )
                process.arguments = KeepAwakeConfiguration.displaySleepArguments
                process.standardOutput = Pipe()
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus
                } catch {
                    return Int32(-1)
                }
            }.value

            guard result == 0 else {
                let message = "Could not turn the display off (pmset \(result))."
                lastError = message
                logger.error("\(message, privacy: .public)")
                return
            }
            lastError = nil
        }
    }

    func restoreIfNeeded() {
        guard requestedEnabled else { return }
        start()
    }

    func stop() {
        requestedEnabled = false
        releaseAssertions()
        isActive = false
        lastError = nil
    }

    func stopForTermination() {
        releaseAssertions()
        isActive = false
        lastError = nil
    }

    private func start() {
        releaseAssertions()

        var createdIDs: [IOPMAssertionID] = []
        for type in KeepAwakeConfiguration.vibeCoding.assertionTypes {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Statusa Vibe Coding Mode is keeping your Mac awake" as CFString,
                &id
            )

            guard result == kIOReturnSuccess else {
                createdIDs.forEach { IOPMAssertionRelease($0) }
                let message = "Could not create power assertion \(type) (IOKit \(result))."
                lastError = message
                isActive = false
                logger.error("\(message, privacy: .public)")
                return
            }
            createdIDs.append(id)
        }

        assertionIDs = createdIDs
        lastError = nil
        isActive = true
        logger.info("Vibe Coding Mode enabled; display sleep remains allowed")
    }

    private func releaseAssertions() {
        assertionIDs.forEach { IOPMAssertionRelease($0) }
        assertionIDs.removeAll()
    }
}
