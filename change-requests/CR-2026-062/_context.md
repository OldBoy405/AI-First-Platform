# _context.md — CR-2026-062 工作流导航缓存

> 本文件仅供返工与 `/resume` 导航。canonical 事实以 `cr.md`、`review-loop.yml`、`traceability.yml`、评审记录为准。

## 当前状态

- CR：CR-2026-062（AIFI-18 · 来源文档 CR-D：Team Agent 和 Private Ask 发送框 UI 优化，target-version 0.35）
- status：**`developing`**（`approve --stage dev-start` 人工审批已通过，commit `9d4306ae`）
- Pipeline：code-implementation；`implement-code` 已全部完成——TASK-01/02/03 done；**TASK-04 环境回修后 done**（cmd-07 e2e 真跑 4/4 绿，kb 本节点提交见下）
- test-report.md machine 区 **status=pass**（cmd-01..09 全绿、skipped=false；command-digest `d49102286ea18ec2f82cc22ac35c980a137ff71425e4809f16fdc33a8e58c2d2`）
- `crctl next` = **`push-progress → review-code`**（humanApproval=false，why=测试证据 pass，推送 checkpoint 后进入代码评审）
- reviewLoop：`write-test-report` attempt 1/3；**PASS 且 blockers=[] → 停在评审节点不执行 approve**（`approve CR-2026-062 --stage code` 指令由 coordinator 发布）

## 产物

- TASK-01 ✅ done：multica commit `2f8dca822` — ChatInputCore 两层 DOM + flow 底栏 + aria + allowSubmitWhileRunning + `chat-input-zero-diff.test.ts`（cmd-09 符号级 zero_diff 检查器）。
- TASK-02 ✅ done：multica commit `f7b07a181` — Team Agent 两层 DOM + ModePane `@container` + leftAdornment 工具栏 + 双源停止（B-005 数组口径）。
- TASK-03 ✅ done：multica commit `47b9aa08d` — Private Ask 两层横幅块 + `private-ask-model-picker` 锚点 + 停止路径原样。
- TASK-04 ✅ done（2026-09-10）：交付物（e2e spec + 差异文档）commit `524428782`；**环境回修 commit `004cb002d`**（spec 定位收窄到 project-chat-composer 子树；runtime 种子补 owner_id/visibility/provider=hermes + 经服务端真实机制种入模型目录；360px 重叠改两轴包围盒断言；AC-7 可观测=队列栏 item；afterEach 补容器 issue 清理；CUSTOM.md #85 同步更新）。
- cmd-07 真跑记录：浏览器二进制安装 1 次环境性修复 + 回修迭代 4 次，最终 4/4 通过（17.4s）；重试与原因已如实写入 test-report 分析段。
- CUSTOM.md：台账 #82–#85（#85 已更新为真跑绿 + 回修记录）。
- test-report.md：machine 区由 `crctl test --plan .crctl/tmp/test-plan.json` 刷新为 pass；分析段（marker 下）记录 env 回修、回修明细、重试次数、未覆盖风险（AC-7 气泡断言因 CR-2026-006 既有数据流不可达，改队列栏 item 观测，未降验收口径）。

## 权威工作区与代码基线

- operationalWorkspace：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-062`（分支 requirement/CR-2026-062）
- multica worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-062`（代码基线 `117fc6be657f91d43df5892b52782a18329c7aed`；HEAD 现为 `004cb002d`）
- tools worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-062`（零改动；diff 白名单经 tools 仓 crctl 受控执行）

## 恢复入口与下一步

- e2e 环境契约（重跑/复核 cmd-07 用）：3000 = CR multica worktree `next dev`（窗口勿关）；8080/5432 = podman 容器；`.env.worktree`（gitignore）提供 DATABASE_URL/MULTICA_DEV_VERIFICATION_CODE/PLAYWRIGHT_BASE_URL。重跑同一 plan：`node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs test CR-2026-062 --plan .crctl/tmp/test-plan.json --workspace <kb worktree>`。
- 评审：全部绿（cmd-01..09 无失败、TASK-04 done、test-report pass）后，由 dev-agent run 收尾只 mention quality-reviewer-agent 发起独立 fresh `review-code`（operationalWorkspace + 三仓 resources 原样传递）；PASS 且 blockers=[] 停在评审节点，`approve-code` 指令由 coordinator 发布；BLOCK 按 repair-target（implement-code 回修本链 / write-dev-plan plan-blocker）。
- 范围纪律（评审前自检）：实际 diff = cmd-08 清单 ∈ §1.1 白名单 + CUSTOM.md 受控例外；scope_out（server/API/迁移/数据模型/Discussion/mobile）零触碰；符号级 zero_diff 仅 cmd-09 机器证据承担。
- 下一步以 `crctl next CR-2026-062` 为准。
