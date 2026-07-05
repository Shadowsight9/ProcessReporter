import Foundation

enum ReportFingerprint {
    static func make(
        processBundleID: String?,
        windowTitle: String?,
        mediaBundleID: String?,
        mediaName: String?,
        isPlaying: Bool
    ) -> String {
        [
            processBundleID ?? "",
            windowTitle ?? "",
            mediaBundleID ?? "",
            mediaName ?? "",
            isPlaying ? "playing" : "paused",
        ].joined(separator: "\u{1F}")
    }
}
