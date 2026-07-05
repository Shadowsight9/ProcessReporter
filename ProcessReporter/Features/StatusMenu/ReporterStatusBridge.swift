//
//  ReporterStatusBridge.swift
//  ProcessReporter
//
//  Created by Innei on 2025/4/10.
//

import Cocoa

@MainActor
class ReporterStatusBridge: NSObject {
	enum ReporterStatus {
		case ready
		case syncing
		case offline
		case paused
		case partialError
		case error
	}

	func updateStatus(_ status: ReporterStatus) {
		StatusMenuStore.shared.status = status
	}

	func updateCurrentProcessItem(_ info: FocusedWindowInfo) {
		StatusMenuStore.shared.currentProcess = info.appName
	}

	func updateCurrentMediaItem(_ mediaInfo: MediaInfo? = nil) {
		if let mediaInfo = mediaInfo, let name = mediaInfo.name {
			StatusMenuStore.shared.currentMedia = StatusMenuFormatter.mediaName(name, artist: mediaInfo.artist, playing: mediaInfo.playing)
		} else {
			StatusMenuStore.shared.currentMedia = "No Media"
		}
	}

	func updateLastSendProcessNameItem(_ info: ReportModel) {
		StatusMenuStore.shared.lastProcess = info.processName ?? "N/A"
		StatusMenuStore.shared.lastMedia = StatusMenuFormatter.mediaName(info.mediaName, artist: info.artist)
        StatusMenuStore.shared.lastReportTime = info.timeStamp
	}
}
