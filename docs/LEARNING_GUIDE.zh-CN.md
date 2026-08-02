# Statusa 新手学习指南

这份指南把项目当作一个真实的 macOS 学习样例。目标不是一次性读懂全部代码，而是按数据流逐层理解，并且每次只做一个可以验证的小改动。

## 1. 先建立整体地图

Statusa 的主数据流是：

```text
系统事件
  -> ApplicationMonitor / MediaInfoManager
  -> Reporter
  -> ReportSnapshot
  -> ShellReporterExtension + DataStore
  -> StatusMenuStore / SwiftUI 界面
```

目录按功能组织：

- `App/`：应用入口、启动过程、AppKit 生命周期、设置窗口。
- `Features/Monitoring/`：当前应用、窗口标题和前台时长。
- `Features/Media/`：系统正在播放的媒体。
- `Features/Reporting/`：组合、过滤、映射和发送报告。
- `Features/History/`：SwiftData 持久化。
- `Features/Settings/`：设置页面和 UserDefaults 持久化。
- `Features/StatusMenu/`：菜单栏状态和界面。
- `Shared/`：多个功能共同使用的组件和工具。

## 2. 推荐阅读顺序

### 第一阶段：SwiftUI 和状态

1. `App/ProcessReporterApp.swift`
2. `App/AppModel.swift`
3. `Features/StatusMenu/StatusMenuView.swift`
4. `Features/StatusMenu/StatusMenuStore.swift`
5. `Features/StatusMenu/StatusPresentation.swift`

重点学习：

- `App`、`Scene`、`MenuBarExtra`
- `@Observable`、`@State`、`@Bindable`
- View 只描述界面，Store/Model 保存状态和执行操作
- 把纯展示规则放到可测试的值类型中

### 第二阶段：偏好设置

1. `Features/Settings/SettingsRootView.swift`
2. `Features/Settings/PreferencesStore.swift`
3. `Features/Settings/Persistence/UserDefaultsRelay.swift`
4. `Features/Settings/Persistence/PreferencesDataModel+*.swift`

重点学习：

- SwiftUI 表单和双向绑定
- 为什么页面不直接到处读写 `UserDefaults`
- 如何用一个 Store 连接界面和持久化层

### 第三阶段：并发和业务流程

1. `Features/Reporting/Reporter.swift`
2. `Features/Reporting/ReportSnapshot.swift`
3. `Features/Reporting/Reporter+Shell.swift`
4. `Features/History/DataStore.swift`

重点学习：

- `async/await`、`Task`、`actor`、`@MainActor`
- 主线程负责 UI，actor 保护共享可变状态
- 使用 Sendable 值对象跨并发边界
- 外部副作用集中在 DataStore 和 ReporterExtension

### 第四阶段：macOS 系统能力

1. `Features/Monitoring/ApplicationMonitor.swift`
2. `Features/Media/MediaInfoManager.swift`
3. `Features/Media/SystemNowPlayingProvider.swift`
4. `App/AppDelegate.swift`

这一层涉及 Accessibility、AppKit 通知和私有媒体 API。建议最后阅读，因为它比普通 SwiftUI 业务代码更依赖系统知识。

## 3. 开发循环

第一次打开：

```sh
open ProcessReporter.xcodeproj
```

每次修改后运行统一检查：

```sh
scripts/check.sh
```

它会依次：

1. 运行 Swift Testing 单元测试。
2. 使用 Xcode Debug 配置构建 macOS App。
3. 禁用代码签名，避免本地证书影响普通编译验证。

只运行快速测试：

```sh
swift test
```

只构建 App：

```sh
xcodebuild \
  -project ProcessReporter.xcodeproj \
  -scheme ProcessReporter \
  -configuration Debug \
  -derivedDataPath .build/xcode-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 4. 适合新手的练习

按下面顺序做，每次完成后运行 `scripts/check.sh`：

1. 修改 `StatusPresentation` 的一段状态文案，并更新对应测试。
2. 在菜单栏卡片中增加一个只读字段，例如当前是否有 Accessibility 权限。
3. 给 `StatusMenuFormatter` 增加边界测试，例如空歌手、暂停状态。
4. 给映射解析器增加一条非法输入测试，再实现校验。
5. 给历史页增加“记录数量”显示，但不要直接让 View 操作 SwiftData。
6. 给 Shell 环境变量构造提取纯函数，并为它增加测试。

不建议一开始做：

- 重写 `SystemNowPlayingProvider`
- 直接切换 Swift 6 严格并发模式
- 同时替换设置存储、数据库和 Reporter 架构
- 引入大型第三方框架

## 5. 这个项目采用的现代 Swift 思路

- SwiftUI 构建界面，AppKit 只处理 macOS 特有生命周期和权限。
- Observation (`@Observable`) 管理界面状态，减少 Combine 样板代码。
- Swift Concurrency 管理异步工作和共享状态。
- SwiftData 保存历史记录，但通过 `DataStore` 隔离数据库细节。
- Swift Testing 编写快速纯逻辑测试。
- 功能目录结构让一次改动尽量限制在一个 Feature 内。

## 6. 修改代码时的判断原则

先问自己四个问题：

1. 这是界面状态、业务规则，还是系统副作用？
2. 它应该运行在主线程、actor 中，还是普通纯函数中？
3. 这段逻辑能不能从 View 中提取并单元测试？
4. 能不能用一次小改动完成，而不是一次性重写整个模块？

如果答案不确定，优先选择“小、可测试、可回退”的实现。
