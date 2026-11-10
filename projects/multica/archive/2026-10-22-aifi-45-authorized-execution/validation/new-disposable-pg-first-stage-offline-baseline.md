# 新 disposable PG 第一阶段：既有组件的离线基线

## 范围与预检

首次确认第一阶段后，只读核查 `../multica/scripts/aifi45-db/` 中先前已有的 fake-I/O 组件。以下源码和所选测试仅直接导入 Node 内建模块及彼此；运行前检查了静态导入与主要外部调用标记，运行后的补充检查发现测试还有四处动态导入，目标均为同一个已检查的 `instance-intent-record.mjs`（带不同 query），没有新增依赖路径；运行前的导入清单遗漏了这四处。lifecycle 测试由内存对象提供 fake `engine`、`record` 和 `runProbe`，不调用旧 runner，不传递真实容器、数据库、网络或本机资源。Node 自身 `--test` 创建其测试子进程；测试文件未调用业务子进程，不创建或清理真实资源。传给 Node 的环境只包含存在的 `SYSTEMROOT`、`WINDIR`、`COMSPEC`、`PATHEXT`、`TEMP`、`TMP`，未继承 `NODE_OPTIONS`、数据库地址或凭据。环境裁剪不是系统沙箱。

## 实际结果

- 明确的 Node v24.15.0 可执行文件，工作目录 `../multica/scripts/aifi45-db/`，参数 `--test --test-reporter=tap --test-concurrency=1`，仅选 `instance-intent-record.test.mjs`、`instance-intent-snapshot.test.mjs`、`instance-lifecycle.test.mjs`、`instance-ownership.test.mjs`。
- 退出 0；TAP 汇总 **180 tests / 180 pass / 0 fail / 0 cancelled / 0 skipped / 0 todo**。完整 TAP 未留存，不能作为逐项独立复跑记录。
- 首次调用没有明确指定 TAP reporter：Node 退出 0，但本次统计器找不到 TAP 汇总，因此该统计执行报告失败；这是**统计器与输出格式不匹配**，不是所选测试的行为 RED。随后显式指定 reporter 的结果如上。
- LF 规范化 SHA-256：`instance-intent-record.mjs` `9022344328d8f8c64894c26cbd3910f0c001954a8be31ea80b4641e8191680bf`；`instance-ownership.mjs` `0361ea8f8322c702220b794912a9d7daad431cb9fd04c50a2063128dbd482d23`；`instance-lifecycle.mjs` `bbe9f75058143d81136046705416358b000ffca109e2c88ea7a40adb3f7263b9`；对应测试依次为 `482f822294931519d44873acd966ca2977528f4b123391f5d99344c131e7563e`、`b3c185393e3fae007f921e59b28d46d70cdf394a418bcda557e361da3d9a6bcd`、`98aa51dbeb76058074c6397ee0ef884d76c06eb68fd5b4cd269980ebf80e59db`、`2cd78b64c1c5c63917823ac8a40047537dce6c6d9da56c9ef7df5ee52e889c7e`。此为所读快照摘要，不认证产物来源。

## 边界

这些组件是历史初稿，尚无真实引擎 adapter、可证明持久的 intent journal、可信进程树退出证明或新正式迁移入口，不能操作或清理真实容器。测试绿色不证明 OS 隔离、镜像和资源身份、迁移、旧行兼容、真实清理或业务 TC。旧实例和旧 runner 继续 HOLD；第一阶段决定见 [确认记录](new-disposable-pg-first-stage-confirmation.md)。
