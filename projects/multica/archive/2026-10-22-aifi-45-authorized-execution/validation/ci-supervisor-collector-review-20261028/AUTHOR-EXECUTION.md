# Supervisor 受控事件收集：作者记录

## 能力与边界

新增 `supervisor-collector.mjs` 和 `supervisor-collector.test.mjs`；尚未接入 `run.mjs`、任何子进程、真实流、容器或生命周期。受控调用方推送 stdout/stderr 非共享 Buffer 事件，stdout 累计最多 65536 字节、stderr 最多 65536 字节且不存储内容；校验两个 EOF 后才调用既有 decoder。重复 EOF、EOF 后数据、空 chunk、异常输入、越界、缺 EOF 和显式 abort 固定错误并粘滞失败；解析与失败后清空内部 stdout 缓冲。结果只含固定字段和 decoder 枚举，不回传输出、异常或秘密。

**不能**据此证明事件来源、真实管道排空、截止时间、进程树退出、可信 engine、journal 落盘或容器清理资格；上层可伪造受控事件，本组件不是授权边界。

## 测试与变异

- 新增测试后但源码模块尚不存在时，`node --test` 因 `ERR_MODULE_NOT_FOUND` 失败；这是测试脚手架 RED，**不是行为断言 RED**。
- 初版 15 项通过后，新增 abort 断言，在无 abort 实现时实际失败；添加 abort 后 16 项通过。
- 两项变异仅在 `mkdtemp` 创建的独占复制树执行：去掉 stderr EOF 检查，16 项中 1 项失败；去掉 stdout 限制检查，16 项中 2 项失败。执行后逐项删除复制的 3 个文件并确认空目录后删除；真实源码未变，最终再跑 16/16、0 skip。
- 作者 Node v26.3.0；六个测试文件（`instance-intent-record`、`instance-lifecycle`、`instance-ownership`、`run`、`supervisor-protocol`、`supervisor-collector`）联合运行 **202/202，0 fail、0 skip**，12 个输入文件前后 raw SHA 均相同。使用独占临时目录作为 TMPDIR/TMP/TEMP，结束确认空后删除；这些是 fake I/O，不是 DB 测试。
- 最终 raw SHA-256：collector `340403a916e68b4eef6be4f17831414de100220c4bd422a76d55fda0eca2ca7a`；test `5350526362ffd81069a291a2272e54532b77e7528b489b654c07a74b810f0e33`；decoder `bed82664f2f17918b47302a94255e3061cbce9f516f578a074a997671b75452c`。没有保存作者完整 stdout/stderr，此处为作者记录。
