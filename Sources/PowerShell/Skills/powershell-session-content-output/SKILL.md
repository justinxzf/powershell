---
name: powershell-session-content-output
description: 将当前 Claude Code session 中用户与 LLM 的全部对话内容以表格形式输出到文档。支持 detail 参数控制 AI 输出详细程度，支持输出到飞书文档或本地文件。当用户输入 /powershell-session-content-output 或要求导出/输出/保存原始对话记录时调用。
---

# PowerShell Session Content Output

将当前 Claude Code 会话中用户与 LLM 的全部对话内容以表格形式输出到文档。

## 参数说明

- **detail**：可选参数，控制 AI 输出的详细程度
  - **不带 detail**（默认）：AI 输出列只包含最终的文本输出，不包含过程中的分析思考和工具调用
  - **带 detail**：AI 输出列包含完整内容，包括过程中的分析思考、工具调用记录（以折叠块形式）
- **输出目标**：可传入本地路径或飞书文档链接
  - 示例：`/powershell-session-content-output detail ~/Desktop`
  - 示例：`/powershell-session-content-output https://.../docx/...`
  - 示例：`/powershell-session-content-output detail https://.../docx/...`
  - 参数顺序不敏感，skill 应自动识别哪个是 `detail`、哪个是路径/链接

## 执行步骤

1. **解析参数**：
   - 检查 skill 调用时的 `args` 参数
   - 从 args 中识别是否包含 `detail` 关键词（不区分大小写）
   - 从 args 中识别输出目标：飞书文档链接、本地路径、或为空
   - 参数顺序不敏感，`detail ~/Desktop` 和 `~/Desktop detail` 均可

2. **定位 transcript 文件**：从当前会话的 `transcript_path` 或环境变量 `CLAUDE_TRANSCRIPT_PATH` 获取 JSONL 对话记录路径

3. **读取并解析对话记录**：
   - 使用 Read 工具读取 transcript JSONL 文件
   - 如果文件较大（超过 2000 行），分批读取
   - 解析每行 JSON，提取 `type` 为 `human` 和 `assistant` 的消息
   - 提取每条消息的文本内容
   - 按对话轮次配对：一轮 = 一次用户消息 + 紧随其后的一次助手回复

4. **处理 AI 输出内容**：
   - **无 detail 模式**：
     - 只提取 assistant 消息中的纯文本输出部分
     - 过滤掉工具调用（tool_use）和工具返回结果（tool_result）
     - 过滤掉过程中的分析性文字（如"让我先读取一下文件"、"我来分析一下"等引导工具调用的过渡句）
     - 只保留最终呈现给用户的结论性文字、代码片段、方案说明等
   - **有 detail 模式**：
     - 保留 assistant 消息的完整内容
     - 工具调用以折叠块形式保留：`<details><summary>工具名称</summary>参数摘要</details>`
     - 工具返回结果也折叠，避免表格过长
     - 保留过程中的分析思考文字

5. **判断输出目标类型**：
   - 如果 args 中包含飞书文档链接（如 `https://.../docx/...`、`https://.../doc/...`、`https://.../wiki/...`），进入**在线文档输出模式**：
     - 使用 Bash 调用 `lark-cli docs +update` 写入在线文档
     - **写入前必须先用 AskUserQuestion 询问用户**采用哪种更新方式：`append` 还是 `overwrite`
     - 提问文案固定为：`检测到你传入的是飞书文档链接，对话记录要如何写入目标文档？`
     - AskUserQuestion 配置固定为单选，提供两个选项：
       - `append`：追加到文档末尾，更安全，保留原有内容
       - `overwrite`：覆盖整篇文档内容，适合重建完整记录
     - 如果用户未明确选择，不要自行决定写入模式
     - 如果是 `/wiki/` 链接，不要自行假设 token 类型；先调用 `lark-cli wiki spaces get_node --params '{"token":"wiki_token"}'` 获取真实 `obj_type` 与 `obj_token`，再按返回结果继续
     - 在线文档输出模式下，**不要生成本地 Markdown 文件**
   - 如果 args 中包含本地路径（非飞书链接、非 `detail`），将其作为本地输出目录，跳过询问
   - 如果 args 为空或只有 `detail`，使用 AskUserQuestion 询问用户：
     - 提供两个选项：「当前目录」和「桌面」，用户也可在"Other"中输入自定义路径
     - 默认使用当前工作目录（`.`）

6. **生成 Markdown 表格文档**：
   - 文档头部包含标题、日期、统计信息、模式标注
   - 核心内容以 Markdown 表格呈现，三列：`轮次` / `用户 Prompt` / `AI 输出`
   - 表格中的内容需要转义 Markdown 表格分隔符（`|` 转为 `\|`）
   - 单元格内换行使用 `<br>` 标签
   - 代码块在表格中使用行内代码（`` ` ``）或 `<pre><code>` 标签包裹
   - 如果某轮 AI 输出内容过长（超过 500 字符），截取前 500 字符并追加 `...（详见完整记录）`（仅限无 detail 模式）
   - detail 模式下不截取，完整保留

7. **保存文件**：
   - **本地输出模式**：
     - 文件名格式：`PowerShell_对话记录_YYYYMMDD.md`
     - 如果同一天已存在同名文件，追加时分：`PowerShell_对话记录_YYYYMMDD_HHmm.md`
     - 完整路径：`{输出目录}/PowerShell_对话记录_YYYYMMDD.md`
     - 使用 Write 工具写入
   - **在线文档输出模式**：
     - 将第 6 步生成的完整 Markdown 作为 `lark-cli docs +update` 的 `--markdown` 输入
     - 更新模式由用户明确选择：`append` 或 `overwrite`
     - 调用示例：`lark-cli docs +update --as user --doc "<lark_doc_url_or_token>" --mode <append|overwrite> --markdown "..."`
     - 如果返回权限错误，按 `lark-shared` 规则处理：优先提示用户补授权或重新以 `--as user` 登录

8. **告知用户**：
   - 本地输出模式：用中文回复，包含文件路径、对话轮次统计和输出模式（是否 detail）
   - 在线文档输出模式：用中文回复，包含目标文档链接/标识、采用的更新模式和对话轮次统计

## 输出格式示例

### 无 detail 模式

```markdown
# 对话记录

**日期**：2026-04-27
**统计**：共 5 轮对话
**模式**：精简（仅最终输出）

---

| 轮次 | 用户 Prompt | AI 输出 |
|:---:|-------------|---------|
| 1 | 帮我优化 NLDetector 的检测逻辑 | 分析后发现以下优化点：<br>1. 优先级判断可以简化<br>2. 正则匹配可以预编译<br>3. 中文检测可以合并到统一分支<br><br>具体修改如下：<br>`static func detect(_ input: String) -> InputType { ... }` |
| 2 | 预编译正则的性能提升有多大？ | 根据 Swift 的正则引擎实现，预编译 vs 运行时编译的性能差异大约在 3-5 倍。在高频调用场景下（如每次按键触发检测），预编译可节省约 2ms/次。 |
| 3 | 把方案落地吧 | 已完成修改：<br>- `Services/NLDetector.swift` — 预编译正则，合并中文检测分支<br>- `Tests/NLDetectorTests.swift` — 新增性能测试用例 |
```

### 有 detail 模式

```markdown
# 对话记录

**日期**：2026-04-27
**统计**：共 3 轮对话
**模式**：详细（含分析过程）

---

| 轮次 | 用户 Prompt | AI 输出 |
|:---:|-------------|---------|
| 1 | 帮我优化 NLDetector 的检测逻辑 | 我来分析当前的 NLDetector 实现，看看有哪些可以优化的地方。<br><br><details><summary>Read Services/NLDetector.swift</summary><code>{"file_path": "Services/NLDetector.swift"}</code></details><br><br>分析后发现以下优化点：<br>1. 优先级判断可以简化<br>2. 正则匹配可以预编译<br>3. 中文检测可以合并到统一分支<br><br>具体修改方案如下：<br><pre><code>static func detect(_ input: String) -> InputType {<br>    // 预编译正则...<br>}</code></pre> |
| 2 | 预编译正则的性能提升有多大？ | 我来查一下 Swift 正则引擎的相关资料。<br><br><details><summary>WebSearch "Swift regex compile performance"</summary>搜索结果摘要</details><br><br>根据 Swift 的正则引擎实现，预编译 vs 运行时编译的性能差异大约在 3-5 倍。 |
```

## 注意事项

- **表格形式输出**：核心内容必须以三列表格呈现，不要回退到旧的 `## 用户` / `## 助手` 交替格式
- **原样输出，不做总结**：与 `powershell-ai-summary` 不同，本 skill 的目的是保留对话内容，不进行提炼或精简
- **无 detail 模式下的过滤规则**：过滤掉工具调用和过渡性分析文字，只保留对用户有价值的最终结论、方案、代码。判断标准：如果一段文字的主要目的是引导下一个工具调用（如"让我先看看代码"、"我来搜索一下"），则过滤
- **代码块在表格中的处理**：短代码用行内代码，多行代码用 `<pre><code>` 标签
- **表格分隔符转义**：内容中的 `|` 必须转为 `\|`，否则会破坏表格结构
- **如果 transcript 文件不可读**，直接基于当前对话上下文输出
- **system 消息不输出**：只输出 `human` 和 `assistant` 类型的消息，过滤掉系统内部消息
