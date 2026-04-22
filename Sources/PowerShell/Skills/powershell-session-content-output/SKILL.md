---
name: powershell-session-content-output
description: 将当前 Claude Code session 中用户与 LLM 的全部对话内容原样输出到文档。当用户输入 /powershell-session-content-output 或要求导出/输出/保存原始对话记录时调用。
---

# PowerShell Session Content Output

将当前 Claude Code 会话中用户与 LLM 的全部对话内容原样输出到 Markdown 文档，不做总结或精简。

## 执行步骤

1. **定位 transcript 文件**：从当前会话的 `transcript_path` 或环境变量 `CLAUDE_TRANSCRIPT_PATH` 获取 JSONL 对话记录路径

2. **读取并解析对话记录**：
   - 使用 Read 工具读取 transcript JSONL 文件
   - 如果文件较大（超过 2000 行），分批读取
   - 解析每行 JSON，提取 `type` 为 `human` 和 `assistant` 的消息
   - 提取每条消息的文本内容

3. **确认输出目录**：
   - 检查 skill 调用时的 `args` 参数
   - 如果 args 非空（如 `/powershell-session-content-output ~/Desktop`），将其作为输出目录，跳过询问
   - 如果 args 为空，使用 AskUserQuestion 询问用户：
     - 提供两个选项：「当前目录」和「桌面」，用户也可在"Other"中输入自定义路径
     - 默认使用当前工作目录（`.`）

4. **生成 Markdown 文档**：
   - 按对话时间顺序，逐轮输出用户消息和 LLM 回复
   - 用户消息以 `## 👤 用户` 标记
   - LLM 回复以 `## 🤖 助手` 标记
   - 工具调用记录以折叠块形式保留，标注工具名称和输入参数摘要
   - 工具返回结果默认折叠（使用 `<details>` 标签），避免文档过长
   - 保留代码块、链接、列表等原始格式，不做改写

5. **保存文件**：
   - 文件名格式：`PowerShell_对话记录_YYYYMMDD.md`
   - 如果同一天已存在同名文件，追加时分：`PowerShell_对话记录_YYYYMMDD_HHmm.md`
   - 完整路径：`{输出目录}/PowerShell_对话记录_YYYYMMDD.md`
   - 使用 Write 工具写入

6. **告知用户**：用中文回复，包含文件路径和对话轮次统计（如"共 15 轮对话"）

## 输出格式示例

```markdown
# 对话记录

**日期**：2026-04-23
**统计**：共 8 轮对话

---

## 👤 用户

帮我优化 NLDetector 的检测逻辑

## 🤖 助手

我来分析当前的 NLDetector 实现，看看有哪些可以优化的地方。

首先读取一下当前的代码：

<details>
<summary>🔧 Read NLDetector.swift</summary>

```json
{"file_path": "Services/NLDetector.swift"}
```

</details>

分析后发现以下几个优化点：

1. 优先级判断可以简化
2. 正则匹配可以预编译
3. 中文检测可以合并到统一分支

具体修改方案如下：

```swift
// 修改后的代码
static func detect(_ input: String) -> InputType {
    // 预编译正则...
}
```

## 👤 用户

预编译正则的性能提升有多大？

## 🤖 助手

根据 Swift 的正则引擎实现，预编译 vs 运行时编译的性能差异大约在...

---

（后续轮次以此类推）
```

## 注意事项

- **原样输出，不做总结**：与 `powershell-ai-summary` 不同，本 skill 的目的是保留完整对话内容，不进行提炼或精简
- **工具调用保留但折叠**：工具调用是对话的一部分，应保留以保持完整性，但工具返回结果用 `<details>` 折叠避免文档过长
- **代码块保持原格式**：对话中的代码片段保持原始格式和语言标注，不做修改
- **如果 transcript 文件不可读**，直接基于当前对话上下文输出
- **system 消息不输出**：只输出 `human` 和 `assistant` 类型的消息，过滤掉系统内部消息
