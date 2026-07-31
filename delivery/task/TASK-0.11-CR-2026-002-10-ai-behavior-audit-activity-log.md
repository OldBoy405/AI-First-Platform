---
id: CR-2026-002-TASK-10
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: AI 行为审计 + EVIDENCE_DRIFT 留证（activity_log 双 action）
status: done
estimate: 8h
depends-on: [CR-2026-002-TASK-09, CR-2026-002-TASK-03]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
spec-id: ai-first-platform
version: "0.11"
---

## 任务描述
FR-6/D6 + FR-7 留证半边（D7）：gitguard 拒绝事件与 crctl 漂移检出经 daemon 任务回调上报，落 `activity_log`；工具调用摘要随任务完成回调持久化。仓库：multica。

## 涉及文件
- gitguard 拒绝路径：记录 `{caller, sub, at}`（**不含参数正文**）→ 随既有任务回调族上报
- crctl gate/validate 检出 EVIDENCE_DRIFT 时输出结构化行 → daemon 捕获 `{cr_id, stage, expected_digest, actual_digest, detected_at}`（**不含证据内容**）→ 上报
- 服务端：activity_log 写入两个新 action（T04 已备常量）
- 任务完成回调：工具调用摘要序列（工具名/目标路径/结果码，不含输入输出正文）与 `skills_used[]` 同层持久化

## 实现要点
- 零新增探针原则：全部复用既有回调通道，不加独立上报进程（源方案 §C.5）。
- 摘要来源：pkg/agent 六类 Message 流的 tool-use/tool-result 已流经服务端，只需在完成回调聚合。

## 验收条件
1. 端到端：任务内触发一次 FORBIDDEN_* → activity_log 出现对应行且无参数正文（AC-6①）。
2. 端到端：批后篡改证据 → validate 检出 → activity_log 出现 evidence_drift 行（AC-7③ 留证半边）。
3. 任务详情可查工具调用摘要序列；与 skills_used[] 同回调到达（AC-6②③）。

## 完成标志
端到端三项实测记录 + go test 绿 + 完成记录回填。

## 完成记录（2026-07-31）

- **提交**：multica worktree 26a547109 + tools@364ee90（crctl 漂移留证）。
- **通道设计偏差（对 SDD"结构化行 → daemon 捕获"的改良）**：漂移与拒绝事件不走 stdout 结构化行解析，改走 T06 已建成的 outbox 事件通道（`event_kind: audit`）——离线可积压、原子可见、采集/ack/三振语义全部免费复用，daemon 零改动。服务端 `audit` 类事件绕过 cr_sync_event 账本（无 commit sha 无幂等键）直插 activity_log；action 白名单锁死两个 `aifirst.*` 常量，伪造 outbox 文件三振进 dead/。
- **gitguard 拒绝（AC-6①）**：`gitguard.SpoolDenial` 写 `{caller, sub, code}` 到 `$CRCTL_WORKSPACE/.crctl/outbox/`（tmp+rename，pid+序号防同毫秒撞名）；`gitguard-exec` 拒绝路径接线，spool 失败不影响拒绝本身。Go 侧常量与 governance 常量有跨包一致性断言测试。daemon 自守（system-orchestrator）的拒绝仅日志不 spool——那是部署配置 bug 不是 AI 行为，且 execenv 包无 workspace 根。
- **EVIDENCE_DRIFT 留证（AC-7③）**：crctl gate（统一摘要/废弃短哈希两分支）+ validate（approval.yml 复核）三个检出点发 audit 事件，payload 只有 `{stage, expected_digest, actual_digest, detected_at}`；确定性文件名（cr+stage+双摘要前8位）保证同一漂移待采集期间只留一份，采集走后仍漂移则下个观测窗再留一条（按观测计数）。
- **工具调用摘要（AC-6②③）**：daemon 已全量上报 tool_use/tool_result（task_message 表），CompleteTask 服务端聚合成 `result.tool_calls`（`{seq, tool, target, status}`，target 只取 file_path/path/notebook_path/url/pattern 等路径类键，command 正文永不上表；封顶 200 条 + total 真实计数）——零 daemon 改动、零新协议字段，恶意 daemon 传入的 tool_calls 会被服务端覆盖。**口径说明**：任务卡写的 skills_used[] 在 multica 上游不存在，摘要落完成回调的 result JSONB（同层语义成立）。
- **测试**：governance audit 5 项（含伪造 action 拒绝、无参数正文断言、账本零污染）+ toolcalls 3 项（含正文泄漏断言、封顶）+ gitguard spool 2 项 + handler 端点级 1 项（真 DB：task_message 入库 → complete → result 校验）+ crctl JS 20/20（新增漂移 outbox 断言与去重）。fmt/vet/全仓 build 干净。
- **基线更新**：internal/daemon 26 项上游 Windows 环境失败（HOME vs USERPROFILE、本机已装 IDE 被真实发现）A/B 逐条一致，记入 CUSTOM.md 基线表。
- **移交 T11**：AC-6① 的"任务内真机触发拒绝→activity_log 出行"与 AC-7③ 的"批后篡改→validate→行"两条端到端，与 AC-5③ 共用同一次环境刷新（镜像重建 + 双 env 重启 daemon）；组件级链路（spool 文件格式 ↔ 采集器 schema ↔ 服务端入库）已由两端契约测试互锁。
