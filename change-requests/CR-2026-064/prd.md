---
id: CR-2026-064-prd
type: PRD
cr-ref: CR-2026-064
title: CR-R：结构化恢复合同原子迁移 — `recoverCommand`/`recover_command` 全量退役为结构化 `recovery`
target-version: 0.37
owner: Ray
owner-role: requirement
status: draft
created: 2026-09-12T22:08:20+08:00
updated: 2026-09-12T22:08:20+08:00
---

## 1. 概述

### 1.1 问题陈述

crctl 的多个事务在失败或可恢复中间态中，把「恢复动作」以 shell 命令字符串形式返回：

```json
{ "recoverCommand": "crctl review-loop reset CR-2026-062 --loop review-tech-design --reason \"...\"" }
```

部分 CLI 路径还同时投影 `recoverCommand` 与 `recover_command` 两个同义字段。

该合同把三种互不相同的责任混在一个字符串里：**机器执行入口**、**参数值与参数边界**、**人类显示文本**。由此产生四类缺陷：

1. **shell 语义可被输入改变**：用户输入（如 reset `--reason`）、workspace 路径、branch/ref 经字符串拼接后进入命令，`"`、`;`、`$()`、反引号、换行都可能改变执行语义；
2. **跨 shell 不可移植**：bash、PowerShell、cmd 的引号与转义规则不同，同一字符串在不同终端语义不同；
3. **显示文本被当执行合同**：Agent 可能直接执行本应只用于展示的字符串；两个同义字段还形成重复投影，消费方无从判断哪个是事实源；
4. **测试不具证明力**：现有测试用 `result.recoverCommand.includes('...')` 只能证明字符串片段存在，无法证明 argv 边界正确。

本 CR 注册时由 `crctl register` 返回的结果本身即同时包含 `recoverCommand` 与 `recover_command` 两个字段，是该缺陷仍在生产路径上的现存实例。

### 1.2 解决方案摘要

把恢复动作从「命令字符串」改为**唯一的结构化数据字段 `recovery`**（`executable` + `args[]` + 可选 `cwd` + `requiresTTY` + `promptFor[]`），执行方一律以非 shell 的 argv 方式调用；需要人重新输入的值不进入 `args[]`，只经 `promptFor[]` 声明。

本 CR 是**单发布原子迁移**：在同一个 CR 内完成全部已知生产者与全部活跃消费者的切换，并在同一个 CR 内删除 `recoverCommand` / `recover_command`，复用既有 contract-scan 防止退役字段回流。不设双写兼容期、不留 deprecated alias、不生成 migration shim、不拆第二个删除 CR。

前提事实：当前不存在仓外机器消费者；活跃生产者与消费者可在同一 tools 发布中同步切换。因此整体原子切换比长期兼容层成本更低、可靠性更高。

### 1.3 需求来源与事实源

- 需求来源文档：`crctl_recoverCommand结构化恢复合同_原子迁移方案.md`（AIFI-25 议题附件），其 §3 定义目标合同、§4 定义盘上影响面、§6 定义安全测试向量、§7 定义交付边界、§8 定义验收条件。
- 边界来源：`AIFI-18_SDD到planTASK_原位修订方案.md` §2——四个 CR（CR-P0 / CR-R / CR-P1 / CR-P2）分别评审、审批、回滚，**不得合并为一个发布单元**；CR-P0 已作为 CR-2026-063 归档；CR-R 只负责 recovery 合同迁移。
- 本 PRD 只写到「行为 + 验收标准 + 引用先例」这一层。确定性算法的实现细节（构造器是否提取、逐文件改法、错误消息文案、契约扫描实现方式）归开发期 SDD。

---

## 2. 用户故事

- **US-1（执行方 / Agent）**：作为收到 crctl 可恢复结果的 Agent 或脚本，我希望恢复动作是结构化 argv 数据而不是命令字符串，这样我可以直接用 `spawn`/`execFile` 类接口按参数边界执行，不必自己判断当前 shell 的转义规则，也不会把展示文本误当执行合同。

- **US-2（CR owner / 人类操作者）**：作为在终端处理失败事务的人，我希望需要我重新确认的值（如 reset 的 reason）被明确声明为「执行时向人索取」，而不是把上一轮的旧值回显在一条可复制命令里，这样我不会无意中复用一个已经不成立的理由。

- **US-3（crctl 维护者）**：作为维护 crctl 事务层的开发者，我希望恢复合同只有一个字段名、一套语义，这样我新增或修改一个可恢复场景时不需要同时维护两个投影，也不需要判断哪个字段是权威的。

- **US-4（评审者 / 测试者）**：作为评审与测试的人，我希望恢复合同的测试断言的是确定的 `executable` 与逐元素 `args[]`，而不是字符串包含，这样测试能真正证明参数边界正确，而不是证明某个片段出现过。

- **US-5（安全视角）**：作为关心注入面的人，我希望用户可控输入（reason、路径、ref）永远不会被拼接进一条会被 shell 解释的字符串，这样含 `"`、`;`、换行、`$()`、反引号的输入不再具备改变执行语义的能力。

---

## 3. 功能需求

> 以下 FR 描述**可观察行为与交付边界**。具体实现算法（是否提取公共构造器、逐文件改写顺序、扫描器实现）归 SDD。
> 实施定位一律以 `rg "recoverCommand|recover_command"` 的实时搜索结果为准；来源文档中的行号仅为参考，**禁止依赖行号做盲改**。

### FR-1 唯一恢复合同字段 `recovery`

crctl 所有可恢复结果必须以唯一字段 `recovery` 表达恢复动作，字段语义如下：

| 字段 | 类型 | 规则 |
|---|---|---|
| `executable` | 非空 string | 实际可执行入口（如 `crctl`、`node`）；不得包含参数或 shell 运算符 |
| `args` | string[] | 每个元素是一个完整 argv；不得把多个参数拼成单个元素 |
| `cwd` | 绝对路径 string 或省略 | 仅当恢复动作必须位于特定 workspace 时返回；不得依赖调用方猜测 |
| `requiresTTY` | boolean | 是否必须在可信交互终端执行 |
| `promptFor` | string[] | 执行时需重新向人获取的逻辑值（如 `reason`）；这些值不得预先拼入 `args` |

`recovery` 是恢复动作的**唯一机器执行事实源**。

### FR-2 argv 边界与参数完整性

1. CR-ID、workspace、branch/ref、路径等每个参数各自占据独立的 `args[]` 元素；
2. `args[]` 的顺序与目标 CLI 的参数顺序一致；
3. 含空格的路径不依赖任何额外引号即可正确传递；
4. 结果中不得返回等价的 shell string 作为「备用执行入口」。

### FR-3 `executable` 安全约束

`executable` 不得包含：空格分隔的参数、管道 `|`、重定向 `>` `<`、分隔符 `;`、连接符 `&&`、命令替换 `$()` 或反引号、任何 shell 展开。使用 `node` 作为入口时，脚本路径必须是 `args[0]`，不得并入 `executable` 字符串。

### FR-4 `promptFor[]` 人工输入行为

对必须由人确认的值（如 `review-loop reset` 的 reason）：

1. 该值**不出现在** `args[]` 中，也不出现在任何 shell string 中；
2. 通过 `promptFor: ["reason"]` 声明，并按需置 `requiresTTY: true`；
3. 执行方必须在可信 TTY 中重新向人获取该值，并按目标 CLI 既有交互入口传入；
4. 执行方**不得**从旧错误消息、评论或日志中提取该值后自动复用；
5. 非 TTY 环境下执行方停止并报告所需的人类动作。

本 CR 不引入新的交互协议；`promptFor` 只是把既有的人工输入要求结构化声明出来。

### FR-5 全部已知生产者迁移

`tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 中全部可恢复场景原位改为返回 `recovery`，至少覆盖：**register、workspace sync、merge、publication lag → checkpoint、checkpoint、writeback traceability、writeback apply、archive、test**。

每个生产者迁移时：保留原错误码与恢复时机；把命令 token 拆成独立 args；workspace / ref / path / reason 不进入模板字符串；需特定 workspace 时写入 `cwd`；**在同一位置删除旧字段，而不是并排双写**。

### FR-6 CLI 投影迁移

`tools/skills/shared/crctl/scripts/crctl.mjs` 原位完成：接收并透传 `recovery`；删除 `recoverCommand` 与 `recover_command` 两个字段的 projection（含双投影位置）；`review-loop reset`（CR-P0 中新增的安全兼容恢复结果）直接返回结构化 `recovery`；CLI 层不得重新拼接 shell string。

### FR-7 全部活跃 Skill / Agent 消费者迁移

至少原位修改：`tools/skills/shared/crctl/SKILL.md`、`tools/skills/writeback/merge-feature-branch/SKILL.md`、`tools/skills/sync/push-progress/SKILL.md`、`tools/skills/cr/cr-archive/SKILL.md`、`multica/cr-prompts-revised/delivery-agent.md`，以及实施时搜索发现的其它活跃 Agent / Skill / Pipeline 引用。

修改规则：把「执行 `recoverCommand`」改为读取 `recovery.executable` / `recovery.args[]` / `cwd` / `requiresTTY` / `promptFor[]`；Agent 不自行转义或补写参数；缺少必需字段时报告合同错误，不猜测恢复命令。`multica/` overlay 文件只提供 owner 可复制版本，本 CR 不更新平台 DB。

### FR-8 文档迁移且不产生第二套合同

原位修改 `tools/README.md` 与 `tools/openwiki/operations/crctl-transactions.md` 的事实源或其既有生成输入。若 openwiki 文件由生成流程维护，则修改其权威输入后重新生成；**不得同时手工维护第二套合同描述**。

### FR-9 测试改为结构断言

至少原位迁移：`archive-tx.test.mjs`、`checkpoint-tx.test.mjs`、`merge-tx.test.mjs`、`register-tx.test.mjs`、`workspace-freshness.test.mjs`、`writeback-tx.test.mjs`，以及 `crctl.test.mjs` 中的 reset 恢复合同测试。

原有 `result.recoverCommand.includes('...')` 形式的字符串断言改为结构断言，例如：

```js
assert.equal(result.recovery.executable, 'crctl');
assert.deepEqual(result.recovery.args, [/* exact argv */]);
assert.equal(result.recovery.requiresTTY, false);
assert.deepEqual(result.recovery.promptFor, []);
```

涉及临时路径时断言数组元素与顺序，**不对完整 JSON 做脆弱快照**。

### FR-10 旧字段同 CR 删除，不留兼容路径

在本 CR 内删除：全部生产者的 `recoverCommand`；全部生产者的 `recover_command`；`crctl.mjs` 的兼容 projection；测试中的字符串断言；活跃 Skill / Agent / Pipeline 中的旧消费说明；README 中的旧合同示例。

不得保留 deprecated alias、不得生成 migration shim、不得新增「若无 `recovery` 则读取 `recoverCommand`」形式的 fallback。

### FR-11 contract-scan 退役保护

复用**既有**静态合同扫描机制，把 `recoverCommand` 与 `recover_command` 两个名称加入退役字段禁止清单。

- 扫描范围：活跃源码、活跃 Skill、活跃 Agent、Pipeline、活跃测试。
- 允许排除：历史 CR、历史 traceability、归档 delivery 证据、changelog/migration 文档、contract-scan 自身的禁止名单。
- **不得**把「全仓零命中」作为唯一实现，因为历史证据合法地包含旧字段。

### FR-12 安全测试向量

每类生产者至少覆盖与其输入相关的边界（不要求每函数全排列）：

1. **参数边界**：CR-ID、workspace、branch/ref 处于独立 `args[]` 元素；含空格路径无需额外引号；参数顺序与 CLI 合同完全一致。
2. **用户输入**：reason 至少覆盖 `normal reason`、含双引号值、含分号值、含换行值、`$(substitution)`、反引号表达式；预期 reset 的 `args[]` 不包含 reason，`promptFor` 包含 `reason`，JSON 序列化后仍是数据、不形成 shell command。
3. **executable 安全**：按 FR-3 断言。
4. **合同缺失**：消费方在「无 `executable`」「`args` 非数组」「`requiresTTY=true` 但环境无 TTY」「`promptFor` 非空却无允许的人类输入入口」四种情况下必须停止并报告合同错误，且**不得自动回退旧字段**（旧字段在本 CR 已删除）。

### FR-13 既有语义零改变

本次修改不得改变：既有错误码、exit code、transaction id、route、files、rollback 信息的原义；reviewLoop、archive、merge、checkpoint、writeback 的业务算法；状态机转换与门禁语义。

### FR-14 实施前有界盘点

进入编码前执行一次有界搜索（排除 `node_modules`、`.git`），范围至少覆盖 `tools/` 与 `multica/cr-prompts-revised/`，把结果按 **producer / code consumer / Prompt-Skill consumer / active test / active docs / historical evidence（排除）** 六类归档到本 CR 的实施计划。该盘点只用于确保本次原子迁移不漏调用方，**不得转化为持续观测机制**。

### FR-15 整体回滚

本迁移是单发布原子切换，回滚必须整体进行：

1. 若本 CR 在合并前失败，回滚整个 CR；
2. 不保留「部分生产者新合同、部分消费者旧合同」的分支状态；
3. 不通过临时恢复 `recoverCommand` 让半迁移版本发布；
4. 已发布版本若必须回退，回退到上一完整 tools 版本，而不是在当前版本双写。

### FR-16 回写与平台部署边界

本 CR 包含正常 writeback 所需的 `specs/` 与 `delivery/` 更新。tools 发布后，由 owner 更新引用恢复合同的 Multica 平台 Prompt；**本 CR 不得声称平台 DB 已部署**。

### FR-17 合同确定性（幂等 / 判定顺序 / 错误闭包 / 副作用）

`recovery` 是 crctl 对外的可调用契约的一部分，其确定性规则如下（实现算法归 SDD）：

**幂等**：`recovery` 是同一失败态的确定性投影。指纹参与字段集合固定为 `executable` + `args[]` 有序序列 + `cwd`（省略时视为不参与）+ `requiresTTY` + `promptFor[]` 有序序列；同一 CR、同一事务、同一失败态重复求值必须产出逐元素相等的结果，不得含时间戳、随机数、进程 id 或环境相关的可变成分。重复消费 `recovery` 不改变其值，也不改变原事务的幂等结论——恢复语义仍由原有事务重跑规则决定。

**判定顺序（消费方校验）**：消费方必须按固定顺序判定并以**首个**不满足项作为唯一结论，禁止「A 或 B」式并列——
1. `executable` 存在且为非空 string 且满足 FR-3；
2. `args` 为数组且每个元素为 string；
3. `cwd` 若存在则为绝对路径；
4. `requiresTTY` 为 true 时当前环境必须具备可信 TTY；
5. `promptFor` 非空时必须存在允许的人类输入入口。

**错误闭包**：上述每一类不满足都必须闭合为「停止执行 + 报告合同错误 + 零执行副作用 + 明确的人类/调用方动作」，至少覆盖：合同字段缺失或类型错误、`executable` 违反安全约束、TTY 要求不满足、`promptFor` 无输入入口。四类均不得自动回退旧字段、不得猜测恢复命令、不得降级为字符串执行。

**副作用**：`recovery` 本身是纯数据，求值与返回**零副作用**（不执行命令、不渲染字符串、不写文件）。生产者返回 `recovery` 不得改变其原有的写入范围、事务边界与回滚语义（见 FR-13）。人类界面若需显示命令，只能从 `recovery` 渲染；**显示结果不得反向作为执行输入**。消费方一律使用非 shell 的 argv 执行方式，禁止 `shell: true` 与 `Invoke-Expression`。

---

## 4. 非功能需求

### 4.1 性能

- `recovery` 为纯数据结构，不引入命令执行、字符串解析或额外 I/O，对既有事务路径的开销增量可忽略；
- 本 CR 不新增常驻进程、不新增扫描调度；FR-11 的退役扫描复用既有静态扫描机制，不新增独立流水线阶段。

### 4.2 安全

- **注入面闭合**：用户可控输入（reason、路径、ref）不再进入任何会被 shell 解释的字符串；含 `"`、`;`、换行、`$()`、反引号的输入在 JSON 序列化后仍为数据；
- **执行方式约束**：全部代码消费者使用 argv 边界的执行接口，禁止 `shell: true` 与 `Invoke-Expression`；
- **人在环保持**：`requiresTTY` / `promptFor[]` 只结构化声明既有的人工确认要求，不削弱任何既有人工门禁，也不新增绕过路径。

### 4.3 兼容性

- **无外部机器消费者前提**：当前不存在仓外机器消费者，活跃生产者与消费者在同一 tools 发布中同步切换；
- **无兼容层**：不提供双写、deprecated alias、migration shim 或 fallback 读取路径；
- **历史证据不改写**：不改写历史 CR、历史 traceability、归档 delivery 证据；旧字段允许继续存在于这些历史材料中；
- **CR 独立性**：本 CR 与 CR-P0 / CR-P1 / CR-P2 分别评审、审批、回滚，不得合并为一个发布单元。

---

## 5. 验收标准

> 对应来源文档 §8「验收条件」。本 CR 只有同时满足以下全部条件才算完成。

- **AC-01（对应 FR-1、FR-2）**：所有可恢复结果使用 `recovery`，字段语义与 FR-1 表格一致；`args[]` 保持逐参数边界且顺序与目标 CLI 一致；结果中不存在等价 shell string 备用入口。
- **AC-02（对应 FR-5、FR-6）**：register、workspace、merge、checkpoint、writeback、archive、test、reset 八类恢复路径的测试全部通过，且其恢复结果均为结构化 `recovery`。
- **AC-03（对应 FR-4、FR-12.2）**：用户提供的 reason 不出现在 reset 的 `args[]` 中，也不出现在任何 shell string 中；`promptFor` 包含 `reason`；六类恶意/特殊 reason 输入在序列化后仍为数据。
- **AC-04（对应 FR-17 副作用段）**：所有代码消费者使用 argv 边界执行，代码中不存在 `shell: true` 或 `Invoke-Expression` 用于执行恢复动作。
- **AC-05（对应 FR-7、FR-8、FR-9、FR-10）**：活跃源代码、活跃 Skill、活跃 Agent、Pipeline、README 与活跃测试均不再消费 `recoverCommand` / `recover_command`；不存在 deprecated alias、migration shim 或旧字段 fallback。
- **AC-06（对应 FR-11）**：`recoverCommand` / `recover_command` 仅允许出现在历史证据、迁移文档与退役禁止名单中；contract-scan 在活跃范围命中旧字段时失败，且对允许排除范围不误报。
- **AC-07（对应 FR-13）**：既有 crctl、ledger transaction、workspace freshness、merge、writeback、archive 全量测试通过。
- **AC-08（对应 FR-13）**：修改未改变错误码、状态转换、transaction id、rollback 或 files 语义（以既有测试与逐项核对为证）。
- **AC-09（对应 FR-16）**：tools 发布后由 owner 更新引用恢复合同的 Multica 平台 Prompt；本 CR 的交付物与结论中不出现「平台 DB 已部署」的声称。
- **AC-10（对应 FR-3、FR-12.3）**：`executable` 不含空格分隔参数与任何 shell 运算符；以 `node` 为入口时脚本路径位于 `args[0]`。
- **AC-11（对应 FR-12.4、FR-17 判定顺序/错误闭包）**：四类合同缺失场景下消费方均停止并报告合同错误，零执行副作用，且不回退旧字段；判定按固定顺序给出唯一结论。
- **AC-12（对应 FR-14）**：实施计划中存在一次有界盘点结果，并按 producer / code consumer / Prompt-Skill consumer / active test / active docs / historical evidence 六类归档；未因此新增任何持续观测机制。
- **AC-13（对应 FR-15）**：交付分支不存在「部分生产者新合同、部分消费者旧合同」的中间状态；回滚方案为整体回滚。
- **AC-14（对应 FR-16）**：正常 writeback 所需的 `specs/` 与 `delivery/` 更新已包含在本 CR 内。

---

## 6. 成功指标

> 来源文档 §2.2 明确不新增使用量、失败率、SLO 或迁移统计。因此本节只列**一次性可核查的发布期事实**，不引入运行期观测或计数门禁。

| 指标 | 判定方式 | 目标 |
|---|---|---|
| 恢复合同单一性 | 活跃范围内恢复结果字段名清点 | 仅 `recovery` 一个，旧字段 0 处活跃引用 |
| 注入面闭合 | FR-12.2 的六类 reason 向量测试 | 全部通过，reason 不进 `args[]` / 不进 shell string |
| 语义零漂移 | 既有 crctl / ledger / freshness / merge / writeback / archive 全量测试 | 全绿，无错误码或状态转换变更 |
| 退役保护有效性 | contract-scan 正反用例 | 活跃范围命中即失败；历史证据与禁止名单自身不误报 |
| 迁移完整性 | FR-14 有界盘点六类归档 | 无「已知调用方未迁移」遗留项 |
| 原子性 | 交付分支状态核对 | 无半迁移中间态；回滚方案为整体回滚 |

---

## 7. 范围排除

本 CR **明确不做**以下内容（来源文档 §2.2 与 §7.2）：

1. 不新增通用命令执行框架；
2. 不新增 shell parser、quoting library 或跨 shell renderer；
3. 不改变 reviewLoop、archive、merge、checkpoint、writeback 的业务算法；
4. 不增加兼容层、双写期或 deprecation 周期；
5. 不改写历史 CR、历史 traceability 或归档 delivery 证据；
6. 不更新 Multica DB（平台 Prompt 部署由 owner 另行执行）；
7. 不新增使用量、失败率、SLO 或迁移统计；
8. 不包含 AIFI-18 的 SDD review 规则；
9. 不包含 `_context.md` 删除（属已归档的 CR-P0 / CR-2026-063）；
10. 不包含 plan/TASK 增量回修（属 CR-P2）；
11. 不调整 Pipeline 节点；
12. 不改造 Multica API 或 importer（含 `aifirst/agent-import.mjs`）；
13. 不拆出第二个「删除旧字段」的 CR；
14. 不与 CR-P1 / CR-P2 合并为同一发布单元。
