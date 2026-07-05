//
//  ReporterStatusItemManager.swift
//  ProcessReporter
//
//  Created by Innei on 2025/4/10.
//

import Cocoa

@MainActor
class ReporterStatusItemManager: NSObject {
	enum StatusItemIconStatus {
		case ready
		case syncing
		case offline
		case paused
		case partialError
		case error
	}

	func toggleStatusItemIcon(_ status: StatusItemIconStatus) {
		StatusMenuStore.shared.status = status
	}

	func updateCurrentProcessItem(_ info: FocusedWindowInfo) {
		StatusMenuStore.shared.currentProcess = info.appName
	}

	func updateCurrentMediaItem(_ mediaInfo: MediaInfo? = nil) {
		if let mediaInfo = mediaInfo, let name = mediaInfo.name {
			StatusMenuStore.shared.currentMedia = formatMediaName(name, mediaInfo.artist, playing: mediaInfo.playing)
		} else {
			StatusMenuStore.shared.currentMedia = "No Media"
		}
	}

	func updateLastSendProcessNameItem(_ info: ReportModel) {
		StatusMenuStore.shared.lastProcess = info.processName ?? "N/A"
		StatusMenuStore.shared.lastReportTime = info.timeStamp
		StatusMenuStore.shared.lastMedia = formatMediaName(info.mediaName, info.artist)
	}

	func formatMediaName(_ mediaName: String?, _ artist: String?, playing: Bool = true) -> String {
		let prefix = playing ? "" : "Paused: "
		if let mediaName = mediaName, let artist = artist {
			return "\(prefix)\(mediaName) - \(artist)"
		}
		return prefix + (mediaName ?? "No Media")
	}
}
