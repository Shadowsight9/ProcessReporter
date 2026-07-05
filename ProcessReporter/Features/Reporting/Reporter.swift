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
	let onSend: (_ data: ReportModel) async -> Result<Void, ReporterError>
}

@MainActor
class Reporter {
	private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProcessReporter", category: "Reporter")
	private var mapping = [String: ReporterOptions]()
	private var statusBridge = ReporterStatusBridge()

	// Add reporter extensions array
	private var reporterExtensions: [ReporterExtension] = []

	private var cachedFilteredProcessAppNames = [String]()
	private var cachedFilteredMediaAppNames = [String]()
	private var subscriptions: [RelaySubscription] = []

	// Mapping cache
	private var mappingCache: [PreferencesDataModel.Mapping] = []

	// Clear all caches for memory cleanup
	public func clearCaches() {
		cachedFilteredProcessAppNames.removeAll()
		cachedFilteredMediaAppNames.removeAll()
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
		let results = await withTaskGroup(of: (String, Result<Void, ReporterError>).self) { group in
			for (name, options) in mapping {
				group.addTask {
					let result = await options.onSend(data)
					return (name, result)
				}
			}

			var allResults = [(String, Result<Void, ReporterError>)]()
			for await result in group {
				allResults.append(result)
			}
			return allResults
		}

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
		data.integrations = successNames
		let reportValue = ReportValue(
			id: data.id,
			processName: data.processName,
			windowTitle: data.windowTitle,
			timeStamp: data.timeStamp,
			artist: data.artist,
			mediaName: data.mediaName,
			mediaProcessName: data.mediaProcessName,
			mediaDuration: data.mediaDuration,
			mediaElapsedTime: data.mediaElapsedTime,
			mediaImageData: data.mediaImageData,
			integrations: data.integrations
		)
		await DataStore.shared.saveReport(reportValue)
		let isAllFailed = successNames.isEmpty && !failures.isEmpty
		if !isAllFailed {
			statusBridge.updateLastSendProcessNameItem(data)
		}

		if failures.isEmpty {
			statusBridge.updateStatus(.syncing)
			return .success(successNames)
		} else {
			statusBridge.updateStatus(isAllFailed ? .error : .partialError)
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
					windowInfo.applicationIdentifier = rule.to
					break
				}
			}

			// Process name mapping
			for rule in mappingCache where rule.type == .processName {
				if windowInfo.appName == rule.from {
					windowInfo.appName = rule.to
					data.processName = rule.to
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
					mediaInfo.processName = rule.to
					data.mediaProcessName = rule.to
					break
				}
			}

			// Media process name mapping
			for rule in mappingCache where rule.type == .mediaProcessName {
				if mediaInfo.processName == rule.from {
					mediaInfo.processName = rule.to
					data.mediaProcessName = rule.to
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
			if PreferencesDataModel.shared.reportOnFocusChange.value
				&& PreferencesDataModel.shared.enabledTypes.value.types.contains(.process)
			{
				self.prepareSend(windowInfo: info)
			}
		}

		MediaInfoManager.startMonitoringPlaybackChanges { [weak self] mediaInfo in
			guard let self = self else { return }
			if PreferencesDataModel.shared.enabledTypes.value.types.contains(.media) {
                                guard let mediaInfo = mediaInfo else {
                                        self.statusBridge.updateCurrentMediaItem(nil)
                                        return
                                }

				self.prepareSend(
					windowInfo: ApplicationMonitor.shared.getFocusedWindowInfo(),
					mediaInfo: mediaInfo
				)
			}
		}
		statusBridge.updateStatus(.syncing)
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

		let appName = windowInfo.appName
		let now = Date()
		// Ignore the first 2 seconds after initialization to wait for the setting synchronization to complete
		if now.timeIntervalSince(reporterInitializedTime) < 2 {
			return
		}

		let enabledTypes = PreferencesDataModel.shared.enabledTypes.value.types
		if enabledTypes.isEmpty {
			statusBridge.updateStatus(.paused)
			return
		}
		if !isNetworkAvailable() {
			statusBridge.updateStatus(.offline)
			return
		} else {
			statusBridge.updateStatus(.syncing)
		}

		var dataModel = ReportModel(
			windowInfo: nil,
			integrations: [],
			mediaInfo: nil)

		let shouldIgnoreArtistNull = PreferencesDataModel.shared.ignoreNullArtist.value

		if enabledTypes.contains(.media), let mediaInfo = mediaInfo, mediaInfo.playing {
			// Filter media name

			if !cachedFilteredMediaAppNames.contains(mediaInfo.processName),
				!shouldIgnoreArtistNull
					|| (mediaInfo.artist != nil && !mediaInfo.artist!.isEmpty)
			{
				dataModel.setMediaInfo(mediaInfo)
			}
		}
		// Filter process name
		if enabledTypes.contains(.process), !cachedFilteredProcessAppNames.contains(appName) {
			dataModel.setProcessInfo(windowInfo)
		}
                if enabledTypes.contains(.media) {
                        statusBridge.updateCurrentMediaItem(mediaInfo)
		}

		// Apply mapping rules to the data model before sending
		applyMappingRules(to: &dataModel)

		Task { @MainActor in
			//            debugPrint(dataModel)
			_ = await self.send(data: dataModel)
		}
	}

	private func dispose() {
		ApplicationMonitor.shared.stopMouseMonitoring()
		ApplicationMonitor.shared.stopWindowFocusMonitoring()
		MediaInfoManager.stopMonitoringPlaybackChanges()

		statusBridge.updateStatus(.paused)
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

		// Register all available extensions
		initializeExtensions()

		subscribeSettingsChanged()
	}

	private func initializeExtensions() {
		// Register all reporter extensions
		let extensions: [ReporterExtension] = [
			ShellReporterExtension(),
		]

		for ext in extensions {
			registerExtension(ext)
		}
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
			.subscribeOnMain { [weak self] mappingList in
				self?.mappingCache = mappingList.getList()
			}
		subscriptions.append(subscription)
	}

	private func subscribeFilterSettingsChanged() {
		let d1 = PreferencesDataModel.filteredProcesses
			.subscribeOnMain { [weak self] appIds in
				self?.cachedFilteredProcessAppNames.removeAll()
				for appId in appIds {
					let appInfo = AppUtility.shared.getAppInfo(for: appId)
					self?.cachedFilteredProcessAppNames.append(appInfo.displayName)
				}
			}
		let d2 = PreferencesDataModel.filteredMediaProcesses
			.subscribeOnMain { [weak self] appIds in
				self?.cachedFilteredMediaAppNames.removeAll()
				for appId in appIds {
					let appInfo = AppUtility.shared.getAppInfo(for: appId)
					self?.cachedFilteredMediaAppNames.append(appInfo.displayName)
				}
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
