## 2026-09-28 | 任务：Markdown 代码块复制按钮

### 用户请求

给代码块右上角添加一个复制按钮，一键复制到剪切板。

### 变更

- `MarkdownRenderer` 为围栏代码块的代码文本添加 `.markdownCodeBlock` 属性，值为原始代码；
  代码块顶部内边距增加到 `codeBlockHeaderHeight`（26pt），为按钮预留位置，避免遮挡首行。
- 新增 `CodeBlockCopyButton`：点击后把原始代码写入剪贴板，图标短暂切换为对勾作为反馈。
- `MarkdownLabel` 在布局时按每个代码块的 `NSTextBlock` 实际区域，把复制按钮叠放在右上角；
  按钮随重新渲染复用，关闭 Markdown 渲染时移除。
- 新增 2 个本地化 key，覆盖 en、es、ja、sk、zh-Hans、zh-Hant。

### 设计意图

复制内容取自渲染时记录的原始代码，而不是界面上的文字，因此不受换行、字体属性或
Markdown 转义影响。按钮只是叠加视图，不改变结果文本和高度计算。

### 范围与限制

- 流式输出中未闭合的代码块也会显示按钮，复制的是当前已收到的内容。
- 未在真实应用中手动验证按钮位置与点击效果。

### 验证

- `xcodebuild build-for-testing -workspace Easydict.xcworkspace -scheme Easydict`：通过。
- `xcodebuild test-without-building`（`MarkdownRendererTests`、`ConversationTurnTests`）：
  44 个测试全部通过，其中新增 1 个代码块属性与顶部留白测试。
- `git diff --check`、`jq -e .`（`Localizable.xcstrings`）、`plutil -lint`
  （`project.pbxproj`）：通过。

### 受影响文件

- `Easydict/Swift/Feature/Markdown/MarkdownRenderer.swift`
- `Easydict/Swift/Feature/Markdown/MarkdownLabel.swift`
- `Easydict/Swift/Feature/Markdown/CodeBlockCopyButton.swift`（新增）
- `Easydict/App/Localizable.xcstrings`
- `Easydict.xcodeproj/project.pbxproj`
- `EasydictTests/Feature/Markdown/MarkdownRendererTests.swift`
- `docs/histories/2026-09/2026-09-28-code-block-copy-button.md`
