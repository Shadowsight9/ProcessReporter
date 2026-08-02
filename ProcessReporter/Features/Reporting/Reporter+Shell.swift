import Foundation
import Darwin

private struct ShellReportPayload: Codable {
    struct EventPayload: Codable {
        var type: String
        var screenState: String
    }

    struct ProcessPayload: Codable {
        var name: String
        var description: String
        var windowTitle: String
        var bundleIdentifier: String
    }

    struct MediaPayload: Codable {
        var name: String
        var artist: String
        var album: String
        var processName: String
        var processDescription: String
        var bundleIdentifier: String
        var duration: Double
        var elapsedTime: Double
        var playing: Bool
    }

    var timestamp: String
    var event: EventPayload
    var process: ProcessPayload
    var media: MediaPayload
    var foregroundUsage: ForegroundUsageSnapshot
}

enum ShellIntegrationEvent: String, Sendable {
    case report
    case screenSleep = "screen_sleep"
    case screenWake = "screen_wake"

    var screenState: String {
        switch self {
        case .report:
            return ""
        case .screenSleep:
            return "off"
        case .screenWake:
            return "on"
        }
    }
}

actor ShellEventDispatcher {
    static let shared = ShellEventDispatcher()

    private var pendingEvents: [ShellIntegrationEvent] = []
    private var isSending = false

    nonisolated func enqueue(_ event: ShellIntegrationEvent) {
        Task {
            await append(event)
        }
    }

    private func append(_ event: ShellIntegrationEvent) async {
        pendingEvents.append(event)
        guard !isSending else { return }

        isSending = true
        defer { isSending = false }

        while !pendingEvents.isEmpty {
            let nextEvent = pendingEvents.removeFirst()
            _ = await ShellReporterExtension.send(event: nextEvent)
        }
    }
}

private struct ShellCommandResult {
    var exitCode: Int
    var stdout: String
    var stderr: String
    var timedOut: Bool = false
}

private enum ShellCommandRunner {
    private static let outputLimit = 32 * 1024

    static func run(command: String, timeoutSeconds: Int, environment: [String: String]) async
        -> ShellCommandResult
    {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in
                new
            }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let stdoutBuffer = LockedData(limit: outputLimit)
            let stderrBuffer = LockedData(limit: outputLimit)
            let didTimeout = LockedFlag()

            stdout.fileHandleForReading.readabilityHandler = { handle in
                stdoutBuffer.append(handle.availableData)
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                stderrBuffer.append(handle.availableData)
            }

            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                return ShellCommandResult(
                    exitCode: -1,
                    stdout: "",
                    stderr: error.localizedDescription
                )
            }

            let timeoutTask = Task {
                try? await Task.sleep(
                    nanoseconds: UInt64(max(timeoutSeconds, 1)) * 1_000_000_000
                )
                if process.isRunning {
                    didTimeout.setTrue()
                    process.interrupt()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                if process.isRunning {
                    process.terminate()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }

            process.waitUntilExit()
            timeoutTask.cancel()
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
            stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())

            return ShellCommandResult(
                exitCode: Int(process.terminationStatus),
                stdout: String(data: stdoutBuffer.data, encoding: .utf8) ?? "",
                stderr: String(data: stderrBuffer.data, encoding: .utf8) ?? "",
                timedOut: didTimeout.value
            )
        }.value
    }
}

private actor ShellCommandExecutionQueue {
    static let shared = ShellCommandExecutionQueue()

    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run(
        command: String,
        timeoutSeconds: Int,
        environment: [String: String]
    ) async -> ShellCommandResult {
        await acquire()
        let result = await ShellCommandRunner.run(
            command: command,
            timeoutSeconds: timeoutSeconds,
            environment: environment
        )
        release()
        return result
    }

    private func acquire() async {
        if !isRunning {
            isRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isRunning = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

class ShellReporterExtension: ReporterExtension {
    var name: String = "Shell"

    var isEnabled: Bool {
        PreferencesDataModel.shellIntegration.value.isEnabled
    }

    func createReporterOptions() -> ReporterOptions {
        ReporterOptions { snapshot in
            await Self.send(snapshot: snapshot, event: .report, requireEnabled: true)
        }
    }

    static func send(data: ReportModel, requireEnabled: Bool) async -> Result<Void, ReporterError> {
        let foregroundUsage = await MainActor.run {
            ForegroundUsageTracker.shared.snapshot(mappings: PreferencesDataModel.mappingList.value)
        }
        return await send(
            snapshot: ReportSnapshot(data, foregroundUsage: foregroundUsage),
            event: .report,
            requireEnabled: requireEnabled
        )
    }

    static func send(
        event: ShellIntegrationEvent,
        requireEnabled: Bool = true
    ) async -> Result<Void, ReporterError> {
        let snapshot = ReportSnapshot(eventAt: .now)
        return await send(snapshot: snapshot, event: event, requireEnabled: requireEnabled)
    }

    static func send(
        snapshot: ReportSnapshot,
        event: ShellIntegrationEvent,
        requireEnabled: Bool
    ) async -> Result<Void, ReporterError> {
        let config = PreferencesDataModel.shellIntegration.value.sanitized()
        let slotIndex = config.normalizedSelectedSlotIndex
        let slot = config.selectedSlot
        guard config.isEnabled || !requireEnabled else { return .failure(.ignored) }
        guard !slot.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.ignored)
        }
        guard event != .report || snapshot.hasProcessInfo || snapshot.hasMediaInfo else {
            return .failure(.ignored)
        }

        let environment = makeEnvironment(snapshot: snapshot, event: event)
        let result = await ShellCommandExecutionQueue.shared.run(
            command: slot.command,
            timeoutSeconds: slot.timeoutSeconds,
            environment: environment
        )

        await MainActor.run {
            var latest = PreferencesDataModel.shellIntegration.value.sanitized()
            guard latest.slots.indices.contains(slotIndex) else { return }
            latest.slots[slotIndex].lastExitCode = result.exitCode
            latest.slots[slotIndex].lastStdout = result.stdout
            latest.slots[slotIndex].lastStderr = result.stderr
            PreferencesDataModel.shellIntegration.accept(latest)
        }

        if result.exitCode == 0 {
            return .success(())
        }
        if result.timedOut {
            return .failure(.networkError("Shell command timed out after \(slot.timeoutSeconds)s"))
        }
        return .failure(.networkError("Shell command exited with \(result.exitCode)"))
    }

    private static func makeEnvironment(
        snapshot: ReportSnapshot,
        event: ShellIntegrationEvent
    ) -> [String: String] {
        let processBundleID = snapshot.processBundleID ?? ""
        let mediaBundleID = snapshot.mediaBundleID ?? ""
        let playing = snapshot.mediaPlaying ? "true" : "false"

        let payload = ShellReportPayload(
            timestamp: iso8601.string(from: snapshot.timeStamp),
            event: .init(type: event.rawValue, screenState: event.screenState),
            process: .init(
                name: snapshot.processName ?? "",
                description: snapshot.processDescription ?? "",
                windowTitle: snapshot.windowTitle ?? "",
                bundleIdentifier: processBundleID
            ),
            media: .init(
                name: snapshot.mediaName ?? "",
                artist: snapshot.artist ?? "",
                album: snapshot.mediaAlbum ?? "",
                processName: snapshot.mediaProcessName ?? "",
                processDescription: snapshot.mediaProcessDescription ?? "",
                bundleIdentifier: mediaBundleID,
                duration: snapshot.mediaDuration ?? 0,
                elapsedTime: snapshot.mediaElapsedTime ?? 0,
                playing: snapshot.mediaPlaying
            ),
            foregroundUsage: snapshot.foregroundUsage
        )

        let jsonData = (try? jsonEncoder.encode(payload)) ?? Data("{}".utf8)
        let json = String(data: jsonData, encoding: .utf8) ?? "{}"
        let processUsageSeconds = snapshot.foregroundUsage.duration(forBundleIdentifier: snapshot.processBundleID)

        return [
            "PROCESS_REPORTER_EVENT": event.rawValue,
            "PROCESS_REPORTER_SCREEN_STATE": event.screenState,
            "PROCESS_REPORTER_PROCESS_NAME": snapshot.processName ?? "",
            "PROCESS_REPORTER_PROCESS_DESCRIPTION": snapshot.processDescription ?? "",
            "PROCESS_REPORTER_PROCESS_USAGE_DURATION": String(processUsageSeconds),
            "PROCESS_REPORTER_WINDOW_TITLE": snapshot.windowTitle ?? "",
            "PROCESS_REPORTER_PROCESS_BUNDLE_ID": processBundleID,
            "PROCESS_REPORTER_MEDIA_NAME": snapshot.mediaName ?? "",
            "PROCESS_REPORTER_MEDIA_ARTIST": snapshot.artist ?? "",
            "PROCESS_REPORTER_MEDIA_ALBUM": snapshot.mediaAlbum ?? "",
            "PROCESS_REPORTER_MEDIA_PROCESS_NAME": snapshot.mediaProcessName ?? "",
            "PROCESS_REPORTER_MEDIA_PROCESS_DESCRIPTION": snapshot.mediaProcessDescription ?? "",
            "PROCESS_REPORTER_MEDIA_PROCESS_BUNDLE_ID": mediaBundleID,
            "PROCESS_REPORTER_MEDIA_DURATION": String(snapshot.mediaDuration ?? 0),
            "PROCESS_REPORTER_MEDIA_ELAPSED_TIME": String(snapshot.mediaElapsedTime ?? 0),
            "PROCESS_REPORTER_MEDIA_PLAYING": playing,
            "PROCESS_REPORTER_TIMESTAMP": iso8601.string(from: snapshot.timeStamp),
            "PROCESS_REPORTER_JSON": json,
        ]
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        if storage.count > limit {
            storage.removeFirst(storage.count - limit)
        }
        lock.unlock()
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func setTrue() {
        lock.lock()
        storage = true
        lock.unlock()
    }
}
