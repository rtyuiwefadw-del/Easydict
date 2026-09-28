## 2026-09-28 | 任务：AI 结果追问与图片输入

### 用户请求

项目只支持一问一答，希望加按钮在当前回答基础上追问；支持发送图片，包括带快捷键的
截图（截图后弹出侧悬浮窗口、图片自动放进输入框）和聊天过程中上传或粘贴图片。
用户把 Easydict 当作随时呼出的 AI 助手二次开发。

### 变更

- 追问：AI（`StreamService`）结果卡片新增“追问”按钮。点击后输入框顶部显示
  “追问：服务名”标签，回车只发给该服务，并携带上一轮完整消息与回答作为上下文；
  回答以分隔线加引用问题的形式追加在同一张卡片中。可点标签上的关闭按钮、清空全部
  或发起普通查询退出追问。
- 对话上下文：`StreamService` 在 `streamTranslate` 开始时记录本轮
  （`ConversationTurn`），完成或中途停止时保存消息和转录；普通查询开始新对话。
  追问请求使用 `QueryModel` 副本，避免清空输入框与异步请求竞争。
- 图片输入：`ChatMessage` 增加 `imageURLs`；图片缩放到长边 2048px 以内并编码为
  JPEG `data:` URL。OpenAI 兼容服务（含 DeepSeek）按 `image_url` 多模态格式发送；
  其他服务收到图片时提示不支持。带图查询只发给支持图片的服务，使用助手式系统提示词
  （启用自定义提示词时沿用用户的系统提示词），不使用翻译 few-shot；无文字时使用默认问题。
- 输入框：顶部附件栏显示缩略图（最多 4 张，可逐个移除）；新增图片按钮；粘贴图片文件
  或截图数据时作为附件，剪贴板含文字时仍按文字粘贴。追问模式或带图时不触发
  “输入时自动查询”。
- 截图问 AI：新增全局快捷键 `ShortcutAction.screenshotAskAI`（默认不绑定，在设置中
  配置），截图后打开侧悬浮窗口并附上图片，等待输入问题后回车发送；原 OCR 截图不变。
  菜单栏也新增对应入口。
- DeepSeek 非 2xx 响应改为显示服务端错误信息，便于识别模型不支持图片等问题。
- 新增 15 个本地化 key，覆盖 en、es、ja、sk、zh-Hans、zh-Hant。

### 设计意图

追问复用顶部输入框，改动集中且符合“随手呼出”的使用方式；上下文保存在服务实例上，
不同服务的对话互不干扰。图片按通用 OpenAI 格式发送，是否可用由所配置模型决定。

### 范围与限制

- Claude、Gemini、CLI 类服务暂不支持图片；拖拽图片、对话持久化未实现。
- 带图普通查询发送后图片保留在输入框（与文字一致），需要手动移除或清空。
- DeepSeek 官方 API 是否接受图片未核实，不支持时会显示服务端错误。

### 验证

- `xcodebuild build-for-testing -workspace Easydict.xcworkspace -scheme Easydict`：通过。
- `xcodebuild test-without-building`（`ConversationTurnTests`、`MarkdownRendererTests`、
  `ClaudeSSEParserTests`）：48 个测试全部通过，其中新增 9 个。
- `git diff --check`、`jq -e .`（`Localizable.xcstrings`）、`plutil -lint`
  （`project.pbxproj`）：通过。
- 构建阶段的 SwiftFormat 已格式化改动文件。
- 未在真实应用中手动验证界面交互；未运行完整测试集。

### 受影响文件

- `Easydict/Swift/Service/OpenAI/`：`ChatMessage.swift`、`StreamService.swift`、
  `StreamService+AsyncStream.swift`、`StreamService+Conversation.swift`（新增）、
  `BaseOpenAIService.swift`
- `Easydict/Swift/Service/DeepSeek/DeepSeekService.swift`
- `Easydict/Swift/Model/QueryModel.swift`
- `Easydict/Swift/Feature/Conversation/`（新增）：`FollowUpButton.swift`、
  `QueryAccessoryView.swift`、`ChatImageLoader.swift`
- `Easydict/Swift/Feature/Shortcut/Model/ShortcutAction.swift`、
  `Easydict/Swift/Feature/Shortcut/View/KeyHolderWrapper.swift`、
  `Easydict/Swift/Feature/Configuration/Defaults.Keys+Extension.swift`、
  `Easydict/Swift/View/MenuItemView.swift`
- `Easydict/objc/ViewController/`：`EZQueryView`、`EZTextView`、`EZWordResultView.m`、
  `EZBaseQueryViewController`、`EZWindowManager`
- `Easydict/App/Localizable.xcstrings`、`Easydict.xcodeproj/project.pbxproj`
- `EasydictTests/Feature/Conversation/ConversationTurnTests.swift`（新增）
- `docs/exec-plans/active/2026-09-28-ai-follow-up-and-image-input.md`
