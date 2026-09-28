## 2026-09-28 | 任务：扩展翻译结果 Markdown 的表格、分隔线与 LaTeX 渲染

### 用户请求

反馈翻译结果的 Markdown 渲染存在问题，且对数学公式的 LaTeX 支持不好；随后要求继续完成该项目。

### 变更

- 识别 GFM 管道表格：表头行下方必须紧跟分隔行才进入表格，使用 `NSTextTable` 与 `NSTextTableBlock` 绘制带边框、表头底色和列对齐的原生表格。
- 识别 `---`、`***`、`___` 等分隔线，使用自绘 `NSTextAttachment` 渲染为整行宽度的细线。
- 围栏代码块改用 `NSTextBlock` 绘制连续背景，避免逐行背景色在换行时出现锯齿边缘。
- 支持 `$...$` 行内公式与 `$$ ... $$` 块级公式：先拆出公式片段再交给 Foundation 解析，避免 `x_i` 等被误识别为斜体；将希腊字母、常用运算符、箭头、集合符号、`\frac`、`\sqrt`、`\text` 系列以及上下标尽力转换为 Unicode，未知命令保留命令名。
- 采用 Pandoc 的 `$` 判定规则，`$5 and $10` 等金额不会被当作公式。
- 移除排查“侧悬浮窗口回车不查询”时在 `EZQueryView.m` 中加入的临时诊断日志；该问题已确认为本机服务配置导致，不涉及代码修改。

### 设计意图

继续由 Easydict 掌控最终视觉样式，只使用 AppKit 原生文本排版能力，不引入 WebView 或第三方 Markdown/LaTeX 依赖。表格依赖分隔行前瞻、公式块未闭合时渲染到当前末尾，从而保持流式输出安全。

### 范围与限制

LaTeX 仅为可读性降级转换，不做真正的公式排版；矩阵、多行对齐环境和图片仍不支持。

### 验证

- `xcodebuild test -workspace Easydict.xcworkspace -scheme Easydict -only-testing:EasydictTests/MarkdownRendererTests`：34 个测试全部通过。
- `git diff --check`：通过。
- `swiftformat --lint`：未执行，当前环境未安装 `swiftformat`。

### 受影响文件

- `Easydict/Swift/Feature/Markdown/MarkdownRenderer.swift`
- `EasydictTests/Feature/Markdown/MarkdownRendererTests.swift`
- `docs/histories/2026-09/2026-09-28-markdown-table-latex-rendering.md`
