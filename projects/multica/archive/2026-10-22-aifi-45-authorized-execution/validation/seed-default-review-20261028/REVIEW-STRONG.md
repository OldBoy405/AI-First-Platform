## 结论：不予整体 PASS；种子修正的静态检查成立，执行安全仍待补证

本次**只读**完成四份文件的全文审阅及 Git 差异核对；**未运行任何 DB、容器或测试，未修改文件**。

### 1. 原始字节 SHA-256：四项全部匹配

核验来源：平台指定的 `source-manifest.json`；实际文件位于 sibling `../multica/`。按原始字节计算，**未规范化换行**。

| sibling 文件 | 实测 SHA-256，与 manifest 一致 |
|---|---|
| `scripts/aifi45-db/run.mjs` | `db8adbdb671b5ee2c49225929d3812f3e0c1cfc87cb85d88f88ed18e34bcba08` |
| `scripts/aifi45-db/run.test.mjs` | `6aedaf7ca1f7f847a84117de643c3abdea773e1c085b94a1ac8fe7a336f05113` |
| `scripts/aifi45-db/README.md` | `d5cffc40fd545a3cd1185007f682a16f2db878ebd16d21b514ec14023668fadb` |
| `server/migrations/101_task_usage_hourly_schema.up.sql` | `6ca1d55807d9c02ab433b74acb825e4d7aac9b9fa4d89a2c8074587653a35eb7` |

以下路径均相对 `../multica/`。

### 2. 种子与隔离：源码中未见继续复制保留库状态行

- **旧的状态表 data-only dump/import 循环已删除。**当前 `run.mjs:124–145` 只将 schema dump 导入临时库，然后执行：
  ```sql
  INSERT INTO public.task_usage_hourly_rollup_state (id) VALUES (1) ON CONFLICT DO NOTHING;
  ```
- 该 INSERT 与迁移 **101:94** 一致，仅增加 `public.` 限定。迁移 **101:86–93** 定义的初始值为：`id=1`、epoch watermark、`last_run_rows=0`，其余三个可空状态字段为 NULL。
- 目标名称由随机 nonce 生成并校验（`run.mjs:16–25,76–78`）；角色创建显式禁用高权限属性（`:129`），数据库由 `template0` 创建（`:134`）；schema 和 seed 都显式使用 `target.database`、`target.role`（`:141–144`）。**静态参数链成立，没有 seed 指向保留库的路径。**
- **限定：实际默认值来自保留库导出的 schema，而非重新执行迁移 101。**若该库的列默认值、触发器等已漂移，文本相同的 INSERT 不足以证明实际行与 101 初始状态完全一致。当前 runner 未查询并核验 seed 全字段，也未核验这些 schema 属性。

**既存 approval backup 必须区分：**`run.mjs:122–123` 仍有一项 `approval_record` data-only 导出，保存为 `.original-approval-record.sql`；其内容是敏感原始行证据，**不是导入材料**，源码未把它传入临时库 SQL。这里不能把“一项 backup”理解成“只有一行记录”；本次未查询数据库记录数。

### 3. 失败及清理路径：未因 seed 修改而放宽，但并非执行证明

Git 差异显示，seed 修改之外没有改动 `catch/finally` 清理流程：

- seed SQL 失败进入 `main` 的 catch，记录 failure，然后进入 finally（`run.mjs:177–180`）。
- 初始快照存在时，复核原库摘要、其他会话及 advisory locks；漂移或未释放则停止清理（`:182–191`）。
- 删除临时库前复核身份；删除角色前复核 OID、marker；最后独立查询两个名字是否缺席（`:192–211`）。
- 失败、原库未确认不变或未清理，最终设置失败退出码（`:225`）。

因此，**静态上未见因 seed 改动引入失败后继续测试、静默成功或扩大删除范围**。但快照只覆盖指定行内容，不覆盖全部 schema、权限、序列变化；也没有跨调用锁，不能由此证明“数据库完全未变”。

### 4. 安全发现：mock 的证明范围明显小于测试标题

**[中／补证项] 新增 mock 不证明 SQL 成功执行或完整流程成功。**

`run.test.mjs:104–163` 在识别 seed 后主动抛出 `simulated stop after disposable seed`（`:144–148`），所以不会到达：

- seed 后事件；
- 真实身份、空表与原库拒读检查；
- Go 测试执行及正常成功收尾。

它证明的是“runner 到达了预期 seed 调用并走失败清理路径”，**不是实际生成了正确默认行**。

**关于 `main catch` 吞掉断言：不能一概认定误报，也不能认为完全防住。**

- mock 内 seed 的数据库、角色断言发生在 `seed = query` **之前**（`:145–147`）。若断言失败，即使异常被 `main` 捕获，外部 seed 匹配断言仍会失败（`:157`）。
- 再次调用旧的特定状态表 dump 时，先记录 `copied`，外部检查它必须为空（`:120–122,156`）。因此对**当前明确针对的旧调用回归**，存在 catch 外的判据，不是仅靠 mock 内抛错。
- 但 mock 对其他 `pg_dump` 一律返回相同 synthetic 文本（`:119–124`），未区分 schema 与 approval backup，也未完整约束所有 data-only 导出／导入。
- seed SQL 只做**非锚定正则**匹配（`:157`）；不能排除前后附带额外 SQL。
- DROP 命令统一返回成功，absence 查询固定返回两个 false（`:143,150`），不跟踪实际创建／删除状态。因此即使漏掉 DROP，也可能仍得到 `owned_resources_cleaned=true`。
- 外部只要求 `meta.error` **包含**预期中止文本（`:160`），未要求没有附加清理错误；本用例也未断言失败退出码。

这些是**测试覆盖及证据强度缺口**，不是已经证实当前生产路径执行了错误 SQL。丢失 CREATE ROLE acknowledgement 用例（`:165` 起）有独立的外部状态、meta 和退出码断言，但也不能替代完整成功路径验证。

### 5. README：主要边界更准确，仍有未核实／不完整处

- `README.md:24–29` 正确区分 schema 导入、默认 seed 与敏感 approval backup。
- `:37–43` 明确环境黑名单并非完整隔离，也明确 `-skip` 可能不产生事件。
- `:51–57` 正确改为每次 invocation 的 finally 比较，并承认快照范围和并发锁限制。
- **`:18` 可选参数列表不完整**：实际还接受 `-migration=...`，且 up/down 都允许（`run.mjs:70–75,146–150`）。应说明这些额外 SQL 同样在临时库中以受限 owner 执行；它们不是 seed 一致性的保证。
- `README.md:46–50` 对 `cmd/server` 的 `TestMain` 作了额外断言；**本次四文件审阅未核验该实现，不能将 README 本身当证明**。
- “密码不进入证据”的实现有生成密码替换及输出检出，但不构成任意编码、分片或恶意输出下的保密证明；README 已明确这不是恶意本地代码沙箱。

### 6. 限定验收意见

**可确认：**manifest 对应的源码已将“复制保留库 rollup 状态行”改成“临时 nonce 库内、受限角色执行迁移 101 形式的默认 INSERT”；既存 approval backup 仅作为敏感证据保存；失败／清理逻辑没有因这次 seed 修改被放宽。

**不能确认：**实际导入 schema 后的 seed 全字段值、真实权限拒绝、原库前后状态及真实资源清理。本次没有执行这些验证。若要宣称运行安全或实际默认值一致，仍需另行授权的真实 DB 证明，或可独立核验的对应执行证据；同时应补强 mock 的命令白名单、外部失败判据和资源状态模型。

作者报告的“旧行为纯 mock RED、修后 10/10、再次调用旧 dump 变异 RED、SHA 恢复 GREEN”，**仅记录为作者陈述，本次未独立执行或复现**。

**通用 CI provisioning 缺口依旧，本次不构成其验收；也不解除事故、旧 runner HOLD、Gate 3 或发布限制。**