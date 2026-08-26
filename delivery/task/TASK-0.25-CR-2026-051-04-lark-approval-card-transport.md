---
spec-id: ai-first-platform
version: "0.25"
id: CR-2026-051-TASK-04
type: TASK
cr-ref: CR-2026-051
plan-ref: "change-requests/CR-2026-051/plan.md"
sdd-ref: "change-requests/CR-2026-051/sdd.md"
title: lark 传输层：APIClient 新方法 + sendCardToOpenID 提取 + 审批卡模板 + 4 个测试替身
slug: lark-approval-card-transport
status: pending
estimate: 8h
depends-on: []
created: 2026-08-25T23:20:00+08:00
---

## 任务描述

给 `lark` 包加"按 `open_id` 私聊发审批提醒卡"的能力：`APIClient` 接口加一行方法（SDD §5 DD-3），把 `SendBindingPromptCard` 与新方法共用的传输段提取为私有 helper `sendCardToOpenID`（SDD §4.5，本 CR 唯一一处改上游函数正文），卡片模板与两个实现（http / stub）全部落在自研文件。同步补齐 4 个上游测试替身的空实现——漏一个 `lark` 包整包 build 失败。

行为等价的回归锁是**既有绑定提示测试原样不改即通过**；审批卡侧另补评审强制的五类测试（SDD §4.5 表）。

## 涉及文件 / 模块

仓根取 `execution_context.resources[]` 中 `repo=multica` 的 `worktreePath`；以下为该仓根相对路径：

- `server/internal/integrations/lark/approval_reminder_card.go`（新：参数类型 + 模板 + `*httpAPIClient` 与 `*stubAPIClient` 两个方法）
- `server/internal/integrations/lark/client.go`（改：`APIClient` 接口 +1 行方法声明，带 `// AIFIRST:`；`:20` 是接口起点，`:62` 是 `SendBindingPromptCard` 声明位置的参照）
- `server/internal/integrations/lark/http_client.go`（改：`SendBindingPromptCard`（`:467-504`）传输段提取为 `sendCardToOpenID`，原函数改为调用它）
- `server/internal/integrations/lark/approval_reminder_card_test.go`（新：五类测试）
- 4 个上游测试替身各补一个空实现（每处 1 行 `// AIFIRST:`）：`outbound_test.go`（`fakeAPIClient`，`:143` 参照）、`outcome_replier_test.go`（`stubAPIClientWithRecorder`，`:73`）、`typing_indicator_test.go`（`fakeTypingAPIClient`，`:48`）、`inbound_enricher_test.go`（`enricherFakeClient`，`:98`）

零改动：`http_client_test.go`（三处既有 `SendBindingPromptCard` 断言必须原样通过）、`bindingPromptTemplate`（`http_client.go:1225`）、`SendInteractiveCard` 及 `outboundMessageRequest` 路径。

## 实现要点

1. **接口方法**（`client.go`，唯一接口面改动）：`SendApprovalReminderCard(ctx context.Context, p ApprovalReminderParams) error`。英文注释写明为何不复用 `SendInteractiveCard`（后者经 `outboundMessageRequest` 固定 `receive_id_type=chat_id`，无法寻址 open_id 私聊）与 `SendBindingPromptCard`（卡片体与 CTA 不同），并注明实现在 `approval_reminder_card.go`。
2. **参数类型**（`approval_reminder_card.go`，镜像 `BindingPromptParams`（`client.go:309-315`）的字段风格）：
   `ApprovalReminderParams{ InstallationID InstallationCredentials; OpenID OpenID; CRID string; CRTitle string; StageLabel string; ApproveURL string }`。
3. **helper 提取**（`http_client.go`）：`func (c *httpAPIClient) sendCardToOpenID(ctx context.Context, creds InstallationCredentials, openID OpenID, cardJSON, op string) error`，内容严格搬迁 `SendBindingPromptCard` 的 `:478-503` 段：`tenantAccessToken(ctx, creds)` → `url.Values{receive_id_type: open_id}` → body `{receive_id, msg_type: "interactive", content: cardJSON}` → `doJSON(ctx, c.resolveBaseURL(creds), http.MethodPost, "/open-apis/im/v1/messages?"+q.Encode(), token, body, &resp)` → `resp.Code != 0` 时 `isTokenError(resp.Code)` 触发 `c.invalidateToken(creds.AppID)` 并返错。`op` 只用于错误信息前缀（`send binding prompt` / `send approval reminder`），**不得**改变既有错误串的可断言部分：`SendBindingPromptCard` 的错误仍需包含 `code=<n>` 且既有测试断言（`code=230002`、`code=99991663`）原样通过。
4. **`SendBindingPromptCard` 改造后仅剩**：两条参数校验（`open_id` / `bind url`，错误串不变）→ `bindingPromptTemplate(p.BindURL)` → `return c.sendCardToOpenID(ctx, p.InstallationID, p.OpenID, cardJSON, "send binding prompt")`。带 `// AIFIRST: CR-2026-051 FR-9` 注释说明这是唯一一处上游正文改动及其回归锁。
5. **模板** `func approvalReminderTemplate(p ApprovalReminderParams) (string, error)`：与 `bindingPromptTemplate` 同款——用 `map[string]any` + `json.Marshal`（**禁止字符串拼接**，保证标题里的引号/反斜杠/换行/emoji 自动转义）。内容严格限于 FR-6 五项：header 标题 `待人工审批`；CR ID（`CRTitle` 为空时只渲染 ID，不留空行）；阶段名（`StageLabel` 原样，映射由调用方负责）；一句固定说明；单一 `url` 类型 button `前往审批` 指向 `ApproveURL`。**不得**出现 approve/reject action、callback、token、审批证据、diff。
6. **http 实现**：先校验 `OpenID == ""` 与 `ApproveURL == ""`（各返回可断言错误、零 HTTP），再渲染模板，再调 `sendCardToOpenID(..., "send approval reminder")`。
7. **stub 实现**：`func (s *stubAPIClient) SendApprovalReminderCard(ctx context.Context, p ApprovalReminderParams) error` → `s.log.Warn("lark stub client: SendApprovalReminderCard called", "open_id", string(p.OpenID))` + `return ErrAPIClientNotConfigured`，与 `client.go:409-413` 的既有 stub 同款，零 HTTP。
8. **五类测试**（`approval_reminder_card_test.go`，复用同包既有设施 `newLarkFake(t)`、`fake.stubToken(...)`、`newTestClient(fake, time.Now)`、`testCreds()`、`writeJSON`、`fake.tokenN`）：① 参数校验（缺 `OpenID` / 缺 `ApproveURL` 各返错且 `fake.tokenN == 0`、无请求到 `/open-apis/im/v1/messages`）；② 成功路径（打到 `/open-apis/im/v1/messages`、`receive_id_type=open_id`、`receive_id == open_id`、`msg_type=interactive`、`content` 可 `json.Unmarshal` 且含五项最小内容与 CTA URL）；③ token 失效（首次响应 `code=99991663` → 断言 `invalidateToken` 生效：第二次调用重新取 token，`fake.tokenN` 从 1 变 2，参照 `http_client_test.go:885-900` 的既有形态）；④ JSON 转义（`CRTitle` 含 `"`、`\`、`\n`、emoji，断言卡片 JSON 可回解且文本无损）；⑤ stub 形态（`NewStubAPIClient` 返回 `ErrAPIClientNotConfigured`、`IsConfigured() == false`、零 HTTP）。
9. 注释与测试注释英文；不新增包级可变全局状态。

## 验收条件

1. `cd server && go build ./... && go vet ./internal/integrations/lark/` 零报告（4 个替身补齐的直接证据：漏一个则整包 build 失败）。
2. `go test ./internal/integrations/lark/ -run 'ApprovalReminderCard' -v -count=1` 五类测试全部 `--- PASS`。
3. **行为等价回归**：`go test ./internal/integrations/lark/ -run 'TestHTTPClient_SendBindingPromptCard_HappyPath|TestHTTPClient_BindingPromptValidation|TestHTTPClient_Send' -v -count=1` 全部 `--- PASS`，且 `git diff --name-only` 不包含 `http_client_test.go`（既有断言一行未改）。
4. `grep -n "receive_id_type" server/internal/integrations/lark/http_client.go` 中 open_id 私聊路径只剩 helper 一处（提取彻底，无残留重复段）。
5. `go test ./internal/integrations/lark/ -count=1` 整包通过（对照 CUSTOM.md「已知测试失败基线」排除既有失败）。

## 完成标志

上述 5 条全通过；`git diff --stat` 显示 `client.go` 仅 +1 方法声明及注释、`http_client.go` 为 helper 提取（净增行数 < 30）、4 个测试替身各 +1 空实现；`crctl task done CR-2026-051 --task CR-2026-051-TASK-04 --workspace <kb worktree>` 已登记。若第 3 条需要改既有测试才能过 ⇒ 判定行为不等价，按 plan.md §4 回滚 helper 提取并改走自持传输段方案（须在本 TASK 内决策，不得带入下游）。

## 接口契约

- **消费**（既有符号，签名原样）：`APIClient` 接口（`client.go:20`）、`InstallationCredentials`（`client.go:341`）、`OpenID`（`ids.go`）、`ErrAPIClientNotConfigured`、`stubAPIClient`（`client.go:371`）、`httpAPIClient` 的私有方法 `tenantAccessToken(ctx, creds) (string, error)`（`:189`）、`resolveBaseURL(creds) string`（`:248`）、`invalidateToken(appID string)`（`:258`）、`doJSON(ctx, baseURL, method, path, token string, body, out any) error`（`:1116`）、`isTokenError(code int) bool`（`:1155`）、`bindingPromptTemplate(bindURL string) (string, error)`（`:1225`）。
- **产出**（TASK-05/TASK-06 直接引用，不得改名或加参数）：
  - `type lark.ApprovalReminderParams struct { InstallationID InstallationCredentials; OpenID OpenID; CRID string; CRTitle string; StageLabel string; ApproveURL string }`；
  - 接口方法 `SendApprovalReminderCard(ctx context.Context, p ApprovalReminderParams) error`（`APIClient` 上，两实现俱备）；
  - 包内私有 `approvalReminderTemplate(p ApprovalReminderParams) (string, error)`、`(*httpAPIClient).sendCardToOpenID(ctx context.Context, creds InstallationCredentials, openID OpenID, cardJSON, op string) error`。
  - TASK-06 的调用形态固定为：`r.client.SendApprovalReminderCard(rctx, ApprovalReminderParams{InstallationID: creds, OpenID: pick.OpenID, CRID: p.CRID, CRTitle: title, StageLabel: stageLabel(p.Status), ApproveURL: approveURL})`。
