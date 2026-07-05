import Testing
@testable import ProcessReporterCoreChecks

@Test func reportFingerprintIsStableForSameInput() {
    let first = ReportFingerprint.make(
        processBundleID: "com.apple.Terminal",
        windowTitle: "zsh",
        mediaBundleID: nil,
        mediaName: nil,
        isPlaying: false
    )
    let same = ReportFingerprint.make(
        processBundleID: "com.apple.Terminal",
        windowTitle: "zsh",
        mediaBundleID: nil,
        mediaName: nil,
        isPlaying: false
    )

    #expect(first == same)
}

@Test func reportFingerprintChangesWithReportContent() {
    let first = ReportFingerprint.make(
        processBundleID: "com.apple.Terminal",
        windowTitle: "zsh",
        mediaBundleID: nil,
        mediaName: nil,
        isPlaying: false
    )
    let changed = ReportFingerprint.make(
        processBundleID: "com.apple.Terminal",
        windowTitle: "vim",
        mediaBundleID: nil,
        mediaName: nil,
        isPlaying: false
    )

    #expect(first != changed)
}
