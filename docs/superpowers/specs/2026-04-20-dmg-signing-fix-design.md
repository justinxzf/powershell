# DMG 打包签名修复设计

## Context

当前 `Scripts/build_dmg.sh` 通过手工组装 `.app` 包后直接生成 DMG，但没有在最终 `.app` 结构稳定后重新执行签名。实际检查结果表明：

- `dist/PowerShell.app` 当前为 ad-hoc / linker-signed 状态
- `Scripts/build_dmg.sh` 中没有 `codesign`、`notarytool`、`stapler` 等分发相关步骤
- Gatekeeper 检查报错：`code has no resources but signature indicates they must be present`

这说明问题不是 DMG 文件本身损坏，而是 `.app` 在被拷贝资源、写入 `Info.plist` 后没有重新形成完整签名，导致下载到其他机器并触发 Gatekeeper 检查时，被判定为“已损坏”。

用户当前目标不是正式发版签名，而是先以最小改动修复“别人机器上无法安装”的问题。

## 目标

- 修复 `Scripts/build_dmg.sh` 产出的 `.app` 在其他设备上被误判为“已损坏”的问题
- 保持现有打包方式不变，仍输出 `dist/PowerShell.app` 和 `dist/PowerShell.dmg`
- 不引入 Developer ID、notarization、stapler 等正式发布流程
- 在脚本内增加本地签名验证，尽早暴露无效包
- 将改动范围限制在当前打包脚本内

## 推荐方案

采用“在 `.app` 包结构完成后执行一次完整 ad-hoc 重签名，再继续打包 DMG”的方案。

核心流程调整为：

1. 保持现有 `swift build -c release` 不变
2. 继续手工创建 `.app` 目录、拷贝可执行文件和图标、写入 `Info.plist`
3. 在 `.app` 内容全部准备完成后，对整个 `dist/PowerShell.app` 执行一次完整 ad-hoc 签名
4. 签名完成后立刻执行本地签名校验
5. 仅在校验通过时继续复制到 staging 目录并生成 DMG

这样可以保证最终进入 DMG 的 `.app` 是一个结构完整且签名与内容一致的包，而不是“二进制有签名，但 bundle 元数据未绑定”的半成品状态。

## 备选方案与取舍

### 方案 A（推荐）：最终 `.app` 完整 ad-hoc 重签名

优点：

- 改动最小，只触及 `Scripts/build_dmg.sh`
- 直接修复当前根因：bundle 内容变更后未重新签名
- 不要求证书、Apple 开发者账号或额外发布配置
- 适合先恢复团队内部分发可用性

缺点：

- 仍不是正式的 Developer ID 签名
- 其他设备首次打开时，仍可能看到“无法验证开发者”类提示
- 不等价于通过 notarization 的正式分发包

### 方案 B：尝试移除现有签名痕迹，不重新签名

优点：

- 实现表面上更少

缺点：

- 不能保证 Gatekeeper 接受最终产物
- 属于规避现象，不是修复根因
- 结果稳定性差，不适合作为团队分发方案

### 方案 C：直接补齐 Developer ID + notarization

优点：

- 能形成正式分发链路
- 用户体验最稳定

缺点：

- 超出本次最小修复范围
- 需要证书、账户和额外环境配置
- 会让当前问题修复变成发布体系建设任务

## 设计细节

### 1. `.app` 组装完成后统一签名

在 `Scripts/build_dmg.sh` 中，签名步骤应发生在以下动作之后：

- 可执行文件已复制到 `Contents/MacOS`
- 图标资源已复制到 `Contents/Resources`
- `Contents/Info.plist` 已写入完成

此时再对整个 `dist/PowerShell.app` 执行：

- `codesign --force --deep --sign - "${APP_BUNDLE}"`

这里使用 ad-hoc 身份（`-`），目的是让最终 bundle 内所有需要签名的内容与当前包结构重新对齐。

### 2. 签名后立即校验

签名完成后，脚本应立刻验证 bundle，而不是等用户在别的设备上发现问题。

推荐增加：

- `codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"`

若校验失败，脚本直接退出，不继续生成 DMG。这样可以把错误尽量前置到构建机上。

### 3. DMG 生成逻辑保持不变

本次不调整以下逻辑：

- `mktemp` staging 目录
- 将 `.app` 复制进 staging
- 创建 `/Applications` 软链
- 通过 `hdiutil create` 生成 `UDZO` 格式 DMG

也就是说，本次修复关注点是“进入 DMG 前的 `.app` 要是合法完整的 bundle”，而不是重新设计 DMG 形式。

### 4. 用户提示文案同步修正

当前脚本尾部提示 `Scripts/build_dmg.sh:82-84` 明确写着“app is not codesigned”，这会与修复后的真实行为冲突。

因此应同步更新结尾输出：

- 不再提示“未签名”
- 改为说明该包已进行本地 ad-hoc 签名
- 明确提醒：这能解决“已损坏”类问题，但仍不是 notarized 正式分发包

## 实现范围

### 受影响文件

仅修改：

- `Scripts/build_dmg.sh`

### 不改动内容

以下内容不在本次范围内：

- SPM 构建参数
- 应用代码与 Swift 源文件
- 正式证书配置
- notarization / stapler 流程
- CI 发布流程
- DMG 样式美化或 Finder 布局

## 测试与验证

### 自动化验证

脚本内需要新增并依赖以下验证步骤：

1. `.app` 完整签名后执行 `codesign --verify --deep --strict --verbose=2`
2. 若验证失败，脚本退出并返回非零状态
3. 若验证通过，再继续生成 DMG

### 手动验证

1. 运行 `./Scripts/build_dmg.sh`
2. 确认脚本输出中出现签名与验证通过信息
3. 在本机执行：
   - `codesign -dv --verbose=4 dist/PowerShell.app`
   - `codesign --verify --deep --strict --verbose=2 dist/PowerShell.app`
4. 将生成的 DMG 发到另一台机器下载后测试安装
5. 预期结果：不再出现“PowerShell.app 已损坏，无法打开”提示
6. 可接受结果：仍可能出现“无法验证开发者”，但不应再是假损坏

## 非目标

以下内容明确不在本次范围内：

- 让应用成为无提示安装的正式发行包
- 通过 Apple notarization
- 消除所有首次启动安全提示
- 支持开发者证书自动选择
- 为 CI/CD 增加发布凭据管理
