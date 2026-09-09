---
id: CR-2026-061-TASK-04
type: TASK
cr-ref: CR-2026-061
plan-ref: "change-requests/CR-2026-061/plan.md"
sdd-ref: "change-requests/CR-2026-061/sdd.md"
target-version: 0.34
title: 前端升级入口与 tools requirement-register 绑定协同
slug: frontend-promotion-ui-and-tools-register-bind
status: pending
estimate: 16h
depends-on: ["CR-2026-061-TASK-03"]
created: 2026-09-08T12:04:37+08:00
---

## 1. 任务描述

双仓收尾：multica 前端消费 TASK-03 冻结的契约（client 方法、schemas、discussion-pane 两个升级入口、Issue 详情来源入口、四语文案），tools 仓 requirement-register SKILL 增加 promotion 绑定步骤（AC-13 消费面）与集成测试。不改任何后端、不改 crctl。

输入：已审批 SDD v1.1 §3.4/§6.1 FR-9/FR-11/§6.2 AC-7/AC-9/AC-12/§9 scope_in（tools 部分）+ TASK-03 契约冻结。

## 2. 涉及文件 / 模块

multica（CR worktree `…\.rayai-worktrees\multica\requirement\CR-2026-061`）：
- `packages/core/api/client.ts`（新增 `promoteDiscussion`；Idempotency-Key 客户端强制，同 `mergeForwardDiscussion` 模式）
- `packages/core/api/schemas.ts`（`PromotionResultSchema` + `IssueSchema.context_refs` 数组 fallback）
- `packages/core/api/client.test.ts`、`packages/core/api/schemas.test.ts`（malformed-response 测试）
- `packages/views/projects/components/discussion-pane.tsx`（多选消息+附件；「转为工作 Issue」「升级为 CR」两入口；结果链接；失败保留选择可重试；复用 merge-forward 多选状态与错误分支模式）
- `packages/views/projects/components/discussion-pane.test.tsx`（新增用例）
- `packages/views/issues/components/issue-detail.tsx`（「来自 Discussion」来源入口，跳回 DiscussionPane 定位 session）
- `packages/views/locales/{en,ja,ko,zh-Hans}.json`（新 key 四语对称）+ `packages/views/locales/parity.test.ts` 全绿

tools（CR worktree `…\.rayai-worktrees\tools\requirement\CR-2026-061`）：
- `skills/requirement/requirement-register/SKILL.md`（promotion 上下文与绑定步骤，见 §3）
- `skills/requirement/requirement-register/scripts/test/promotion-bind.test.mjs`（新建集成测试，node --test）

## 3. 实现要点（SDD 对应节）

- **client（§3.1 消费面）**：`promoteDiscussion(projectId, body, idempotencyKey)` → `POST /api/projects/{projectId}/discussion/promote`，必填 `Idempotency-Key`（客户端生成 UUID）；返回 `PromotionResult`（`run_id: string | null`）。
- **schemas（§3.4）**：`PromotionResultSchema = z.object({ issue_id: uuidSchema, issue_number: z.number(), session_id: uuidSchema, source_refs: z.object({ session_id, message_ids: z.array(uuid), attachment_ids: z.array(uuid) }), created: z.boolean(), upgrade_to_cr: z.boolean(), run_id: z.union([uuid, z.null()]) })`；`IssueSchema` 增 `context_refs: z.array(IssueContextRefSchema).catch([])`（旧后端缺字段回退空数组）；走 `parseWithFallback` + malformed 测试（CLAUDE.md API Compatibility）。
- **discussion-pane（FR-11/AC-9）**：入口渲染不依赖 `coordinator_agent_id` 非空（纯人类 Discussion 可用）；成功后展示目标 Issue 链接、Discussion 内容不重载；失败按错误闭包表恢复动作（保留选择/换 key/原 key 重试），不吞错误。
- **issue-detail 来源入口（FR-9/AC-7 前端面）**：`context_refs` 含 `kind='discussion_promotion'` 条目时展示「来自 Discussion」入口，点击跳回 Discussion 并定位 `session_id`。
- **locales（AC-12）**：新 UI key en/ja/ko/zh-Hans 对称；不改既有 key；parity.test.ts 全绿。
- **tools SKILL（AC-13 消费面，§9 scope_in）**：
  - 可选输入：promotion 上下文（`issue_id` + `run_id`，来自升级响应与目标 Issue `context_refs` 条目）；**缺失时按普通注册处理，不定位不绑定，行为不变**；
  - 绑定步骤：`crctl register` 成功拿到 CR-ID 后执行 `multica cr bind-promotion-run {cr_id} --run-id {run_id}`；
  - 绑定失败（404/409/401/500 任一）→ **注册按技术失败停止**并报错，可经 `registration_key` 幂等重试；
  - **硬不变量**：绑定完成前该 CR 不得推进到 `requirement-reviewing`（SDD §4.5 护栏）；
  - 绑定幂等：同 run+同 CR 重放 changed=false 视为成功；异 CR 409 `RUN_CR_CONFLICT` 报错停止。
- **tools 集成测试（§14.3）**：promotion-bind.test.mjs 用受控夹具（PATH 前置的 fake `multica` 可执行文件或注入脚本）断言：① 有 promotion 上下文 → register 成功后调用绑定命令且参数为 `{cr_id} --run-id {run_id}`；② 绑定失败 → 测试断言注册流程技术失败停止且输出含幂等重试指引；③ 无 promotion 上下文 → 不调用绑定（普通注册行为不变）；④ SKILL.md 文本含「绑定完成前不得推进 requirement-reviewing」硬不变量。
- **lint（cmd-06）**：`node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` 零 CONTRADICTS/STALE-REF（SKILL.md 新增内容不得引入 crctl 已接管的手写操作回退）。

## 4. 验收条件

1. `pnpm test`（packages/views）：discussion-pane 多选/两入口/成功链接/失败保留选择用例全绿（AC-9）；issue-detail 来源入口用例全绿（AC-7 前端面）；locales parity.test.ts 全绿（AC-12）。
2. `pnpm test`（packages/core）：client.test.ts 断言 `promoteDiscussion` 携带 `Idempotency-Key` 与请求形状；schemas malformed-response/fallback 用例全绿（AC-7 client 面）。
3. `node --test skills/requirement/requirement-register/scripts/test/promotion-bind.test.mjs` 全绿（AC-13 tools 面，见 §3 四条断言）。
4. `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` 零退出（cmd-06）。

## 5. 完成标志

- 上述 4 条全部通过；`pnpm typecheck`（core/views）零报错；
- multica 与 tools 各自提交落盘对应 CR 分支（独立 commit，可分别 revert）；
- cmd-03 / cmd-04 / cmd-05 / cmd-06 四条证据命令全部先行跑通。

## 6. 接口契约

**消费**（TASK-03 产出，逐字对齐）：

```text
POST /api/projects/{projectId}/discussion/promote
  201 {"issue_id","issue_number","session_id","source_refs":{"session_id","message_ids","attachment_ids"},"created","upgrade_to_cr","run_id"}
  错误体 {"code","error"}：400 invalid_request_body|invalid_project_id|invalid_promotion_selection|invalid_promotion_title|invalid_promotion_description|idempotency_key_required|invalid_idempotency_key；403 forbidden_promotion；404 project_not_found|chat_session_not_found；409 idempotency_key_reused；500 internal_error；502 pipeline_run_create_failed
GET issue 响应 "context_refs": [{"kind","session_id","message_ids","attachment_ids","pipeline_run_id","promoted_by","promoted_at"}]
multica cr bind-promotion-run <cr-id> --run-id <uuid>（200 {"cr_id","run_id","issue_id","changed"}；错误体 {"error":"<code>"}）
```

**产出**（本 TASK 内部与下游交付，逐字对齐 SDD）：

```ts
// packages/core/api/client.ts
async promoteDiscussion(
  projectId: string,
  body: { session_id: string; message_ids?: string[]; attachment_ids?: string[]; title?: string; description?: string; upgrade_to_cr?: boolean },
  idempotencyKey: string,          // 必填；≤255B；客户端生成
): Promise<PromotionResult>

// packages/core/api/schemas.ts
export const PromotionResultSchema = z.object({
  issue_id: uuidSchema, issue_number: z.number(), session_id: uuidSchema,
  source_refs: z.object({ session_id: uuidSchema, message_ids: z.array(uuidSchema), attachment_ids: z.array(uuidSchema) }),
  created: z.boolean(), upgrade_to_cr: z.boolean(), run_id: z.union([uuidSchema, z.null()]),
});
export const IssueContextRefSchema = z.object({
  kind: z.string().optional(), session_id: uuidSchema.optional(),
  message_ids: z.array(uuidSchema).optional(), attachment_ids: z.array(uuidSchema).optional(),
  pipeline_run_id: uuidSchema.optional(), promoted_by: uuidSchema.optional(), promoted_at: z.string().optional(),
});
// IssueSchema 增 context_refs: z.array(IssueContextRefSchema).catch([])
```

- tools SKILL 的 promotion 上下文字段名：`issue_id` / `run_id`（可选输入）；绑定命令调用形态 `multica cr bind-promotion-run {cr_id} --run-id {run_id}`；失败语义与重试口径如 §3 所列（与本 TASK 测试夹具断言一致）。
- 不引入任何 crctl 命令面改动；`crctl register` 深原语零改动（SDD §8/§9 scope_out）。
