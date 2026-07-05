import Cocoa
import os

enum ReporterError: Error {
	case networkError(String)
	case cancelled(message: String)
	case unknown(message: String, successIntegrations: [String])
	case ratelimitExceeded(message: String)
	case ignored
	case databaseError(String)
}

enum SendError: Error {
	case failure([String])
}

struct ReporterOptions {
	let onSend: (_ snapshot: ReportSnapshot) async -> Result<Void, ReporterError>
}

actor ReportDelivery {
	func send(
		snapshot: ReportSnapshot,
		mapping: [String: ReporterOptions]
	) async -> [(String, Result<Void, ReporterError>)] {
		await withTaskGroup(of: (String, Result<Void, ReporterError>).self) { group in
			for (name, options) in mapping {
				group.addTask {
					let result = await options.onSend(snapshot)
					return (name, result)
				}
			}

			var results = [(String, Result<Void, ReporterError>)]()
			for await result in group {
				results.append(result)
			}
			return results
		}
	}
}

@MainActor
class Reporter {
	private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProcessReporter", category: "Reporter")
	private var mapping = [String: ReporterOptions]()
	private let delivery = ReportDelivery()

	// Add reporter extensions array
	private var reporterExtensions: [ReporterExtension] = []

	private var cachedFilteredProcessBundleIDs = Set<String>()
	private var cachedFilteredMediaBundleIDs = Set<String>()
	private var lastReportFingerprint: String?
	private var lastReportFingerprintDate: Date?
	private var subscriptions: [RelaySubscription] = []

	// Mapping cache
	private var mappingCache: [PreferencesDataModel.Mapping] = []

	// Clear all caches for memory cleanup
	public func clearCaches() {
		cachedFilteredProcessBundleIDs.removeAll()
		cachedFilteredMediaBundleIDs.removeAll()
		lastReportFingerprint = nil
		lastReportFingerprintDate = nil
		mappingCache.removeAll()
	}

	// Handle wake from sleep - reinitialize components if needed
	public func handleWakeFromSleep() {
		logger.info("Handling wake from sleep - reinitializing components")

		// Clear caches that might be stale after sleep
		clearCaches()

		// Restart application monitoring if it was active
		if PreferencesDataModel.shared.isEnabled.value {
			ApplicationMonitor.shared.startMouseMonitoring()
			ApplicationMonitor.shared.startWindowFocusMonitoring()
			if let info = ApplicationMonitor.shared.getFocusedWindowInfo() {
				ForegroundUsageTracker.shared.focusChanged(to: info)
			}
		}

		logger.info("Wake from sleep handling completed")
	}

	// Register a reporter extension
	public func registerExtension(_ extension: ReporterExtension) {
		reporterExtensions.append(`extension`)
		if `extension`.isEnabled {
			Task {
				await `extension`.register(to: self)
			}
		}
	}

	// Update the status of all extensions
	public func updateExtensions() async {
		for ext in reporterExtensions {
			if ext.isEnabled {
				await ext.register(to: self)
			} else {
				await ext.unregister(from: self)
			}
		}
	}

	public func register(name: String, options: ReporterOptions) {
		mapping[name] = options
	}

	public func unregister(name: String) {
		mapping.removeValue(forKey: name)
	}

	public func send(data: ReportModel) async -> Result<[String], SendError> {
		let foregroundUsage = ForegroundUsageTracker.shared.snapshot(mappings: mappingCache)
		let snapshot = ReportSnapshot(data, foregroundUsage: foregroundUsage)
		let results = await delivery.send(snapshot: snapshot, mapping: mapping)

		var successNames = [String]()
		var failureNames = [String]()

		let failures = results.filter { name, result in
			if case .success = result {
				successNames.append(name)
				return false
			}
			if case let .failure(error) = result {
				switch error {
				case .ignored, .ratelimitExceeded:
					successNames.append(name)
					return false
				case .databaseError(let message):
					failureNames.append(name)
					logger.error("\(name) database error: \(message)")
					return true
				default:
					failureNames.append(name)
					logger.error("\(name) failed: \(String(describing: error))")
					return true
				}
			}
			return true
		}

		// Persist via DataStore (value-only, no SwiftData leakage)
		await DataStore.shared.saveReport(snapshot.reportValue(integrations: successNames))
		let isAllFailed = successNames.isEmpty && !failures.isEmpty
		if !isAllFailed {
			StatusMenuStore.shared.updateLastReport(data)
		}

		if failures.isEmpty {
			StatusMenuStore.shared.status = .syncing
			return .success(successNames)
		} else {
			StatusMenuStore.shared.status = isAllFailed ? .error : .partialError
			return .failure(.failure(failureNames))
		}
	}

	// Apply mapping rules to the data model
	private func applyMappingRules(to data: inout ReportModel) {
		// Skip if no mapping rules or no data to map
		if mappingCache.isEmpty || (data.processInfoRaw == nil && data.mediaInfoRaw == nil) {
			return
		}

		// Apply process name mapping
		if var windowInfo = data.processInfoRaw {
			// Process application identifier mapping
			for rule in mappingCache where rule.type == .processApplicationIdentifier {
				if windowInfo.applicationIdentifier == rule.from {
					if !rule.to.isEmpty {
						windowInfo.applicationIdentifier = rule.to
					}
					data.processDescription = rule.description
					break
				}
			}

			// Process name mapping
			for rule in mappingCache where rule.type == .processName {
				if windowInfo.appName == rule.from {
					if !rule.to.isEmpty {
						windowInfo.appName = rule.to
						data.processName = rule.to
					}
					data.processDescription = rule.description
					break
				}
			}

			data.processInfoRaw = windowInfo
		}

		// Apply media name mapping
		if var mediaInfo = data.mediaInfoRaw {
			// Media process application identifier mapping
			for rule in mappingCache where rule.type == .mediaProcessApplicationIdentifier {
				if mediaInfo.applicationIdentifier == rule.from {
					if !rule.to.isEmpty {
						mediaInfo.processName = rule.to
						data.mediaProcessName = rule.to
					}
					data.mediaProcessDescription = rule.description
					break
				}
			}

			// Media process name mapping
			for rule in mappingCache where rule.type == .mediaProcessName {
				if mediaInfo.processName == rule.from {
					if !rule.to.isEmpty {
						mediaInfo.processName = rule.to
						data.mediaProcessName = rule.to
					}
					data.mediaProcessDescription = rule.description
					break
				}
			}

			data.mediaInfoRaw = mediaInfo
		}
	}

	private func monitor() {
		monitor(promptForAccessibility: true)
	}

	private func monitor(promptForAccessibility: Bool) {
		ApplicationMonitor.shared.startMouseMonitoring(promptIfNeeded: promptForAccessibility)
		ApplicationMonitor.shared.startWindowFocusMonitoring(promptIfNeeded: promptForAccessibility)
		ApplicationMonitor.shared.onWindowFocusChanged = { [weak self] info in
			guard let self = self else { return }
			ForegroundUsageTracker.shared.focusChanged(to: info)
			if PreferencesDataModel.shared.reportOnFocusChange.value
				&& PreferencesDataModel.shared.enabledTypes.value.types.contains(.process)
			{
				self.prepareSend(windowInfo: info)
			}
		}

		if let info = ApplicationMonitor.shared.getFocusedWindowInfo() {
			ForegroundUsageTracker.shared.focusChanged(to: info)
		}

		MediaInfoManager.startMonitoringPlaybackChanges { [weak self] mediaInfo in
			guard let self = self else { return }
			if PreferencesDataModel.shared.enabledTypes.value.types.contains(.media) {
                                guard let mediaInfo = mediaInfo else {
                                        StatusMenuStore.shared.updateCurrentMedia(nil)
                                        return
                                }

				self.prepareSend(
					windowInfo: ApplicationMonitor.shared.getFocusedWindowInfo(),
					mediaInfo: mediaInfo
				)
			}
		}
		StatusMenuStore.shared.status = .syncing
	}

	private var reporterInitializedTime: Date

	private func prepareSend(
		windowInfo optionalWindowInfo: FocusedWindowInfo?,
		mediaInfo optionalMediaInfo: MediaInfo? = nil
	) {
		Task { @MainActor in
			await prepareSendAsync(windowInfo: optionalWindowInfo, mediaInfo: optionalMediaInfo)
		}
	}

	private func prepareSendAsync(
		windowInfo optionalWindowInfo: FocusedWindowInfo?,
		mediaInfo optionalMediaInfo: MediaInfo? = nil
	) async {
		var windowInfo: FocusedWindowInfo!
		if let optionalWindowInfo = optionalWindowInfo {
			windowInfo = optionalWindowInfo
		} else {
			windowInfo = ApplicationMonitor.shared.getFocusedWindowInfo()
			if windowInfo == nil {
				return
			}
		}

		var mediaInfo: MediaInfo?
		if let optionalMediaInfo = optionalMediaInfo {
			mediaInfo = optionalMediaInfo
		} else {
			mediaInfo = try? await MediaInfoManager.getMediaInfoAsync(timeout: 3.0)
		}

		let now = Date()
		// Ignore the first 2 seconds after initialization to wait for the setting synchronization to complete
		if now.timeIntervalSince(reporterInitializedTime) < 2 {
			return
		}

		let enabledTypes = PreferencesDataModel.shared.enabledTypes.value.types
		if enabledTypes.isEmpty {
			StatusMenuStore.shared.status = .paused
			return
		}
		if !isNetworkAvailable() {
			StatusMenuStore.shared.status = .offline
			return
		} else {
			StatusMenuStore.shared.status = .syncing
		}

		var dataModel = ReportModel(
			windowInfo: nil,
			integrations: [],
			mediaInfo: nil)

		let shouldIgnoreArtistNull = PreferencesDataModel.shared.ignoreNullArtist.value

		if enabledTypes.contains(.media), let mediaInfo = mediaInfo, mediaInfo.playing {
			// Filter media name

			if !cachedFilteredMediaBundleIDs.contains(mediaInfo.applicationIdentifier ?? ""),
				!shouldIgnoreArtistNull
					|| (mediaInfo.artist != nil && !mediaInfo.artist!.isEmpty)
			{
				dataModel.setMediaInfo(mediaInfo)
			}
		}
		// Filter process name
		if enabledTypes.contains(.process),
		   !cachedFilteredProcessBundleIDs.contains(windowInfo.applicationIdentifier) {
			dataModel.setProcessInfo(windowInfo)
		}
                if enabledTypes.contains(.media) {
                        StatusMenuStore.shared.updateCurrentMedia(mediaInfo)
		}

		// Apply mapping rules to the data model before sending
		applyMappingRules(to: &dataModel)
		guard dataModel.hasProcessInfo || dataModel.hasMediaInfo else { return }
		guard shouldSend(dataModel, now: now) else { return }

		_ = await send(data: dataModel)
	}

	private func shouldSend(_ report: ReportModel, now: Date) -> Bool {
		let fingerprint = ReportFingerprint.make(
			processBundleID: report.processInfoRaw?.applicationIdentifier,
			windowTitle: report.windowTitle,
			mediaBundleID: report.mediaInfoRaw?.applicationIdentifier,
			mediaName: report.mediaName,
			isPlaying: report.mediaInfoRaw?.playing == true
		)

		if fingerprint == lastReportFingerprint,
		   let lastDate = lastReportFingerprintDate,
		   now.timeIntervalSince(lastDate) < 2 {
			return false
		}

		lastReportFingerprint = fingerprint
		lastReportFingerprintDate = now
		return true
	}

	private func dispose() {
		ForegroundUsageTracker.shared.pause()
		ApplicationMonitor.shared.stopMouseMonitoring()
		ApplicationMonitor.shared.stopWindowFocusMonitoring()
		MediaInfoManager.stopMonitoringPlaybackChanges()

		StatusMenuStore.shared.status = .paused
	}

	private var timer: Timer?
	private func setupTimer() {
		disposeTimer()

		let interval = PreferencesDataModel.shared.sendInterval.value
		timer = Timer.scheduledTimer(
			withTimeInterval: TimeInterval(interval.rawValue), repeats: true
		) { [weak self] _ in
			Task { @MainActor in
				guard let self = self else { return }
				if let info = ApplicationMonitor.shared.getFocusedWindowInfo() {
					self.prepareSend(windowInfo: info)
				}
			}
		}
		RunLoop.main.add(timer!, forMode: .common)
	}

	private func disposeTimer() {
		timer?.invalidate()
	}

	init() {
		reporterInitializedTime = Date()

		registerExtension(ShellReporterExtension())

		subscribeSettingsChanged()
	}

	deinit {
		subscriptions.forEach { $0.dispose() }
	}
}

extension Reporter {
	private func subscribeSettingsChanged() {
		subscribeGeneralSettingsChanged()
		subscribeFilterSettingsChanged()
		subscribeMappingSettingsChanged()
	}

	private func subscribeMappingSettingsChanged() {
		let subscription = PreferencesDataModel.mappingList
			.subscribeOnMain { [weak self] mappings in
				self?.mappingCache = mappings
			}
		subscriptions.append(subscription)
	}

	private func subscribeFilterSettingsChanged() {
		let d1 = PreferencesDataModel.filteredProcesses
			.subscribeOnMain { [weak self] appIds in
				self?.cachedFilteredProcessBundleIDs = Set(appIds)
			}
		let d2 = PreferencesDataModel.filteredMediaProcesses
			.subscribeOnMain { [weak self] appIds in
				self?.cachedFilteredMediaBundleIDs = Set(appIds)
			}
		subscriptions.append(contentsOf: [d1, d2])
	}

	private func subscribeGeneralSettingsChanged() {
		let preferences = PreferencesDataModel.shared

		#if DEBUG
			var isInitialEnabledEmission = true
		#endif

		let d1 = preferences.isEnabled
			.subscribeOnMain { [weak self] enabled in
				guard let self = self else { return }
				#if DEBUG
					let shouldPromptForAccessibility = !isInitialEnabledEmission
					isInitialEnabledEmission = false
				#else
					let shouldPromptForAccessibility = true
				#endif

				if enabled {
					self.monitor(promptForAccessibility: shouldPromptForAccessibility)
				} else {
					self.dispose()
					self.disposeTimer()
				}
			}

		if preferences.isEnabled.value {
			if let info = ApplicationMonitor.shared.getFocusedWindowInfo() {
				prepareSend(windowInfo: info)
			}
		}

		let d2 = preferences.sendInterval
			.subscribeOnMain { [weak self] _ in
				guard let self = self else { return }
				if preferences.isEnabled.value {
					self.setupTimer()
				} else {
					self.disposeTimer()
				}
			}

		// Subscribe to extension configuration changes
		let d3 = preferences.shellIntegration
			.subscribeOnMain { [weak self] _ in
				guard let self = self else { return }
				Task {
					await self.updateExtensions()
				}
			}

		subscriptions.append(contentsOf: [d1, d2, d3])
	}
}
