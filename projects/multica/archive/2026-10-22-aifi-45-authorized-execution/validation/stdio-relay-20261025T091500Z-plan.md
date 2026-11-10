# daemon 私有中继：把已签证明只交给本 run 的子进程（计划）

> 前置事实（已实证）：`server/internal/daemon/execenv/isolation.go` 的 `PrepareIsolated` 只是把 **prepare 阶段** 放进一个可被 kill 的 helper 子进程（`__multica_execenv_prepare`），**不是**容器/沙箱。因此本片不继承任何“已隔离”假设。

## 为什么要做这一片

服务端已能签 `execution-binding/v1`（20 键、Ed25519，T 侧已互通验证）。但**证明怎么到 T 手里**目前不存在：没有传递通道，也就没有“只给本 run”的语义。这一片只解决**交付正确性**，不解决**隔离**（同 UID 对手仍可读同 UID 的任何文件/管道，真正的边界要容器，见 `trust-root-20261025T084600Z-report.md`）。

## 交付判据（可验证）

1. 同一次 run 的 T 子进程**能**收到与该 run 的 `(task_id, runtime_id, dispatched_at)` 匹配的 envelope。
2. **另一次 run/另一个 task**（同 workspace、同 daemon、不同代次）的子进程**拿不到**它——不是“权限检查失败”，而是**通道里就没有**。
3. 未签（没有 envelope）时，子进程**不**收到空/占位文件，daemon 也不创建通道（fail-closed，无空证明）。
4. 通道在 run 结束后不残留（文件被删/描述符关闭），且不进 task 日志。
5. `EXECUTION_CONSUMPTION_REQUIRED` **保持不变**：交付≠准入，T 仍不得据此消费。

## 有界范围

- 只加：一个 per-run 私有交付原语 + 在既有 exec 点接线 + 一条真实合成子进程测试。
- 不加：容器、cgroup（已有独立实证）、T 侧消费事务、activation、新表、新 env 全局开关。
- 不改：`handleTask` 的 claim/fence 语义、终态上报路径（前两片已冻结）。

## RED 先行

先写一个**真实合成子进程**测试（子进程打印它实际收到的字节摘要与来源），在当前代码上必须**失败**（因为通道尚不存在）；再实现最小通道使其通过。禁止用 mock 代替子进程。

## 待定（等 seam 调查结果）

- 通道形态：`ExtraFiles` 附加 fd（首选，需 exec 点可控）vs 0600 per-run 文件 + env 指向路径（次选，需确认 execenv task root 已是 per-run 且清理）。
- 若 exec 点在 SDK 内部不可注入，则退回“per-run 文件 + env”，并在报告中明确该形态**不防同 UID**。

## 不做/不声称

不签消费、准入、activation、隔离执行域、全局 C1；不关闭任何 major；TC 计数不变（0/49）。
