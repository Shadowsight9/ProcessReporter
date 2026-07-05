# ProcessReporter 重构计划

本文记录两个方向的重构计划：

1. 用应用内 Swift 实现替换外部媒体播放依赖。
2. 用用户可配置的 shell 命令集成替换内置服务集成。

目标是让 ProcessReporter 更简单，更适合作为个人工具使用，并且在接入外部服务时不必每次都修改 Swift 代码。

## 重构前状态

### 媒体播放

媒体播放信息目前统一经过 `MediaInfoManager`。

当前实现已统一使用 `LocalMediaInfoProvider`，它加载 Apple 的私有 `MediaRemote.framework`。旧的 `CLIMediaInfoProvider` 和外部 `media-control` 路径已移除。

相关文件：

- `ProcessReporter/Core/MediaInfoManager/MediaInfoManager.swift`
- `ProcessReporter/Core/MediaInfoManager/LocalMediaInfoProvider.swift`
- `ProcessReporter/AppDelegate.swift`

### 集成

应用原先为多个服务提供了专用 reporter extension：

- MixSpace
- S3
- Slack
- Discord

这些扩展原先由 `Reporter.initializeExtensions()` 直接注册。每个集成都有自己的偏好设置模型和 UI。

相关文件：

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

## 当前槽点与不足

### 技术栈混用

项目里同时存在 RxSwift/RxCocoa、Combine、Swift Concurrency、Timer、DispatchQueue 和回调式 API。每一种本身都能工作，但混在一起会带来几个问题：

- 状态来源不统一，排查一次上报为什么触发会绕过多个模型。
- 主线程边界靠约定和局部 guard 维护，容易漏。
- RxSwift 主要承担 UserDefaults 绑定和 UI 状态传播，成本高于收益。
- Combine 只在媒体 debounce 等局部使用，没有形成统一架构。

建议方向：偏好设置和 UI 状态迁移到 Swift 原生 Observation 或简单的 `@MainActor` store；异步流程统一使用 Swift Concurrency；事件流需要 debounce 时用 `AsyncStream` 或局部 Combine，避免继续扩散 Rx。

### 媒体链路过重

当前媒体链路为适配 `media-control` 做了大量补丁：CLI 检测、安装提示、stream/poll fallback、主线程保护、超时中断、失败计数、缓存、actor coalescing。很多复杂度不是业务需要，而是外部命令带来的。

建议方向：删除 CLI provider 后，`MediaInfoManager` 应只保留本地 provider、轻量缓存、状态变更回调和 debounce。能删掉的线程保护代码不要保留给“以后可能再接 CLI”。

### 集成模型膨胀

MixSpace、S3、Slack、Discord 都有独立模型、UI、上报代码和资源。对一个个人工具来说，这会把维护成本锁死在服务 API 细节上：

- 每接一个服务都要改 Swift、改 UI、改导入导出。
- 凭据散落在 UserDefaults 模型里。
- S3/Discord 额外引入上传器、SDK bridge、资源和调试状态。
- Reporter 的扩展架构存在，但实际仍被内置服务绑住。

建议方向：用 `ShellReporterExtension` 作为唯一内置集成。服务专用逻辑交给用户脚本或 `curl`。这比维护一堆半通用 integration 更小、更稳。

### 偏好设置和安全边界不够清晰

当前偏好设置既是 UI 状态源，也是导入导出结构，还是集成凭据存储位置。旧集成移除后应顺手收敛：

- 导入配置时不要自动启用 shell 命令。
- shell 命令默认禁用。
- 旧服务 token/access key 立即停止读取，并在 UI 中不再可达。
- 后续如果还需要长期保存敏感值，应迁移到 Keychain；shell 命令文本本身可以继续保存在 UserDefaults。

### 数据库迁移策略偏粗

`Database.initialize()` 在 migration 失败时会删除旧数据库并重新创建。对个人工具可接受，但这不是可靠迁移策略。历史记录已经作为产品功能展示时，直接清库会变成数据丢失。

建议方向：本轮不要为了“先进”重写数据库层。先保留 SwiftData，但补真实 migration stage 或至少把清库行为变成显式用户确认/备份恢复路径。

### 全局单例和生命周期耦合

`Reporter`、`ApplicationMonitor`、`MediaInfoManager`、`PreferencesDataModel`、`DataStore`、`Database` 都是全局访问。小应用可以接受，但当前问题是生命周期交叉太多：睡眠唤醒、菜单栏状态、媒体监听、定时上报、数据库 flush 互相调用。

建议方向：不做大型依赖注入框架。先把副作用集中在少数入口：`Reporter` 负责 report 生命周期，`MediaInfoManager` 只负责媒体，`PreferencesStore` 只负责偏好。能通过构造参数传入的地方再传，不为了测试提前铺架构。

### UI 技术债

偏好设置主要是 AppKit ViewController，局部混入 SwiftUI。AppKit 不是问题，问题是多个集成 UI 造成重复表单和复杂侧边栏。直接全量 SwiftUI 重写收益不确定。

建议方向：Shell 集成页可以用 SwiftUI 或保留 AppKit，哪个改动小用哪个。等旧集成 UI 删除后，再判断是否值得把偏好设置整体迁到 SwiftUI + Observation。

### 日志和调试体验弱

当前调试依赖 `print`/`NSLog`、UI 状态和局部 debug store。shell 集成上线后，用户最需要知道的是“命令有没有执行、退出码是什么、stdout/stderr 是什么”。

建议方向：使用 `Logger`/`OSLog` 记录系统日志；偏好设置里提供一次手动调试按钮，并显示最近一次 exit code、stdout、stderr。不要做复杂日志浏览器。

## 现代化重构原则

优先用新 API 的地方：

1. 用 Swift Concurrency 统一异步上报、媒体读取、数据库调用和 shell 执行。
2. 用 actor 保护共享可变状态，例如数据库、shell 执行状态、媒体缓存。
3. 用 `Codable`/`JSONEncoder` 生成 shell payload，避免字符串拼接。
4. 用 SwiftData 继续承载历史记录，但补真实迁移或显式数据保全策略。
5. 用 `Logger` 替代散落的 `print`/`NSLog`。
6. 用 Observation 或一个 `@MainActor` 偏好 store 替代 RxSwift，先从新 Shell 设置页开始。

暂时不做的升级：

- 不为了“先进”一次性重写整个 UI。
- 不新增服务专用 SDK。
- 不新增插件系统，shell 命令已经覆盖扩展诉求。
- 不把私有 `MediaRemote.framework` 包装成看似公开稳定的 API。
- 不新增依赖来替代 Swift 标准库和系统框架已经能完成的事。

## 目标设计

### 媒体播放

只使用本地 Swift provider 作为唯一媒体 provider。

第一版可落地实现复用原有 MediaRemote 做法，并整理为语义更清晰的本地 provider：

- `LocalMediaInfoProvider`

这个 provider 仍会使用 `MediaRemote.framework`，因为 macOS 没有提供完整的公开 Swift API 来读取跨应用的系统级正在播放元数据。

重要取舍：

- 移除外部 `media-control` 依赖。
- 仍依赖 Apple 私有 framework。
- 适合本地使用和学习。
- 不应视为 App Store 安全方案。

### Shell 命令集成

用一个集成替换所有内置的服务专用集成：

- `ShellReporterExtension`

用户在偏好设置中配置一条 shell 命令。每次 report 都执行这条命令，并通过环境变量暴露当前 report 数据。

用户命令示例：

```sh
curl -X POST "https://example.com/report" \
  -H "Content-Type: application/json" \
  -d "$PROCESS_REPORTER_JSON"
```

命令通过固定 shell 运行：

```text
/bin/zsh -lc "<configured command>"
```

固定使用 zsh 可以避免不同用户 shell 对 `-lc`、启动文件和语法的差异。应用不应解析任何服务专用 API。用户可以自行组合 `curl`、本地脚本、Python、Node.js 或其他本地命令。

## Shell 集成契约

### 偏好设置模型

新增偏好设置模型：

```swift
struct ShellIntegration: UserDefaultsJSONStorable, DictionaryConvertible {
    var isEnabled: Bool = false
    var command: String = ""
    var timeoutSeconds: Int = 10
    var lastExitCode: Int?
    var lastStdout: String = ""
    var lastStderr: String = ""
}
```

未来可选字段：

- `workingDirectory`
- `sendOnlyWhenChanged`
- `includeArtwork`

### 环境变量

每次 shell 命令调用都应收到一组稳定的环境变量。

进程字段：

- `PROCESS_REPORTER_PROCESS_NAME`
- `PROCESS_REPORTER_WINDOW_TITLE`
- `PROCESS_REPORTER_PROCESS_BUNDLE_ID`

媒体字段：

- `PROCESS_REPORTER_MEDIA_NAME`
- `PROCESS_REPORTER_MEDIA_ARTIST`
- `PROCESS_REPORTER_MEDIA_ALBUM`
- `PROCESS_REPORTER_MEDIA_PROCESS_NAME`
- `PROCESS_REPORTER_MEDIA_PROCESS_BUNDLE_ID`
- `PROCESS_REPORTER_MEDIA_DURATION`
- `PROCESS_REPORTER_MEDIA_ELAPSED_TIME`
- `PROCESS_REPORTER_MEDIA_PLAYING`

通用字段：

- `PROCESS_REPORTER_TIMESTAMP`
- `PROCESS_REPORTER_JSON`

空值应以空字符串传入，而不是省略。这样 shell 脚本更简单、更可预测。

### JSON Payload

`PROCESS_REPORTER_JSON` 应包含一个紧凑的 JSON object。

建议结构：

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

JSON 应使用 `JSONEncoder` 或 `JSONSerialization` 构造，不要手动拼接字符串。

### 执行规则

shell 集成应满足：

- 禁用时不执行任何操作。
- 命令为空时返回 ignored result。
- report 至少包含一种已启用数据类型时才执行命令。
- 在主线程外运行。
- 强制执行超时。
- 捕获并截断 stdout 和 stderr 以便调试。
- 将退出状态 `0` 视为成功。
- 将非零退出状态视为失败。
- 不阻塞其他集成或主应用循环。
- 偏好设置 UI 提供手动调试按钮，显示最近一次 exit code、stdout 和 stderr。

由于本次重构会移除其他集成，shell 集成通常会成为唯一的 reporter extension。

### 安全说明

这个功能有意允许用户执行本地命令。

必需行为：

- 默认禁用。
- 在用户启用前，绝不自动执行导入的配置。
- 导入旧配置时立即忽略旧集成字段，不迁移旧服务凭据。
- 将命令文本作为偏好设置存储。
- 在 UI 中清楚说明命令会在本地以用户权限运行。

当前应用已禁用 App Sandbox，因此技术上可以执行 shell。这也意味着命令可以按照应用进程权限访问用户文件。

## 实施步骤

### 阶段 1：Shell 集成

1. 在 `PreferencesDataModel+Integration.swift` 中添加 `ShellIntegration`。
2. 在 `PreferencesDataModel.swift` 中添加导入/导出支持。
3. 添加 `Reporter+Shell.swift`。
4. 修改 `Reporter.initializeExtensions()`，只注册 `ShellReporterExtension`。
5. 修改集成偏好设置 UI，只展示 Shell 设置。
6. 从偏好设置侧边栏中移除 MixSpace、S3、Slack 和 Discord 集成 UI，或停止引用它们。
7. 立即停止导入、读取和展示旧集成偏好设置。
8. 添加手动调试按钮，显示最近一次 exit code、stdout 和 stderr。
9. report 至少包含一种已启用数据类型时才执行 shell 命令。
10. 构建并验证一次 report 可以触发已配置的 shell 命令。

### 阶段 2：本地媒体 Provider

1. 将 `MediaInfoManager` 中的 provider 选择逻辑替换为本地 provider。
2. 将原有 legacy provider 重命名或复制为 `LocalMediaInfoProvider`。
3. 移除 `CLIMediaInfoProvider` 的使用。
4. 从 `AppDelegate` 中移除 media-control 安装提示。
5. 移除或废弃 `MediaControlInstallationHelper`。
6. 为 MediaRemote 符号解析、通知注册和 callback 等待补防御式处理。
7. 简化 `MediaInfoManager` 中仅用于防止 CLI 调用阻塞的逻辑。
8. 构建并验证媒体状态变化仍会产生 `MediaInfo`。

### 阶段 3：清理

1. 如果不再需要，移除旧集成的未使用资源。
2. 如果没有其他功能引用，移除 `S3Uploader` 等未使用 helper 代码。
3. 更新提到 MixSpace、S3、Slack、Discord 或 media-control 的用户文档。
4. 将 `DEVELOPMENT.md` 和 `USER_GUIDE.md` 的有效内容合并到 README/架构文档。
5. 新增中文 README。
6. 用 `Logger` 替换本轮触达代码里的 `print`/`NSLog`。
7. 执行一次 clean build。

## 验证计划

### 构建

运行：

```sh
xcodebuild -project ProcessReporter.xcodeproj -scheme ProcessReporter -configuration Debug build
```

### Shell 集成检查

使用本地测试命令：

```sh
mkdir -p /tmp/process-reporter-test
printf '%s\n' "$PROCESS_REPORTER_JSON" >> /tmp/process-reporter-test/reports.jsonl
```

预期结果：

- report 会创建或追加写入 `/tmp/process-reporter-test/reports.jsonl`。
- 当有应用/窗口获得焦点时，JSON 包含进程数据。
- 当有媒体正在播放时，JSON 包含媒体数据。
- 命令退出缓慢或失败时，应用仍保持响应。

失败测试：

```sh
exit 42
```

预期结果：

- reporter 将该集成标记为失败。
- 应用不崩溃。

超时测试：

```sh
sleep 30
```

预期结果：

- 命令会在配置的超时时间后终止。
- 应用不会阻塞菜单栏 UI。

### 媒体检查

使用 Apple Music、Spotify 或浏览器媒体播放测试。

预期结果：

- 播放变化时，媒体标题和艺术家会更新。
- 暂停或不可用的媒体不会产生错误的活跃播放报告。
- 即使没有媒体播放，焦点应用上报仍继续工作。

## 已决策问题

1. shell 命令只在 report 至少包含一种已启用数据类型时运行。
2. 旧集成偏好设置立即移除，不迁移。
3. 偏好设置 UI 暴露 stdout/stderr，并增加手动调试按钮。
4. shell 命令不接收 artwork，避免环境变量 payload 过大。
5. 命令固定通过 `/bin/zsh -lc` 运行，避免不同用户 shell 的启动行为差异。
