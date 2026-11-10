# Kill-on-close 双 Job 方案（只读设计审查）

**execution: BLOCKED**。无源码、未运行；非实测、非能力证据。依据：`KILL-ON-CLOSE-PLAN-BLOCKED.md` `7704a5d8…6e39`、探针 `27bb70f9…1c3a`、x/sys v0.48.0/Go 1.27.1 源码。

## 结构
- S：主测试建，匿名、nil 属性不可继承，仅主测试持有；KILL_ON_JOB_CLOSE，回读无 breakaway 且为空。
- T：helper 建，同配置；helper 已在 S，故 T 嵌套于 S。
- 主测试不入 S/T。S 成员仅来自主测试按已证身份句柄分配的 helper 及其继承，TerminateJobObject(S) 只触及本次进程。
- 不用 DuplicateHandle；PID 仅比对，不用于打开或终止。

## 握手
- P0 主测试：opt-in 检查，建 S。
- P1 exec 启动 helper（stdin/stdout 管道，环境仅 opt-in+role+nonce）。helper 收 `G` 前不派生，EOF 即退出。
- P2 Wait 前（exec 持句柄，PID 不复用）OpenProcess(SET_QUOTA|TERMINATE|SYNCHRONIZE|QUERY_LIMITED)，验 GetProcessId，分配入 S，验 S={helper}、1/1。失败则关 stdin、有界 Wait。
- P3 helper 收 `G`：建 T、回读、自身加入、验 T={self}；派生 gc（stdin=NUL 不读；写 `R` 后睡 20s 自然退出 0；-test.timeout=25s）。有界读 `R`，验 T={self,gc}、2/2，回报 ARMED。失败：经 exec 句柄显式终止 gc 并 Wait，报固定码。
- P4 主测试有界读状态（超时经句柄终止 helper），验 S 2/2 且含 helper。
- P5 写 `Q`：helper 原地 os.Exit(0)，不走杀 gc 的 defer、不显式关 T。EOF 无 `Q`：显式终止 gc 后退出。
- P6 句柄等 helper ≤5s、码 0；3s 内 S active=0、total=2，且 `R`→S 空 ≤12s 才 PASS，否则 FAIL/INCONCLUSIVE。
- P7 S 未空→TerminateJobObject(S)，3s 验空；仍未空→CLEANUP_FAILED，观察至 gc 自限期+5s；不按名称/PID 清理。
- P8 关 helper 句柄，最后关 S，exec Wait 带 WaitDelay。

## 负控（同源码，独立运行）
- N1 EOF 控：T 不设 KILL_ON_JOB_CLOSE。helper 退出后 3s 内 S active 应仍=1，证明 helper 死亡/管道 EOF 不令 gc 退出；随后 TerminateJobObject(S) 清理验空。
- N2 自然退出控：不发 `Q`，gc 约 20s 自然退出后 S active=1，校准自然退出远离 12s 判据。
N1、N2 均符合预期，主实验 PASS 才可解释。

## crash 清理
- 主测试死于 `G` 前：helper EOF 退出，无派生。
- 死于 `G` 后：helper EOF 无 `Q`→显式终止 gc；S 关闭为第二层。
- helper 死于派生后、回报前：主测试经 EOF/句柄检测→P7。
- 两者同死：仅剩 Job 机制与自限期，遗留**有界非零**（≤约 25s），零遗留不可证。
- 意外进程入 S/T 会被清理并致计数失败。

## PASS 证据边界
S 打开、N1 成立时 S 由 2→0，仅表明 T 关闭终止了一个本次自有的休眠 grandchild；不证明对抗逃逸、进程树退出、CI/容器清理。

## 未验证前提
- Wait 前 OpenProcess(pid) 必得同一进程。
- Win8+ 允许 H→S→T 嵌套；宿主限制致前置失败（安全）。
- `G` 前 Go 运行时不派生；gc 继承控制台不建 conhost。
- EDR 持 T 句柄则 FAIL+S 清理。

## 实测前
按 P0–P8、N1/N2 写源码并另行 strong 审查：`G` 前零派生、`Q` 绕过 defer、EOF 无 `Q` 显式杀 gc、gc 不读 stdin、等待全有界、终止只经 S 或自有句柄。通过前保持 BLOCKED。
