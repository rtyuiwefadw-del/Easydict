## 2026-09-01 | 任务：复用 Foundation Markdown 解析渲染翻译结果

### 用户请求

为 Easydict 的翻译结果增加自动 Markdown 渲染，并支持全局与单条结果切换；用户偏好原生 macOS 风格，并要求尽量利用已有渲染能力。

### 变更

- 使用 macOS Foundation `AttributedString(markdown:)` 解析行内 Markdown，替代重复维护的手写行内标记扫描逻辑。
- 复用现有 `MarkdownRenderer` 的字体、颜色、代码背景、链接和段落样式，将 Foundation 的 presentation intent 映射为 AppKit 属性。
- 保留现有流式结果、全局开关、单条结果 toggle、纯文本回退和代码块/列表/引用布局。
- 增加 Foundation 转义标记回归测试。

### 设计意图

Foundation 负责 Markdown 语法识别，Easydict 继续掌控最终视觉样式，因此库的解析能力与产品的 macOS 原生视觉保持解耦。解析失败时保留可读原文，避免流式响应中的不完整标记影响结果展示。

### 范围与限制

本次仅调整翻译结果 Markdown 的行内解析；不引入新的 CocoaPods 或 Swift Package 依赖，不扩展图片、表格、LaTeX 或 WebView Markdown 渲染。

### 验证

- `swiftc -typecheck Easydict/Swift/Feature/Markdown/MarkdownRenderer.swift`：通过。
- `git diff --check`：通过。
- Foundation Markdown 行为探测：已确认粗体、斜体、组合强调、行内代码、删除线、链接和转义标记可取得预期属性。
- `swiftformat --lint`：未执行，当前环境未安装 `swiftformat`。
- `xcodebuild`：未执行，当前开发者目录为 CommandLineTools，且环境未安装完整 Xcode.app。

### 受影响文件

- `Easydict/Swift/Feature/Markdown/MarkdownRenderer.swift`
- `EasydictTests/Feature/Markdown/MarkdownRendererTests.swift`
- `docs/histories/2026-09/2026-09-01-foundation-markdown-rendering.md`
