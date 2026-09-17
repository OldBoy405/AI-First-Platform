---
id: CR-2026-069
title: CR 流程降本提效首期：FR-8 成本基线 + FR-1 OutputGuard + FR-2 crctl 输出瘦身
summary: "CR 流程降本提效首期：在不改变 CR 阶段、门禁、审批、Git、账本与事务语义的前提下，只实施三项。FR-8 离线建立成本基线与历史回放（读取既有 session 工具结果与 Provider usage，对 672 个历史 Pi session 离线回放 OutputGuard policy，部署后固定 14 天窗口复测；只在改造前与部署后各执行一次，不进 Pipeline 节点、不参与门禁、不写状态与账本，目标桶 tokens/CR 需下降至少 20% 且三项质量护栏全部不恶化才允许重新立项评估候选 FR）。FR-1 无状态 OutputGuard Core 加五个 Runtime 薄 Adapter（在工具结果进入下一轮模型上下文之前治理无界检索、递归列举与全文读取；policy/capabilities/conformance 为唯一事实源；裁剪结果必须标记 complete=false 并保留 toolName、toolCallId、isError、exitCode 与结果结构，被丢弃正文不落盘、不进 transcript；complete=false 结果不得作为充分门禁证据；一次性首行注释逃生阀只影响当前调用、原因必填、不绕过安全控制；Adapter 或 policy 缺失损坏时显式 fail-open 并标 coverage=unavailable；按 Pi 到 Claude 到 CodeBuddy 到 Qoder 到 Codex(partial) 顺序启用；Core、Policy、五个 Adapter 随同一 Tools Release 原子发布升级）。FR-2 只对基线识别出的、覆盖至少 80% crctl 输出 token 的最小命令集增加 summary projector（默认输出 compact summary，完整字段经 --detail 获取，不新增 --output json、--verbose、--pretty 平行开关，不在全局 ok() 粗暴删字段；退出码、错误码、字段语义与状态、门禁、审批、CAS、事务、Git 行为逐一不变）。范围为一个 CR、十个 TASK，复用既有跨仓 checkpoint、事务与受控 Git，每个 Adapter 独立提交可单独回滚；明确零改动 AI-First-multica 的 tool_output_preview.go，不新建事务协调器、WAL、CAS 层或 Git 提交框架，不拆分或重构 workspace-transactions.mjs，不复制 passCondition、状态映射或 reviewLoop 算法，不实现完整 Bash/PowerShell parser，不调用 LLM 做输出摘要，不新增状态、门禁、审批或 CR 生命周期节点，不新增账本、数据库、仪表盘、sidecar 日志或远程动态开关。FR-3 至 FR-7 与 FR-9 保留为候选 Backlog，不属于本 CR 验收范围，不得借本 CR 扩大范围。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-09-17T14:33:42+08:00"
  development:
    id: Ray
    assigned-at: "2026-09-17T14:33:42+08:00"
  test:
    id: Ray
    assigned-at: "2026-09-17T14:33:42+08:00"
target-version: 0.42
target-spec-id: ai-first-platform
source: AIFI-32
origin: ""
status: code-reviewing
created: "2026-09-17T14:33:42+08:00"
updated: "2026-09-17T22:00:19+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-09-17T14:33:42+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-09-17T14:33:42+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-09-17T14:33:42+08:00", reason: initial-assignment }
handover-history: []
---
