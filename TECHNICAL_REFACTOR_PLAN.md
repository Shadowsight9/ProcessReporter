# ProcessReporter Refactor Plan

This document records the planned refactor for two areas:

1. Replace the external media playback dependency with an in-app Swift implementation.
2. Replace built-in service integrations with a user-configurable shell command integration.

The goal is to make ProcessReporter simpler, more personal-tool friendly, and easier to extend without changing Swift code for every external service.

## Current State

### Media Playback

Media playback is currently routed through `MediaInfoManager`.

On macOS 15.4 and later, `MediaInfoManager` uses `CLIMediaInfoProvider`, which calls the external `media-control` command. On older systems it uses `LegacyMediaInfoProvider`, which loads Apple's private `MediaRemote.framework`.

Related files:

- `ProcessReporter/Core/MediaInfoManager/MediaInfoManager.swift`
- `ProcessReporter/Core/MediaInfoManager/CLIMediaInfoProvider.swift`
- `ProcessReporter/Core/MediaInfoManager/LegacyMediaInfoProvider.swift`
- `ProcessReporter/Core/Utilities/MediaControlInstallationHelper.swift`
- `ProcessReporter/AppDelegate.swift`

### Integrations

The app currently has dedicated reporter extensions for several services:

- MixSpace
- S3
- Slack
- Discord

These are registered directly by `Reporter.initializeExtensions()`. Each integration has its own preferences model and UI.

Related files:

- `ProcessReporter/Core/Reporter/Reporter.swift`
- `ProcessReporter/Core/Reporter/Reporter+MixSpace.swift`
- `ProcessReporter/Core/Reporter/Reporter+S3.swift`
- `ProcessReporter/Core/Reporter/Reporter+Slack.swift`
- `ProcessReporter/Core/Reporter/Reporter+Discord.swift`
- `ProcessReporter/Preferences/DataModels/PreferencesDataModel+Integration.swift`
- `ProcessReporter/Preferences/Controllers/PreferencesIntegrationViewController.swift`
- `ProcessReporter/Preferences/Views/PreferencesIntegrationMixSpaceView.swift`
- `ProcessReporter/Preferences/Views/PreferencesIntegrationS3View.swift`
- `ProcessReporter/Preferences/Views/PreferencesIntegrationSlackView.swift`
- `ProcessReporter/Preferences/Views/PreferencesIntegrationDiscordView.swift`

## Target Design

### Media Playback

Use a local Swift provider as the only media provider.

The first practical version should reuse the existing `LegacyMediaInfoProvider` approach and rename or reshape it into a clearer local provider, for example:

- `LocalMediaInfoProvider`

This provider will continue to use `MediaRemote.framework`, because macOS does not provide a complete public Swift API for system-wide now-playing metadata across all apps.

Important tradeoff:

- This removes the external `media-control` dependency.
- It still depends on a private Apple framework.
- It is suitable for local use and learning.
- It should not be considered App Store-safe.

### Shell Command Integration

Replace all built-in service-specific integrations with one integration:

- `ShellReporterExtension`

The user configures a shell command in preferences. Every report executes that command with the current report data exposed through environment variables.

Example user command:

```sh
curl -X POST "https://example.com/report" \
  -H "Content-Type: application/json" \
  -d "$PROCESS_REPORTER_JSON"
```

The command should run through:

```text
/bin/zsh -lc "<configured command>"
```

The app should not try to parse service-specific APIs. Users can compose `curl`, local scripts, Python, Node.js, or any other local command themselves.

## Shell Integration Contract

### Preferences Model

Add a new preferences model:

```swift
struct ShellIntegration: UserDefaultsJSONStorable, DictionaryConvertible {
    var isEnabled: Bool = false
    var command: String = ""
    var timeoutSeconds: Int = 10
}
```

Optional future fields:

- `workingDirectory`
- `sendOnlyWhenChanged`
- `includeArtwork`
- `lastExitCode`
- `lastStdout`
- `lastStderr`

### Environment Variables

Each shell command invocation should receive a stable set of environment variables.

Process fields:

- `PROCESS_REPORTER_PROCESS_NAME`
- `PROCESS_REPORTER_WINDOW_TITLE`
- `PROCESS_REPORTER_PROCESS_BUNDLE_ID`

Media fields:

- `PROCESS_REPORTER_MEDIA_NAME`
- `PROCESS_REPORTER_MEDIA_ARTIST`
- `PROCESS_REPORTER_MEDIA_ALBUM`
- `PROCESS_REPORTER_MEDIA_PROCESS_NAME`
- `PROCESS_REPORTER_MEDIA_PROCESS_BUNDLE_ID`
- `PROCESS_REPORTER_MEDIA_DURATION`
- `PROCESS_REPORTER_MEDIA_ELAPSED_TIME`
- `PROCESS_REPORTER_MEDIA_PLAYING`

General fields:

- `PROCESS_REPORTER_TIMESTAMP`
- `PROCESS_REPORTER_JSON`

Empty values should be passed as empty strings, not omitted. This keeps shell scripts simple and predictable.

### JSON Payload

`PROCESS_REPORTER_JSON` should contain one compact JSON object.

Suggested shape:

```json
{
  "timestamp": "2026-07-05T12:00:00Z",
  "process": {
    "name": "Code",
    "windowTitle": "ProcessReporter",
    "bundleIdentifier": "com.microsoft.VSCode"
  },
  "media": {
    "name": "Song Title",
    "artist": "Artist",
    "album": "Album",
    "processName": "Music",
    "bundleIdentifier": "com.apple.Music",
    "duration": 240,
    "elapsedTime": 42,
    "playing": true
  }
}
```

The JSON should be built with `JSONEncoder` or `JSONSerialization`, not by string concatenation.

### Execution Rules

The shell integration should:

- Do nothing when disabled.
- Return an ignored result when the command is empty.
- Run off the main thread.
- Enforce a timeout.
- Capture stdout and stderr for debugging.
- Treat exit status `0` as success.
- Treat non-zero exit status as failure.
- Avoid blocking other integrations or the main app loop.

Since this refactor removes the other integrations, the shell integration will normally be the only reporter extension.

### Security Notes

This feature intentionally allows the user to execute local commands.

Required behavior:

- Default disabled.
- Never execute imported configuration automatically until the user enables it.
- Store command text as a preference.
- Show clear UI copy that the command runs locally with the user's permissions.

The current app has App Sandbox disabled, so shell execution is technically possible. That also means commands can access user files according to the app process permissions.

## Implementation Steps

### Phase 1: Shell Integration

1. Add `ShellIntegration` to `PreferencesDataModel+Integration.swift`.
2. Add import/export support in `PreferencesDataModel.swift`.
3. Add `Reporter+Shell.swift`.
4. Change `Reporter.initializeExtensions()` to register only `ShellReporterExtension`.
5. Change integration preferences UI to show only Shell settings.
6. Remove or stop referencing MixSpace, S3, Slack, and Discord integration UI from the preferences sidebar.
7. Keep old integration files temporarily if needed, but ensure they are no longer registered or reachable.
8. Build and verify that one report can trigger a configured shell command.

### Phase 2: Local Media Provider

1. Replace provider selection in `MediaInfoManager` with a local provider.
2. Rename or duplicate `LegacyMediaInfoProvider` into `LocalMediaInfoProvider`.
3. Remove `CLIMediaInfoProvider` usage.
4. Remove the media-control install prompt from `AppDelegate`.
5. Remove or retire `MediaControlInstallationHelper`.
6. Simplify `MediaInfoManager` logic that only exists to protect against blocking CLI calls.
7. Build and verify media state changes still produce `MediaInfo`.

### Phase 3: Cleanup

1. Remove unused assets for old integrations if no longer needed.
2. Remove unused helper code such as `S3Uploader` if no other feature references it.
3. Update user-facing docs that mention MixSpace, S3, Slack, Discord, or media-control.
4. Run a clean build.

## Validation Plan

### Build

Run:

```sh
xcodebuild -project ProcessReporter.xcodeproj -scheme ProcessReporter -configuration Debug build
```

### Shell Integration Checks

Use a local test command:

```sh
mkdir -p /tmp/process-reporter-test
printf '%s\n' "$PROCESS_REPORTER_JSON" >> /tmp/process-reporter-test/reports.jsonl
```

Expected result:

- A report creates or appends to `/tmp/process-reporter-test/reports.jsonl`.
- The JSON contains process data when an app/window is focused.
- The JSON contains media data when media is playing.
- The app remains responsive if the command exits slowly or fails.

Failure test:

```sh
exit 42
```

Expected result:

- The reporter marks the integration as failed.
- The app does not crash.

Timeout test:

```sh
sleep 30
```

Expected result:

- The command is terminated after the configured timeout.
- The app does not block the menu bar UI.

### Media Checks

Test with Apple Music, Spotify, or browser media playback.

Expected result:

- Media title and artist update while playback changes.
- Paused or unavailable media does not produce incorrect active playback reports.
- Focused app reporting continues to work even when no media is playing.

## Open Questions

1. Should shell commands run for every report, or only when the report contains at least one enabled data type?
2. Should old integration preferences be migrated, ignored, or removed immediately?
3. Should stdout/stderr be exposed in the preferences UI for debugging?
4. Should the shell command receive artwork data, or should artwork be omitted to keep environment payloads small?
5. Should the command run through `/bin/zsh`, the user's `$SHELL`, or a configurable shell path?

## Recommendation

Start with Phase 1.

The shell integration gives the biggest simplification and creates a flexible replacement for all current service-specific integrations. After that is working, the media provider cleanup can be done with less risk because the reporting output path will already be simpler.
