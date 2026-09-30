## 2026-09-30 | 任务：修复 DeepSeek 自定义请求地址时从云端获取模型失败

### 用户请求

在 DeepSeek 服务中填好公司内部站点的请求地址和 API Key 后，“从云端获取模型”报错
`Authentication Fails, Your api key: ****zYZl is invalid`；预期获取后模型自动出现在
支持模型列表和下拉框中。要求测试获取列表的协议、检查请求格式、编写测试复现并修复。

### 根因

`DeepSeekService` 将模型列表地址固定为 `https://api.deepseek.com/models`，忽略用户填写
的请求地址。聊天请求发往公司站点，而获取列表时却把公司内部 Key 发给 DeepSeek 官方，
官方返回认证失败。用任意无效 Key 请求官方 `/v1/models` 可得到与截图完全一致的错误文本。

### 变更

- `BaseOpenAIService` 把模型列表请求拆为可测试的 `fetchRemoteModelIDs(chatEndpoint:apiKey:)`、
  `remoteModelsURL(chatEndpoint:)`、`remoteModelsHeaders(apiKey:)` 与可覆盖的
  `remoteModelsEndpoint(forChatEndpoint:)`；发送前去除 API Key 首尾空白。
- `DeepSeekService` 仅在请求地址为 `api.deepseek.com` 时使用官方 `/models`，自定义地址
  按 OpenAI 兼容约定从 `…/chat/completions` 推导同站点的 `…/models`；移除
  `remoteModelFetchRequiresEndpoint = false`，使设置页对无效地址禁用获取按钮。
- 新增 `LocalHTTPServer` 测试辅助（仅监听 127.0.0.1），记录真实发出的请求。

### 请求格式

`GET <站点>/v1/models`，请求头 `Authorization: Bearer <key>`、`api-key: <key>`、
`Accept: application/json`，响应按 OpenAI `{"data":[{"id":…}]}` 解析。公司站点需实现
OpenAI 兼容的模型列表接口。

### 验证

- 修复前：`RemoteModelsFetchTests` 5 项中 4 项失败，其中 DeepSeek 自定义地址用例捕获到与
  截图一致的 `Authentication Fails … ****zYZl is invalid`，本地模拟站点未收到请求。
- 修复后：`RemoteModelsFetchTests`、`ConversationTurnTests`、`MarkdownRendererTests`
  共 49 个测试全部通过。
- `git diff --check`、`plutil -lint`（`project.pbxproj`）：通过。
- 公司内部站点无法从本机访问，未做真实站点联调。

### 受影响文件

- `Easydict/Swift/Service/OpenAI/BaseOpenAIService.swift`
- `Easydict/Swift/Service/DeepSeek/DeepSeekService.swift`
- `EasydictTests/Service/RemoteModelsFetchTests.swift`（新增）
- `EasydictTests/Support/LocalHTTPServer.swift`（新增）
- `Easydict.xcodeproj/project.pbxproj`
- `docs/histories/2026-09/2026-09-30-deepseek-custom-endpoint-models.md`
