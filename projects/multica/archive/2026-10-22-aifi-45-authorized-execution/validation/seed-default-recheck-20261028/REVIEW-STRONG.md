## 追加复审结论

**原报告保留，不作改写。**本次四文件全文复读及静态检查显示：全字段读回与 mock 的主要补强有效，**可以有条件进入一次既有批准范围内的 pinned 容器／新 nonce 库真实测试**。这不是执行证明，也不是全局 PASS。

本次**未修改文件，未运行 DB、容器或测试**。

### 1. 新 manifest：四项原始字节 SHA 全部匹配

来源：`validation/seed-default-recheck-20261028/source-manifest.json`。以下实际文件均位于 sibling `../multica/`，按原始字节计算，未规范化换行。

| 文件 | 实测 SHA-256，与 manifest 一致 |
|---|---|
| `scripts/aifi45-db/run.mjs` | `02a62a686f3b120a0ad3449bb418565d2d63d95235be291d50d77b63d20cdae1` |
| `scripts/aifi45-db/run.test.mjs` | `76f710e8712c841b7df87871348d8c58109099d0756e2cb39e7d2ec1cb2fdc24` |
| `scripts/aifi45-db/README.md` | `9a56fa819ed6e631ace68af30644fb2d1ef188c5c737e12c1e18e5b15bd61339` |
| `server/migrations/101_task_usage_hourly_schema.up.sql` | `6ca1d55807d9c02ab433b74acb825e4d7aac9b9fa4d89a2c8074587653a35eb7` |

### 2. seed 读回：六字段齐全，静态上 fail-closed

迁移 `101:85–93` 的初始行，与 `run.mjs:144–149` 对照：

| 字段 | 读回要求 |
|---|---|
| `id` | `1` |
| `watermark_at` | 带时区的 epoch instant |
| `last_run_started_at` | NULL |
| `last_run_finished_at` | NULL |
| `last_run_rows` | `0` |
| `last_error` | NULL |

SELECT 同时要求 **总行数 `rows=1`、完整符合默认值的行数 `default_rows=1`**，不只是检查存在某一行。时间比较显式使用带偏移的 `timestamptz`，不依赖显示时区。

**目标参数成立：**

- nonce 名称生成及约束：`run.mjs:16–25,76–78`。
- 受限角色、`template0` 库及 owner：`:129–138`。
- schema、INSERT、SELECT 都显式传入 `target.database`、`target.role`：`:141–148`；SQL wrapper 将其用于 `psql -d/-U`（`:92–95`）。

**错误与缺失值处理成立：**

- SQL 非零状态先抛错（`:87–95`）。
- 非法 JSON 解析失败；无输出、null、缺失字段、字符串 `"1"` 或其他非数字 1 均不能通过严格比较。
- 空表、额外行、任一字段漂移均不能通过两个计数。
- 不匹配在记录成功 seed 事件及继续迁移／身份检查／Go 测试之前抛错（`:149–167`）。
- 异常进入 catch/finally，最终失败退出（`:182–230`）。

**仍有边界：**这是对当时实际行值的验证，不是完整 schema、触发器或迁移历史一致性证明；而且检查发生在可选 migrations **之前**（`:151–156`）。后续迁移仍可能改变状态。单次 seed 验证不应被表述为永久不变量。

### 3. mock：原主要误报风险明显收紧，但仍不是数据库模拟器

**已补强且可静态确认：**

- INSERT 改为 catch 外的**完整字符串相等**断言（`run.test.mjs:176`）；漏调用或附加 SQL 不再仅靠非锚定匹配放过。
- SELECT 的调用、目标和六字段条件有外部检查（`:155–160,177–182`）。
- 有效分支必须到达后续身份检查；失效分支不得到达（`:162–164,183`）。因此删掉读回判定，失效分支会出现外部断言不符。
- mock 内断言发生在记录 `seed`／`checkedSeed` 之前（`:149–159`）；错误即使被 `main` catch 捕获，也会使外部判据失败。
- 角色／库存在状态分别记录；只有精确 DROP 才改变状态，absence 查询返回该状态（`:111,134,148,166–168`）。外部同时要求 meta 清理成功和两个实例状态均不存在（`:185–187`）。**普通漏 DROP 不再能靠固定 false 的 absence 响应掩盖。**
- `meta.error` 改为精确相等，并检查失败退出码（`:188–189`）；附加清理错误不能再靠“包含预期文本”混过。

**剩余安全／证据发现：**

1. **[中，测试边界] 并未模拟实际行写入。**  
   SELECT 的响应只由 `valid` 决定（`:160`），不依赖实际表状态。外部断言能捕获“缺失 INSERT 调用”，但不能证明 INSERT 在 PostgreSQL 中真的产生预期行。

2. **[中，mock 完整性] 实例模型仍不约束全部生命周期。**  
   observe 返回身份时不检查资源存在；schema／seed 调用也不要求库已存在（`:144–160`）。例如漏掉 CREATE DATABASE 调用，而保留后续流程，可能仍被这种模型掩盖；DROP 也没有模拟“不存在则失败”。它比原版强，但不能称为完整实例状态机。

3. **[低，回归覆盖] 两分支都仍是预期失败路径。**  
   有效分支在身份检查处主动中止（`:162–164`），未覆盖实际身份拒绝、Go 执行及正常 exit-0 收尾。另未枚举空输出、JSON null、缺键、SQL 错误、零／多行等读回异常；这些目前由源码推理支持，而非本次独立测试。

4. **[低，导入判据] dump 白名单仍是参数包含式匹配。**  
   schema 和 approval backup 返回相同 synthetic 文本（`:121–130`），不能证明两者绝无混用。**当前 runner 源码未见这种混用**，但 mock 本身不充分证明这一点。

### 4. README 与保留边界

- `README.md:18–21` 已补齐 ordered up/down migration 参数及“不能证明完整迁移历史”的限制，原文档缺口已补。
- `:27–32,70–71` 正确区分 schema-only 导入、默认 seed 与敏感 approval backup。
- `:40–60` 保留环境黑名单、skip 选择、快照范围及无跨调用锁的限制，符合当前实现。
- 补读了 README 引用的 `cmd/server/integration_test.go`：启动身份检查确实先于 fixture setup（`:64–71`），检查内容见 `:110–132`。但**收尾 cleanup 前没有再次验证身份**（`:98–104,245–252`）；README `:50–54` 不应理解为每次 cleanup 都重新检查。该辅助文件不在此次四项 SHA manifest 内。

**既存 approval backup 仍只作为敏感证据：**`run.mjs:122–123` 的 data-only 导出被保存，没有进入临时库 SQL 调用。这里是“一项 backup”，不是断言只有一行记录。

### 5. 是否可进入单一真实隔离库测试

**可以，有条件；本次不执行。**平台 `phase-context.md:37–43` 记载的既有范围是保留原库／事故证据、另建可丢弃库继续，并不解除原库 HOLD。本次未发现新增的 seed 代码阻断项；剩余关键问题需要真实受控执行补证。

条件应限定为：

- **一个执行者、一次 runner invocation、一个明确包及精确测试选择**；不扩大为整包／多包回归，不使用 `-skip` 隐去用例。
- 使用 manifest 对应源码；冻结所选 Go 测试及实际依赖版本——四文件 manifest 本身未固定完整 Go 执行输入。
- 仅既有批准的完整 pinned 容器身份；无替代服务器、无维护／重建／全局权限变更。
- 使用新 nonce 库和 owner；本次 seed 验证优先不附加无关 migration。
- 保留独立证据前缀，核对 `seed-state-initialized.verified={rows:1,default_rows:1}`、真实身份／拒读、预定测试实际通过且零 skip、原库前后摘要与释放状态、精确资源缺席及最终 meta。任何失败、漂移或清理不明即停止，不以强删收尾。

作者所称“两负例先红、删除 readback 校验又红、恢复源码 SHA 后 11/11”，**仅记录为作者陈述，未独立执行或复现**。

**最终限定：可以进入上述单次受控补证，不等于 runner 已全面验收。未来作者实测也只能作为该次证据审阅；通用 CI provisioning 缺口、事故历史、旧 runner HOLD、业务闭环及 Gate 3／发布限制均不因此关闭。**