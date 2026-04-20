# 通知统一为应用内浮窗设计

## Context

当前 PowerShell 的通知存在两条分支：

- App Bundle + 授权通过时走 `UNUserNotificationCenter` 系统横幅
- 非 App Bundle 或授权失败时走右上角应用内浮窗

这带来了两类问题：

1. debug 启动与 DMG 启动的通知表现不一致，用户无法形成稳定预期。
2. 这次产品目标已经明确变成“无论 DMG 还是 debug，都统一显示右上角应用内浮窗”，因此系统通知分支本身已经不再符合需求。

用户同时确认了两个边界：

- 不再请求或使用 macOS 系统通知权限
- 保持当前浮窗样式、交互、停留方式和点击行为不变，只统一通知通道

因此这次改动的本质不是“优化降级逻辑”，而是把 `NotificationManager` 从双通道管理器收敛成单通道浮窗路由器。

## 目标

- 让 debug 启动与 DMG 启动的通知表现完全一致
- 所有通知统一通过现有右上角应用内浮窗展示
- 不再请求或依赖 macOS 系统通知权限
- 保持现有浮窗点击跳转、关闭按钮、堆叠和样式不变
- 将改动范围限制在通知入口、启动调用点、测试和相关文档

## 推荐方案

采用“彻底单通道化”的方案：删除 `UNUserNotificationCenter` 相关分支，让 `NotificationManager.send()` 永远调用现有 `FloatingNotificationPresenting`。

核心调整：

1. 删除 `NotificationManager` 中与系统通知相关的依赖、状态和 delegate 实现
2. 保留 `send(title:body:sessionId:)` 作为外部唯一通知入口，但内部始终转给浮窗 presenter
3. 删除应用启动时的系统通知授权请求
4. 将现有测试从“双通道降级”语义改为“统一浮窗”语义
5. 更新通知设计文档，使文档与现行实现保持一致

该方案最符合当前明确需求，也能彻底消除“不同启动方式走不同通知通道”的不确定性。

## 备选方案与取舍

### 方案 A（推荐）：彻底移除系统通知分支

优点：

- 行为最一致，debug 与 DMG 无差异
- 代码语义最干净，没有无效分支和死状态
- 不再依赖系统权限、bundle 形态和授权结果
- 最容易测试，也最不容易再次出现“某种启动方式没通知”的问题

缺点：

- 会完全移除系统通知能力
- 若未来想恢复系统通知，需要重新设计而不是简单开开关

### 方案 B：保留系统通知代码，但永远不启用

优点：

- 表面上改动更小

缺点：

- 保留无效授权逻辑和未使用依赖，增加理解成本
- 容易让后续维护者误以为仍存在双通道能力
- 不符合“彻底统一”的目标

### 方案 C：增加配置开关，默认走浮窗

优点：

- 后续可以按用户偏好切换

缺点：

- 引入了本次并未提出的新需求
- 会增加设置、状态和测试复杂度
- 与“保持当前浮窗行为不变，仅统一通道”的目标不匹配

## 组件设计

### 1. NotificationManager

`NotificationManager` 保留为通知入口，但职责缩小为“浮窗通知路由器”。

保留内容：

- `send(title:body:sessionId:)`
- `onNotificationClicked`
- `FloatingNotificationPresenting` 依赖注入
- 将浮窗点击回调桥接到 `onNotificationClicked`

删除内容：

- `UserNotificationCenterProviding` 协议
- `UNUserNotificationCenter` 扩展
- `authorizationGranted`
- `notificationCenter` / `notificationCenterFactory`
- `bundleInspector`
- `isAppBundle` / `canUseUNNotifications`
- `requestAuthorization()`
- `sendUNNotification(...)`
- `UNUserNotificationCenterDelegate` 实现

调整后，`send(title:body:sessionId:)` 的行为固定为：

```swift
floatingPresenter.show(title: title, body: body, sessionId: sessionId)
```

这样 `NotificationManager` 的外部调用方式不变，但内部再也不区分运行环境或授权状态。

### 2. PowerShellApp 启动流程

`Sources/PowerShell/App/PowerShellApp.swift` 中当前启动时会调用：

```swift
NotificationManager.shared.requestAuthorization()
```

这一步将被删除。

调整后应用启动只保留：

- 加载 LLM 配置
- 配置通知点击后的 session 跳转回调
- 启动 Hook 路由

也就是说，通知系统不再有“先申请权限、再决定走哪条通道”的前置状态，启动流程变成纯本地浮窗模型。

### 3. FloatingNotificationPanelPresenter

`FloatingNotificationPanelPresenter`、`FloatingNotificationCenter`、`FloatingNotificationPanelController` 和卡片视图不做行为改动。

保持不变的内容包括：

- 右上角浮窗展示位置
- 当前卡片样式
- 点击卡片打开对应 session
- 点击关闭按钮仅关闭卡片
- 当前堆叠/聚合策略

本次统一通知通道只影响“入口路由”，不影响“浮窗如何展示”。

## 数据流

调整后的通知路径统一为：

```text
Hook/终端事件
  → RootContentView 计算目标 session
  → NotificationManager.send(title:body:sessionId:)
  → FloatingNotificationPresenting.show(...)
  → 浮窗面板展示
  → 用户点击卡片
  → onNotificationClicked(sessionId)
  → SessionManager 切换到对应终端
```

与现状相比，唯一变化是中间不再存在系统通知分支。

## 测试策略

这次改动必须遵循 TDD，先让测试表达“所有通知都走浮窗”。

### 保留并继续验证的行为

- `NotificationManager` 能把浮窗点击回调转发给 `onNotificationClicked`
- 打开卡片会移除对应 session 的通知并触发跳转
- 关闭卡片不会触发跳转
- 点击解析逻辑保持原样

### 删除或改写的测试语义

当前测试里那些围绕以下前提的内容需要被删掉或重写：

- 非 App Bundle 时才走浮窗
- 默认初始化不应提前触碰 `UNUserNotificationCenter`
- 授权状态决定通知通道
- bundle 类型决定通知通道

这些测试前提在新设计下不再成立。

### 新的核心测试语义

建议测试覆盖收敛为：

1. `NotificationManager.send()` 无条件调用浮窗 presenter
2. `NotificationManager` 默认初始化不需要系统通知相关依赖
3. 浮窗 presenter 的交互回调仍能打开对应 session
4. 关闭与点击解析行为不变

这样测试重点就从“降级逻辑正确”转成“单通道路由正确且交互未回归”。

## 文档更新

`feature/trd/notification.md` 当前仍描述“双通道通知降级”，这会和新实现冲突。

文档需要同步更新为：

- 所有运行形态统一使用应用内浮窗
- 不再请求系统通知权限
- `NotificationManager` 是浮窗通知统一入口
- 删除对 `UNUserNotificationCenter`、授权缓存和 bundle 判断的说明

这能避免后续再根据旧文档误判当前实现。

## 影响范围

### 修改文件

- `Sources/PowerShell/Services/NotificationManager.swift`
- `Sources/PowerShell/App/PowerShellApp.swift`
- `Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift`
- `feature/trd/notification.md`

### 明确不改

- HookConfigurator / HookNotificationServer
- Session 路由逻辑
- FloatingNotificationPanelPresenter 的 UI 与交互
- DMG 打包脚本
- 其他设置项和非通知功能

## 风险与控制

### 风险 1：删除系统通知后遗漏编译引用

控制方式：

- 在改动前先通过测试和编译定位所有 `UNUserNotificationCenter` 相关引用
- 收敛 `NotificationManager` 的公开接口，避免残留失效方法调用

### 风险 2：测试仍绑定旧的“双通道”语义

控制方式：

- 先改测试，再改实现
- 明确删除旧前提，而不是在旧测试上做条件修补

### 风险 3：文档与实现再次偏离

控制方式：

- 在同一改动中同步更新 `feature/trd/notification.md`
- 用“统一浮窗”替换所有“双通道降级”表述

## 验证方式

1. 先运行通知相关测试，确认新测试在旧实现上失败
2. 实现单通道路由后再次运行通知相关测试并通过
3. 本地启动 debug 版本，触发一次 Claude Hook 通知，确认展示为右上角浮窗
4. 本地启动 `.app` / DMG 产物，触发同类通知，确认展示为同样的右上角浮窗
5. 验证点击卡片仍能切换到对应终端，关闭按钮仍只关闭卡片

## 非目标

- 重新设计浮窗 UI
- 增加系统通知与浮窗之间的用户可配置开关
- 改造通知内容映射规则
- 调整 Hook 事件来源或 session 绑定逻辑
- 顺手修改 DMG 打包和签名流程
