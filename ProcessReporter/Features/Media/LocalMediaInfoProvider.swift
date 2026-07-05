// LocalMediaInfoProvider.swift
// ProcessReporter
// Created by Claude on 2025/7/12.

import AppKit
import Combine
import Foundation

/// MediaInfoProvider implementation using private MediaRemote framework APIs
final class LocalMediaInfoProvider: MediaInfoProvider {

  // Type definitions for MediaRemote framework function pointers
  typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (
    DispatchQueue, @escaping (NSDictionary?) -> Void
  ) -> Void
  typealias MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction = @convention(c) (
    DispatchQueue, @escaping (Bool) -> Void
  ) -> Void
  typealias MRMediaRemoteGetNowPlayingApplicationPIDFunction = @convention(c) (
    DispatchQueue, @escaping (Int32) -> Void
  ) -> Void
  typealias MRMediaRemoteRegisterForNowPlayingNotificationsFunction = @convention(c) (
    DispatchQueue
  ) -> Void
  
  private struct MediaRemoteFunctions {
    let bundle: CFBundle
    let getNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunction
    let getNowPlayingApplicationIsPlaying: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction
    let getNowPlayingApplicationPID: MRMediaRemoteGetNowPlayingApplicationPIDFunction
    let registerForNowPlayingNotifications: MRMediaRemoteRegisterForNowPlayingNotificationsFunction?
  }

  private struct NowPlayingSnapshot {
    let metadata: NSDictionary
    let isPlaying: Bool
    let pid: pid_t
  }

  private enum MediaRemoteKey {
    static let title = "kMRMediaRemoteNowPlayingInfoTitle"
    static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
    static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
    static let elapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
    static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
    static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
    static let artworkMIMEType = "kMRMediaRemoteNowPlayingInfoArtworkMIMEType"
  }
  
  private static let playingStateChangedNotificationName =
    "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
  private static let applicationChangedNotificationName =
    "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
  private static let infoChangedNotificationName =
    "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
    
  private static let frameworkURL = URL(
    fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
  private static let fetchTimeout: TimeInterval = 2.0

  private let fetchQueue = DispatchQueue(
    label: "ProcessReporter.LocalMediaInfoProvider.fetch",
    qos: .userInitiated
  )
  private let mediaRemoteCallbackQueue = DispatchQueue(
    label: "ProcessReporter.LocalMediaInfoProvider.mediaRemoteCallbacks",
    qos: .userInitiated,
    attributes: .concurrent
  )
  private let callbackLock = NSLock()
  private let functionsLock = NSLock()
  private let notificationSubject = PassthroughSubject<Void, Never>()

  private var cancellables = Set<AnyCancellable>()
  private var callback: MediaInfoManager.PlaybackStateChangedCallback?
  private var functions: MediaRemoteFunctions?
  private var isMonitoring = false
  private var didRegisterForNotifications = false
  
  // MARK: - MediaInfoProvider Implementation
  
  func startMonitoring(callback: @escaping MediaInfoManager.PlaybackStateChangedCallback) {
    setCallback(callback)

    guard let functions = loadMediaRemoteFunctions() else {
      return
    }

    guard !isMonitoring else {
      return
    }

    if !didRegisterForNotifications {
      functions.registerForNowPlayingNotifications?(DispatchQueue.main)
      didRegisterForNotifications = true
    }

    isMonitoring = true
    subscribeToMediaRemoteNotifications()
    scheduleCallbackFetch()
  }
  
  func stopMonitoring() {
    cancellables.removeAll()
    setCallback(nil)
    isMonitoring = false
  }
  
  func getMediaInfo(timeout: TimeInterval) -> MediaInfo? {
    guard let snapshot = fetchNowPlayingSnapshot(timeout: timeout) else { return nil }
    return makeMediaInfo(from: snapshot)
  }
  
  // MARK: - Private Methods
  
  private func subscribeToMediaRemoteNotifications() {
    for name in [
      Self.playingStateChangedNotificationName,
      Self.applicationChangedNotificationName,
      Self.infoChangedNotificationName,
    ] {
      NotificationCenter.default.publisher(for: Notification.Name(name))
        .sink { [weak self] _ in
          self?.notificationSubject.send()
        }
        .store(in: &cancellables)
    }
    
    notificationSubject
      .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        self?.scheduleCallbackFetch()
      }
      .store(in: &cancellables)
  }

  private func scheduleCallbackFetch() {
    guard currentCallback != nil else { return }

    fetchQueue.async { [weak self] in
      guard let self = self else { return }
      guard let mediaInfo = self.getMediaInfo(timeout: Self.fetchTimeout),
        let callback = self.currentCallback
      else {
        return
      }

      DispatchQueue.main.async {
        callback(mediaInfo)
      }
    }
  }

  private var currentCallback: MediaInfoManager.PlaybackStateChangedCallback? {
    callbackLock.lock()
    defer { callbackLock.unlock() }
    return callback
  }

  private func setCallback(_ callback: MediaInfoManager.PlaybackStateChangedCallback?) {
    callbackLock.lock()
    self.callback = callback
    callbackLock.unlock()
  }

  private func loadMediaRemoteFunctions() -> MediaRemoteFunctions? {
    functionsLock.lock()
    defer { functionsLock.unlock() }

    if let functions = functions {
      return functions
    }
    
    guard let bundle = CFBundleCreate(kCFAllocatorDefault, Self.frameworkURL as CFURL) else {
      print("Failed to load MediaRemote framework")
      return nil
    }
    
    guard
      let getNowPlayingInfo = loadFunction(
        "MRMediaRemoteGetNowPlayingInfo",
        from: bundle,
        as: MRMediaRemoteGetNowPlayingInfoFunction.self
      ),
      let getNowPlayingApplicationIsPlaying = loadFunction(
        "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
        from: bundle,
        as: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction.self
      ),
      let getNowPlayingApplicationPID = loadFunction(
        "MRMediaRemoteGetNowPlayingApplicationPID",
        from: bundle,
        as: MRMediaRemoteGetNowPlayingApplicationPIDFunction.self
      )
    else {
      return nil
    }

    let loadedFunctions = MediaRemoteFunctions(
      bundle: bundle,
      getNowPlayingInfo: getNowPlayingInfo,
      getNowPlayingApplicationIsPlaying: getNowPlayingApplicationIsPlaying,
      getNowPlayingApplicationPID: getNowPlayingApplicationPID,
      registerForNowPlayingNotifications: loadFunction(
        "MRMediaRemoteRegisterForNowPlayingNotifications",
        from: bundle,
        as: MRMediaRemoteRegisterForNowPlayingNotificationsFunction.self
      )
    )
    functions = loadedFunctions
    return loadedFunctions
  }

  private func loadFunction<T>(_ name: String, from bundle: CFBundle, as type: T.Type) -> T? {
    guard let pointer = CFBundleGetFunctionPointerForName(bundle, name as CFString) else {
      return nil
    }
    return unsafeBitCast(pointer, to: type)
  }
  
  private func fetchNowPlayingSnapshot(timeout: TimeInterval) -> NowPlayingSnapshot? {
    guard let functions = loadMediaRemoteFunctions() else { return nil }

    let group = DispatchGroup()
    let resultLock = NSLock()

    var metadata: NSDictionary?
    var isPlaying = false
    var pid: Int32 = 0

    autoreleasepool {
      group.enter()
      functions.getNowPlayingApplicationIsPlaying(mediaRemoteCallbackQueue) { playing in
        resultLock.lock()
        isPlaying = playing
        resultLock.unlock()
        group.leave()
      }

      group.enter()
      functions.getNowPlayingApplicationPID(mediaRemoteCallbackQueue) { applicationPID in
        resultLock.lock()
        pid = applicationPID
        resultLock.unlock()
        group.leave()
      }

      group.enter()
      functions.getNowPlayingInfo(mediaRemoteCallbackQueue) { information in
        resultLock.lock()
        metadata = information
        resultLock.unlock()
        group.leave()
      }
    }

    guard group.wait(timeout: .now() + timeout) == .success else {
      return nil
    }

    resultLock.lock()
    defer { resultLock.unlock() }

    guard let metadata = metadata else { return nil }
    return NowPlayingSnapshot(metadata: metadata, isPlaying: isPlaying, pid: pid_t(pid))
  }

  private func makeMediaInfo(from snapshot: NowPlayingSnapshot) -> MediaInfo {
    let runningApplication = NSRunningApplication(processIdentifier: snapshot.pid)
    let processID = Int(snapshot.pid)
    let processName = runningApplication?.localizedName ?? ""
    let executablePath = runningApplication?.executableURL?.path ?? ""
    let bundleIdentifier =
      runningApplication?.bundleIdentifier ?? AppUtility.getBundleIdentifierForPID(snapshot.pid)

    return MediaInfo(
      name: stringValue(snapshot.metadata, for: MediaRemoteKey.title),
      artist: stringValue(snapshot.metadata, for: MediaRemoteKey.artist),
      album: stringValue(snapshot.metadata, for: MediaRemoteKey.album),
      image: artworkBase64(from: snapshot.metadata),
      duration: doubleValue(snapshot.metadata, for: MediaRemoteKey.duration),
      elapsedTime: doubleValue(snapshot.metadata, for: MediaRemoteKey.elapsedTime),
      processID: processID,
      processName: processName,
      executablePath: executablePath,
      playing: snapshot.isPlaying,
      applicationIdentifier: bundleIdentifier
    )
  }

  private func stringValue(_ metadata: NSDictionary, for key: String) -> String? {
    guard let value = metadata[key] as? String else { return nil }
    return value.isEmpty ? nil : value
  }

  private func doubleValue(_ metadata: NSDictionary, for key: String) -> Double {
    return (metadata[key] as? NSNumber)?.doubleValue ?? 0
  }

  private func artworkBase64(from metadata: NSDictionary) -> String? {
    guard let data = metadata[MediaRemoteKey.artworkData] as? Data, !data.isEmpty else {
      return nil
    }

    let mimeType = metadata[MediaRemoteKey.artworkMIMEType] as? String
    if mimeType == "image/png" || mimeType == "image/jpeg" {
      return data.base64EncodedString(options: [])
    }

    if let image = NSImage(data: data), let tiffData = image.tiffRepresentation {
      return tiffData.base64EncodedString(options: [])
    }

    return data.base64EncodedString(options: [])
  }
}
