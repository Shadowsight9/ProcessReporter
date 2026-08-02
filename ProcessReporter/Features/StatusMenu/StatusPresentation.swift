import Foundation

enum StatusDeliveryKind: Equatable {
    case idle
    case sending
    case success
    case partialFailure
    case failure
}

enum StatusScreenKind: Equatable {
    case on
    case off
}

enum StatusLaunchKind: Equatable {
    case starting
    case ready
    case failed
}

struct StatusPresentation: Equatable {
    var headline: String
    var headlineSymbol: String
    var menuBarSymbol: String

    static func make(
        launch: StatusLaunchKind = .ready,
        reporting: Bool,
        delivery: StatusDeliveryKind,
        screen: StatusScreenKind
    ) -> StatusPresentation {
        switch launch {
        case .starting:
            return StatusPresentation(
                headline: "STARTING",
                headlineSymbol: "hourglass",
                menuBarSymbol: "cloud"
            )
        case .failed:
            return StatusPresentation(
                headline: "STARTUP FAILED",
                headlineSymbol: "exclamationmark.triangle.fill",
                menuBarSymbol: "exclamationmark.icloud.fill"
            )
        case .ready:
            break
        }

        if screen == .off {
            return StatusPresentation(
                headline: "SCREEN OFF",
                headlineSymbol: "moon.fill",
                menuBarSymbol: reporting ? "cloud.fill" : "cloud"
            )
        }

        guard reporting else {
            return StatusPresentation(
                headline: "PAUSED",
                headlineSymbol: "pause.fill",
                menuBarSymbol: "cloud"
            )
        }

        switch delivery {
        case .sending:
            return StatusPresentation(
                headline: "SENDING",
                headlineSymbol: "arrow.up",
                menuBarSymbol: "cloud.fill"
            )
        case .partialFailure:
            return StatusPresentation(
                headline: "PARTIAL",
                headlineSymbol: "exclamationmark",
                menuBarSymbol: "cloud.fill"
            )
        case .failure:
            return StatusPresentation(
                headline: "FAILED",
                headlineSymbol: "exclamationmark",
                menuBarSymbol: "exclamationmark.icloud.fill"
            )
        case .idle, .success:
            return StatusPresentation(
                headline: "REPORTING",
                headlineSymbol: "circle.fill",
                menuBarSymbol: "cloud.fill"
            )
        }
    }
}
