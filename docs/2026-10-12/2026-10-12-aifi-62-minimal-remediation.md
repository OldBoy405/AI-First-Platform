# AIFI-62 六项异常最小修订实施方案

> **For agentic workers:** 按工作区已有 CR、受控 shell、评审、审批与发布流程逐任务执行。本文件只授权范围讨论，不授权执行或状态推进；不要求引入新 Skill、第二执行器或新的权限框架。

**Goal：** 修复 T1、T2、T3、T4、T5、M2，解除追溯生成阻塞，减少根绑定与文本交付问题，同时保留现有门禁、审计和恢复合同。

**Architecture：** 修改现有生成器、恢复参数构造、交付衔接约定和任务结果保存逻辑。复用 `workspace inspect`、`resolveOperationalWorkspace`、`execution_context`、checkpoint、事务恢复及现有复制组件，不新增数据库表、接口、状态转换或依赖。

**Tech Stack：** tools 使用现有 Node.js 脚本、`node:test`、Skill／Agent／Pipeline 定义；multica 使用现有 Go 服务、Go 测试、Vitest 和共享复制组件。运行版本按两仓现有要求，不在本方案中升级工具链。

**Spec：** 本会话经 Ray 确认的修订范围：T1／T2／T3／T4／T5／M2；M1 明确排除。事实依据为 AIFI-62 的机器回执、两份人工终端附件及当前仓库源码。

**状态：** 方案待确认；没有实施补丁、运行仓库回归、创建 CR 或重新派发任务。

## 1. 背景与源码基线

截至本会话已读取的最新回执：

- AIFI-62：`blocked`，关联业务 CR 为 `CR-2026-076`。
- feature-writeback 的 node 1 合并、node 2 PRD／SDD 回写、node 3 的 17 个 TASK 回写已完成并发布。
- node 4 `writeback-traceability` 因 `FR-SUP-01…09` 编号不被生成器接受而失败；node 5 尚未执行。
- 此前发布滞后已由人工 checkpoint 批次 `14a02f8cde9a59a4` 解除，不能因此重跑已经完成的合并。
- 原排队问题 M1 不纳入本方案。

本方案核对的源码：

| 仓库 | Commit |
|---|---|
| AI-First-tools | `c69336475d01c4de5a42efc0dc087a5e605b5c82` |
| AI-First-multica | `c47381ae72d4a274cf55208ea45bc105bb0bfc77` |

下文路径均相对各自仓库根。实施者开始前应比较实际目标分支；行号仅帮助定位，函数与合同为准。不得把本方案引用的源码版本当成已经部署的版本。

### 事实入口

- T1：AIFI-62 评论 `01a12f37-3428-7322-b68c-6bbacac5dbe3`、`01a12f39-dda7-7f20-8343-b92647898642`。
- T2：评论 `01a12f06-7c3c-7133-83be-049a7768f6d7`、`01a12f09-0c13-79e4-9b80-182823a04a2d`。
- T3／T4／T5：评论 `01a12f2e-95cb-7216-8fb5-755b2c3447b1`、`01a12f31-a995-71b3-bd58-862daf412600`。
- M2：附件 `01a12f11-1e26-782d-9a1e-f515f19bad73`；修正命令后的成功附件 `01a12f16-1dda-75ff-8d33-bb194d762d57`。
- Issue：`01a120c6-4681-7c18-ae40-e13067c94ed6`。

## 2. 全局约束与不做事项

1. 原 CR 已进入 `writing-back`，不新增回开发阶段的转换，不私改冻结 plan／审批／账本。修复按现有正常 CR 路径另行交付，具体组织由 Ray 确认；本方案不自动注册 CR。
2. 不放松跨根校验、可信绑定、发布前置、TASK／证据交叉检查、candidate-only、CAS 或审计。
3. 不清除／覆盖 Task 环境，不在同一 Task 中切换操作根，不改写机器 recovery 的 argv。
4. 不强推、不手工清理 journal、不改历史合并事实，不为了修复生成器重新审批原业务 CR。
5. 不新增通用 FR 命名框架、运行中重绑定、队列迁移、自动回退、根注册中心、诊断状态机或持久化去重台账。
6. 不关闭个人路径／凭据脱敏，不从 `[REDACTED PATH]` 猜测真实目录，不从显示文本恢复秘密。
7. 不把正式 `specs/`、`delivery/`、traceability 或 CR 治理文件作为人工直接修改目标；只经现有深原语生成、应用与归档。
8. 当前方案只需一份文档；实施时按最小提交拆分，不强制为每个条目建立独立流程或服务。

## 3. 实施顺序与文件范围

推荐三个交付切片：

1. **A：T1 优先。** 直接解除当前阻塞；不要等待低优先级诊断优化才能交付 T1。
2. **B：T2、T3、T4、T5。** 同一条根解析／调用衔接链上依次修复；T5 最后。
3. **C：M2。** 可独立评审、测试和发布，与原 CR 的追溯恢复不形成强制依赖。

| 条目 | 生产修改范围 | 主要测试范围 |
|---|---|---|
| T1 | tools：`skills/writeback/scripts/writeback-traceability.mjs` | `skills/writeback/scripts/test/writeback.test.mjs`；既有 writeback／archive 事务测试 |
| T2 | tools：`skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | `skills/shared/crctl/scripts/test/merge-tx.test.mjs` |
| T3 | tools：`agents/delivery-agent.md`、`skills/writeback/merge-feature-branch/SKILL.md`、`pipeline-templates/feature-writeback.pipeline.json` | `pipeline-structure.test.mjs`；复用 multica 既有绑定测试和一次受控衔接验收 |
| T4 | tools：`skills/shared/crctl/scripts/crctl.mjs` 中漂移诊断、status／next 输出 | `skills/shared/crctl/scripts/test/crctl.test.mjs` |
| T5 | tools：同一 `crctl.mjs` 中参数缺失提示与 status 摘要 | 同一 `crctl.test.mjs` |
| M2 | multica：`server/internal/service/task.go`；`server/internal/util/text.go` 只同步说明；tools：`skills/shared/crctl/SKILL.md` | Go 完成路径测试、既有 quick-create 测试；共享复制链路保真测试 |

T3 不要求修改 multica 的绑定实现：`server/internal/daemon/pipeline_task.go` 已能消费 `execution_context.cr_id` 与 `operational_workspace`，本会话也已通过该能力成功从 txws 续跑。不要新增仓库中并不存在的 `cr-coordinator-agent.md` 或 `pipeline-runner` Skill。

## 4. Review Focus

以下五类风险必须在对应任务中验收，不另建通用框架：

1. 混合普通／补充 FR：标签、标题、数字顺序以及全部引用必须完整，不能静默丢行。（T1）
2. 完整可信绑定下的恢复：执行机器返回的原始 argv 成功，真正的跨根调用仍失败。（T2）
3. merge 后权威根变化：新 Task 承接 txws，旧根不能诱导重跑 merge，不能同 Task 改 env。（T3／T4）
4. 缺少查询参数与真实产物缺失：前者不被伪装成后者，摘要去重不能隐藏不同产物的缺失。（T5）
5. 合法代码字符与安全脱敏并存：Windows 路径、正则和真实换行保真；秘密仍被遮罩。（M2）

## 5. Task 1：T1 补充 FR 兼容

### 问题与目标

`buildNewMilestone()` 三处假定 `FR-数字`：行校验、数字提取排序、标签／标题切分。修改一处会在下一处产生 `TypeError`。仅扩展当前确实使用的 `SUP` 形式，不接受任意新命名空间。

### 修改方法

在首次调用 `buildNewMilestone()` 之前的现有常量区定义：

```js
const FR_ID = /^FR-(?:SUP-)?\d+/;
```

三处分别替换为：

```js
// 行校验：列数规则与原 fail 的信息／参数保持不变。
if (cells.length !== 5 || !FR_ID.test(cells[0].trim())) {
  fail('STRUCTURE_MISMATCH', `交付覆盖表行结构非法: ${row}`, { cr });
}
```

```js
// 替换现有 coverRows 的排序表达式。
.sort((a, b) =>
  FR_ID.exec(a[0])[0].localeCompare(
    FR_ID.exec(b[0])[0], 'en', { numeric: true }
  )
);
```

```js
// 原有 fr、title 的后续赋值不改。
const frM = FR_ID.exec(cells[0]);
const fr = frM[0];
const title = cells[0].slice(frM[0].length).trim();
```

同步原注释，避免继续写“首格只能是 FR-数字”。不把补充编号映射成普通编号，不改变输出 schema。

### 步骤

- [ ] 在 `writeback.test.mjs` 复用 `makeTraceWs()`、`run()`、`traceOut()`，补 `--mode new` 用例，不传 legacy 的 `--milestone-file`。
- [ ] 使用实际规范表头构造输入：覆盖表 `FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚`；命令表 `证据ID | repo | cwd | executable | args | timeout`。
- [ ] 构造 14 条普通 FR、9 条补充 FR；17 个 done TASK；15 个存在于命令表和 test-report 的 cmd ID。先确认旧实现报 `STRUCTURE_MISMATCH`。
- [ ] 应用上述三处修改，运行测试至绿。
- [ ] 验证 `frs` 的本 CR 段中恰有 23 条；普通编号数字顺序不变，补充编号按数字顺序排列；标签和标题完整。
- [ ] 补负例：`FR-SUP-X`、其他未支持命名空间、非五列、未知 TASK、缺失证据仍失败；正式文件不变且不输出可应用的半成品。
- [ ] 复用 existing legacy／幂等／证据验证测试，确认旧段逐字保留、重复应用不追加第二个 CR 段。
- [ ] 使用现有生成、YAML 解析、writeback 与 archive 校验验证下游；只有发现直接消费者也有同类限制才修改该消费者，并在提交中列明，不预先扩展全链。
- [ ] 形成独立小提交与评审证据。

**运行（tools 根）：**

```text
node --test skills/writeback/scripts/test/writeback.test.mjs
node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs skills/shared/crctl/scripts/test/archive-tx.test.mjs
```

**验收：** 23 条链完整生成，原有普通 FR 与 legacy 行为不回退，非法输入仍 fail-closed。

## 6. Task 2：T2 恢复参数与已确认根一致

### 问题与目标

`mergeCr()` 已有 `mergeWorkspace`，由现有 CLI 的 `resolveOperationalWorkspace` 解析结果经 `input.workspace` 传入。merge 自身 recovery 已使用它，但 checkpoint recovery 使用 `ctx.installRoot`，形成不同根。

### 最小改法

只替换已有 checkpoint recovery 构造中的根，不引入新 resolver 或 env 覆盖逻辑：

```diff
- const checkpointRecovery = buildRecovery(['checkpoint', cr, '--workspace', ctx.installRoot], { cwd: ctx.installRoot });
+ const checkpointRecovery = buildRecovery(['checkpoint', cr, '--workspace', mergeWorkspace], { cwd: mergeWorkspace });
```

保持 `executable`、脚本路径、CR-ID、`requiresTTY`、`promptFor` 和 `shell:false` 消费合同。安装根发起的无绑定人工入口仍兼容，但不承诺恢复结果继续硬编码安装根；更新旧测试对固定安装根的断言。

### 步骤

- [ ] 在 `merge-tx.test.mjs` 复用 `makeCodeApprovedFixture()` 和 `runCrctl()`。
- [ ] 测试完整绑定三元组下的 CR worktree 调用，分别构造远端 source 缺失和 source 滞后；旧实现应暴露 recovery 根与绑定根不同。
- [ ] 应用一行替换；断言 `recovery.args` 的 workspace 和 `recovery.cwd` 与本次已解析的 mergeWorkspace 相同。
- [ ] 按返回的 `executable + args + cwd` 原样执行真实 checkpoint，再重跑同一 merge。不能只模拟 push 或只比较参数字符串就宣称恢复成功。
- [ ] 验证 publication preflight 失败时 CR 仍为 `code-approved`、无 prepare／publish 副作用；恢复后 merge 能完成。
- [ ] 验证无绑定人工入口仍能执行；完整绑定下任意跨根显式覆盖仍报既有 MISMATCH。错误绑定不是本任务要自动修复的对象。
- [ ] 同 run 内 recovery 最多一次；再次失败仍停止，不改 env、不自行构造替代 argv、不单独派发 checkpoint Task。
- [ ] 形成小提交，保留既有事务、冻结 source SHA 和审计测试。

**运行（tools 根）：**

```text
node --test skills/shared/crctl/scripts/test/merge-tx.test.mjs
```

**验收：** 两种 publication lag 均能在合法绑定下原样恢复；安全边界和事务恢复语义不变。

## 7. Task 3：T3 合并成功后的跨 Task 衔接

### 问题与目标

node 1 finalize 创建 txws，权威根由 CR worktree 变为 txws；旧 Task 的可信 env 不应、也不能运行中改变。解决方式是沿用已有协调委派和 execution_context，创建后续 Task，而不是放松绑定。

### 修改方法

仅更新已有 Agent／Skill／Pipeline 调用约定：

1. `agents/delivery-agent.md`：明确 node 1 成功且根发生变化时是“成功交接”，不是 TECHNICAL_ABORT；停止本 Task 对后续业务根的读写并进入既有协调入口。
2. `merge-feature-branch/SKILL.md`：消费 `phase=complete`、txId、返回操作根；区分同 run publication recovery 与成功后的跨 Task 交接。
3. `feature-writeback.pipeline.json`：同步 node 1 的现有 prompt；入口使用当前已预检的根，而非固定“主 checkout”；其返回根用于后续委派。保持五节点、现有输入和 `onFail`，不新增 JSON 字段。
4. 同步 delivery-agent 表格中的固定主 checkout 提示为已确认操作根，避免归档前再次引导跨根调用；不改变 archive 深原语。

后续触发评论继续使用既有 `execution_context`，只声明平台已经消费的两项：

| 字段 | 实际取值来源 |
|---|---|
| `execution_context.cr_id` | 本次正式 CR 上下文的 ID；恢复当前 Issue 时为 `CR-2026-076` |
| `execution_context.operational_workspace` | merge JSON 返回并由 `workspace inspect` 确认的实际路径 |

协调入口必须将确认后的值写入已有 YAML 声明，不发送变量名或占位符，不通过显示文本、脱敏文本猜测路径，不新增续跑字段。

### 步骤

- [ ] 在 `pipeline-structure.test.mjs` 中补既有模板／定义的衔接合同断言，先记录旧定义缺少 Task 边界。
- [ ] 修改上述三份既有定义，不创建新的 coordinator 文件或 Runner Skill。
- [ ] 交接回执记录完成的 node 1、txId、返回根及发布证据；明确后续从现有 node 2 续跑，不能把合并成功说成整个交付成功。
- [ ] 经现有协调入口发出一次后续委派；沿用 `issue runs --active` 检查是否已有相同目标运行，避免本次流程重复派发，不新增去重服务。
- [ ] 新 Task 的执行上下文经现有 daemon 预检后绑定 txws；传递既有 `cr_id`、`spec_id`、`target_version`，不推测缺失值。
- [ ] 复用 `server/internal/daemon/pipeline_task_test.go` 的绑定测试，不修改其生产实现；受控衔接验收检查新 Task ID、绑定根、后续节点入口。
- [ ] 验证 node 1 未再次 merge，旧 Task 未改 env，新 Task 的 nodes 2–5 使用同一合法操作根。
- [ ] 人工 gate 和不明错误仍停止；该边界不授权额外 checkpoint、新恢复算法或绕过审批。

**运行：**

```text
# tools 根
node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
node --test pipeline-templates/emit-registry.test.mjs

# multica/server 根：复用既有绑定回归
 go test ./internal/daemon -run 'Binding|Pipeline' -count=1
```

实施者必须检查 Go `-run` 实际命中用例，不能把“无匹配测试”记为通过。Pipeline prompt 变更按既有 registry 检查／生成链路核对：确有生成物变化才提交，禁止手改生成文件、伪造 digest 或为此增加 feature-writeback Runner 支持。

**验收：** 正常根切换只产生一次必要交接，不再制造 node 2 技术终止；平台现有绑定实现不扩权。

## 8. Task 4：T4 阶段性权威根诊断

### 问题与目标

`detectStatusDivergence()` 当前把 requirement worktree 一律认定为事实源，甚至在正在旧 worktree 中查询时提前返回。merge 后该分支可能只是历史投影，提示会引导用户离开真正权威的 txws。

### 最小改法

在同一文件复用已导入的解析能力：

```js
const authority = resolveOperationalWorkspace(resolveRepositories(ws), cr);
```

将这一步纳入现有漂移诊断，不复制阶段映射、不建立根注册表。

- 先确认当前阶段权威，再比较当前查询根与 worktree 副本；不能因为 `wtPath === ws` 就提前认定当前根权威。
- 权威为 CR worktree 时，保留原有“主 checkout 陈旧”的告警事实。
- 权威为 txws 时，旧 requirement 分支只作为历史／参考副本，提示不得要求切回该分支。
- 当前查询根不是权威时，明确本次返回是该查询根的视图，不能据此调度；绑定不一致时走现有新 Task 声明，不自动重定向读取或写入。
- 无法解析权威时，只说明未确认并引导 `workspace inspect`；不臆断某根为权威。
- `cmdNext()` 复用现有 `warnings[]` 输出通道同步该诊断；保留已有字段类型，不新增状态、错误码或自动跳转。

### 步骤

- [ ] 在 `crctl.test.mjs` 复用已有 git／worktree 夹具，保留合并前主根陈旧用例。
- [ ] 补合并后 txws 查询与旧 CR worktree 查询两个红测；旧实现会给出错误方向或缺少告警。
- [ ] 修改现有诊断和 status／next 输出，不改变 CR 状态的写入算法。
- [ ] 验证 status 的 `source.crMd` 仍指向实际读取文件；告警明确阶段性权威，不能把历史分支差异当成需要回退的业务失败。
- [ ] 验证 next 在非权威根下附带明确告警，调用方不得依其建议重跑 merge；权威根下保持正常建议。
- [ ] 保留非 git workspace、终态历史查询、相同真实路径别名和解析失败回归；所有查询零业务写入。

**运行（tools 根）：**

```text
node --test skills/shared/crctl/scripts/test/crctl.test.mjs
```

**验收：** 合并前、合并后与终态三种来源不混淆；没有跨根自动读写，也没有为了消除提示同步所有历史分支。

## 9. Task 5：T5 缺参数诊断与有限去重

### 问题与目标

status 中两项 specs 检查在未给 `--spec-id` 时重复显示同一消息。缺参数表示本次检查未完成，不代表正式文件不存在。

### 最小改法

在现有常量区定义单一消息值并由 `runGateChecks()` 使用：

```js
const SPEC_ID_REQUIRED_WHY = '未提供 --spec-id，无法校验 specs 落点；本项未完成校验，不表示产物不存在';
```

仅在 `cmdStatus()` 的 gateBlockers 摘要层对该消息去重；详细 `checks` 仍保留每条检查：

```js
const reasons = g.checks.filter((c) => !c.ok)
  .map((c) => c.why || c.path || c.stage || c.section);
missing[target] = reasons.filter((reason, index, all) =>
  reason !== SPEC_ID_REQUIRED_WHY || all.indexOf(reason) === index
);
```

不得对所有“文件不存在”消息统一 Set 去重，以免掩盖不同产物。不得因缺参数把 gate 改成 pass。

### 步骤

- [ ] 在 `crctl.test.mjs` 构造同目标态两项 specs 检查、无 spec-id 的查询，确认旧输出重复。
- [ ] 应用上述消息与摘要改法；先让实际调用方传递已有必填 spec_id，而不是靠诊断优化替代传参。
- [ ] 验证摘要只显示一条参数缺失提示，详细 checks 数量不变、gate 仍未通过。
- [ ] 带 spec-id 后两份真实产物都缺失时，仍保留两项真实失败，不因同义消息而吞掉。
- [ ] 写入命令缺 spec-id 的现有 `BAD_ARGS`／拒绝规则不变；无关 blocker 和 warning 输出不变。

**运行：** 与 Task 4 共用 `crctl.test.mjs`，不另建诊断框架。

**验收：** 只改善参数缺失的可读性，不扩大成功条件。

## 10. Task 6：M2 文本完成路径保真

### 已定位的机制

`task.go` 对已经 `json.Unmarshal` 的 Output 再调用 `UnescapeBackslashEscapes`。该函数会把合法代码中的反斜杠加 n／r／t 解释为控制字符；个人目录还会被 `redact.Text` 替换为 `[REDACTED PATH]`。

前者是本次应修的文本损坏，后者是明确的隐私合同，不通过关闭脱敏解决。

### 生产改法

`server/internal/service/task.go` 的三处目标修改：

```diff
- body := util.UnescapeBackslashEscapes(payload.Output)
+ body := payload.Output
```

上面分别应用于 Issue 完成后补发评论、`writeChatCompletionOutcome()`。第三处为：

```diff
- body := strings.TrimSpace(util.UnescapeBackslashEscapes(payload.Output))
+ body := strings.TrimSpace(payload.Output)
```

用于 `quickCreateFailureDetail()`。保持现有空白检测、协议尾部剥离、截断、数据库安全清洗与 `redact.Text`。

`server/internal/util/text.go` 只修改“服务端完成路径也使用它”的过时说明，函数实现不变；`server/cmd/multica/cmd_issue.go` 的 CLI 内联文本兼容合同不变。已经 JSON 解码的服务端结果不能继续依靠猜测转义美化。

### 最小测试数据

服务端用例使用如下结构化 payload 进行编码和解码，真实换行与字面字符必须区分：

```go
out := "段落一\n段落二\n```powershell\n" +
    `$p = 'D:\tools\requirement\new'` + "\n" +
    `$rx = '\d+\s*'` + "\n```"
payload := protocol.TaskCompletedPayload{Output: out}
result, err := json.Marshal(payload)
if err != nil {
    t.Fatal(err)
}
```

使用不含个人目录的 `D:` 测试路径是为了隔离反转义行为；另设个人目录和凭据用例验证脱敏，不把安全遮罩误判为保真失败。

### 步骤

- [ ] 在现有聊天／Issue 完成测试中追加上述回归，先证明旧实现把路径字符改坏。复用 `server/internal/testutil`，不新建 fixture 框架。
- [ ] 修改三处调用和过时注释。
- [ ] 更新 `server/internal/service/quick_create_failure_detail_test.go` 中旧的自动反转义预期：解码后的字面字符原样保留；真正换行正常保留。
- [ ] 验证数据库消息、完成事件和重载后的消息一致；Issue fallback 路径也必须覆盖，不能只测 quick-create 辅助函数。
- [ ] 验证空白／无回复、附件绑定、协议尾部剥离、过长 fallback 与凭据脱敏不回退。
- [ ] 在 `packages/views/chat/lib/copy-text.test.ts` 补原文复制用例；复用 `packages/views/editor/utils/clipboard.test.ts` 验证 Clipboard API 和 textarea fallback 原样传递。前端生产实现先不改。
- [ ] 在 AI-First-tools 的 `skills/shared/crctl/SKILL.md` 调用方约定中补 Windows 人工示例规则：使用已确认的工作根变量、`Join-Path`、路径检查；不输出包含个人目录的可直接复制绝对路径，不把遮罩占位符当目录。
- [ ] 评论／长正文复用 `--content-file`，避免 CLI 内联转义兼容路径；不更改机器 recovery 实际 argv，不复制同一规则到所有审批 Skill。

### 不修改的生产模块

- `server/pkg/redact/redact.go`：保留个人路径、Token、密码等遮罩。
- `server/cmd/multica/cmd_issue.go`：保留既有文件／stdin 保真输入和内联兼容能力。
- `packages/views/rich-content/rich-code-block.tsx`、`packages/views/chat/lib/copy-text.ts`、`packages/ui/lib/clipboard.ts`：现有原文复制逻辑优先复用，只有新回归证明仍有独立损坏才另报具体证据。

**运行（multica）：**

```text
# server 根
 go test ./internal/util ./pkg/redact ./internal/service ./internal/handler -count=1

# 仓库根：共享复制相关用例
pnpm --filter @multica/views test chat/lib/copy-text.test.ts editor/utils/clipboard.test.ts
```

Go 完成路径涉及数据库时，按仓库既有测试配置启动测试数据库；未运行或被跳过的 DB 用例必须在回执中明确列出，不能当作完成。

**验收：** 非秘密代码内容从已解码 Output 到复制结果不再被二次反转义；真实换行正常；敏感信息继续安全遮罩。历史已经损坏的消息不做猜测性批量修复，应重新生成安全的操作说明。

## 11. 发布、原 Issue 恢复与回退

### 11.1 发布前

- [ ] Ray 确认范围及现有 CR 实施方式。原 CR 不回开发阶段，不代签、不编辑治理账本。
- [ ] 每个切片有最小差异、对应回归和独立评审；使用现有受控 git 入口，保留用户配置的提交身份。
- [ ] Skill／Agent／Pipeline 修改按 tools 的既有权限矩阵、索引和 lint 规则检查。节点数仍为 5，不增加 inputs，不改审批合同。
- [ ] 比较源代码版本、安装／imported Skill 版本和实际入口脚本，不能只以 PR 合并证明消费者已经更新。

### 11.2 生效

- tools：使用现有发布／导入／生效切换方式。记录实际 crctl 路径、tools commit、生成器 SHA；不顺手切换所有安装根、不修改 Task 运行中的 PATH。
- multica：使用现有服务端发布流程让 `task.go` 变更生效；这不是通过重启 Agent Runtime 就能修复的问题。部署窗口由维护者选择，本方案不发起重启。
- 绑定衔接定义更新后，使用新 Task 验收，不拿旧 Task 环境当成新声明。
- 若生成器版本变化需要重新生成 candidate，复用现有 candidate／manifest 流程；不手工删 journal、不篡改 generatorSha。

### 11.3 恢复 AIFI-62

只依赖 T1 的修复已经完成评审、发布并在受控执行入口生效；T2–T5／M2 可以后续独立交付。

1. 新运行开始前读取最新 Issue、CR 权威状态、`workspace inspect` 和正式节点产物；若现场已变化，按新事实裁定，不能照本方案快照盲跑。
2. 核实 node 1 合并及 nodes 2–3 发布证据仍有效；从正式字段取得 spec_id 与 target_version，不能臆造版本。
3. 新委派绑定 `workspace inspect` 返回的当前操作根；保持其审计根与操作根分工，不在旧 Task 里换根。
4. 从 node 4 的公开 `writeback-traceability` Skill／`writeback-apply` 入口续跑，不直接在正式文件中补 9 行，不手动制作最终 milestone。
5. 确认本 CR 23 条链完整、17 个 TASK 和证据引用有效；manifest／应用／发布成功后再执行 node 5。
6. 归档只经既有 `cr-archive`；有新错误则返回原始回执并停止，不自动重试结构错误。
7. 记录归档终态、正式产物和发布证据后，才把 Issue 交付状态按现有流程推进；Task completed 不替代业务完成。

### 11.4 回退

代码或定义回归使用已有审查过的 revert／旧版本发布路径，不使用 force、reset 或直接改状态。已发布的业务合并与回写资产不能跟着“回退程序版本”被手工撤销；若恢复旧生成器导致 node 4 再次不兼容，应保持阻塞并重新修复，不删除已完成节点或伪造归档。

## 12. 最终验收清单

| ID | 必须提交的证据 |
|---|---|
| T1 | 23 条混合编号的生成与下游验证；普通／legacy／负例及无半成品测试 |
| T2 | 完整绑定下原样执行 recovery 后 merge 成功；两类 lag、非法跨根及无绑定兼容回归 |
| T3 | 合并完成回执、新 Task ID 与 txws 绑定；无重复 merge、无 env 修改、节点仍为 5 |
| T4 | 合并前／后／历史终态的来源诊断；status／next 不诱导回到错误根，查询零业务写入 |
| T5 | 缺参摘要去重、checks 保留、真实多产物失败不被吞、写入 gate 不放宽 |
| M2 | 聊天与 Issue 完成链路保真；真实换行／代码／复制／安全脱敏与既有 CLI 合同回归 |
| 发布 | 源码 commit 与实际消费版本、入口路径、生成器 SHA 或服务端构建版本 |
| 恢复 | 原 AIFI-62 只续跑尚未完成节点；归档及正式产物证据，不以重试次数或 Task 状态代替 |

**交付回执必须区分：已修改、已运行、未运行、已部署、未部署、原 Issue 是否恢复。** 本方案文件本身不代表这些工作已经完成。
