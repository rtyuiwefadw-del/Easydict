## 2026-10-08 | 任务：按模型名切换 API 协议

### 用户请求

不同模型厂商的 API 格式不同，要求代码根据模型名使用不同格式。已确认：公司站点使用同一个
地址，但不同模型要求不同格式；需要支持 OpenAI Chat Completions、Anthropic Messages、
Google Gemini 和 OpenAI Responses；功能完成后与 2.22.0-ai.2 一起发布。

### 变更

- 新增 `ModelAPIProtocol`：模型名以 `claude` 开头走 Anthropic，以 `gemini` 开头走
  Gemini（支持 `anthropic/claude-…` 这类带命名空间的名称），其余走 OpenAI Chat
  Completions；`ModelProtocolRule` 解析用户规则（每行 `模型=协议`，结尾 `*` 通配），
  规则优先于自动识别，Responses 协议通过规则指定。
- 新增 `ModelAPIRequestBuilder`：从请求地址推出站点前缀，拼接 `/v1/messages`、
  `/v1beta/models/{model}:streamGenerateContent?alt=sse`、`/v1/responses`；按各协议生成
  鉴权头（`x-api-key` + `anthropic-version`、`x-goog-api-key`，并附带 Bearer）和请求体，
  系统提示、历史对话与图片按各自格式编码。
- 新增 `ModelAPIStreamParser` 与 `StreamService+ModelProtocol`：统一 SSE 流式传输，
  复用 `ClaudeSSEParser` 切分事件；Gemini 过滤思考片段；非 2xx 响应显示服务端错误信息。
- 自定义 OpenAI 与 DeepSeek 服务启用按模型名路由；设置页新增“模型协议规则”输入框。
- 新增 3 个本地化 key（6 种语言）。

### 设计意图

公司网关常保留各厂商原生接口，只靠服务类型决定格式无法在同一个服务里混用多家模型。
自动识别覆盖常见命名，规则用于不规范的模型名和 Responses 这类无法从名称推断的情况。
OpenAI Chat Completions 仍走原有路径，现有行为不变。

### 范围与限制

- 模型列表仍通过 OpenAI 兼容的 `GET /v1/models` 获取。
- DeepSeek 的推理强度参数只在 OpenAI 格式下发送。
- 公司站点无法从本机访问，各协议的真实路径和鉴权方式按官方约定实现，未做真实站点联调。

### 验证

- `xcodebuild build-for-testing -workspace Easydict.xcworkspace -scheme Easydict`：通过。
- `ModelProtocolTests`、`RemoteModelsFetchTests`、`ConversationTurnTests`、
  `MarkdownRendererTests`、`ClaudeSSEParserTests`：66 个测试全部通过，其中新增 12 个，
  包括通过本地模拟网关的三种原生协议端到端流式请求和错误透传。
- `git diff --check`、`jq -e .`、`plutil -lint`：通过。

### 受影响文件

- `Easydict/Swift/Service/ModelProtocol/`（新增）：`ModelAPIProtocol.swift`、
  `ModelAPIRequestBuilder.swift`、`ModelAPIStreamParser.swift`、
  `StreamService+ModelProtocol.swift`
- `Easydict/Swift/Service/OpenAI/StreamService.swift`、`BaseOpenAIService.swift`
- `Easydict/Swift/Service/DeepSeek/DeepSeekService.swift`
- `Easydict/Swift/Service/CustomOpenAI/CustomOpenAIService.swift`
- `Easydict/Swift/Feature/Configuration/ServiceConfigurationKey.swift`
- `Easydict/Swift/View/SettingView/Tabs/ServiceConfigurationView/StreamConfigurationView.swift`
- `Easydict/App/Localizable.xcstrings`、`Easydict.xcodeproj/project.pbxproj`
- `EasydictTests/Service/ModelProtocolTests.swift`（新增）
- `docs/exec-plans/completed/2026-10-08-model-protocol-routing.md`
