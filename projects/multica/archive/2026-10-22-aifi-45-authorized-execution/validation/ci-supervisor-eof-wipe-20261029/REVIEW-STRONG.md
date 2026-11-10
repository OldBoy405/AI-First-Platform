# Supervisor collector：独立静态复核

请求 strong（`GBClaude/claude-opus-5-5:high`），实际 backend receipt unknown。复核者只读 `source-final/` 与 `source-sticky-green/`，未运行测试或核算 hash；以下 raw SHA 为作者的 `REVIEW-STICKY-GREEN.json` 与独立 balanced 复跑所记录，不归称 strong 自测。

## 发现及修订

- 对旧版 collector `9c4d561f…`：双 EOF 解码成功后，若擦除与异常处理中的第二次擦除都抛异常，`failure` 尚未登记且 `decoded` 已是成功结果；在浅栈重新 `result()` 会错误返回成功，缓冲也未擦。受控双重故障注入 `REVIEW-FAULT-RED.json` 复现该后果；是合成异常而非真实栈耗尽实验。
- `b24050bc…` 将解码结果延迟发布至擦除后，排除该 false-success；但 fault 后再触发数据事件可能将 `DATA_AFTER_EOF` 误作首错。`REVIEW-STICKY-RED.json` 检出，历史源码/测试分别保存在 `source-fault-green/` 与 `source-sticky-red/`。
- 静态复核 `fa9d4013…`：先记录 sticky failure、擦除成功才置 `wiped`，失败保留重试条件，已擦除不重复填充；解码结果只在擦除后发布。其受控事件语义的条件性 GO 不是进程或部署 GO。`REVIEW-STICKY-GREEN.json` 为作者的 59/59；后续仅测试扩展，最新版见 `FINAL-GREEN.json` 与 `source-final-rechecked/`。

## 未闭合与接口约束

- 同 realm 内建方法可被篡改；栈临界、内存异常等可能在错误对象分配前抛出，不能保证 sticky 首错、擦除或固定错误形状。若多次擦除都抛异常，异常可能直接逸出，私有缓冲可能仍含明文；此时必须标记清理未证实，不能声称已擦除或输出异常原文。
- 只到一个 EOF 或异常后再无调用时无法自动保证擦除。未来 pump 必须把任何异常视为失败，在 finally 进行有界的 result/abort 尝试；多次失败不得无限重试或报告清理完成。`scripts/aifi45-db/README.md` 现记录该接入前置。
- 独立测试是 Buffer 注入的受控故障，不代表真实栈耗尽、OS 资源退出、跨进程可信、所有副本或 GC 擦除。`MUTATION-FINAL.json` 记录实际运行的早擦/首错变异；未运行的变异不能说已证实。
- 本次 GO 不授权调用生产入口、清理数据库/容器或推进 Gate。原始测试 stdout/stderr 未保存；JSON 仅为派生计数和固定诊断。
