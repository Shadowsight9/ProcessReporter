import Testing
@testable import ProcessReporterCoreChecks

@Test func startingStateTakesPriorityOverReportingState() {
    let presentation = StatusPresentation.make(
        launch: .starting,
        reporting: true,
        delivery: .success,
        screen: .on
    )

    #expect(presentation.headline == "STARTING")
    #expect(presentation.headlineSymbol == "hourglass")
    #expect(presentation.menuBarSymbol == "cloud")
}

@Test func startupFailureUsesWarningPresentation() {
    let presentation = StatusPresentation.make(
        launch: .failed,
        reporting: false,
        delivery: .idle,
        screen: .on
    )

    #expect(presentation.headline == "STARTUP FAILED")
    #expect(presentation.menuBarSymbol == "exclamationmark.icloud.fill")
}

@Test func screenOffTakesPriorityOverDeliveryState() {
    let presentation = StatusPresentation.make(
        reporting: true,
        delivery: .failure,
        screen: .off
    )

    #expect(presentation.headline == "SCREEN OFF")
    #expect(presentation.headlineSymbol == "moon.fill")
    #expect(presentation.menuBarSymbol == "cloud.fill")
}

@Test func pausedStateUsesOutlineCloud() {
    let presentation = StatusPresentation.make(
        reporting: false,
        delivery: .success,
        screen: .on
    )

    #expect(presentation.headline == "PAUSED")
    #expect(presentation.menuBarSymbol == "cloud")
}

@Test func failedDeliveryUsesWarningCloud() {
    let presentation = StatusPresentation.make(
        reporting: true,
        delivery: .failure,
        screen: .on
    )

    #expect(presentation.headline == "FAILED")
    #expect(presentation.menuBarSymbol == "exclamationmark.icloud.fill")
}

@Test func sendingStateHasDedicatedPresentation() {
    let presentation = StatusPresentation.make(
        reporting: true,
        delivery: .sending,
        screen: .on
    )

    #expect(presentation.headline == "SENDING")
    #expect(presentation.headlineSymbol == "arrow.up")
}
