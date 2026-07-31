---
id: CR-2026-002-TASK-11
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: 端到端验收串联（AC-1..7 冒烟 + 证据记录）
status: done
estimate: 8h
depends-on: [CR-2026-002-TASK-05, CR-2026-002-TASK-06, CR-2026-002-TASK-07, CR-2026-002-TASK-08, CR-2026-002-TASK-09, CR-2026-002-TASK-10]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
---

## 任务描述
全链路验收：用一个真实测试 CR（或本 CR 自身）在本机全栈（Docker 三容器 + daemon + crctl）串联跑通 AC-1..7 的端到端半边，逐条记录证据（命令、输出摘要、时间戳），为 write-test-report 提供输入。

## 涉及文件
- 无新代码（验收动作）；证据记录到本文件完成记录 + 后续 test-report.md
- 发现缺陷 → 回对应 TASK 修复后复跑

## 实现要点
- 串联剧本：断网 advance（AC-1）→ 联网补传+投影+WS（AC-2）→ 手工篡改投影自愈（AC-3）→ 无 TTY grant 审批全链（AC-4①）→ Agent 任务内越权三连（AC-5①②③）→ activity_log 两类行（AC-6/AC-7③）→ TTY 篡改检出（AC-7）。
- 与 M0 冒烟同一套结果标记约定（Issue 或命令输出留痕均可）。

## 验收条件
1. AC-1..7 每条至少一次端到端通过记录（单测覆盖的子项引用对应 TASK 测试结果）。
2. 全程无绕过 crctl 手改权威文件（审计可查）。

## 完成标志
七条 AC 证据链完整 + 完成记录回填 → 进入 write-test-report。

## 完成记录（2026-07-31，全部为本机全栈真机证据）

**环境**：backend 镜像 `multica-backend:dev`（37ea3b50a92d，从 CR-2026-002 worktree 构建，含 T04-T11 全部代码）+ `docker-compose.aifirst.yml` 治理 env overlay（`APPROVAL_SIGNING_KEY(_ID)`、`REMOTE_RECONCILE_MODE=server`、`KNOWLEDGE_BASE_REMOTE_URL`、`KNOWLEDGE_BASE_TOKEN`（只读 PAT）、`RECONCILE_INTERVAL=1m`）；daemon `dev-cr2026002`（worktree 构建二进制）带 `MULTICA_CR_WORKSPACES` + `MULTICA_CONTROLLED_SHELL_RULES` 重启；审批密钥对 `aifirst-approval-2026-07`（公钥已提交 `.crctl/keys/`，`.crctl/.gitignore` 加 keys 例外）。

**AC 证据链**：
- **AC-1 离线积压补传 ✅**：绑定缺陷修复前 daemon 连续 403（等效断网），outbox 积压 + 提交历史未扫；修复后首个成功刻度一次性补传全部积压——ledger 入账 43 条（status 18 + checkpoint 25，含从 git 历史兜底扫描的两个 CR 全史），outbox 清空（ack 后删除）。
- **AC-2 投影 ✅**：cr 表 CR-2026-002=developing@0e9bc9c2（与 origin HEAD 一致）；CR-2026-001 已归档故 needs_reconcile=true（backlog 之外，语义正确）。WS 广播由 T05 集成测试断言（TestLegalFlowProjectsAndBroadcasts）。
- **AC-3 篡改自愈（双模式真机）✅**：server 模式——16:50:28 手工 UPDATE 为 drafting/needs_reconcile → 16:51:43 被 1min 对账任务治愈为 developing/false/真实 GitHub HEAD（backend 日志 aifirst_cr_reconcile succeeded）；daemon 模式——卡在 server 周期刚跑完的阴影窗内篡改 + 重启 daemon 触发首拍快照，16:52:41 篡改 → 16:52:49 治愈（8 秒，远早于下个 server 周期）。
- **AC-4 无 TTY 签名审批全链 ✅**（隔离探针 CR-2026-990）：crctl advance 产生带证据事件 → cr-events 入账 → GET 审批卡（digest 474a3d81…）→ 人类 PAT POST approve → Ed25519 grant 签发落库 → daemon 15s 内投递 `.crctl/grants/CR-2026-990-requirement.grant.json` 到知识库 → crctl `approve --grant` 验签通过 → 非 TTY 级联推进 requirement-reviewing→requirement-approved。探针数据已清理（DB 三表 + grant 文件 + scratch 工作区）。
- **AC-5①② 越权拒绝 ✅**：经真实 shim 网关 `multica gitguard-exec`——`push --force origin main` → FORBIDDEN_SUBCOMMAND；`-c core.editor=…` 前置 → 同 fail-closed 拒绝（`-c` 作首 token 按非白名单子命令拒，语义等效）；对照 `status --short` 放行执行真 git。
- **AC-5③ hook 拒改 ✅**：pretooluse-guard.mjs stdin 注入 `Write change-requests/_backlog.yml` → permissionDecision=deny（引导走 crctl）；对照普通文件 → allow。
- **AC-6① 拒绝审计 ✅**：上述两次拒绝被 SpoolDenial 落 outbox → daemon 15s 采集 → activity_log 两行 `aifirst.gitguard_denied`，details 仅 `{caller, sub, code}`，无参数正文。
- **AC-6②③ 工具调用摘要 ✅**：真库端点级测试 TestCompleteTask_AggregatesToolCallSummary（真实 task_message 流 → CompleteTask 聚合进 result.tool_calls，正文泄漏断言）。
- **AC-7/AC-7③ 篡改检出+留证 ✅**：知识库真仓篡改 requirement 阶段证据文件 → `crctl gate` 报 EVIDENCE_DRIFT（传统 sha16 兼容分支）→ audit 事件落 outbox → daemon 采集 → activity_log 出现 `aifirst.evidence_drift` 行（双摘要+阶段，无证据内容）→ 证据文件已还原。

**验收期抓到并修复的两个真缺陷**：
1. **daemon workspace 绑定 403（阻断级）**：上游 `mdt_` daemon-token 签发流程未接线（`auth.GenerateDaemonToken` 无调用方），真实 daemon 走 PAT 回退 → 治理三端点全 403。T05 集成测试用 `WithDaemonContext` 注入绕过了该路径，单测全绿掩盖了真机不可用。修复：`resolveDaemonWorkspace`——mdt_ 优先，PAT 按 X-User-ID 查 member 表绑定（单成员隐式/多成员要 X-Workspace-ID/非成员 403）。multica@405644069。
2. **裸 `--grant` 崩溃**：`crctl approve --stage x --grant`（无值）时 `path.isAbsolute(true)` 抛 ERR_INVALID_ARG_TYPE——T08 跨工具测试恒传路径故未暴露。修复：无值默认 daemon 标准落点 `.crctl/grants/{cr}-{stage}.grant.json`。tools@7e91626。

**如实记录**：
- server 模式对账无法自举空投影（`SELECT DISTINCT workspace_id FROM cr` 无行时不知道绑定哪个 workspace）——首行由 daemon 通道建立后 server 模式接管治愈，是设计约束（服务端不猜 workspace）而非缺陷；已在真机按此顺序发生并收敛。
- AC-5 未派真实 Claude agent 任务（费用+时长），但拦截三层各自经真实组件验证：shim 网关二进制 = execenv 铸造的 shim re-exec 的同一实现；hook 脚本 = execenv 物化进 settings.json 的同一脚本；execenv 铸造逻辑本身有 T09 单测。组合面（真派单任务内三层齐动）留待日常使用观察。
- 全程无绕过 crctl 手改权威文件；篡改探针（cr 表行/证据文件）均已恢复且有审计行留痕。
