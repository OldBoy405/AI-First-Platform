# Design Adjustments — 2026-11-17-execution-admission-simplification

> 汇总 BUILD 期间的调整（源自 pending-adjustments.md PA-001～PA-006）。受审承诺（G1–G5、成功标准）未变；以下为同一合同下的实现/测试调整与评审处置。

## 切片与执行口径
- PA-001：长程 full_auto 预授权（用户「确认全部」）。相对模板收紧：阻塞绕不过即暂停、迭代到 10 轮上限即暂停。平台差异：pi 会话，Claude Code 权限配置步骤不适用，未改 `.claude/settings.local.json` 与 pi 全局配置。
- PA-002：切片重排——驱动 `--default-contract` 改造与默认契约实现合为 S1（原 S1 诊断+S2 实现），S4/S3 不变。TC 归属不变（每 TC 恰一切片）。

## 实现调整（同一合同）
- PA-004：契约补齐发生在 `BuildExecutionAuthorization` 与 HTTP 处理器（重放比较前）；`decodeExecutionRawRequest` 拆形状校验+必填校验。`routerStartupRefusal` 函数变量接缝（生产仍 os.Exit(1)）。驱动 `--default-contract` 不传 manifest flag、请求省略三字段；按 `.github/aifirst-tools-pin`（7a0a2ab5）暂存 crctl；daemon_token 写 owner_id（迁移 588）。
- PA-006：C2 证据 run 暴露 GET 路由遮蔽（C1 代码评审 HIGH）。S4 原用 `r.Route(父路径)` Mount GET 子路由，chi 遮蔽 architecture start/requirement POST。修复：GET 改叶子路由 `r.With(RequireWorkspaceMemberFromURL).Get("…/pipeline-runs/{runID}")`。共存测试改用真实 task token（原无凭证测试假阴性）。真实运行驱动修复后 exit 0。属实现缺陷，仅重审 Gate 3。

## 评审处置（C1 三路）
- code HIGH（路由遮蔽）：初判误报（无凭证共存测试假阴性），C2 证据 run 证实为真实 bug，已修（PA-006）。
- code MEDIUM（completeExecutionContractFields 在“另一字段省略+本字段非字符串”时悄悄默认化非法值）：真实窄口 bug，已修（仅缺席/空串补齐，非字符串/非法值原样保留交解析器拒绝）+2 子测试。
- code LOW（CLI 帮助文案仍说等待 trusted verdict；validateExecutionContractFields 注释误称生产 head 读取使用）：已修。
- code MEDIUM（head-only 不查 stage='execution'）：保留为已知限制——head 指针只由授权/撤销流程设置（指向 execution 记录），损坏指针属 DB 完整性问题，超出本变更威胁模型；范围校验（workspace+cr）与撤销锁序保留。
- code MEDIUM（progressOf 残留 wait_reason / waiting_approval 映射）：SC-EWV-003/004/005 明文规定的取舍——waiting 仅在前沿 running 且无活动任务时采信 wait_reason；waiting_approval→waiting_human 按 run 状态。记录为已知限制，非缺陷。
- test_config H1（CP-RUN-105 断言与实际输出不匹配）：修受审 agent spec 断言，重审 Gate 2。
- test_config M1（命令 CP 断言无业务观测）：折中——CP 断言补 fail=0/skip=0 计数，业务正确性由带 expected 对账的 Go 测试承载；重审 Gate 2。
- test_config H2/M2/M3/M4/M6/M8/M9/M10、H3/H4/H5：测试/selection 强化与深度补全（用户「补全深度」），见下。
- docs#8（spec“任一显式不等均409”与格式非法先 SOURCE/SCOPE_INVALID 不符）、docs#2（design 重放承诺）：修受审 spec/design 措辞，重审 Gate 2。
- docs#3/#4/#11/#12：切片登记/全量回归/调整格式/历史行号快照标注，已处理或说明。

## 测试/selection 强化与深度补全（用户裁定补全）
- H2：ath-head-matrix 扩选非法入参/空事务/reconcile 等待转成功测试。
- M2：矩阵拒绝动作断言 wait_reason==admission 且 run 未 failed；准入 enqueue 另起真实 TaskService runner 断言真实队列行+1。
- M3：补 requirement 入队 source_task 缺失/非法→RunnerErrAuthorityMismatch。
- M4：m005-consumption-effect 补 expected（20 项）。
- M6：cmd/server 新增 manifest loader 失败用例（半配置/相对路径/sha 错/超限/空），入 run-default-contract-wiring。
- M8：waiting_human 夹具改 human_approval；补 running human 节点 idle 变体。
- M9：新增 architecture start 回执 progress 测试（真实 HandleStartArchitecture）。
- M10：CP-EWV-004 扩选 start 请求体/令牌与 resume supersede 测试+PASS 断言（受审，重审 Gate 2）。
- H3：真实撤销并发——另一 goroutine head 指针 UPDATE 指向真实 reject 记录，pg_stat_activity 证明持锁 enqueue 期间被阻塞，效果提交后撤销成功→HEAD_REJECTED。（未走 HTTP 撤销路由：内部测试包无法复用外部路由夹具；head 指针 UPDATE 与撤销首锁 FOR UPDATE OF c 同行锁语义。）
- H4：run_003 启用真实 Runner，真实 ACK 路由仅提交 delivery 不直接派发（execution 阶段 ACK 在 approval.go 被排除在 legacy continuation 与 post-commit wake 之外），派发来自发现/周期唤醒（PipelineResume）；补撤销头变体不派发。
- H5：run-requirement-shape 改发现路径——StartRequirement（无头）→注册等待 0 任务→真实默认契约路由签头→ResumeActiveRuns→writer 入队→reviewer；源任务零消费。

## 已知限制（接受，记录在案）
- head-only 不额外查 stage='execution'（依赖 head 指针完整性，威胁模型外）。
- progressOf 对“任务完成但 reconcile 未处理”的瞬态、waiting_approval 人工门被撤销阻塞等场景按 SC-EWV 明文取舍显示，非全状态精确镜像。
- H3 用 head 指针 UPDATE 模拟撤销锁语义，未走 HTTP 撤销路由（行锁语义一致）。
- 全量 "." 回归在本地 Windows 有平台性/共享库失败（chat/repo/claim/migration 等未改动包）；TestTC_RUN_003 全量失败经核实为共享库跨包交互（governance 迁移测试 DROP 表 + CR-9% 清理），不可归因本变更；curated selections（独立一次性库）全部 PASS 为有效证据。

## Gate 重审记录
- Gate 2 重审两次：①A 组受审措辞+M1 折中（07:55:14）；②M10 CLI 选择补全（08:34:49）。业务承诺未变，未重审 Gate 1。
- PA-006 路由修复属实现缺陷，仅 Gate 3。
