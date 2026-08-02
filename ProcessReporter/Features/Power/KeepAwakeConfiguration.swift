import Foundation

/// Pure configuration kept separate from IOKit so the intended assertion set
/// is easy to review and test.
struct KeepAwakeConfiguration: Equatable {
    let assertionTypes: [String]
    let allowsDisplaySleep: Bool

    static let displaySleepExecutable = "/usr/bin/pmset"
    static let displaySleepArguments = ["displaysleepnow"]

    static let vibeCoding = KeepAwakeConfiguration(
        assertionTypes: [
            "PreventUserIdleSystemSleep",
            "PreventSystemSleep",
        ],
        allowsDisplaySleep: true
    )
}
