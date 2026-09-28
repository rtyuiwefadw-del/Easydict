# AI 结果追问与图片输入

- 状态：active
- 创建日期：2026-09-28
- 负责人：wangjiapeng
- 关联 Issue/PR：none

## 背景

用户在二次开发 Easydict，把它当作随时呼出的 AI 助手使用。当前 AI 服务只能一问一答，
每次查询都会重置结果；也只能发送文本，截图只能走 OCR 转文字。

## 任务摘要

- 意图模式：implementation
- 交付授权：auto-local-commit（本机 `.claude/settings.local.json` 禁止 `git add`，
  实际无法自动暂存，完成后交由用户暂存）
- 安全状态：normal
- 目标结果：AI 结果卡片支持在当前回答基础上追问；输入框支持附带图片，
  新增“截图问 AI”快捷键。
- 允许修改路径：`Easydict/Swift/Service/OpenAI/`、`Easydict/Swift/Service/DeepSeek/`、
  `Easydict/Swift/Service/Model/QueryService.swift`、`Easydict/Swift/Model/QueryModel.swift`、
  `Easydict/Swift/Feature/Conversation/`（新增）、`Easydict/Swift/Feature/Shortcut/`、
  `Easydict/Swift/Feature/Configuration/Defaults.Keys+Extension.swift`、
  `Easydict/Swift/View/MenuItemView.swift`、`Easydict/objc/ViewController/`、
  `Easydict/App/Localizable.xcstrings`、`Easydict.xcodeproj/project.pbxproj`、
  `EasydictTests/Feature/Conversation/`（新增）、本计划与同任务 history。
- 同任务 history：`docs/histories/2026-09/2026-09-28-ai-follow-up-and-image-input.md`
- 禁止动作：push、pull、rebase、merge；改动与本任务无关的既有未提交文件。
- 预期交付物：源码、单元测试、本地化、计划与 history。
- 验收标准：见“完成条件”。

## 语义与范围

- 用户要求 Agent 做什么：修改（新增两个功能）。
- 已确认的交互决策：
  - 追问：结果卡片增加“追问”按钮，复用顶部输入框，只发给该服务并携带上下文，
    卡片内按轮次展示问答。
  - 截图：新增独立快捷键“截图问 AI”，保留原 OCR；截图后弹出侧悬浮窗口，
    图片放入输入框，等待用户输入问题后回车发送。
  - 图片格式：凡 OpenAI 兼容服务（含 DeepSeek）都按 `image_url` 多模态格式发送，
    模型不支持时显示服务端错误。
- 歧义：DeepSeek 当前 API 是否支持图片未能核实，按通用格式发送。

## 写入前状态

- 写入前检查：pass
- 自动提交资格：disabled（`git add` 被本机权限设置禁止）
- 初始 HEAD：`377736b2`
- 初始 staged 路径：无
- 初始 unstaged 路径：`.claude/settings.local.json`、
  `Easydict/Swift/Feature/Markdown/MarkdownRenderer.swift`、
  `EasydictTests/Feature/Markdown/MarkdownRendererTests.swift`（上一任务，未提交）
- 初始 untracked 路径：`docs/histories/2026-09/2026-09-28-markdown-table-latex-rendering.md`
- 初始冲突：无
- Agent-owned paths：允许修改路径中本任务实际改动的文件。

## 目标与非目标

### 目标

- LLM 服务（`StreamService` 子类）的结果卡片出现“追问”按钮；进入追问模式后，
  输入框显示追问对象，回车只向该服务发送，并携带此前的完整消息上下文。
- 追问回答以 Markdown 分隔线和引用的形式追加在同一张卡片内。
- 输入框可粘贴图片、通过按钮选择图片文件，并以缩略图展示、可逐个移除。
- 带图片的查询只发给支持图片的服务，使用助手式提示词而非翻译提示词。
- 新增全局快捷键“截图问 AI”，截图后打开侧悬浮窗口并附上图片。

### 非目标

- Claude、Gemini、CLI 类服务的图片输入（收到图片时提示不支持）。
- 拖拽图片、对话持久化、多服务同时追问。

## 工作计划

1. 服务层：`ChatMessage` 增加图片；`StreamService` 保存对话上下文并在
   `streamTranslate` 中拼接展示文本；OpenAI 兼容与 DeepSeek 编码多模态消息。
2. 模型层：`QueryModel` 增加附件图片，`copy` 同步。
3. UI：输入框附件栏（追问标签 + 缩略图 + 移除）、图片按钮与粘贴；结果卡片追问按钮。
4. 控制器：追问模式状态、定向发送、带图查询的服务过滤、空文本默认提问。
5. 快捷键：`ShortcutAction.screenshotAskAI`、Defaults key、设置映射、菜单项。
6. 本地化、Xcode 工程登记、单元测试、构建与测试验证。

## 风险与决策

- `startQueryStream` 在异步 Task 中读取 `queryModel.queryText`，追问发送后立即清空
  输入框会产生竞争，因此追问请求使用 `QueryModel` 的副本。
- 追问模式和带图输入下禁用“输入时自动查询”，避免半句话被发出。
- 图片统一缩放到长边 2048px 以内并编码为 JPEG data URL，控制请求体积。

## 进度

- [x] 服务层
- [x] 模型层
- [x] UI
- [x] 控制器
- [x] 快捷键
- [x] 本地化、工程登记、测试、验证
- [ ] 在真实应用中手动验证追问、粘贴/选择图片、截图问 AI

## 验证

- `xcodebuild build-for-testing`：通过；首轮因 `photoBadgePlus` 需 macOS 14 失败，
  改用 `photo` 后通过。
- `ConversationTurnTests`、`MarkdownRendererTests`、`ClaudeSSEParserTests`：48 个测试通过。
- `git diff --check`、`jq -e .`、`plutil -lint`：通过。
- 自动提交未执行：本机设置禁止 `git add`。
- 待办：安装后手动验证界面；调试版为 adhoc 签名，重新安装会使辅助功能与屏幕录制
  授权失效，需要用户重新授权。

## 完成条件

- 构建通过，新增与相关既有单元测试通过。
- history 记录变更、验证与限制；计划移入 `completed/`。
