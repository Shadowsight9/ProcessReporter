import Foundation
import Darwin

private struct ShellReportPayload: Codable {
    struct ProcessPayload: Codable {
        var name: String
        var windowTitle: String
        var bundleIdentifier: String
    }

    struct MediaPayload: Codable {
        var name: String
        var artist: String
        var album: String
        var processName: String
        var bundleIdentifier: String
        var duration: Double
        var elapsedTime: Double
        var playing: Bool
    }

    var timestamp: String
    var process: ProcessPayload
    var media: MediaPayload
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

class ShellReporterExtension: ReporterExtension {
    var name: String = "Shell"

    var isEnabled: Bool {
        PreferencesDataModel.shellIntegration.value.isEnabled
    }

    func createReporterOptions() -> ReporterOptions {
        ReporterOptions { data in
            await Self.send(data: data, requireEnabled: true)
        }
    }

    static func send(data: ReportModel, requireEnabled: Bool) async -> Result<Void, ReporterError> {
        let config = PreferencesDataModel.shellIntegration.value
        guard config.isEnabled || !requireEnabled else { return .failure(.ignored) }
        guard !config.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.ignored)
        }
        guard data.hasProcessInfo || data.hasMediaInfo else {
            return .failure(.ignored)
        }

        let environment = makeEnvironment(data: data)
        let result = await ShellCommandRunner.run(
            command: config.command,
            timeoutSeconds: config.timeoutSeconds,
            environment: environment
        )

        await MainActor.run {
            var latest = PreferencesDataModel.shellIntegration.value
            latest.lastExitCode = result.exitCode
            latest.lastStdout = result.stdout
            latest.lastStderr = result.stderr
            PreferencesDataModel.shellIntegration.accept(latest)
        }

        if result.exitCode == 0 {
            return .success(())
        }
        if result.timedOut {
            return .failure(.networkError("Shell command timed out after \(config.timeoutSeconds)s"))
        }
        return .failure(.networkError("Shell command exited with \(result.exitCode)"))
    }

    private static func makeEnvironment(data: ReportModel) -> [String: String] {
        let processBundleID = data.processInfoRaw?.applicationIdentifier ?? ""
        let mediaBundleID = data.mediaInfoRaw?.applicationIdentifier ?? ""
        let playing = data.mediaInfoRaw?.playing == true ? "true" : "false"

        let payload = ShellReportPayload(
            timestamp: iso8601.string(from: data.timeStamp),
            process: .init(
                name: data.processName ?? "",
                windowTitle: data.windowTitle ?? "",
                bundleIdentifier: processBundleID
            ),
            media: .init(
                name: data.mediaName ?? "",
                artist: data.artist ?? "",
                album: data.mediaInfoRaw?.album ?? "",
                processName: data.mediaProcessName ?? "",
                bundleIdentifier: mediaBundleID,
                duration: data.mediaDuration ?? 0,
                elapsedTime: data.mediaElapsedTime ?? 0,
                playing: data.mediaInfoRaw?.playing == true
            )
        )

        let jsonData = (try? jsonEncoder.encode(payload)) ?? Data("{}".utf8)
        let json = String(data: jsonData, encoding: .utf8) ?? "{}"

        return [
            "PROCESS_REPORTER_PROCESS_NAME": data.processName ?? "",
            "PROCESS_REPORTER_WINDOW_TITLE": data.windowTitle ?? "",
            "PROCESS_REPORTER_PROCESS_BUNDLE_ID": processBundleID,
            "PROCESS_REPORTER_MEDIA_NAME": data.mediaName ?? "",
            "PROCESS_REPORTER_MEDIA_ARTIST": data.artist ?? "",
            "PROCESS_REPORTER_MEDIA_ALBUM": data.mediaInfoRaw?.album ?? "",
            "PROCESS_REPORTER_MEDIA_PROCESS_NAME": data.mediaProcessName ?? "",
            "PROCESS_REPORTER_MEDIA_PROCESS_BUNDLE_ID": mediaBundleID,
            "PROCESS_REPORTER_MEDIA_DURATION": String(data.mediaDuration ?? 0),
            "PROCESS_REPORTER_MEDIA_ELAPSED_TIME": String(data.mediaElapsedTime ?? 0),
            "PROCESS_REPORTER_MEDIA_PLAYING": playing,
            "PROCESS_REPORTER_TIMESTAMP": iso8601.string(from: data.timeStamp),
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
