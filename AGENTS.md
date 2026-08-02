# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

Statusa (the Xcode project is still named ProcessReporter) is a macOS 15+ menu bar app that observes the focused application, optional window title, foreground duration, and system now-playing metadata. Reports are stored locally with SwiftData and can be sent through user-configured shell commands.

The repository intentionally uses Apple-first technologies and has no third-party Swift package dependencies.

## Build and Development Commands

```bash
# Open in Xcode
open ProcessReporter.xcodeproj

# Preferred local verification: Swift tests + unsigned Debug build
scripts/check.sh

# Fast pure-logic tests
swift test

# App-only command line build
xcodebuild \
  -project ProcessReporter.xcodeproj \
  -scheme ProcessReporter \
  -configuration Debug \
  -derivedDataPath .build/xcode-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Requirements:

- macOS 15+
- Xcode 16.2+ (the project file was last upgraded with Xcode 16.2)
- Accessibility permission for window titles

## Current Architecture

### App lifecycle (`ProcessReporter/App/`)

- `ProcessReporterApp.swift`: SwiftUI `App`, `MenuBarExtra`, app commands.
- `AppModel.swift`: observable startup state and ownership of `Reporter`.
- `AppDelegate.swift`: AppKit lifecycle plus sleep, wake, and screen notifications.
- `SettingsWindowPresenter.swift`: explicit AppKit settings-window presentation.

### Status UI (`ProcessReporter/Features/StatusMenu/`)

- `StatusMenuView.swift`: SwiftUI menu bar panel.
- `StatusMenuStore.swift`: `@Observable` UI state and user actions.
- `StatusPresentation.swift`: pure status-to-symbol/text mapping; covered by Swift Testing.

### Monitoring and media

- `ApplicationMonitor.swift`: focused app/window observation and Accessibility handling.
- `ForegroundUsageTracker.swift`: per-app duration tracking.
- `MediaInfoManager.swift`: media cache, monitoring, and async fetch coordination.
- `SystemNowPlayingProvider.swift`: private MediaRemote-backed implementation.

### Power (`ProcessReporter/Features/Power/`)

- `KeepAwakeController.swift`: IOKit system-sleep assertions and immediate display sleep.
- `KeepAwakeConfiguration.swift`: pure, tested assertion/command configuration.
- This implementation adapts an MIT-licensed approach; preserve `THIRD_PARTY_NOTICES.md`.

### Reporting (`ProcessReporter/Features/Reporting/`)

- `Reporter.swift`: main orchestration, filtering, mapping, deduplication, timer, and delivery.
- `ReportSnapshot.swift`: Sendable value crossing reporting/concurrency boundaries.
- `Reporter+Shell.swift`: shell integration, environment payload, timeout, serial execution.
- `Reporter+Types.swift`: report types and extension protocol.

### Persistence and settings

- `DataStore.swift`: actor and sole intended gateway to SwiftData for application features.
- `Database.swift`: ModelContainer setup and background contexts.
- `PreferencesStore.swift`: Observation-based UI facade.
- `PreferencesDataModel+*.swift`: UserDefaults-backed preference definitions.
- `UserDefaultsRelay.swift`: small in-house observable persistence primitive.

## Design Rules

1. Keep SwiftUI views declarative; move state and actions into observable stores/models.
2. UI-facing mutable state belongs on `@MainActor`.
3. Use actors for shared asynchronous mutable state.
4. Pass value types such as `ReportSnapshot` across concurrency boundaries.
5. Keep SwiftData access behind `DataStore`; do not leak persistent models into new views/services.
6. Put pure display/parsing rules in small files that the Swift package test target can compile.
7. Prefer incremental modernization over broad rewrites, especially around media and Accessibility APIs.
8. Shell commands run with the user's permissions; preserve privacy and never enable imported commands automatically.

## Tests

`Package.swift` defines a lightweight testable core target rather than attempting to compile the full AppKit app as a Swift package. When adding a pure helper:

1. Add its source path to the target's `sources` list.
2. Exclude surrounding app-only files as needed.
3. Add tests under `Tests/ProcessReporterCoreChecksTests/` using Swift Testing (`import Testing`, `@Test`, `#expect`).
4. Run both `swift test` and the Xcode build, preferably through `scripts/check.sh`.

## Good Beginner Changes

- Status text/symbol behavior plus tests.
- Pure mapping, formatting, and payload helpers.
- Small SwiftUI layout improvements.
- History UI that continues to use `DataStore`.

High-risk areas to change only with focused verification:

- `SystemNowPlayingProvider.swift` and private media APIs.
- Accessibility permission behavior.
- SwiftData migration/recovery logic.
- Shell process termination and timeout handling.
- Enabling Swift 6 language mode across the whole app.

See `docs/LEARNING_GUIDE.zh-CN.md` for the recommended learning order.
