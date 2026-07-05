# ProcessReporter Architecture

ProcessReporter is a macOS menu bar utility that records focused app/window activity and system media playback. It stores reports locally and can forward each report to one selected user-configured shell command slot.

The current design deliberately removes service-specific SDK integrations. The app owns activity collection, persistence, filtering, mapping, and shell payload generation; users own service delivery through scripts or commands.

## Runtime Flow

1. `ApplicationMonitor` observes focused app and window changes through `NSWorkspace`, Accessibility APIs, and mouse/focus events.
2. `MediaInfoManager` reads system now-playing metadata through `LocalMediaInfoProvider`.
3. `Reporter` merges focused window data and media data into `ReportModel`.
4. `Reporter` applies filters and mapping rules from `PreferencesDataModel`.
5. `Reporter` persists the report through `DataStore`.
6. `ShellReporterExtension` exports the report as environment variables and executes the selected command slot.
7. `ReporterStatusBridge` updates `StatusMenuStore`, which drives the SwiftUI `MenuBarExtra`.

## Main Components

- `ProcessReporter/App/ProcessReporterApp.swift`: SwiftUI app entry, `MenuBarExtra`, and Settings scene.
- `ProcessReporter/App/AppDelegate.swift`: AppKit lifecycle hooks and sleep/wake handling.
- `ProcessReporter/App/SettingsWindowPresenter.swift`: lightweight settings window presenter for menu bar and first-launch flows.
- `ProcessReporter/Features/StatusMenu/`: menu bar UI, menu state, and reporter-to-menu bridge.
- `ProcessReporter/Features/Settings/`: SwiftUI settings pages and `PreferencesStore`.
- `ProcessReporter/Features/Settings/Persistence/`: persisted preference models and local `UserDefaultsRelay`.
- `ProcessReporter/Features/Reporting/`: report lifecycle, timers, filters, mapping, persistence, extension dispatch, and shell execution.
- `ProcessReporter/Features/Monitoring/`: focused app/window title tracking.
- `ProcessReporter/Features/Media/`: media facade, latest media cache, serialized async fetches, and local MediaRemote-backed provider.
- `ProcessReporter/Features/History/`: SwiftData container, actor-isolated value API, and report/icon models.
- `ProcessReporter/Shared/Components/`: shared UI helpers such as toast feedback.
- `ProcessReporter/Shared/Utilities/`: shared system helpers such as app lookup, rate limiting, and network checks.
- `ProcessReporter/Shared/Extensions/`: small standard-library/AppKit extensions.

## Shell Contract

The selected configured command slot is executed as:

The command runs through the user's `$SHELL -lc` when possible, with `/bin/zsh` as fallback.

The command receives the current process environment plus the following variables:

- `PROCESS_REPORTER_JSON`
- `PROCESS_REPORTER_PROCESS_NAME`
- `PROCESS_REPORTER_PROCESS_DESCRIPTION`
- `PROCESS_REPORTER_PROCESS_DAILY_FOREGROUND_DURATION`
- `PROCESS_REPORTER_WINDOW_TITLE`
- `PROCESS_REPORTER_PROCESS_BUNDLE_ID`
- `PROCESS_REPORTER_MEDIA_NAME`
- `PROCESS_REPORTER_MEDIA_ARTIST`
- `PROCESS_REPORTER_MEDIA_ALBUM`
- `PROCESS_REPORTER_MEDIA_PROCESS_NAME`
- `PROCESS_REPORTER_MEDIA_PROCESS_DESCRIPTION`
- `PROCESS_REPORTER_MEDIA_PROCESS_BUNDLE_ID`
- `PROCESS_REPORTER_MEDIA_DURATION`
- `PROCESS_REPORTER_MEDIA_ELAPSED_TIME`
- `PROCESS_REPORTER_MEDIA_PLAYING`
- `PROCESS_REPORTER_FOREGROUND_USAGE_JSON`
- `PROCESS_REPORTER_TIMESTAMP`

Empty values are passed as empty strings. `PROCESS_REPORTER_JSON` is encoded with `JSONEncoder`; command strings should never be assembled by interpolating JSON manually in Swift.

Shell execution rules:

- Shell integration is disabled by default.
- Imported shell settings are forced disabled until the user enables them.
- Empty commands are ignored.
- Reports with neither process nor media data are ignored.
- Commands run off the main thread.
- Commands have a configurable timeout.
- On timeout, the app terminates the shell process.
- stdout/stderr are captured before being stored in preferences.

## Media Provider

`LocalMediaInfoProvider` loads `/System/Library/PrivateFrameworks/MediaRemote.framework` at runtime and resolves required symbols dynamically. Function pointers must be guarded because private framework symbols can change between macOS versions.

Media fetches are serialized through `MediaInfoFetchActor`. The provider itself also uses a timeout around MediaRemote callbacks so a missing callback cannot permanently block future media reads.

This approach removes the previous external `media-control` dependency. The tradeoff is that MediaRemote is private Apple API and should be treated as a local-tooling implementation detail, not an App Store-safe API contract.

## Persistence

Reports and icon metadata are stored with SwiftData. Feature code should pass value types to `DataStore`; it should not share `ModelContext` or SwiftData models across feature boundaries.

Current persistence rule:

- `Reporter` creates `ReportModel` for the active report.
- `Reporter.send(data:)` converts it to `ReportValue`.
- `DataStore` performs the actor-isolated save.

Future database changes should prefer explicit migration stages or a user-visible backup/restore path over silent data deletion.

## Preferences

Settings are presented with SwiftUI. `PreferencesStore` is the view-facing boundary for settings screens. The lower-level `PreferencesDataModel` and local `UserDefaultsRelay` remain in `Features/Settings/Persistence` and provide typed `value`/`accept`/subscription behavior without RxSwift.

Important safety rule:

- Importing preferences may copy shell command slots and debug output, but must force `shellIntegration.isEnabled = false`.

## Concurrency

- SwiftUI views, UI stores, and `Reporter` are main-actor oriented.
- Database work is routed through actor-isolated `DataStore`/`Database` APIs.
- Shell commands run in detached utility tasks.
- Media fetches are serialized through `MediaInfoFetchActor`.
- Media playback notifications are debounced before invoking the reporting path.

## Development

Open the project:

```sh
open ProcessReporter.xcodeproj
```

Build:

```sh
xcodebuild -project ProcessReporter.xcodeproj -scheme ProcessReporter -configuration Debug build
```

Current dependencies:

- No third-party Swift packages are required.

When changing behavior:

- Reporting changes start in `Features/Reporting/Reporter.swift`.
- Shell behavior changes start in `Features/Reporting/Reporter+Shell.swift`.
- Media behavior changes start in `Features/Media/MediaInfoManager.swift` and `Features/Media/LocalMediaInfoProvider.swift`.
- Preference UI changes start in `Features/Settings/PreferencesStore.swift` and the relevant SwiftUI view.
- Preference persistence changes start in `Features/Settings/Persistence/PreferencesDataModel.swift`.
- Avoid adding new service-specific integrations unless the shell contract cannot reasonably express the use case.

## Security Notes

- Accessibility permission is required for window titles.
- Shell execution intentionally runs local commands with the app user's permissions.
- Shell commands should be treated as trusted local code.
- The app does not capture screenshots, record keystrokes, inspect file contents, or track mouse movement paths.
- Media tracking uses private Apple API.
