//
//  ReporterStatusItemManager.swift
//  ProcessReporter
//
//  Created by Innei on 2025/4/10.
//

import Cocoa
import RxCocoa
import RxSwift
import SnapKit
import SwiftUI

@MainActor
class ReporterStatusItemManager: NSObject {
	private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

	// MARK: - Items

	private var enabledItem = NSMenuItem()
	private var accessibilityPermissionItem = NSMenuItem()
    private var settingItem = NSMenuItem()

	private var currentProcessItem = NSMenuItem()
	private var currentMediaNameItem = NSMenuItem()

	private var lastSendProcessNameItem = NSMenuItem()
	private var lastSendProcessTimeItem = NSMenuItem()
	private var lastSendMediaNameItem = NSMenuItem()

	private var lastReportTime: Date?
	private var updateTimer: Timer?

	// Action
	private var enableMediaReportButton = NSMenuItem()
	private var enableProcessReportButton = NSMenuItem()

	override init() {
		super.init()

		setupStatusItem()
		synchronizeUI()
	}

	deinit {
		updateTimer?.invalidate()
		updateTimer = nil
	}

	private func synchronizeUI() {
		let preferences = PreferencesDataModel.shared
		enabledItem.state = preferences.isEnabled.value ? .on : .off
		enableMediaReportButton.state = preferences.enabledTypes.value.types.contains(.media) ? .on : .off
		enableProcessReportButton.state = preferences.enabledTypes.value.types.contains(.process) ? .on : .off
	}

	private func setupStatusItem() {
		toggleStatusItemIcon(.ready)

		let menu = NSMenu()
		currentProcessItem = NSMenuItem(title: "No Process", action: #selector(noop), keyEquivalent: "", target: self)
		menu.addItem(NSMenuItem.sectionHeader(title: "Current Process"))
		menu.addItem(currentProcessItem)

		menu.addItem(NSMenuItem.separator())
		menu.addItem(NSMenuItem.sectionHeader(title: "Current Media"))
		currentMediaNameItem = NSMenuItem(title: "No Media", action: #selector(noop), keyEquivalent: "", target: self)
		menu.addItem(currentMediaNameItem)

		menu.addItem(NSMenuItem.separator())
		menu.addItem(NSMenuItem.sectionHeader(title: "Last Send"))
		lastSendProcessNameItem = NSMenuItem(title: "..Last Process", action: #selector(noop), keyEquivalent: "", target: self)
		menu.addItem(lastSendProcessNameItem)
		lastSendMediaNameItem = NSMenuItem(title: "..Last Media", action: #selector(noop), keyEquivalent: "", target: self)
		menu.addItem(lastSendMediaNameItem)
		lastSendProcessTimeItem = NSMenuItem(title: "..Last Time", action: #selector(noop), keyEquivalent: "", target: self)
		menu.addItem(lastSendProcessTimeItem)
        
		menu.addItem(NSMenuItem.separator())
		enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "s", target: self)
		menu.addItem(enabledItem)
		accessibilityPermissionItem = NSMenuItem(
			title: "Request Accessibility Permission",
			action: #selector(requestAccessibilityPermission),
			keyEquivalent: "",
			target: self
		)
		menu.addItem(accessibilityPermissionItem)
        settingItem = NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ",", target: self)
		menu.addItem(settingItem)

		menu.addItem(NSMenuItem.separator())
		menu.addItem(NSMenuItem.sectionHeader(title: "Enabled Reporters"))
		enableMediaReportButton = NSMenuItem(title: "Media", action: #selector(toggleEnableMedia), keyEquivalent: "", target: self)
		enableProcessReportButton = NSMenuItem(title: "Process", action: #selector(toggleEnableProcess), keyEquivalent: "", target: self)
		menu.addItem(enableMediaReportButton)
		menu.addItem(enableProcessReportButton)

		menu.addItem(NSMenuItem.separator())
		menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q"))

		menu.delegate = self
		statusItem.menu = menu

		setupUpdateTimer()
	}

	private func setupUpdateTimer() {
		updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
			Task { @MainActor in
				self?.updateLastSendTimeDisplay()
			}
		}
		if let updateTimer {
			RunLoop.main.add(updateTimer, forMode: .common)
		}
	}

	private func updateLastSendTimeDisplay() {
		guard let lastTime = lastReportTime else { return }
		lastSendProcessTimeItem.title = lastTime.relativeTimeDescription()
	}

	enum StatusItemIconStatus {
		case ready
		case syncing
		case offline
		case paused
		case partialError
		case error
	}

	func toggleStatusItemIcon(_ status: StatusItemIconStatus) {
		guard let button = statusItem.button else { return }
		switch status {
		case .ready:
			button.image = NSImage(systemSymbolName: "icloud.fill", accessibilityDescription: "Ready")
		case .offline:
			button.image = NSImage(systemSymbolName: "icloud.slash.fill", accessibilityDescription: "Network Error")
		case .paused:
			button.image = NSImage(systemSymbolName: "icloud.slash.fill", accessibilityDescription: "Paused")
		case .syncing:
			button.image = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90.icloud.fill", accessibilityDescription: "Syncing")
		case .partialError:
			button.image = NSImage(systemSymbolName: "exclamationmark.icloud", accessibilityDescription: "Partial Error")
		case .error:
			button.image = NSImage(systemSymbolName: "exclamationmark.icloud.fill", accessibilityDescription: "Error")
		}
	}

	func updateCurrentProcessItem(_ info: FocusedWindowInfo) {
		currentProcessItem.title = info.appName
		currentProcessItem.image = {
			let icon = info.icon
			icon?.size = NSSize(width: 16, height: 16)
			return icon
		}()
	}

	func updateCurrentMediaItem(_ mediaInfo: MediaInfo? = nil) {
		if let mediaInfo = mediaInfo, let name = mediaInfo.name {
			let statusPrefix = mediaInfo.playing ? "" : "⏸ "
			currentMediaNameItem.title = statusPrefix + formatMediaName(name, mediaInfo.artist)
			if let base64 = mediaInfo.image, let data = Data(base64Encoded: base64) {
				let firstLine = statusPrefix + name + "\n"
				let secondLine = mediaInfo.artist ?? "-"
				let fullString = firstLine + secondLine

				let attributedString = NSMutableAttributedString(string: fullString)

				// First line: Bold font
				let firstLineRange = NSRange(location: 0, length: firstLine.count)
				attributedString.addAttribute(
					.font, value: NSFont.systemFont(ofSize: 16, weight: .medium), range: firstLineRange)

				// Second line: Secondary color
				let secondLineRange = NSRange(location: firstLine.count, length: secondLine.count)
				attributedString.addAttribute(
					.foregroundColor, value: NSColor.secondaryLabelColor, range: secondLineRange)

				currentMediaNameItem.attributedTitle = attributedString
				currentMediaNameItem.image = NSImage(data: data, size: .init(width: 40, height: 40))?
					.withRoundedCorners(radius: 8)
			}

		} else {
			currentMediaNameItem.title = "..No Media"
		}
	}

	func updateLastSendProcessNameItem(_ info: ReportModel) {
		lastSendProcessNameItem.title = info.processName ?? "N/A"
		lastReportTime = info.timeStamp
		updateLastSendTimeDisplay()

		lastSendMediaNameItem.title = formatMediaName(info.mediaName, info.artist)
	}

	func formatMediaName(_ mediaName: String?, _ artist: String?) -> String {
		if let mediaName = mediaName, let artist = artist {
			return "\(mediaName) - \(artist)"
		}
		return mediaName ?? "No Media"
	}
}

// MARK: - Menu Delegate

extension ReporterStatusItemManager: NSMenuDelegate {
	func menuWillOpen(_ menu: NSMenu) {
		synchronizeUI()
		guard let info = ApplicationMonitor.shared.getFocusedWindowInfo() else { return }
		updateCurrentProcessItem(info)

		// Fetch media info via async actor with short wait to avoid main-thread blocking
		var mediaInfo: MediaInfo?
		let semaphore = DispatchSemaphore(value: 0)
		Task.detached(priority: .utility) {
			let result = try? await MediaInfoManager.getMediaInfoAsync(timeout: 3.0)
			mediaInfo = result ?? mediaInfo
			semaphore.signal()
		}
		_ = semaphore.wait(timeout: .now() + .milliseconds(150))
		if let mediaInfo = mediaInfo ?? MediaInfoManager.getMediaInfo() {
			updateCurrentMediaItem(mediaInfo)
		}
	}
}

// MARK: - Menu Actions

extension ReporterStatusItemManager {
	@objc private func noop() {}

	@objc private func toggleEnabled() {
		let isEnabled = PreferencesDataModel.shared.isEnabled.value
		PreferencesDataModel.shared.isEnabled.accept(!isEnabled)
	}

	@objc private func requestAccessibilityPermission() {
		if ApplicationMonitor.shared.requestAccessibilityAuthorization() {
			ToastManager.shared.success("Accessibility permission is already enabled.")
		}
	}

	@objc private func showSettings() {
		SettingWindowManager.shared.showWindow()
	}

	@objc private func toggleEnableMedia(sender: NSMenuItem) {
		let currentState = sender.state

		var snapshot = PreferencesDataModel.shared.enabledTypes.value.types
		if currentState == .on {
			snapshot.remove(.media)
		} else {
			snapshot.insert(.media)
		}
		PreferencesDataModel.shared.enabledTypes.accept(.init(types: snapshot))
	}

	@objc private func toggleEnableProcess(sender: NSMenuItem) {
		let currentState = sender.state

		var snapshot = PreferencesDataModel.shared.enabledTypes.value.types
		if currentState == .on {
			snapshot.remove(.process)
		} else {
			snapshot.insert(.process)
		}
		PreferencesDataModel.shared.enabledTypes.accept(.init(types: snapshot))
	}
}
