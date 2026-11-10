# CI intent 解码快照加固计划

**目标：** 不改变 intent wire 格式，在不可信输入对象的有界快照上校验和解析，避免 checksum 与解析读取不同字节。

**范围：** `multica/scripts/aifi45-db/instance-intent-record.mjs`、同名测试和 `multica/CUSTOM.md`。既有约束见 `ci-instance-intent-review-20261028/`、`ci-disposable-db-implementation-plan-20261028.md`。该 codec 是未接入生产 journal 的草案，SHA-256 仅是完整性校验，不认证来源或授予清理权限。

- [x] 按原始字节保存变更前源码、测试、依赖和 CUSTOM 快照；核查 codec 调用方。
- [x] 先补可执行 RED：共享缓冲在校验后被修改不能改变结果；伪造长度不得绕过实际字节上限；非真实 byte view 和自有方法欺骗不能逃逸固定错误或影响解析。测试只输出固定诊断，不打印 payload、canary 或异常正文。
- [x] 沿用 supervisor parser 的 intrinsic getter / typed-array kind 判定模式。拒绝共享和可调整 backing、分离输入走固定错误；复制前限制实际长度；hash、header、JSON 都只读同一私有字节快照。有效非共享 Buffer view 含 offset/pool 正例保留。
- [x] 快照所有解析结果发布前尝试清零；擦除失败不发布成功。初始化时捕获 decoder 防止该方法晚替换，仍不代表调用方原始 buffer、JS string/native 副本或其他同 realm 内建函数未被篡改。
- [x] 保留此前总长度边界、payload 长度和 fatal UTF-8 测试的可观测正控；最终版本十一项定向变异含 fatal，见 `MUTATIONS-V3.md`。
- [x] no-DB 精确选择 Node 测试，捕获派生计数，不保存或打印原 stdout/stderr；分别记录 RED/GREEN/skip/源码 raw SHA。未证明 OS 级网络隔离或子进程输出不存在敏感内容。
- [x] strong 请求会话已完成限定边界静态复查：`REVIEW-STRONG-V3.md`；actual backend unknown，未独立重算 SHA 或动态复跑，不等于生产或 Gate 验收。
- [x] `CUSTOM.md` 按当时结构登记；未运行真实 DB、容器、进程终止实验、真实 CR；未改历史报告或任何未知路径。
