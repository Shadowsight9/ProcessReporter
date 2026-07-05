# ProcessReporter Technical Refactor Final State

本轮目标已经完成：消除 SwiftUI 迁移后的历史残余代码，收敛目录结构，移除不必要第三方依赖，让项目更接近一个适合新手学习的现代 macOS SwiftUI 菜单栏应用。

## Final Architecture

当前目录按功能边界组织：

```text
ProcessReporter/
  App/
    ProcessReporterApp.swift
    AppDelegate.swift
    SettingsWindowPresenter.swift

  Features/
    StatusMenu/
      StatusMenuView.swift
      StatusMenuStore.swift
      ReporterStatusBridge.swift

    Settings/
      SettingsRootView.swift
      GeneralSettingsView.swift
      ShellIntegrationSettingsView.swift
      PreferencesFilterView.swift
      MappingSettingsView.swift
      HistorySettingsView.swift
      AppPickerView.swift
      PreferencesStore.swift
      SendInterval.swift
      Persistence/
        PreferencesDataModel*.swift
        UserDefaultsRelay.swift

    Reporting/
      Reporter.swift
      Reporter+Shell.swift
      Reporter+Types.swift

    Monitoring/
      ApplicationMonitor.swift
      FocusedWindowInfo.swift
      MouseClickInfo.swift

    Media/
      MediaInfo.swift
      MediaInfoManager.swift
      MediaInfoProvider.swift
      LocalMediaInfoProvider.swift

    History/
      DataStore.swift
      Database.swift
      ReportModel.swift
      IconModel.swift

  Shared/
    Components/
    Constants/
    Extensions/
    Utilities/
```

## Completed

- 旧 AppKit settings stack 已删除：`SettingWindow`、`SettingWindowManager`、`PreferencesMappingViewController`、`Preferences/Controllers`、`Windows`。
- Settings 入口统一到 `SettingsWindowPresenter`，菜单栏和 AppDelegate 使用同一个打开路径。
- 状态栏逻辑已收敛到 `Features/StatusMenu/`，`ReporterStatusItemManager` 已替换为 `ReporterStatusBridge`。
- Settings 页面全部拆成 SwiftUI view 文件，`SettingsRootView` 只负责组合页面。
- Filter/Mapping/General/Shell 的写入动作收敛到 `PreferencesStore`，view 不再直接写底层 relay。
- `PreferencesFilterView` 的初始 filter state 也改由 `PreferencesStore` 提供。
- `StatusMenuStore` 和 `PreferencesStore` 标记为 `@MainActor`，后台订阅更新通过主线程发布。
- `UserDefaultsRelay` 已改为本地轻量 observable relay，保留 `value`、`accept`、subscription 三个核心能力。
- RxSwift/RxCocoa 已完全移除。
- Toast 已从 SnapKit 迁移到原生 Auto Layout。
- SnapKit 已完全移除。
- `Package.resolved` 已删除，Xcode target dependency graph 只剩应用 target。
- 旧组件和资源已删除：`NSScrollTextField`、`NSMenuItem` extension、terminal asset。
- `DictionaryConvertible` 已移动到 `Shared/`。
- README、README.zh-CN、ARCHITECTURE 已同步到新目录和无第三方依赖状态。

## Verification

已通过：

```sh
xcodebuild -project ProcessReporter.xcodeproj -scheme ProcessReporter -configuration Debug build
```

构建日志显示 target dependency graph 只有 `ProcessReporter`，没有 Swift Package dependency。

## Remaining Intentional Tradeoffs

- `PreferencesDataModel` 仍保留为底层偏好持久化适配层。它现在不依赖 Rx，但仍使用 relay 风格 API，原因是 Reporter 和 Settings 都依赖实时设置变化。
- `Reporter` 仍是 `@MainActor` singleton-style runtime object。下一步若要增强测试性，可以先引入协议边界，而不是一次性重写核心上报流程。
- MediaRemote 仍是私有 Apple API，只适合本地工具使用；这属于产品取舍，不是历史残余。
- `Network.swift` 仍使用 macOS 14.4 deprecated 的 `SCNetworkReachability` API。后续可换成 `NWPathMonitor`，但本轮没有改变网络行为。

## Next Improvements

这些不是本轮清理的阻塞项：

1. 为 settings export/import、shell payload builder、status mapping 增加轻量单元测试。
2. 将 shell stdout/stderr 做长度上限，避免 UserDefaults 膨胀。
3. 引入小协议边界：`ApplicationMonitoring`、`MediaInfoProviding`、`ReportPersisting`、`SettingsPersisting`。
4. 将 `SCNetworkReachability` 替换为 `NWPathMonitor`。
5. 给设置页增加 Diagnostics 区域：accessibility 状态、数据库状态、最近上报结果、最近 shell 结果。

## Learning Path

推荐新手按这个顺序阅读：

1. `App/ProcessReporterApp.swift`：SwiftUI app lifecycle、`MenuBarExtra`、Settings scene。
2. `Features/StatusMenu/`：菜单栏状态如何展示。
3. `Features/Settings/`：SwiftUI form 如何通过 store 修改持久化设置。
4. `Features/Reporting/`：如何组合 process/media 数据并上报。
5. `Features/Monitoring/`：如何读取当前 app/window。
6. `Features/Media/`：如何桥接 MediaRemote。
7. `Features/History/`：如何用 SwiftData 保存历史记录。
