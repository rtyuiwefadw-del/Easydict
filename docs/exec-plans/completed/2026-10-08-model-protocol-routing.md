# 按模型名切换 API 协议

- 状态：completed
- 创建日期：2026-10-08
- 负责人：wangjiapeng
- 关联 Issue/PR：none

## 背景

用户的公司站点用同一个地址提供多家厂商的模型，但不同模型要求不同的请求格式。
当前 Easydict 的请求格式由服务类型固定（DeepSeek/自定义 OpenAI 只发 OpenAI Chat
Completions），无法用同一个服务调用 Claude、Gemini 等原生格式的模型。

## 任务摘要

- 意图模式：implementation
- 交付授权：auto-local-commit；完成后与已构建的 2.22.0-ai.2 改动一起发布（用户要求暂停发布等待本功能）
- 安全状态：normal
- 目标结果：自定义 OpenAI 与 DeepSeek 服务按模型名选择 OpenAI Chat Completions、
  Anthropic Messages、Google Gemini 或 OpenAI Responses 协议发送请求。
- 允许修改路径：`Easydict/Swift/Service/ModelProtocol/`（新增）、
  `Easydict/Swift/Service/OpenAI/`、`Easydict/Swift/Service/DeepSeek/`、
  `Easydict/Swift/Service/CustomOpenAI/`、
  `Easydict/Swift/Feature/Configuration/ServiceConfigurationKey.swift`、
  `Easydict/Swift/View/SettingView/Tabs/ServiceConfigurationView/StreamConfigurationView.swift`、
  `Easydict/App/Localizable.xcstrings`、`Easydict.xcodeproj/project.pbxproj`、
  `EasydictTests/Service/`、`EasydictTests/Support/`、本计划与同任务 history。
- 同任务 history：`docs/histories/2026-10/2026-10-08-model-protocol-routing.md`
- 禁止动作：push、pull、rebase、merge（发布阶段另行按用户要求执行）。

## 语义与范围

- 已确认：同一地址、不同模型不同格式；需要支持 OpenAI Chat Completions、
  Anthropic Messages、Google Gemini、OpenAI Responses。
- 歧义：公司站点各协议的具体路径与鉴权头未知，按各厂商官方约定实现，并允许用户用
  规则覆盖自动识别。

## 写入前状态

- 写入前检查：pass
- 自动提交资格：eligible
- 初始 HEAD：`04a44b3d`
- 初始 staged 路径：无
- 初始 unstaged 路径：`.claude/settings.local.json`（与任务无关，保留）
- 初始 untracked 路径：无
- 初始冲突：无

## 设计

- 协议识别：模型名以 `claude` 开头 → Anthropic；以 `gemini` 开头 → Gemini；其余 →
  OpenAI Chat Completions。用户可在设置中填写 `模式=协议` 规则（支持结尾 `*` 通配）
  覆盖自动识别，Responses 协议通过规则指定。
- 地址推导：从请求地址去掉 `…/chat/completions` 与末尾 `v1` 得到站点前缀，再拼接
  `/v1/messages`、`/v1beta/models/{model}:streamGenerateContent?alt=sse`、`/v1/responses`；
  OpenAI Chat Completions 仍用原地址。
- 鉴权：OpenAI/Responses 用 `Authorization: Bearer`；Anthropic 用 `x-api-key` +
  `anthropic-version`，并附带 Bearer；Gemini 用 `x-goog-api-key`，并附带 Bearer。
- 消息：复用 `chatMessageDicts`，追问上下文与图片在四种协议中都按各自格式编码。
- 流式：统一用 SSE 解析，事件切分复用 `ClaudeSSEParser`。

## 工作计划

1. 协议枚举、识别与规则解析。
2. 请求构造（地址、请求头、各协议请求体）。
3. 流式事件解析与错误信息提取。
4. 服务接入（自定义 OpenAI、DeepSeek）与设置界面规则输入框。
5. 本地化、工程登记、单元测试（含本地模拟站点端到端）。
6. 构建、测试、history、提交；之后与 ai.2 改动一起发布。

## 进度

- [x] 1–5 完成
- [ ] 6 发布（与 ai.2 改动一起，按用户要求执行）

## 验证

- 构建通过；5 个相关测试套件共 66 个测试通过，其中新增 12 个。
- `git diff --check`、`jq -e .`、`plutil -lint`：通过。
- 未与公司真实站点联调。

## 完成条件

- 构建通过，新增与相关测试通过；history 完整；计划移入 `completed/`。
