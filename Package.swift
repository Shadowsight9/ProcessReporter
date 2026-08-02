// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProcessReporterCoreChecks",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ProcessReporterCoreChecks", targets: ["ProcessReporterCoreChecks"]),
    ],
    targets: [
        .target(
            name: "ProcessReporterCoreChecks",
            path: "ProcessReporter/Features",
            exclude: [
                "History",
                "Media",
                "Monitoring",
                "Power/KeepAwakeController.swift",
                "Reporting/ReportSnapshot.swift",
                "Reporting/Reporter.swift",
                "Reporting/Reporter+Shell.swift",
                "Reporting/Reporter+Types.swift",
                "Settings/AppPickerView.swift",
                "Settings/GeneralSettingsView.swift",
                "Settings/HistorySettingsView.swift",
                "Settings/MappingSettingsView.swift",
                "Settings/PreferencesFilterView.swift",
                "Settings/PreferencesStore.swift",
                "Settings/SendInterval.swift",
                "Settings/SettingsRootView.swift",
                "Settings/ShellIntegrationSettingsView.swift",
                "Settings/Persistence/PreferencesDataModel.swift",
                "Settings/Persistence/PreferencesDataModel+Filter.swift",
                "Settings/Persistence/PreferencesDataModel+General.swift",
                "Settings/Persistence/PreferencesDataModel+Integration.swift",
                "Settings/Persistence/PreferencesDataModel+Mapping.swift",
                "Settings/Persistence/UserDefaultsRelay.swift",
                "StatusMenu/StatusMenuStore.swift",
                "StatusMenu/StatusMenuView.swift",
            ],
            sources: [
                "Power/KeepAwakeConfiguration.swift",
                "Reporting/ReportFingerprint.swift",
                "Settings/Persistence/MappingDictionaryParser.swift",
                "StatusMenu/StatusPresentation.swift",
            ]
        ),
        .testTarget(
            name: "ProcessReporterCoreChecksTests",
            dependencies: ["ProcessReporterCoreChecks"],
            path: "Tests/ProcessReporterCoreChecksTests"
        ),
    ]
)
