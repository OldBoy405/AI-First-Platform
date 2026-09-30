---
id: CR-2026-073-prd
type: PRD
cr-ref: CR-2026-073
title: crctl test 长输出与审计归属修复、普通 CR 验收范围约束
target-version: 0.46
owner: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
owner-role: requirement
status: draft
created: 2026-09-30T12:23:08+08:00
updated: 2026-09-30T12:23:08+08:00
---

# CR-2026-073 需求文档

## 1. 概述

本 CR 承接 Dayan Issue AIFI-38 的三项可独立验收工作。AIFI-37 / CR-2026-072 及 AIFI-39 仅为问题来源与历史线索；本 CR 独立推进，不重开其审批或推断历史记录。三项分别为：

- **A — 测试长输出**：`crctl test` 的 `runTestPlan` 使用未显式设置 `maxBuffer` 的 `spawnSync`，输出超过默认约 1 MiB 时可能报 `ENOBUFS`、`exit=null`，现按 `TEST_EXECUTABLE_INVALID` 处理，丢失真实退出信息。采用有界缓冲（建议 10 MiB），明确区分缓冲溢出与命令真实失败。
- **B — 审计落点**：`merge`、`writeback-apply`、`archive` 的审计随 CR worktree / txws 等调用位置分散，终态清理后 install-root `.crctl/audit.log` 不完整。将三者审计统一归属已解析的 install-root，保留 actor、去重与清理语义。
- **C — 验收证据范围**：普通 CR 的 plan / TASK / review 按 FR/AC 的实际证明范围确定定向证据，不默认要求全仓绿色；上游同步仍按 `CUSTOM.md` 的全量要求执行。

来源事实：AIFI-38 描述及 Ray 在该 Issue 的裁决（2026-09-30）。已核对 tools 仓 `skills/shared/crctl/scripts/lib/workspace-transactions.mjs#runTestPlan` 的 `spawnSync` 调用未设置 `maxBuffer`，`skills/shared/crctl/scripts/crctl.mjs` 存在审计调用及 `writeback-apply` 的 `emitAdvanceAudit`，现有 `write-dev-plan` / `review-dev-plan` Skill 已约束 `cmd-NN` 的证明范围。本 PRD 不替 SDD 决定具体实现算法。

## 2. 用户故事

- **US-1（A）**：作为运行 CR 测试的开发者，我希望长输出且未超过明确上限的命令完整保留日志与真实退出码，以免将正常或真正失败的测试误报为可执行文件无效。
- **US-2（A）**：作为测试证据使用者，我希望输出超过上限时得到明确的技术错误和阈值，而不把截断片段当作完整测试证据。
- **US-3（B）**：作为本机审计核查者，我希望从 KB 主 checkout、CR worktree 或 txws 调用终态命令后，在 install-root 找到一致的审计及真实 actor，且清理和重放不改写历史。
- **US-4（C）**：作为普通 CR 的计划作者与评审者，我希望验收命令只覆盖已批准 FR/AC 需要的范围，并由评审在证据不足或擅设全仓门槛时阻断。

## 3. 功能需求

### A. `crctl test` 长输出

- **FR-1**：`crctl test` 保持 `spawnSync` 与 `shell:false` 执行方式，对每条命令显式设置有限 `maxBuffer`（目标建议 10 MiB；最终值由设计确认并在诊断中展示），使超过 Node 默认约 1 MiB 但未超过所设上限的 stdout/stderr 可完整落入各自分区的 `cmd-NN.log`，并记录命令真实 `exitCode`、`signal`、`timedOut`、`skipped` 和日志 SHA-256；既有判定合同不变。
- **FR-2**：在有界输出内，命令以真实非零码退出仍记测试失败；超时和启动失败仍按既有分类处理，不以增加缓冲上限改变测试结果或失败边界。
- **FR-3**：若超出显式缓冲上限，返回可识别的**技术错误**，明确标注 `ENOBUFS` 与配置阈值；真实退出码不可得时保持 `null`。已捕获片段仅供诊断，不能作为完整日志、通过证据或断言失败；命令执行未能产生有效完整证据时 `crctl test` 非零退出且 canonical 产物零变化。

### B. 审计归属

- **FR-4**：`merge`、`writeback-apply`、`archive` 的审计写入根均使用当次上下文已解析的 `ctx.installRoot`，不以传入工作目录重新推导；`writeback-apply` 的 `emitAdvanceAudit` / `auditLogOnce` 与其他对应审计同根。actor 与写入根分别确定，不因归档清理后的 worktree / txws 消失而退化为 `unknown`。
- **FR-5**：三种合法 `--workspace` 入口（KB 主 checkout、CR worktree、txws）执行对应终态命令时，审计均保留在本机 install-root `.crctl/audit.log`。完成归档清理后不为写审计重建已删除的 worktree / txws；幂等重放仍遵循原有审计去重合同，不重复记录同一事件，也不伪造历史记录。

### C. 普通 CR 验收范围

- **FR-6**：普通 CR 的 `plan.md` 证据命令表为每行 FR/关键 AC 指定能证明该验收面的定向 `cmd-NN`，写明实际执行范围；只有已审批 SDD / AC 明确要求全量时，才将 `go test ./...`、`make test` 等全仓命令列为该 CR 的验收条件。子集测试不得宣称全量通过。
- **FR-7**：`write-dev-tasks` 仅继承 plan 对应的证据 ID、范围及其验收口径，不额外增加“全量通过”作为 TASK 完成条件。`review-dev-plan` 对普通 CR 误设全仓门槛，或 plan/TASK 声称的验收面大于证据可观测面，判定 blocker 并退回修订；若已审批验收确实要求全量绿色而当前不可达，应先解决失败或正式修订验收合同，不绕过 `crctl test`。
- **FR-8**：上游同步仍按 `CUSTOM.md` 执行全量测试；已知 Windows 失败保留原始结果并与基线对照，不以局部绿色伪装为通过的关键 `cmd-NN`。本项只调整文档/评审口径，不新增测试计划字段或机器门禁。

## 4. 非功能需求

- **NFR-1（兼容性）**：保持 `crctl test` 的 stdout/stderr 分区、超时、真实 exit/signal、skip 判定、日志 SHA-256 与 canonical 原子发布合同；不改为流式输出。
- **NFR-2（安全与可恢复性）**：超限与其他技术失败非零退出、canonical 零变化；有限缓冲须明确容量，不允许无界增长。审计改根不得改变 actor、去重、merge 事务或终态清理的既有语义。
- **NFR-3（范围）**：不改状态机、已有门禁判据、账本语义或 merge 事务算法；不以 Pipeline 强制 `--workspace` 指向 KB 主 checkout 代替根因修复。

## 5. 验收标准

各组独立验收，A 的通过不能替代 B 或 C。

- **AC-1（FR-1）**：测试命令输出超过默认约 1 MiB 且低于新上限，`cmd-NN.log` 的 stdout/stderr 内容分别完整，测试报告记录真实退出码、signal/skip/timeout 与日志 SHA-256；没有 `ENOBUFS` 误判。
- **AC-2（FR-2）**：同范围内真正非零退出的命令仍判测试失败而非可执行文件无效；启动失败与超时分别按既有合同分类。
- **AC-3（FR-3）**：超过新上限时可见 `ENOBUFS` 和实际阈值；真实退出码不可得显示 `null`，截断内容标为诊断片段，`crctl test` 非零技术退出且 canonical 文件字节不变，不产生伪造的成功/失败断言。
- **AC-4（FR-4、FR-5）**：分别从 KB 主 checkout、CR worktree、txws 合法入口运行 merge / writeback / archive 的适用路径，核对三类审计均写在 install-root；归档后原已清理的目录不被重建，记录保有可证明的 actor。
- **AC-5（FR-5）**：对已完成终态命令重放，核对原有去重语义仍成立且无重复审计；不补造 CR-2026-070/071/072 已缺失的 actor 或时间。
- **AC-6（FR-6、FR-7）**：取一个普通 CR，误把无审批要求的全仓命令设为关键 `cmd-NN` 时 review 判 blocker；改为可证明对应 FR/AC 的定向命令并标注实际范围后，TASK 继承相同证据、不附加全量通过条件，子集测试不宣称全量通过。
- **AC-7（FR-7、FR-8）**：核查一个“命令只观测子集却声称全量”的 plan/TASK，review 判 blocker；另核查上游同步场景，仍执行全量并保留 Windows 原始失败及基线对照。已审批 AC 要求全量但全量不可达时，不允许以局部测试绕过。

## 6. 成功指标

- A：覆盖默认上限之上的成功/真实失败与新上限之外的超限用例，误报 `TEST_EXECUTABLE_INVALID` 数为 0；超限无 canonical 假证据。
- B：三种入口对应的 merge/writeback/archive 审计可在 install-root 核查，归档后的重放不新增同一事件记录、不重建已清理目录。
- C：普通 CR 的计划、任务与评审案例各完成范围核查；定向证据与声明验收面一致，上游同步仍留有全量执行及基线对照。

## 7. 范围排除

- 不新增 `crctl test` 的流式收集、无界缓冲或新的测试计划字段；不新增 C 项机器门禁。
- 不改变 CR 状态机、门禁判据、账本含义、merge 事务算法，或以改 Pipeline 话术强制单一 `--workspace` 入口代替 B 项修复。
- install-root `.crctl` 为本机 Git 忽略目录；本 CR 不提供跨机器或服务端持久审计。该保证需另案定义 outbox 投影与服务端验收。
- 不根据旧 journal 推断或伪造 CR-2026-070/071/072 的缺失历史审计 actor / 时间；AIFI-39 仅作历史线索。
