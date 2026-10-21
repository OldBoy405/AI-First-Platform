# Gate 2 冲突裁决矩阵

> 变更：`2026-10-20-upstream-sync-4efd5062c9`
> 窗口：`e0f84dda4..4efd5062c9`（101 提交）
> 状态：Gate 2 草案，未确认；merge 未执行

## 1. 规则

- 文件级处置按 CUSTOM 四类口径：上游胜出 / 重新摘除 / 取并集 / 贴回挂钩。
- 生成物不按四类：丢弃冲突块，重跑生成器。
- 迁移号不是文件名冲突：上游 565–584 与 fork 565–621 重叠，fork 整体 +20 → 585–641。
- 同一文件可按 hunk 拆分处置；`分半` 表示两类并存。
- 无标记文件不能靠 grep 判定，必须按内容核对；发现未登记改动先补台账。

## 2. 汇总

| 主处置 | 文件数 |
|---|---|
| 贴回挂钩 | 38 |
| 取并集 | 58 |
| 生成物重跑 | 9 |
| 按内容核对 | 12 |
| 重新摘除 | 1 |
| 分半 | 1 |
| **合计** | **119** |

| 区域 | 文件数 |
|---|---|
| 前端 locales | 25 |
| 前端 views | 19 |
| M10 daemon | 15 |
| handler | 14 |
| DB 生成物 | 9 |
| 前端 core | 9 |
| M1 Agent | 6 |
| integrations | 5 |
| service | 4 |
| DB 真源 | 3 |
| CI/脚本 | 2 |
| M1 路由/main | 2 |
| protocol | 2 |
| realtime/events | 2 |
| server 其他 | 1 |
| 迁移 | 1 |

## 3. 文件矩阵

| # | 文件 | 区域 | 标记 A/CR/AIFI-63 | 主处置 | 特殊处理/备注 | 验证 |
|---|---|---|---|---|---|---|
| 1 | `.github/workflows/ci.yml` | CI/脚本 | 7/1/0 | 取并集 | fork jobs + 上游 jobs 取并集 | pnpm typecheck；相关脚本测试 |
| 2 | `packages/core/api/client.test.ts` | 前端 core | 0/10/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 3 | `packages/core/api/client.ts` | 前端 core | 3/22/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 4 | `packages/core/api/schemas.ts` | 前端 core | 2/16/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 5 | `packages/core/package.json` | 前端 core | 0/0/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 6 | `packages/core/realtime/use-realtime-sync.ts` | 前端 core | 0/3/0 | 分半 | fork queueStatusAll 取并集；working-agent 投影上游胜出 | pnpm --filter @multica/core test；重点 use-realtime-sync |
| 7 | `packages/core/types/agent.ts` | 前端 core | 3/4/0 | 取并集 | skill org 三列 + 上游 labels 取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 8 | `packages/core/types/events.ts` | 前端 core | 0/1/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 9 | `packages/core/types/index.ts` | 前端 core | 0/0/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 10 | `packages/core/types/project.ts` | 前端 core | 0/3/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 11 | `packages/views/chat/components/chat-input.test.tsx` | 前端 views | 0/3/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 12 | `packages/views/chat/components/chat-input.tsx` | 前端 views | 4/9/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 13 | `packages/views/chat/components/chat-message-list.tsx` | 前端 views | 0/1/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 14 | `packages/views/chat/components/chat-window.tsx` | 前端 views | 0/0/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 15 | `packages/views/chat/components/use-chat-controller.ts` | 前端 views | 0/0/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 16 | `packages/views/editor/content-editor.tsx` | 前端 views | 0/1/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 17 | `packages/views/editor/extensions/index.ts` | 前端 views | 0/1/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 18 | `packages/views/editor/extensions/mention-suggestion.tsx` | 前端 views | 0/2/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 19 | `packages/views/editor/utils/link-handler.ts` | 前端 views | 0/0/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 20 | `packages/views/inbox/components/inbox-page.test.tsx` | 前端 views | 1/1/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 21 | `packages/views/inbox/components/inbox-page.tsx` | 前端 views | 0/2/0 | 取并集 | presenter 路由 + 上游列表常量取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 22 | `packages/views/issues/components/issue-detail.test.tsx` | 前端 views | 0/0/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 23 | `packages/views/issues/components/issue-detail.tsx` | 前端 views | 0/1/0 | 取并集 | presenter 六项 + 上游 chronological/CommentRun 取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 24 | `packages/views/locales/en/chat.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 25 | `packages/views/locales/en/inbox.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 26 | `packages/views/locales/en/issues.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 27 | `packages/views/locales/en/modals.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 28 | `packages/views/locales/en/search.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 29 | `packages/views/locales/fr/chat.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 30 | `packages/views/locales/fr/inbox.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 31 | `packages/views/locales/fr/issues.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 32 | `packages/views/locales/fr/modals.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 33 | `packages/views/locales/fr/search.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 34 | `packages/views/locales/ja/chat.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 35 | `packages/views/locales/ja/inbox.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 36 | `packages/views/locales/ja/issues.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 37 | `packages/views/locales/ja/modals.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 38 | `packages/views/locales/ja/search.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 39 | `packages/views/locales/ko/chat.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 40 | `packages/views/locales/ko/inbox.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 41 | `packages/views/locales/ko/issues.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 42 | `packages/views/locales/ko/modals.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 43 | `packages/views/locales/ko/search.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 44 | `packages/views/locales/zh-Hans/chat.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 45 | `packages/views/locales/zh-Hans/inbox.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 46 | `packages/views/locales/zh-Hans/issues.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 47 | `packages/views/locales/zh-Hans/modals.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 48 | `packages/views/locales/zh-Hans/search.json` | 前端 locales | 0/0/0 | 取并集 | 四语言同步；新增键取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 49 | `packages/views/package.json` | 前端 views | 0/0/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 50 | `packages/views/projects/components/project-detail.test.tsx` | 前端 views | 0/0/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 51 | `packages/views/projects/components/project-detail.tsx` | 前端 views | 0/1/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 52 | `packages/views/search/search-command.test.tsx` | 前端 views | 1/2/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 53 | `packages/views/search/search-command.tsx` | 前端 views | 4/4/0 | 取并集 | 上游本地索引 + fork spec 搜索取并集 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 54 | `packages/views/skills/components/skill-detail-page.tsx` | 前端 views | 1/1/0 | 取并集 | 前端定制清单核对；无标记也逐文件 | pnpm typecheck；对应包 vitest；locales 跑 parity |
| 55 | `scripts/ci-scope.test.mjs` | CI/脚本 | 1/0/0 | 取并集 | fork CI scope 测试贴回 | pnpm typecheck；相关脚本测试 |
| 56 | `server/cmd/migrate/main.go` | 迁移 | 10/11/0 | 取并集 | cleanup map 取并集；fork 迁移 +20 → 585–641 | 空库 migrate up，末位 641 |
| 57 | `server/cmd/multica/main.go` | server 其他 | 0/0/0 | 按内容核对 | 无标记；按内容核对，若发现未登记改动先补台账 | 人工对照上游新结构 + grep；对应包定向 go test |
| 58 | `server/cmd/server/main.go` | M1 路由/main | 4/6/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 59 | `server/cmd/server/router.go` | M1 路由/main | 23/25/0 | 重新摘除 | #1 重新摘除 Stripe/cloud-billing；其余 AIFIRST 挂钩贴回 | curl -i .../api/webhooks/stripe 与 /api/cloud-billing 均须 404 |
| 60 | `server/internal/daemon/client.go` | M10 daemon | 0/0/0 | 按内容核对 | 无标记；按内容核对，若发现未登记改动先补台账 | 人工对照上游新结构 + grep；对应包定向 go test |
| 61 | `server/internal/daemon/config.go` | M10 daemon | 1/0/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 62 | `server/internal/daemon/config_test.go` | M10 daemon | 0/0/0 | 按内容核对 | 无标记；按内容核对，若发现未登记改动先补台账 | 人工对照上游新结构 + grep；对应包定向 go test |
| 63 | `server/internal/daemon/daemon.go` | M10 daemon | 15/17/0 | 贴回挂钩 | 含 #58 terminal report 已上游化，勿贴回；其余挂钩贴回 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 64 | `server/internal/daemon/daemon_test.go` | M10 daemon | 0/1/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 65 | `server/internal/daemon/execenv/context.go` | M10 daemon | 2/0/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 66 | `server/internal/daemon/execenv/execenv_test.go` | M10 daemon | 0/0/0 | 按内容核对 | 无标记；按内容核对，若发现未登记改动先补台账 | 人工对照上游新结构 + grep；对应包定向 go test |
| 67 | `server/internal/daemon/execenv/runtime_config_sections.go` | M10 daemon | 1/3/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 68 | `server/internal/daemon/execenv/runtime_config_test.go` | M10 daemon | 0/0/0 | 按内容核对 | 无标记；按内容核对，若发现未登记改动先补台账 | 人工对照上游新结构 + grep；对应包定向 go test |
| 69 | `server/internal/daemon/execenv/sidecar_manifest.go` | M10 daemon | 1/0/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 70 | `server/internal/daemon/health.go` | M10 daemon | 1/3/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 71 | `server/internal/daemon/health_test.go` | M10 daemon | 2/3/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 72 | `server/internal/daemon/prompt.go` | M10 daemon | 1/2/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 73 | `server/internal/daemon/types.go` | M10 daemon | 2/3/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 74 | `server/internal/daemonws/hub.go` | M10 daemon | 0/0/0 | 按内容核对 | 无标记；按内容核对，若发现未登记改动先补台账 | 人工对照上游新结构 + grep；对应包定向 go test |
| 75 | `server/internal/events/bus.go` | realtime/events | 0/2/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 76 | `server/internal/handler/agent.go` | handler | 2/5/0 | 贴回挂钩 | #19 originator 语义 + fork OriginatorUserID 取并集 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 77 | `server/internal/handler/chat.go` | handler | 0/11/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 78 | `server/internal/handler/chat_title.go` | handler | 0/0/0 | 按内容核对 | 无标记；按内容核对，若发现未登记改动先补台账 | 人工对照上游新结构 + grep；对应包定向 go test |
| 79 | `server/internal/handler/comment.go` | handler | 0/4/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 80 | `server/internal/handler/daemon.go` | handler | 10/16/2 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 81 | `server/internal/handler/file.go` | handler | 0/3/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 82 | `server/internal/handler/handler.go` | handler | 0/5/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 83 | `server/internal/handler/issue.go` | handler | 0/6/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 84 | `server/internal/handler/mika_onboarding.go` | handler | 0/0/0 | 按内容核对 | 无标记；按内容核对，若发现未登记改动先补台账 | 人工对照上游新结构 + grep；对应包定向 go test |
| 85 | `server/internal/handler/project.go` | handler | 0/12/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 86 | `server/internal/handler/runtime_local_skills.go` | handler | 0/0/0 | 按内容核对 | 无标记；按内容核对，若发现未登记改动先补台账 | 人工对照上游新结构 + grep；对应包定向 go test |
| 87 | `server/internal/handler/runtime_models.go` | handler | 0/1/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 88 | `server/internal/handler/skill.go` | handler | 1/1/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 89 | `server/internal/handler/workspace_delete_manifest_test.go` | handler | 0/0/0 | 按内容核对 | 口径盲区 #87；无标记，按内容核对 | 人工对照上游新结构 + grep；对应包定向 go test |
| 90 | `server/internal/integrations/ghsnapshot/client.go` | integrations | 0/1/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 91 | `server/internal/integrations/lark/client.go` | integrations | 1/1/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 92 | `server/internal/integrations/lark/http_client.go` | integrations | 2/2/0 | 贴回挂钩 | fork 动态 op 保留；上游 APIError 结构适配 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 93 | `server/internal/integrations/lark/outbound_test.go` | integrations | 1/1/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 94 | `server/internal/integrations/lark/typing_indicator_test.go` | integrations | 1/1/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 95 | `server/internal/realtime/hub.go` | realtime/events | 0/4/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 96 | `server/internal/service/autopilot.go` | service | 2/1/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 97 | `server/internal/service/issue.go` | service | 0/6/0 | 贴回挂钩 | createInTx 与上游 properties 校验取并集 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 98 | `server/internal/service/task.go` | service | 9/29/4 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 99 | `server/internal/service/task_agent_skills_test.go` | service | 0/0/0 | 按内容核对 | 无标记；按内容核对，若发现未登记改动先补台账 | 人工对照上游新结构 + grep；对应包定向 go test |
| 100 | `server/pkg/agent/agent.go` | M1 Agent | 2/0/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 101 | `server/pkg/agent/claude.go` | M1 Agent | 1/0/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 102 | `server/pkg/agent/models.go` | M1 Agent | 1/0/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 103 | `server/pkg/agent/pi.go` | M1 Agent | 4/0/0 | 贴回挂钩 | #102 自持管道三件套必须保留；上游 closePiReadPipe 可用于读端中断 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 104 | `server/pkg/agent/pi_test.go` | M1 Agent | 0/0/0 | 按内容核对 | 无标记；按内容核对，若发现未登记改动先补台账 | 人工对照上游新结构 + grep；对应包定向 go test |
| 105 | `server/pkg/agent/thinking.go` | M1 Agent | 1/1/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 106 | `server/pkg/db/generated/agent.sql.go` | DB 生成物 | 13/20/0 | 生成物重跑 | 丢弃冲突块，重跑 make sqlc；不手改 | make sqlc；git diff -- server/pkg/db/generated 无意外差异 |
| 107 | `server/pkg/db/generated/autopilot.sql.go` | DB 生成物 | 1/1/0 | 生成物重跑 | 丢弃冲突块，重跑 make sqlc；不手改 | make sqlc；git diff -- server/pkg/db/generated 无意外差异 |
| 108 | `server/pkg/db/generated/chat.sql.go` | DB 生成物 | 1/12/0 | 生成物重跑 | 丢弃冲突块，重跑 make sqlc；不手改 | make sqlc；git diff -- server/pkg/db/generated 无意外差异 |
| 109 | `server/pkg/db/generated/models.go` | DB 生成物 | 0/0/0 | 生成物重跑 | 丢弃冲突块，重跑 make sqlc；不手改 | make sqlc；git diff -- server/pkg/db/generated 无意外差异 |
| 110 | `server/pkg/db/generated/project.sql.go` | DB 生成物 | 0/2/0 | 生成物重跑 | 丢弃冲突块，重跑 make sqlc；不手改 | make sqlc；git diff -- server/pkg/db/generated 无意外差异 |
| 111 | `server/pkg/db/generated/runtime.sql.go` | DB 生成物 | 0/0/0 | 生成物重跑 | 丢弃冲突块，重跑 make sqlc；不手改 | make sqlc；git diff -- server/pkg/db/generated 无意外差异 |
| 112 | `server/pkg/db/generated/search_index.sql.go` | DB 生成物 | 0/0/0 | 生成物重跑 | 丢弃冲突块，重跑 make sqlc；不手改 | make sqlc；git diff -- server/pkg/db/generated 无意外差异 |
| 113 | `server/pkg/db/generated/supplement.sql.go` | DB 生成物 | 0/0/0 | 生成物重跑 | 丢弃冲突块，重跑 make sqlc；不手改 | make sqlc；git diff -- server/pkg/db/generated 无意外差异 |
| 114 | `server/pkg/db/generated/wakeup.sql.go` | DB 生成物 | 0/0/0 | 生成物重跑 | 丢弃冲突块，重跑 make sqlc；不手改 | make sqlc；git diff -- server/pkg/db/generated 无意外差异 |
| 115 | `server/pkg/db/queries/agent.sql` | DB 真源 | 13/20/0 | 取并集 | SQL 真源取并集；重跑 make sqlc | make sqlc |
| 116 | `server/pkg/db/queries/autopilot.sql` | DB 真源 | 1/1/0 | 取并集 | SQL 真源取并集；重跑 make sqlc | make sqlc |
| 117 | `server/pkg/db/queries/project.sql` | DB 真源 | 0/2/0 | 取并集 | SQL 真源取并集；重跑 make sqlc | make sqlc |
| 118 | `server/pkg/protocol/events.go` | protocol | 3/4/0 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |
| 119 | `server/pkg/protocol/messages.go` | protocol | 0/1/1 | 贴回挂钩 | 按 CUSTOM 对应 #N 行贴回；含已上游化项要退役 | go build/vet；对应包定向 go test；合并后 hooks 四数对账 |

## 4. Gate 2 边界

- 本矩阵确认的是文件级主处置与特殊处理规则，不是逐个 hunk 的最终结论。
- 合并中出现矩阵未覆盖的改动：停止，按 CUSTOM 口径补台账/升级复核。
- 迁移 +20 与 SQL/生成物重跑属于 Gate 2 确认项，不是合并时临时决定。

## 5. 待确认
- [ ] 四类口径的文件级分配
- [ ] 无标记文件的“按内容核对”范围
- [ ] 迁移 +20 → 585–641
- [ ] 生成物重跑清单
- [ ] Gate 2 确认
