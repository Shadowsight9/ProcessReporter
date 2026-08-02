import Testing
@testable import ProcessReporterCoreChecks

@Test func vibeCodingModePreventsSystemSleepWithoutHoldingTheDisplayOn() {
    let configuration = KeepAwakeConfiguration.vibeCoding

    #expect(configuration.assertionTypes.contains("PreventUserIdleSystemSleep"))
    #expect(configuration.assertionTypes.contains("PreventSystemSleep"))
    #expect(!configuration.assertionTypes.contains("PreventUserIdleDisplaySleep"))
    #expect(configuration.allowsDisplaySleep)
    #expect(KeepAwakeConfiguration.displaySleepExecutable == "/usr/bin/pmset")
    #expect(KeepAwakeConfiguration.displaySleepArguments == ["displaysleepnow"])
}
