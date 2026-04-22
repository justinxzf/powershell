---
name: powershell-ai-summary
description: 将当前 Claude Code session 的对话内容总结并保存为 Markdown 文档。当用户输入 /powershell-ai-summary 或要求保存/总结/导出当前对话时调用。
---

# PowerShell AI Session Summary

将当前 Claude Code 会话内容总结并保存为结构化 Markdown 文档。

## 执行步骤

1. **定位 transcript 文件**：从当前会话的 `transcript_path` 或环境变量 `CLAUDE_TRANSCRIPT_PATH` 获取 JSONL 对话记录路径

2. **读取并解析对话记录**：
   - 使用 Read 工具读取 transcript JSONL 文件
   - 解析每行 JSON，提取 `type` 为 `human` 和 `assistant` 的消息
   - 提取每条消息的文本内容、工具调用记录和文件变更

3. **生成结构化 Markdown**，包含以下章节：
   - **标题**：根据首条用户消息推断会话主题
   - **日期**：当前日期时间
   - **摘要**：1-3 句话概括本次会话的核心目标和成果
   - **详细记录**：按时间顺序列出关键对话，标注角色（用户/助手）
   - **文件变更**：列出所有被创建、修改、删除的文件及变更说明
   - **关键命令**：列出执行的重要 shell 命令

4. **保存文件**：
   - 路径：`~/Desktop/PowerShell_Session_YYYYMMDD_HHmmss.md`
   - 使用 Write 工具写入
   - 时间戳格式：20260422_143052

5. **告知用户**：用中文回复，包含文件路径和一段简短摘要

## 注意事项

- 对话内容较长时，摘要应侧重关键决策和操作，省略中间调试过程
- 代码片段仅保留最终版本，不保留迭代过程
- 如果 transcript 文件不可读，直接基于当前对话上下文生成总结
