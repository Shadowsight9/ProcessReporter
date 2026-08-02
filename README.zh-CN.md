# Statusa

<p align="center">
  <img src="ProcessReporter/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" alt="Statusa icon" width="144">
</p>

> 你的菜单栏状态娘。她会把“我现在在干嘛”收拾成一条可保存、可映射、可发布的小状态。

[![macOS](https://img.shields.io/badge/macOS-15%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org/)
[![Xcode](https://img.shields.io/badge/Xcode-15%2B-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

[English](readme.md)

Statusa 会记录当前聚焦应用、窗口标题、前台使用时长和系统正在播放的音乐。你可以把她当本地活动日志，也可以让她把你的当前状态递到个人主页、聊天机器人、直播 overlay、badge 或任意 webhook。

比如：

- `正在使用 Chrome 网上冲浪`
- `正在玩 Baldur's Gate 3，BGM: Song Title - Artist`
- `正在用 Xcode 写代码，已使用 1.25 小时`
- `正在看视频，大概是在学习`

## 为什么

很多在线状态只能告诉别人“我在线”。Statusa 可以更具体一点：你是在网上冲浪、写代码、打游戏、看剧、听歌，还是在做一些只有窗口标题知道的事。她不抢戏，只在菜单栏里安静地举起一张“当前状态”小牌牌。

适合用来：

- 在个人主页展示自己的网上冲浪、游戏、编码、听歌状态。
- 把活动状态推送到聊天机器人、仪表盘或 webhook。
- 保存一份本地应用使用时间线。
- 把原始应用名映射成更适合公开展示的文案。
- 在保存或发送前过滤敏感应用。

## 功能

- 轻量菜单栏应用，可爱但不吵。
- 记录聚焦应用、窗口标题和前台使用时长。
- 本地读取系统正在播放的媒体信息。
- 用 SwiftData 保存本地历史。
- 通过可配置 shell 命令上报。
- 支持过滤和映射，适合做隐私友好的公开状态。

## 系统要求

- macOS 15.0 或更高版本。
- 读取窗口标题需要辅助功能权限。
- 本地开发需要 Xcode 15 或更高版本。

媒体检测使用 Apple 私有 `MediaRemote.framework`。它适合本地工具，不是 App Store 安全 API 方案。

## 安装

1. 从 Releases 下载最新版本。
2. 打开 `.dmg`。
3. 将 Statusa 拖入 Applications。
4. 启动应用。
5. 按提示授予辅助功能权限。

首次启动会打开偏好设置，方便你选择要记录什么。

Release 使用 ad-hoc 签名，没有 Apple 公证，所以 macOS 可能会提示“Apple 无法验证”。首次打开可以：

- 在 Applications 中右键 Statusa，选择打开。
- 或运行：

```sh
xattr -dr com.apple.quarantine /Applications/Statusa.app
```

## 配置

- General：启用上报、设置间隔、选择应用/媒体数据。
- Filters：排除不想保存或发送的应用。
- Mapping：把应用名或 bundle ID 映射成更友好的描述。
- Integrations：用 shell 命令处理最新报告。

Mapping 是好玩的地方。你可以把 `Google Chrome` 映射成 `网上冲浪`，把 `Steam` 映射成 `打游戏`，把 `Xcode` 映射成 `正在构建一些奇怪的东西`。

## Shell

Shell 是唯一外部集成。它很朴素，也很自由：命令你写，目标你定，风险你负责。

打开 Preferences -> Integrations，启用 Shell，输入命令，然后用 Test 查看退出码、stdout 和 stderr。

发送 webhook：

```sh
curl -X POST "https://example.com/report" \
  -H "Content-Type: application/json" \
  -d "$PROCESS_REPORTER_JSON"
```

写入本地日志：

```sh
mkdir -p /tmp/process-reporter
printf '%s\n' "$PROCESS_REPORTER_JSON" >> /tmp/process-reporter/reports.jsonl
```

拼一段人能看的状态：

```sh
message="${PROCESS_REPORTER_PROCESS_DESCRIPTION:-正在使用 ${PROCESS_REPORTER_PROCESS_NAME:-未知应用}}"

if [[ -n "$PROCESS_REPORTER_MEDIA_NAME" ]]; then
  message="$message，BGM: $PROCESS_REPORTER_MEDIA_NAME"
  if [[ -n "$PROCESS_REPORTER_MEDIA_ARTIST" ]]; then
    message="$message - $PROCESS_REPORTER_MEDIA_ARTIST"
  fi
fi

if [[ -n "$PROCESS_REPORTER_PROCESS_USAGE_DURATION" ]]; then
  hours="$(awk "BEGIN { printf \"%.2f\", $PROCESS_REPORTER_PROCESS_USAGE_DURATION / 3600 }")"
  message="$message，已使用 $hours 小时"
fi

printf '%s\n' "$message"
```

命令会通过 `/bin/zsh -lc` 在本地运行，权限与当前用户一致。只运行你理解的命令。

## 环境变量

每次 shell 上报都会收到这些变量。没有值的字段是空字符串。

- `PROCESS_REPORTER_JSON`
- `PROCESS_REPORTER_EVENT`（`report`、`screen_sleep` 或 `screen_wake`）
- `PROCESS_REPORTER_SCREEN_STATE`（`off`、`on`，普通上报时为空）
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

`PROCESS_REPORTER_JSON` 是同一份报告的结构化 JSON，包含事件类型、屏幕状态、应用、媒体和前台使用数据。息屏和亮屏事件即使没有应用或媒体数据，也会执行当前选中的 Shell 命令。

这些环境变量名沿用 `PROCESS_REPORTER_*` 前缀，方便旧脚本继续工作。Statusa 换了新名字，但不会突然把你的 webhook 脚本弄哭。

## 隐私

Statusa 不截图，不记录键盘输入，不读取文件内容，也不追踪鼠标轨迹。她只按你的设置记录应用名、窗口标题、媒体元数据和时长。

建议先保守一点：

- Shell 先关闭，确认本地历史内容没问题。
- 过滤密码管理器、银行应用、隐私浏览器和敏感工作工具。
- 公开展示时，把原始名称映射成模糊描述。
- 妥善保管 webhook 地址。

## Vibe Coding 模式

菜单栏里的 **Vibe Coding Mode** 会保持 macOS 系统唤醒，适合长时间运行编译、Agent、下载或其他无人值守任务。它不会阻止显示器按系统设置自动关闭，所以可以让任务继续运行，同时减少屏幕常亮。

启用后可以点击 **Turn Display Off Now** 立即关闭显示器；移动鼠标或按键即可重新点亮，后台任务会继续运行。

这个模式：

- 不需要管理员权限。
- 不会启动额外的 `caffeinate` 子进程。
- 关闭开关或退出 Statusa 时会立即释放电源断言。
- 不会阻止 MacBook 因合盖而睡眠。

实现采用 IOKit 电源断言，核心思路参考并改编自 MIT 许可的 `demiaochen/caffeinate-disablesleep`。Statusa 只使用“保持系统唤醒、允许屏幕休眠”的部分，不会修改 `pmset disablesleep`，也不会安装 sudoers 规则。

完整第三方许可见 `THIRD_PARTY_NOTICES.md`。

## 常见问题

- 读不到窗口标题：在 System Settings -> Privacy & Security -> Accessibility 中启用 Statusa，然后重启。
- Shell 命令失败：用 Test 看 stdout/stderr，尽量使用工具的绝对路径。
- 菜单栏图标不见：先在 Activity Monitor 确认应用还在，再重启应用。
- 内存占用偏高：清理旧历史，降低上报频率。

## 开发

```sh
open ProcessReporter.xcodeproj
xcodebuild -project ProcessReporter.xcodeproj -scheme ProcessReporter -configuration Debug build
```

不需要第三方 Swift Package。新的外部上报通常应该走 `ShellReporterExtension`，不要再加一堆内置服务 SDK。

常用入口：

- `ProcessReporter/App/ProcessReporterApp.swift`
- `ProcessReporter/Features/Reporting/Reporter.swift`
- `ProcessReporter/Features/Reporting/Reporter+Shell.swift`
- `ProcessReporter/Features/Settings/PreferencesStore.swift`
- `ProcessReporter/Features/Media/MediaInfoManager.swift`
- `ProcessReporter/Features/History/DataStore.swift`

## License

2026 © Shadowsight9, released under the MIT License.

本项目 fork 自 Innei 的 ProcessReporter。原始作品 © Innei，同样基于 MIT License 发布。

## 新手开发与学习

如果你刚开始学习 macOS + Swift，建议先阅读 [`docs/LEARNING_GUIDE.zh-CN.md`](docs/LEARNING_GUIDE.zh-CN.md)。它包含项目数据流、推荐阅读顺序、并发概念和循序渐进的练习。

统一运行测试和 Debug 构建：

```sh
scripts/check.sh
```

快速反馈时可以只运行纯逻辑测试：

```sh
swift test
```

Release Workflow 会从 Git 标签自动写入应用版本：例如 `v1.6.0` 会生成 `CFBundleShortVersionString = 1.6.0`，构建号使用当前提交数量。支持 `v1.6.0-beta.1` 这类预发布标签。
