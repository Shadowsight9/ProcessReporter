# ProcessReporter

[![macOS](https://img.shields.io/badge/macOS-15%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org/)
[![Xcode](https://img.shields.io/badge/Xcode-15%2B-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

[English](readme.md)

ProcessReporter 是一个 macOS 菜单栏应用，用来记录当前活跃应用、窗口标题和系统媒体播放信息。记录会保存在本地；如果你愿意，也可以通过一条自己配置的 shell 命令发送到任意服务。

## 功能

- 记录当前聚焦的应用和窗口标题。
- 通过本地 Swift provider 读取系统正在播放的媒体信息。
- 使用 SwiftData 在本地保存活动历史。
- 通过用户可配置的 shell 命令发送报告。
- 支持应用过滤和名称映射，方便保护隐私。
- 以轻量菜单栏应用形式运行。

## 系统要求

- macOS 15.0 或更高版本。
- 本地开发需要 Xcode 15 或更高版本。
- 如果需要读取窗口标题，需要授予辅助功能权限。

媒体检测使用 Apple 的私有 `MediaRemote.framework`。这移除了之前对外部 `media-control` 命令的依赖，但它更适合作为本地工具使用，不适合作为 App Store 安全 API 方案。

## 安装

1. 从 Releases 下载最新版本。
2. 打开 `.dmg` 文件。
3. 将 ProcessReporter 拖入 Applications。
4. 启动 ProcessReporter。
5. 按提示在系统设置中授予辅助功能权限。

首次启动时，应用会打开偏好设置，方便你选择要记录的内容，以及是否启用 shell 上报。

## 配置

### 通用

在 Preferences -> General 中可以启用或暂停上报、设置上报间隔，并选择是否记录应用活动、媒体播放，或两者都记录。

### 过滤

在 Preferences -> Filters 中可以排除不想记录的应用。被过滤的应用不会被保存，也不会发送到 shell 命令。

### 映射

在 Preferences -> Mapping 中可以把应用名或 bundle identifier 映射成更友好的名字。适合隐藏敏感项目名，或者把嘈杂的窗口标题整理成稳定名称。

### Shell 集成

ProcessReporter 只有一个内置外部集成：Shell。

1. 打开 Preferences -> Integrations。
2. 启用 Shell。
3. 输入命令。
4. 设置超时时间。
5. 点击 Test，查看最近一次执行的退出码、stdout 和 stderr。

发送到 webhook 的例子：

```sh
curl -X POST "https://example.com/report" \
  -H "Content-Type: application/json" \
  -d "$PROCESS_REPORTER_JSON"
```

写入本地日志的例子：

```sh
mkdir -p /tmp/process-reporter-test
printf '%s\n' "$PROCESS_REPORTER_JSON" >> /tmp/process-reporter-test/reports.jsonl
```

命令会通过 `/bin/zsh -lc` 在本地运行，权限与当前应用进程一致。导入的 shell 命令不会自动启用，必须由用户手动开启。

## Shell 环境变量

每次 shell 上报都会收到以下环境变量。没有值的字段会传空字符串。

- `PROCESS_REPORTER_JSON`
- `PROCESS_REPORTER_PROCESS_NAME`
- `PROCESS_REPORTER_WINDOW_TITLE`
- `PROCESS_REPORTER_PROCESS_BUNDLE_ID`
- `PROCESS_REPORTER_MEDIA_NAME`
- `PROCESS_REPORTER_MEDIA_ARTIST`
- `PROCESS_REPORTER_MEDIA_ALBUM`
- `PROCESS_REPORTER_MEDIA_PROCESS_NAME`
- `PROCESS_REPORTER_MEDIA_PROCESS_BUNDLE_ID`
- `PROCESS_REPORTER_MEDIA_DURATION`
- `PROCESS_REPORTER_MEDIA_ELAPSED_TIME`
- `PROCESS_REPORTER_MEDIA_PLAYING`
- `PROCESS_REPORTER_TIMESTAMP`

`PROCESS_REPORTER_JSON` 的结构如下：

```json
{
  "timestamp": "2026-07-05T12:00:00.000Z",
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

## 隐私说明

ProcessReporter 不会截图，不会记录键盘输入，不会读取文件内容，也不会记录鼠标移动轨迹。它只会根据你的设置记录应用名、当前窗口标题和媒体元数据。

建议配置：

- 一开始先关闭 Shell，只查看本地历史。
- 过滤密码管理器、银行应用、隐私浏览器和敏感工作软件。
- 妥善保管 webhook 地址。
- 外部请求优先使用 HTTPS。
- 只运行你理解并信任的 shell 命令。

## 常见问题

### 读不到窗口标题

打开 System Settings -> Privacy & Security -> Accessibility，确认 ProcessReporter 已启用。修改权限后建议重启应用。

### Shell 命令失败

在 Preferences -> Integrations 中点击 Test，查看退出码、stdout 和 stderr。如果命令在 Terminal 中能运行，但在应用里失败，优先使用工具的绝对路径，或者在命令里初始化需要的环境变量。

### 菜单栏图标不见了

先在 Activity Monitor 中确认 ProcessReporter 是否还在运行。如果应用仍在运行但图标不可见，重启应用，并检查 macOS 菜单栏设置。

### 内存占用偏高

可以清理历史记录、降低上报频率，并避免 shell 命令输出大量 stdout/stderr。

## 开发

打开工程：

```sh
open ProcessReporter.xcodeproj
```

命令行构建：

```sh
xcodebuild -project ProcessReporter.xcodeproj -scheme ProcessReporter -configuration Debug build
```

当前依赖：

- SnapKit：AppKit 布局辅助。
- RxSwift/RxCocoa：现有偏好设置和 UI 绑定。

Alamofire、Discord Game SDK、S3 helper 和服务专用集成已经移除。新的外部上报需求应优先通过 `ShellReporterExtension` 完成，而不是新增内置服务 SDK。

常用入口：

- `ProcessReporter/Core/Reporter/Reporter.swift`
- `ProcessReporter/Core/Reporter/Reporter+Shell.swift`
- `ProcessReporter/Core/MediaInfoManager/MediaInfoManager.swift`
- `ProcessReporter/Core/MediaInfoManager/LocalMediaInfoProvider.swift`
- `ProcessReporter/Preferences/Views/PreferencesIntegrationShellView.swift`
- `ProcessReporter/Core/Database/DataStore.swift`

## License

2025 © Innei, released under the MIT License.

[Personal Website](https://innei.in/) · GitHub [@Innei](https://github.com/innei/)
