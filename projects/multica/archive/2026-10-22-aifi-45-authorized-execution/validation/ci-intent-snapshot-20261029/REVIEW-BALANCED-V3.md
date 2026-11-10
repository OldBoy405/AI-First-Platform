# intent snapshot v3：独立 balanced 复审

**结论：限定范围内 PASS；非全验收。** 在标准内建函数可信、模块初始化可信且不受任意同 realm 篡改的前提下，未发现新的可证明实现 bug；本次测试和 raw SHA 核对通过。旧报告的 late TextDecoder 替换路径在该前提下已针对性收窄。强档独立复审仍未完成；backend actual **unknown**。旧 `REVIEW-BALANCED.md` 保留，不以本结论改写旧报告的执行违规事实。

## 快照与执行

对 live 的 `../multica/scripts/aifi45-db/` 四文件与 `source-final-v3/` 四文件逐原始字节 SHA-256 核对，测试前 8/8 匹配下表，测试后 8/8 仍匹配，前后逐项不变 8/8。源文件匹配用户指定 SHA：

| 文件 | live 与 v3 的 raw SHA-256 |
|---|---|
| `instance-intent-record.mjs` | `9022344328d8f8c64894c26cbd3910f0c001954a8be31ea80b4641e8191680bf` |
| `instance-intent-record.test.mjs` | `482f822294931519d44873acd966ca2977528f4b123391f5d99344c131e7563e` |
| `instance-intent-snapshot.test.mjs` | `b3c185393e3fae007f921e59b28d46d70cdf394a418bcda557e361da3d9a6bcd` |
| `instance-ownership.mjs` | `5c4785ae4a03a951a00a72248528ba97b11163caf5675c8304e6a8c656e05288` |

本次仅一次 Node 命令：`node --test --test-reporter=tap`，同时指定上述两个 live 测试文件；没有运行 `node --version` 或其他 Node 命令。Python 父进程禁用 stdin，子进程环境仅系统变量 SYSTEMROOT/WINDIR/COMSPEC/PATHEXT/TEMP/TMP 和收窄 PATH；完整 stdout/stderr 只在内存解析，不保存、不输出原始流。未证明 OS 级网络隔离。结果 exit 0，**36 tests / 36 pass / 0 fail / 0 cancelled / 0 skipped / 0 todo**；stdout 6509 bytes、stderr 0；六个固定审查控制测试名均为通过，两个选定 fixture 标记无输出命中。标记检查不是对所有可能泄露的穷举证明。本次不操作 DB、容器、真实 CR，不写删固定 /tmp 文件。

## late replacement 与测试正控

- `instance-intent-record.mjs:17,56` 在模块求值时保存 `TextDecoder.prototype.decode`，随后显式调用保存的函数。模块初始化**之后**仅替换该原型方法，不再能借这条调用拿到经摘要的子视图。
- `instance-intent-snapshot.test.mjs:104-118` 在正常模块已导入后安装替换方法，测试返回原值且替换方法未调用。静态比较 `source-late-decoder-red/`：旧源码是 v2，包含同一 late 测试体；旧动态方法调用会进入替换，先改变合法字段再原样解码，因原值和未调用断言失败。该对照是静态因果分析和用户所述作者 RED，**本次没有重跑旧源码、没有独立观测作者 RED 的进程计数**。
- v3 正常 GREEN 的 late 测试本身没有另行主动调用其恶意替换方法以验证它能成功修改；不应把 `invoked === false` 单独称作已动态验证攻击正控。擦除测试的预导入 hook 会被实际调用并观察到非空私有子视图，提供了较窄的 decoder 插桩正控，但不是同一 late 攻击的旧版运行结果。若交付门要求独立动态 RED/变异证据，该项仍待授权另行执行。

## fatal、擦除与既有边界

- `instance-intent-record.test.mjs:143-151` 在带唯一查询参数导入模块前安装 decoder 包装，之后恢复全局方法。被测副本持有包装；正常记录成功解码、观测 `fatal === true`。若去掉 fatal 配置，该断言不再通过；另有无效 UTF-8 和匹配摘要的拒绝测试，避免仅靠最终 JSON 错误伪装配置证据。
- `instance-intent-snapshot.test.mjs:121-156` 在导入副本之前同时安装分配/decoder 观察器，导入后恢复全局；执行时断言 hook 实际进入、观察到非空私有分配、触发嵌套成功、两个分配分别清零，以及畸形输入分配清零、调用方原件不被清零。`159` 起的失败注入在导入前替换 fill：擦除抛错时不得发布成功，finally 手工清理测试观察到的分配。这些断言有可观察正控；本次未实际运行变异体。
- 实现仍先验证 Buffer 形状及真实 Uint8Array kind，通过内建 getter 读取实际 backing、byteLength、offset，拒绝 shared/resizable；detached 构造 view 失败后固定拒绝。超总长在私有分配前拒绝；复制后摘要及解析读取同一私有快照，finally 尝试清零，擦除抛错覆盖返回。非零 offset 和跨 realm 真 byte view 正例、伪 brand/代理/分离及两条长度门的观测控制仍在测试中。覆盖不等于所有 Node 版本或平台兼容证明。

## 限制与风险

- **任意同 realm 篡改明确不在保证内。** 初始化前替换 captured 方法可被捕获；初始化后其他动态 Buffer/crypto/JSON 内建方法仍可被替换或借观察到的视图修改快照。模块级捕获不把 JS realm 变成沙箱，也不保证对全部同 realm 攻击一致性。`Buffer.isBuffer` 先于真实 kind 检查，恶意代理/原型链检查可能触发用户代码；固定异常不代表无副作用。
- finally 只尝试清理私有 Buffer；不清理调用方 Buffer、字符串、native 副本，也不保证异常终止时或物理内存擦除。摘要不是来源认证、授权或新鲜性保证。
- 本次未进行真实并发、生产 journal/引擎接线、DB/容器生命周期、部署、跨平台矩阵或 Gate3 验收。balanced 不能代替 strong；backend actual unknown。上述范围外风险和独立动态 RED 缺口应保留在交付判断中。
