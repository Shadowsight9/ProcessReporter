// SystemNowPlayingProvider.swift
// ProcessReporter

import AppKit
import Foundation
import os

/// System media reader backed by the system osascript runtime.
///
/// Direct MediaRemote access from the app process is not reliable on newer
/// macOS versions. The monitor path keeps a single system helper process alive
/// and reads one JSON line per state change instead of spawning per poll.
final class SystemNowPlayingProvider {
  private struct NowPlayingPayload: Decodable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let calculatedPlaybackPosition: Double?
    let playbackRate: Double?
    let displayName: String?
    let bundleIdentifier: String?
  }

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "ProcessReporter",
    category: "SystemNowPlayingProvider"
  )

  private static let nowPlayingReaderScript = """
    ObjC.import('Foundation');

    const mediaRemote = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
    if (mediaRemote) {
      mediaRemote.load;
    }

    const MRNowPlayingRequest = $.NSClassFromString('MRNowPlayingRequest');

    function unwrap(value) {
      if (!value) {
        return null;
      }
      try {
        const unwrapped = ObjC.unwrap(value);
        return unwrapped === undefined ? null : unwrapped;
      } catch (error) {
        return null;
      }
    }

    function safeValue(block) {
      try {
        return block();
      } catch (error) {
        return null;
      }
    }

    function numberValue(value) {
      if (value === null || value === undefined) {
        return null;
      }
      const number = Number(value);
      return Number.isFinite(number) ? number : null;
    }

    function stringValue(value) {
      if (value === null || value === undefined) {
        return null;
      }
      const text = String(value);
      return text.length > 0 ? text : null;
    }

    function infoString(info, key) {
      return stringValue(unwrap(info.valueForKey(key)));
    }

    function infoNumber(info, key) {
      return numberValue(unwrap(info.valueForKey(key)));
    }

    function readNowPlaying() {
      if (!MRNowPlayingRequest) {
        return null;
      }

      const item = safeValue(() => MRNowPlayingRequest.localNowPlayingItem);
      const info = item ? safeValue(() => item.nowPlayingInfo) : null;
      if (!info) {
        return null;
      }

      const title = infoString(info, 'kMRMediaRemoteNowPlayingInfoTitle');
      if (!title) {
        return null;
      }

      const playerPath = safeValue(() => MRNowPlayingRequest.localNowPlayingPlayerPath);
      const client = playerPath ? safeValue(() => playerPath.client) : null;
      const metadata = item ? safeValue(() => item.metadata) : null;

      return {
        title: title,
        artist: infoString(info, 'kMRMediaRemoteNowPlayingInfoArtist'),
        album: infoString(info, 'kMRMediaRemoteNowPlayingInfoAlbum'),
        duration: infoNumber(info, 'kMRMediaRemoteNowPlayingInfoDuration'),
        elapsedTime: infoNumber(info, 'kMRMediaRemoteNowPlayingInfoElapsedTime'),
        calculatedPlaybackPosition: metadata ? numberValue(unwrap(metadata.calculatedPlaybackPosition)) : null,
        playbackRate: infoNumber(info, 'kMRMediaRemoteNowPlayingInfoPlaybackRate'),
        displayName: client ? stringValue(unwrap(client.displayName)) : null,
        bundleIdentifier: client ? stringValue(unwrap(client.bundleIdentifier)) : null,
      };
    }

    function fingerprint(payload) {
      if (!payload) {
        return 'none';
      }

      return JSON.stringify({
        title: payload.title || '',
        artist: payload.artist || '',
        album: payload.album || '',
        bundleIdentifier: payload.bundleIdentifier || '',
        playing: Number(payload.playbackRate || 0) > 0,
      });
    }

    function writeLine(text) {
      const output = $.NSFileHandle.fileHandleWithStandardOutput;
      const line = $.NSString.alloc.initWithString(text + '\\n');
      output.writeData(line.dataUsingEncoding($.NSUTF8StringEncoding));
    }
    """

  private static let getScript = """
    \(nowPlayingReaderScript)

    function run() {
      return JSON.stringify(readNowPlaying());
    }
    """

  private static let streamScript = """
    \(nowPlayingReaderScript)

    function run() {
      let lastFingerprint = '__initial__';

      while (true) {
        const payload = readNowPlaying();
        const currentFingerprint = fingerprint(payload);

        if (currentFingerprint !== lastFingerprint) {
          lastFingerprint = currentFingerprint;
          writeLine(JSON.stringify(payload));
        }

        $.NSThread.sleepForTimeInterval(1);
      }
    }
    """

  private let stateQueue = DispatchQueue(label: "ProcessReporter.SystemNowPlayingProvider.state")
  private let decoder = JSONDecoder()

  private var process: Process?
  private var stdoutPipe: Pipe?
  private var stderrPipe: Pipe?
  private var lineBuffer = Data()
  private var callback: MediaInfoManager.PlaybackStateChangedCallback?
  private var latestMediaInfo: MediaInfo?
  private var didReceiveStreamState = false
  private var didStopIntentionally = false

  func startMonitoring(callback: @escaping MediaInfoManager.PlaybackStateChangedCallback) {
    stateQueue.async {
      self.callback = callback
      self.latestMediaInfo = nil
      self.didReceiveStreamState = false
      self.didStopIntentionally = false
      self.stopStreamLocked()

      do {
        try self.startStreamLocked()
      } catch {
        Self.logger.error("Failed to start now playing stream: \(error.localizedDescription)")
      }
    }
  }

  func stopMonitoring() {
    stateQueue.sync {
      didStopIntentionally = true
      callback = nil
      latestMediaInfo = nil
      didReceiveStreamState = false
      stopStreamLocked()
    }
  }

  func getMediaInfo(timeout: TimeInterval) -> MediaInfo? {
    guard let payload = runGetScript(timeout: timeout) else {
      return nil
    }

    return makeMediaInfo(from: payload)
  }

  private func startStreamLocked() throws {
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = [
      "-l",
      "JavaScript",
      "-e",
      Self.streamScript,
    ]
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }

      self?.stateQueue.async {
        self?.handleStreamDataLocked(data)
      }
    }

    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
      _ = handle.availableData
    }

    process.terminationHandler = { [weak self] terminatedProcess in
      self?.stateQueue.async {
        guard self?.process === terminatedProcess else { return }

        let shouldClear = self?.didStopIntentionally == false
        let callback = self?.callback
        self?.stopStreamLocked()

        if shouldClear, let callback {
          self?.latestMediaInfo = nil
          self?.didReceiveStreamState = true
          DispatchQueue.main.async {
            callback(nil)
          }
        }
      }
    }

    try process.run()

    self.process = process
    self.stdoutPipe = stdoutPipe
    self.stderrPipe = stderrPipe
    self.lineBuffer.removeAll(keepingCapacity: true)
  }

  private func stopStreamLocked() {
    stdoutPipe?.fileHandleForReading.readabilityHandler = nil
    stderrPipe?.fileHandleForReading.readabilityHandler = nil
    process?.terminationHandler = nil

    if let process, process.isRunning {
      process.terminate()
    }

    process = nil
    stdoutPipe = nil
    stderrPipe = nil
    lineBuffer.removeAll(keepingCapacity: true)
  }

  private func handleStreamDataLocked(_ data: Data) {
    lineBuffer.append(data)

    while let newlineRange = lineBuffer.firstRange(of: Data([0x0A])) {
      let line = lineBuffer.subdata(in: lineBuffer.startIndex..<newlineRange.lowerBound)
      lineBuffer.removeSubrange(lineBuffer.startIndex..<newlineRange.upperBound)

      handleStreamLineLocked(line)
    }
  }

  private func handleStreamLineLocked(_ line: Data) {
    let trimmedLine = line.trimmedASCIIWhitespace()
    let mediaInfo: MediaInfo?

    if trimmedLine.isEmpty || trimmedLine == Data("null".utf8) {
      mediaInfo = nil
    } else {
      do {
        let payload = try decoder.decode(NowPlayingPayload.self, from: trimmedLine)
        mediaInfo = makeMediaInfo(from: payload)
      } catch {
        Self.logger.error("Failed to decode now playing stream line: \(error.localizedDescription)")
        return
      }
    }

    latestMediaInfo = mediaInfo
    didReceiveStreamState = true

    guard let callback else { return }
    DispatchQueue.main.async {
      callback(mediaInfo)
    }
  }

  private func runGetScript(timeout: TimeInterval) -> NowPlayingPayload? {
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let semaphore = DispatchSemaphore(value: 0)

    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = [
      "-l",
      "JavaScript",
      "-e",
      Self.getScript,
    ]
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.terminationHandler = { _ in
      semaphore.signal()
    }

    do {
      try process.run()
    } catch {
      Self.logger.error("Failed to run now playing query: \(error.localizedDescription)")
      return nil
    }

    let waitResult = semaphore.wait(timeout: .now() + timeout)
    if waitResult == .timedOut {
      process.terminate()
      return nil
    }

    let output = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let errorOutput = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    guard process.terminationStatus == 0 else {
      let message = String(data: errorOutput, encoding: .utf8) ?? "unknown error"
      Self.logger.error("Now playing query failed: \(message)")
      return nil
    }

    let trimmedOutput = output.trimmedASCIIWhitespace()
    guard !trimmedOutput.isEmpty, trimmedOutput != Data("null".utf8) else {
      return nil
    }

    do {
      return try decoder.decode(NowPlayingPayload.self, from: trimmedOutput)
    } catch {
      Self.logger.error("Failed to decode now playing query output: \(error.localizedDescription)")
      return nil
    }
  }

  private func makeMediaInfo(from payload: NowPlayingPayload) -> MediaInfo? {
    guard let title = emptyStringAsNil(payload.title) else {
      return nil
    }

    let runningApplication = runningApplication(for: payload)
    let processID = runningApplication.map { Int($0.processIdentifier) } ?? 0
    let bundleIdentifier =
      payload.bundleIdentifier
      ?? runningApplication?.bundleIdentifier

    return MediaInfo(
      name: title,
      artist: emptyStringAsNil(payload.artist),
      album: emptyStringAsNil(payload.album),
      image: nil,
      duration: payload.duration ?? 0,
      elapsedTime: payload.calculatedPlaybackPosition ?? payload.elapsedTime ?? 0,
      processID: processID,
      processName: runningApplication?.localizedName ?? payload.displayName ?? bundleIdentifier ?? "",
      executablePath: runningApplication?.executableURL?.path ?? "",
      playing: (payload.playbackRate ?? 0) > 0,
      applicationIdentifier: bundleIdentifier
    )
  }

  private func runningApplication(for payload: NowPlayingPayload) -> NSRunningApplication? {
    let runningApplications = NSWorkspace.shared.runningApplications

    if let bundleIdentifier = payload.bundleIdentifier {
      return runningApplications.first { $0.bundleIdentifier == bundleIdentifier }
    }

    if let displayName = payload.displayName {
      return runningApplications.first { $0.localizedName == displayName }
    }

    return nil
  }

  private func emptyStringAsNil(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
  }
}

private extension Data {
  func trimmedASCIIWhitespace() -> Data {
    var lowerBound = startIndex
    var upperBound = endIndex

    while lowerBound < upperBound, self[lowerBound].isASCIIWhitespace {
      lowerBound = index(after: lowerBound)
    }

    while lowerBound < upperBound, self[index(before: upperBound)].isASCIIWhitespace {
      upperBound = index(before: upperBound)
    }

    return subdata(in: lowerBound..<upperBound)
  }
}

private extension UInt8 {
  var isASCIIWhitespace: Bool {
    self == 0x09 || self == 0x0A || self == 0x0D || self == 0x20
  }
}
