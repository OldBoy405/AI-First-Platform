# AIFI-45 当前 BUILD 安全与隔离切片计划

**Goal:** 保持可信准入失败关闭，实证一个真实 CLI 的隔离启动，并在本 change 定位 MDispatch001，而非用组件数量冒充完整 TC。

**Architecture:** 授权/账本留在可信宿主；不可信执行侧不拿宿主凭据或控制根写权限。当前 binding proof 仍不含平台 current-head/revoke/claim 全链，故不得返回 consumed=true。复用现有 STDD、Git/ledger、TaskService；不增加第二预算/总账。

**Tech Stack:** Node 原生测试、Go、已存在 rootless Podman；用户已授权真实 Agent CLI/镜像作为隔离 PoC 依赖，未授权模型支出/生产启用。

**Spec:** `wire-contract.md` §3；两侧 `canonical/`、`design.md`、`pending-adjustments.yaml`；原 Gate1/2 evidence 不改。

## Global Constraints

- 普通模式 BUILD/in_progress；不启动 CR 流程，不操作真实 CR/真实 refs，不 commit/push，不自行 Gate3。
- 既定公开验证接缝：T `authorization-bind` CLI、M Runner/TaskService+专用隔离 DB、容器运行时真实可观察行为。
- 仓库文本先规范 CRLF；签名/来源原 bytes 不改写。M 注释英文，CUSTOM 主线程归口。
- 不用 flag/env/自报字段作为可信合同或隔离证明。不得把静态签名/fixture proof 当当前平台验证。
- 不新增或读取真实凭据以运行 PoC；CLI --version/help 可离线，真实模型任务须另有凭据/支出授权。

## Review Focus

- fresh fixture proof但无 current-head/revoke/claim → 拒绝消费，零 receipt/CR 写。
- 两次并发或掉电后重试不被单文件 rename 误称 exactly-once；未接现有事务的 receipt 不保留为准入权威。
- 公钥可公开但不可由 Agent 替换；grant/source 是签名运输，不凭所在目录自动建立信任。
- 容器必须有正向 canary 读取对照；`C:/...` 在 Linux 不存在或 DNS 失败不能独立证明隔离/断网。
- 首次全包失败不可被后续绿色替代；LiveGitHub 不静默联网；单跑绿色不等于 MDispatch 根因。

## Task 1 — 主线程：撤销未完成可信链上的 live 放行

Files: T `skills/shared/crctl/scripts/{crctl.mjs,lib/execution-authorization.mjs,test/execution-authorization.test.mjs}`。

- [x] RED：公开fresh proof断言实际1FAIL/exit1（预期拒绝，旧版exit0）；无execution-consumptions/HEAD写。
- [x] GREEN：删除独立receipt writer/import/caller；保持grant→binding→source诊断，最终EXECUTION_CONSUMPTION_REQUIRED。
- [x] 预置receipt不能激活/绕过准入，同公开CLI seam验证。
- [x] 授权104/104；显式TAP三文件162/161PASS/0FAIL/1file-symlink EPERM/exit0；旧grant14/14/0skip/exit0，不算完整TC。

Run (cwd tools): `node --test --test-name-pattern="^TC-AUTH-001 source boundary preserves CRLF and Chinese original bytes$" skills/shared/crctl/scripts/test/execution-authorization.test.mjs`；然后 `node --test` 对三个相关文件。

## Task 2 — 并行：MDispatch001 本 change 根因

Files: M `server/internal/governance/four_phase_dispatch_cp_test.go` 与明确因果相关 Runner 文件（不猜改）。

- [x] 每轮核专用容器ID/label/55432/DB+user，URL仅内存；移除LiveGitHub凭据、不运行该用例。
- [x] 单进程architecture同名fixture→ownID缺失反例实际SQL23505/3层FAIL；公共setup按registry name清理后修绿。跨进程另有真实冲突与lease1FAIL后修复。
- [x] 不用sleep/skip/snapshot：双进程各10轮140/140；最新显式缺ID前态后扩大588/588/0fail/skip/exit0（-shuffle=3，仅排除LiveGitHub）。初始历史错误上下文缺失仍保留，不反推全部同源，见M mdispatch-diagnosis.md。

## Task 3 — 主线程：真实 CLI 隔离启动 PoC

Files: M `scripts/aifi45-isolation/`（仅实验，不接生产 dispatcher），T change `isolation-evidence.md`，M `CUSTOM.md`。

- [x] 固定官方Codex0.163.0 native release大小/SHA，完整下载/SHA/tar/临时镜像构建均实际通过；未全局安装/挂真实HOME/调用模型。
- [ ] 构建并实际运行 CLI --version；仅私有测试代码卷写入，read-only rootfs/cap-drop/no-new-privileges/network-none/私有HOME。
- [ ] synthetic canary 的正对照须可读，隔离侧读/写穿越必须被拒；检查实际 mount/network/caps，不以声明 flag 单独代证。
- [x] 真实CLI在限定配置下已实际跑通：`codex-cli 0.163.0`、非root/只读根/零cap/network-none、synthetic正负canary及链接穿越/宿主凭据/socket不可见、资源按nonce定向清理，exit0。**限制包揘**：本机无委派cgroup控制器（授权试启machine systemd后可用，但WSL API proxy pipe失效，已完整回退且恢复三容器/专用DB），因此`resourceLimitsEnforced:false`，CPU/内存/PID耗尽未受控；不据此开启准入。

## Task 4 — 主线程集成

- [x] design/test-plan/tasks/pending/phase-context及CUSTOM已同步，撤回不成立的消费闭环声明并保留历史结果。
- [x] 两仓原生validate/canon verify exit0（proposal各2/2），diff-check0；normal BUILD/in_progress，major未关闭，未改Gate evidence/扩权。
- [x] 后台执行/复审任务均已受理结束；instance/purpose label资源核容器/卷/镜像均0。当前实际阻断需新增VM/cgroup权限协助。

## 当前结果

Task1/2安全组件与Task4已按实际证据登记；Task3的CLI bootstrap与正/负canary已真实跑通，但resource limits在无委派控制器的本机未强制（已记录并未提权），且不接daemon任务/claim，不打开消费。独立审查curlrc/代理、cleanup误绿与cache重读TOCTOU已回修并随实跑生效。完整业务TC/切片仍0，Gate3未申请。
