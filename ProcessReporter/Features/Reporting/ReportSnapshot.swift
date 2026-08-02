import Foundation

struct ReportSnapshot: Sendable {
    var id: UUID
    var timeStamp: Date
    var processName: String?
    var processDescription: String?
    var windowTitle: String?
    var processBundleID: String?
    var artist: String?
    var mediaName: String?
    var mediaProcessName: String?
    var mediaProcessDescription: String?
    var mediaBundleID: String?
    var mediaAlbum: String?
    var mediaDuration: Double?
    var mediaElapsedTime: Double?
    var mediaPlaying: Bool
    var mediaImageData: Data?
    var foregroundUsage: ForegroundUsageSnapshot

    init(
        _ report: ReportModel,
        foregroundUsage: ForegroundUsageSnapshot = .init(
            date: "",
            apps: [],
            totalDuration: 0,
            currentBundleIdentifier: nil
        )
    ) {
        id = report.id
        timeStamp = report.timeStamp
        processName = report.processName
        processDescription = report.processDescription
        windowTitle = report.windowTitle
        processBundleID = report.processInfoRaw?.applicationIdentifier
        artist = report.artist
        mediaName = report.mediaName
        mediaProcessName = report.mediaProcessName
        mediaProcessDescription = report.mediaProcessDescription
        mediaBundleID = report.mediaInfoRaw?.applicationIdentifier
        mediaAlbum = report.mediaInfoRaw?.album
        mediaDuration = report.mediaDuration
        mediaElapsedTime = report.mediaElapsedTime
        mediaPlaying = report.mediaInfoRaw?.playing == true
        mediaImageData = report.mediaImageData
        self.foregroundUsage = foregroundUsage
    }

    init(eventAt timeStamp: Date = .now) {
        id = UUID()
        self.timeStamp = timeStamp
        processName = nil
        processDescription = nil
        windowTitle = nil
        processBundleID = nil
        artist = nil
        mediaName = nil
        mediaProcessName = nil
        mediaProcessDescription = nil
        mediaBundleID = nil
        mediaAlbum = nil
        mediaDuration = nil
        mediaElapsedTime = nil
        mediaPlaying = false
        mediaImageData = nil
        foregroundUsage = .init(
            date: "",
            apps: [],
            totalDuration: 0,
            currentBundleIdentifier: nil
        )
    }

    var hasMediaInfo: Bool {
        mediaName != nil || artist != nil
    }

    var hasProcessInfo: Bool {
        processName != nil
    }

    func reportValue(integrations: [String]) -> ReportValue {
        ReportValue(
            id: id,
            processName: processName,
            processDescription: processDescription,
            windowTitle: windowTitle,
            timeStamp: timeStamp,
            artist: artist,
            mediaName: mediaName,
            mediaProcessName: mediaProcessName,
            mediaProcessDescription: mediaProcessDescription,
            mediaDuration: mediaDuration,
            mediaElapsedTime: mediaElapsedTime,
            mediaImageData: mediaImageData,
            integrations: integrations
        )
    }
}
