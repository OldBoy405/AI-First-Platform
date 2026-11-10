# 必需环境键局部修复：作者证据

## 旧代码 RED

在 `../multica/scripts/aifi45-db`、白名单环境并清空 NODE_OPTIONS，使用 Node v24.15.0 执行 `node --test --test-reporter=tap --test-name-pattern="reject (non-enumerable required environment key|inherited required PGDATA)" instance-ownership.test.mjs`。5 个独立用例均以 `Missing expected exception` 失败，exit 1，pass 0/fail 5/skip 0；四个隐藏必需键加一个继承 PGDATA。旧源码 raw SHA `5c4785ae4a03a951a00a72248528ba97b11163caf5675c8304e6a8c656e05288`，含新增测试的 raw SHA `ba914cb5f952c8c71877dc442767aec172de2a9d0dfcf07954e3cc3d81ad6f02`。测试的首个 intent 断言已失败，因此不能声称 RED 时 ownership 断言也执行。此前试误用 sandbox `process.execPath`（Bun）退出 1，未选中目标测试；后来 Node spec-reporter 同样 5 次缺异常，未计入上面的 TAP 结果。

## 最小修改及 GREEN

必需 PGDATA 和 POSTGRES_DB/USER/PASSWORD 均改为要求自身可枚举，PGDATA 的固定路径和其他非空字符串规则、全部键值匹配保持。继承/隐藏属性无法再满足必需项；未承诺对恶意 Proxy、动态 getter/随时间变化输入或同 realm 篡改的防护。

单次 Node `--test --test-reporter=tap` 运行 `instance-ownership.test.mjs instance-lifecycle.test.mjs instance-intent-record.test.mjs instance-intent-snapshot.test.mjs`，exit 0，**166 pass/0 fail/0 skip**，不加总其他历史结果。相同白名单限制环境但不能证明 OS 网络隔离。全部是纯内存合成输入；未启 Podman/DB/网络或调用真实引擎。

最终 raw SHA：ownership `1593287fafd87424bb8d19564748048003a07ed0c2966e0d6c9936ee28b2b871`，ownership test `ba914cb5f952c8c71877dc442767aec172de2a9d0dfcf07954e3cc3d81ad6f02`，lifecycle test `9a628afcde61bdd1b0a2c47ad0ab8f2c9656db04943c196c1c8cc6b614f5b5f4`，intent record test `482f822294931519d44873acd966ca2977528f4b123391f5d99344c131e7563e`，intent snapshot test `b3c185393e3fae007f921e59b28d46d70cdf394a418bcda557e361da3d9a6bcd`；`source-final/` 为独占创建的 7 个原字节副本。未保存原始测试 stdout/stderr，以上为内存解析派生结果。独立复核等待中；不代表生产隔离、清理或 Gate3 证据。
