# ProcessReporter

> Fork version maintained by Shadowsight9. This fork focuses on a cleaner modern SwiftUI/macOS codebase, shell-command based reporting, and removal of legacy service-specific integrations from the upstream project.

[![macOS](https://img.shields.io/badge/macOS-15%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org/)
[![Xcode](https://img.shields.io/badge/Xcode-15%2B-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

[中文文档](README.zh-CN.md)

ProcessReporter is a macOS menu bar app for recording focused applications, active window titles, and system media playback. Reports are stored locally and can optionally be sent to a shell command that you control.

## Features

- Tracks focused applications and window titles.
- Reads system now-playing metadata through a local Swift provider.
- Stores activity history locally with SwiftData.
- Sends reports through one of four configurable shell command slots.
- Supports application filters and mapping rules for privacy-friendly reporting.
- Runs as a lightweight menu bar utility.

## Requirements

- macOS 15.0 or later.
- Xcode 15 or later for local development.
- Accessibility permission when you want window titles.

Media tracking uses Apple's private `MediaRemote.framework`. This removes the previous external `media-control` dependency, but it is intended for local tooling rather than App Store distribution.

## Installation

1. Download the latest release from the Releases page.
2. Open the `.dmg` file.
3. Drag ProcessReporter into Applications.
4. Launch ProcessReporter.
5. Enable Accessibility permission in System Settings when prompted.

On first launch, the app opens Preferences so you can choose what to track and whether to enable shell reporting.

## Configuration

### General

Use Preferences -> General to enable or pause reporting, choose a reporting interval, and select whether process activity, media playback, or both should be included.

### Filters

Use Preferences -> Filters to exclude applications from process or media reporting. Filtered applications are skipped before reports are saved or sent.

### Mapping

Use Preferences -> Mapping to rename app names or bundle identifiers before a report is stored or sent. This is useful when raw app names are too noisy or too sensitive.

### Shell Integration

ProcessReporter has one built-in external integration: Shell.

1. Open Preferences -> Integrations.
2. Enable Shell.
3. Pick a command slot and enter a command.
4. Set a timeout.
5. Use Test to inspect the latest exit code, stdout, and stderr.

Example webhook command:

```sh
curl -X POST "https://example.com/report" \
  -H "Content-Type: application/json" \
  -d "$PROCESS_REPORTER_JSON"
```

Example local log command:

```sh
mkdir -p /tmp/process-reporter-test
printf '%s\n' "$PROCESS_REPORTER_JSON" >> /tmp/process-reporter-test/reports.jsonl
```

The selected command slot runs locally through `/bin/zsh -lc` with the app user's permissions. Imported shell commands are forced disabled until you explicitly enable them.

## Shell Environment

Every shell report receives these environment variables. Missing values are passed as empty strings.

- `PROCESS_REPORTER_JSON`
- `PROCESS_REPORTER_PROCESS_NAME`
- `PROCESS_REPORTER_PROCESS_DESCRIPTION`
- `PROCESS_REPORTER_PROCESS_USAGE_DURATION`
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
- `PROCESS_REPORTER_TIMESTAMP`

`PROCESS_REPORTER_JSON` has this shape:

```json
{
  "timestamp": "2026-07-05T12:00:00.000Z",
  "process": {
    "name": "Code",
    "description": "Writing code",
    "windowTitle": "ProcessReporter",
    "bundleIdentifier": "com.microsoft.VSCode"
  },
  "media": {
    "name": "Song Title",
    "artist": "Artist",
    "album": "Album",
    "processName": "Music",
    "processDescription": "Listening to music",
    "bundleIdentifier": "com.apple.Music",
    "duration": 240,
    "elapsedTime": 42,
    "playing": true
  },
  "foregroundUsage": {
    "date": "2026-07-05",
    "apps": [
      {
        "bundleIdentifier": "com.microsoft.VSCode",
        "name": "Code",
        "description": "Writing code",
        "duration": 3600
      }
    ],
    "totalDuration": 3600,
    "currentBundleIdentifier": "com.microsoft.VSCode"
  }
}
```

## Privacy Notes

ProcessReporter does not capture screenshots, record keystrokes, inspect file contents, or track mouse movement paths. It records app names, focused window titles, and media metadata according to your preferences.

Recommended setup:

- Start with Shell disabled and inspect local history first.
- Filter password managers, banking apps, private browsers, and sensitive work tools.
- Keep webhook URLs private.
- Prefer HTTPS endpoints.
- Only run shell commands you understand and trust.

## Troubleshooting

### Window Titles Are Missing

Open System Settings -> Privacy & Security -> Accessibility and make sure ProcessReporter is enabled. Restart the app after changing the permission.

### Shell Command Fails

Use the Test button in Preferences -> Integrations. Check the exit code, stdout, and stderr. If a command works in Terminal but not in the app, use absolute paths for tools or initialize your environment inside the command.

### Menu Bar Icon Is Missing

Check Activity Monitor to see whether ProcessReporter is running. If it is running but the icon is hidden, restart the app and check macOS menu bar settings.

### High Memory Usage

Clear old history from Preferences -> History, reduce the report frequency, and avoid shell commands that emit very large stdout/stderr output.

## Development

Open the project:

```sh
open ProcessReporter.xcodeproj
```

Build from the command line:

```sh
xcodebuild -project ProcessReporter.xcodeproj -scheme ProcessReporter -configuration Debug build
```

Current dependencies:

- No third-party Swift packages are required.

Alamofire, Discord Game SDK, S3 helpers, and service-specific integrations have been removed. New external reporting should go through `ShellReporterExtension`, not a new built-in service SDK.

Useful entry points:

- `ProcessReporter/App/ProcessReporterApp.swift`
- `ProcessReporter/Features/Reporting/Reporter.swift`
- `ProcessReporter/Features/Reporting/Reporter+Shell.swift`
- `ProcessReporter/Features/StatusMenu/StatusMenuView.swift`
- `ProcessReporter/Features/StatusMenu/StatusMenuStore.swift`
- `ProcessReporter/Features/Settings/PreferencesStore.swift`
- `ProcessReporter/Features/Settings/SettingsRootView.swift`
- `ProcessReporter/Features/Media/MediaInfoManager.swift`
- `ProcessReporter/Features/Media/LocalMediaInfoProvider.swift`
- `ProcessReporter/Features/History/DataStore.swift`

## License

2025 © Innei, released under the MIT License.

[Personal Website](https://innei.in/) · GitHub [@Innei](https://github.com/innei/)
