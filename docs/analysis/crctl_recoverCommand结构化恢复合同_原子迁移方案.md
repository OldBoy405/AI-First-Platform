# crctl `recoverCommand` 结构化恢复合同原子迁移方案

> **用途**：作为独立 CR-R 的需求来源。
> **交付约束**：一个 CR 内迁移全部已知生产者和消费者，并直接删除旧字段；不双写、不设置兼容周期、不拆第二删除 CR。
> **前提事实**：当前不存在仓外机器消费者；活跃生产者与消费者可在同一 tools 发布中同步切换。

---

## 1. 问题

crctl 多个事务在失败或可恢复中间态中返回 shell 命令字符串：

```json
{
  "recoverCommand": "crctl review-loop reset CR-2026-062 --loop review-tech-design --reason \"...\""
}
```

部分 CLI 路径还同时投影：

```json
{
  "recoverCommand": "...",
  "recover_command": "..."
}
```

这个合同把三种责任混在一起：

1. 机器执行入口；
2. 参数值与参数边界；
3. 人类显示文本。

因此存在以下缺陷：

- 用户输入、workspace、路径或 reason 经字符串拼接后可能改变 shell 语义；
- bash、PowerShell 和 cmd 的转义规则不同；
- Agent 可能把显示文本直接当执行合同；
- 两个字段名形成重复投影；
- 测试使用 `.includes()` 只能证明字符串片段存在，不能证明 argv 边界正确。

CR-R 必须把恢复动作改成结构化数据，并让执行方使用 argv 调用，不再执行拼接后的命令字符串。

---

## 2. 目标与非目标

## 2.1 目标

- 定义一个唯一的 `recovery` 合同；
- 全部生产者返回 `executable + args[]`，保留参数边界；
- 需要人类重新输入的值通过 `promptFor[]` 声明，不回显到可执行数据；
- 全部活跃消费者在同一个 CR 内迁移；
- 同一个 CR 内删除 `recoverCommand` 与 `recover_command`；
- 使用既有 contract-scan 防止退役字段回流；
- 保持现有事务、状态机、错误码和恢复语义不变。

## 2.2 非目标

- 不新增通用命令执行框架；
- 不新增 shell parser、quoting library 或跨 shell renderer；
- 不改变 reviewLoop、archive、merge、checkpoint、writeback 的业务算法；
- 不增加兼容层或 deprecation 周期；
- 不改写历史 CR、历史 traceability 或归档 delivery 证据；
- 不更新 Multica DB；平台 Prompt 部署由 owner 另行执行；
- 不新增使用量、失败率、SLO 或迁移统计。

---

## 3. 唯一目标合同

可恢复结果使用唯一字段 `recovery`：

```json
{
  "recovery": {
    "executable": "crctl",
    "args": [
      "review-loop",
      "reset",
      "CR-2026-062",
      "--loop",
      "review-tech-design"
    ],
    "cwd": "C:/authority/workspace",
    "requiresTTY": true,
    "promptFor": ["reason"]
  }
}
```

## 3.1 字段语义

| 字段 | 类型 | 规则 |
|---|---|---|
| `executable` | non-empty string | 实际可执行入口，如 `crctl`、`node`；不得包含参数或 shell 运算符 |
| `args` | string[] | 每个元素是一个完整 argv；不得把多个参数拼成单个元素 |
| `cwd` | absolute path string 或省略 | 仅在恢复动作必须位于特定 workspace 时返回；不得依赖调用方猜测 |
| `requiresTTY` | boolean | 是否必须在可信交互终端执行 |
| `promptFor` | string[] | 执行时需重新向人获取的逻辑值，如 `reason`；这些值不得预先拼入 `args` |

## 3.2 必须满足的不变量

1. `recovery` 是唯一机器执行事实源。
2. 不返回 `recoverCommand` 或 `recover_command`。
3. 不返回等价 shell string 作为备用执行入口。
4. 用户输入保持为独立 argv，或通过 `promptFor` 在执行时获取。
5. `executable` 不允许包含空格分隔参数、管道、重定向、连接符或 shell 展开。
6. `args[]` 的顺序与目标 CLI 参数顺序一致。
7. 人类界面若需要显示命令，只能从 `recovery` 渲染；显示结果不得反向作为执行输入。
8. 调用方使用非 shell argv 执行方式；不得调用 `shell: true` 或 `Invoke-Expression`。
9. 现有错误码、exit code、transaction id、route、files、rollback 信息保持原义。

## 3.3 `promptFor` 行为

对于 reset reason 等必须由人确认的值：

```json
{
  "requiresTTY": true,
  "promptFor": ["reason"]
}
```

执行方必须：

1. 在可信 TTY 中重新获取值；
2. 按目标 CLI 已有交互入口传入；
3. 不从旧错误消息、评论或日志中提取后自动复用；
4. 非 TTY 环境停止并报告需要的人类动作。

本 CR 不引入新的交互协议；`promptFor` 只结构化声明现有人工输入要求。

---

## 4. 盘上影响面

以下是排除 `node_modules`、构建产物、历史 traceability、历史 change-request 和 test evidence 后的活跃影响面。

## 4.1 核心生产者

目标文件：

`tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs`

已知恢复场景：

| 场景 | 当前大致位置 | CR-R 修订 |
|---|---:|---|
| register | 777 | 原位把字符串构造改为 `recovery` 对象 |
| workspace sync | 1074 | 同上；workspace 放入 `cwd` 或独立 argv |
| merge | 1514 | 同上；分支/ref 各自保持独立 argv |
| publication lag → checkpoint | 1572～1575 | 不再返回字符串 fallback |
| checkpoint | 1945 | 同上 |
| writeback traceability | 2814 / 2821 | 同上 |
| writeback apply | 2882 | 同上 |
| archive | 3460 | 同上 |
| test | 4186 | 同上 |

实际实施前使用 `rg "recoverCommand|recover_command"` 重新定位，禁止依赖本文行号做盲改。

## 4.2 CLI 投影

目标文件：

`tools/skills/shared/crctl/scripts/crctl.mjs`

当前已知位置约包括：

- 2686：`recoverCommand` 投影；
- 3237：`recoverCommand` / `recover_command` 双投影；
- `review-loop reset` 在 CR-P0 中增加的安全兼容恢复结果。

CR-R 原位完成：

- 接收/透传 `recovery`；
- 删除两个旧字段的 projection；
- reset 直接返回结构化 `recovery`；
- 不在 CLI 层重新拼接 shell string。

## 4.3 活跃 Skill 与 Agent 消费者

原位修改：

- `tools/skills/shared/crctl/SKILL.md`
- `tools/skills/writeback/merge-feature-branch/SKILL.md`
- `tools/skills/sync/push-progress/SKILL.md`
- `tools/skills/cr/cr-archive/SKILL.md`
- `multica/cr-prompts-revised/delivery-agent.md`
- 其它经实施时搜索发现的活跃 Agent/Skill/Pipeline 引用。

修改规则：

- 把“执行 `recoverCommand`”改成读取 `recovery.executable`、`recovery.args[]`、`cwd`、`requiresTTY` 与 `promptFor[]`；
- Agent 不自行转义或补写参数；
- 缺少必需字段时报告合同错误，不猜测恢复命令；
- Multica overlay 文件只提供 owner 可复制版本，本 CR 不更新平台 DB。

## 4.4 文档

原位修改：

- `tools/README.md`
- `tools/openwiki/operations/crctl-transactions.md` 的事实源或既有生成输入。

如果 openwiki 文件由生成流程维护，修改其权威输入后重新生成；不得同时手工维护第二套合同。

## 4.5 测试

至少原位迁移：

- `archive-tx.test.mjs`
- `checkpoint-tx.test.mjs`
- `merge-tx.test.mjs`
- `register-tx.test.mjs`
- `workspace-freshness.test.mjs`
- `writeback-tx.test.mjs`
- `crctl.test.mjs` 中 reset 恢复合同测试。

旧测试中的：

```js
result.recoverCommand.includes('...')
```

改为结构断言，例如：

```js
assert.equal(result.recovery.executable, 'crctl');
assert.deepEqual(result.recovery.args, [/* exact argv */]);
assert.equal(result.recovery.requiresTTY, false);
assert.deepEqual(result.recovery.promptFor, []);
```

涉及临时路径时断言数组元素和顺序，不对完整 JSON 做脆弱快照。

---

## 5. 原位实施方案

## 5.1 在既有 crctl 公共层定义最小构造器

优先在 `workspace-transactions.mjs` 已有结果构造邻近位置复用一个最小函数，例如：

```js
function recovery(executable, args, options = {}) {
  return {
    executable,
    args,
    requiresTTY: options.requiresTTY ?? false,
    promptFor: options.promptFor ?? [],
    ...(options.cwd ? { cwd: options.cwd } : {}),
  };
}
```

约束：

- 只在多个生产者确实重复时提取；
- 不新增 class、factory、builder 或 registry；
- 构造器不执行命令、不渲染字符串；
- 参数校验复用当前项目已有断言风格。

如果现有结果辅助函数已能表达该对象，直接复用，不增加上述函数。

## 5.2 逐个替换既有字符串构造

对每个生产者：

1. 保留原错误码和恢复时机；
2. 把命令 token 拆成独立 args；
3. workspace/ref/path/reason 不进入模板字符串；
4. 需要人输入的 reason 改为 `promptFor: ['reason']`；
5. 要求特定 workspace 时写入 `cwd`；
6. 删除同一位置的旧字段，而不是并排双写。

示意：

```js
// before
recoverCommand: `crctl checkpoint ${cr} --workspace "${workspace}"`

// after
recovery: {
  executable: 'crctl',
  args: ['checkpoint', cr, '--workspace', workspace],
  cwd: workspace,
  requiresTTY: false,
  promptFor: [],
}
```

## 5.3 同步迁移所有消费者

- 代码消费者使用 spawn/execFile 类 argv API；
- Prompt/Skill 消费者按字段逐项传递；
- 人类显示层可用既有 UI/CLI renderer 显示，但不得执行显示结果；
- 不新增“如果没有 recovery 就读取 recoverCommand”的 fallback。

## 5.4 删除旧字段

同一个 CR 内删除：

- 所有生产者的 `recoverCommand`；
- 所有生产者的 `recover_command`；
- `crctl.mjs` 兼容 projection；
- 测试中的字符串断言；
- 活跃 Skill/Agent/Pipeline 中旧消费说明；
- README 中旧合同示例。

不留 deprecated alias，不生成 migration shim。

## 5.5 加入既有 contract-scan 退役名单

复用已有静态合同扫描机制，把以下名称加入退役字段禁止清单：

```text
recoverCommand
recover_command
```

扫描范围：

- 活跃源码；
- 活跃 Skill；
- 活跃 Agent；
- Pipeline；
- 活跃测试。

允许排除：

- 历史 CR；
- 历史 traceability；
- 归档 delivery 证据；
- changelog/migration 文档；
- contract-scan 自身的禁止名单。

不要把简单全仓零命中作为唯一实现，因为历史证据合法包含旧字段。

---

## 6. 安全测试向量

每类生产者至少覆盖与其输入相关的边界；不要求复制成每函数全排列测试。

### 6.1 参数边界

- CR-ID、workspace、branch/ref 处于独立 `args[]` 元素；
- 含空格路径不依赖额外引号；
- 参数顺序与 CLI 合同完全一致。

### 6.2 用户输入

reason 至少覆盖：

```text
normal reason
quote " value
semi;colon
line1\nline2
$(substitution)
`powershell-expression`
```

预期：

- reset 的 `args[]` 不包含 reason；
- `promptFor` 包含 `reason`；
- JSON 序列化后仍保持数据，不形成 shell command。

### 6.3 executable 安全

- `executable` 不含空格参数；
- 不含 `|`、`>`、`<`、`;`、`&&`、`$()`；
- 使用 `node` 时脚本路径是 `args[0]`，不是 executable 字符串的一部分。

### 6.4 合同缺失

消费方收到以下结果时必须停止并报告合同错误：

- 无 `executable`；
- `args` 不是数组；
- `requiresTTY=true` 但运行环境无 TTY；
- `promptFor` 非空却没有允许的人类输入入口。

不得自动回退旧字段，因为旧字段在该 CR 已删除。

---

## 7. CR-R 交付边界

## 7.1 必须包含

- 目标合同定义；
- 全部已知生产者迁移；
- 全部活跃消费者迁移；
- reset 的 CR-P0 兼容恢复迁移；
- 两个旧字段删除；
- contract-scan 退役保护；
- 测试与 README/Skill/Agent 原位同步；
- 正常 writeback 需要的 specs/delivery 更新。

## 7.2 必须排除

- AIFI-18 的 SDD review 规则；
- `_context.md` 删除；
- plan/TASK 增量回修；
- Pipeline 节点调整；
- Multica API 或 importer 改造；
- 第二个删除 CR；
- 兼容版本；
- 迁移指标或遥测。

---

## 8. 验收条件

CR-R 只有同时满足以下条件才完成：

1. 所有可恢复结果使用 `recovery`，字段语义符合本文第 3 节。
2. register、workspace、merge、checkpoint、writeback、archive、test、reset 的恢复测试通过。
3. 用户 reason 不出现在 reset `args[]` 或任何 shell string 中。
4. 所有代码消费者使用 argv 边界，不使用 `shell: true` / `Invoke-Expression`。
5. 活跃源代码、Skill、Agent、Pipeline、README 和测试不再消费旧字段。
6. `recoverCommand` / `recover_command` 只允许出现在历史证据、迁移文档和退役禁止名单中。
7. 既有 crctl、ledger transaction、workspace freshness、merge、writeback、archive 全量测试通过。
8. 修改没有改变错误码、状态转换、transaction id、rollback 或 files 语义。
9. tools 发布后，由 owner 更新引用恢复合同的 Multica 平台 Prompt；本 CR 不伪称 DB 已部署。

---

## 9. 回滚

该迁移是单发布原子切换，回滚也必须整体进行：

- 若 CR-R 在合并前失败，回滚整个 CR；
- 不保留“部分生产者新合同、部分消费者旧合同”的分支状态；
- 不通过临时恢复 `recoverCommand` 让半迁移版本发布；
- 已发布版本若必须回退，回退到上一完整 tools 版本，而不是在当前版本双写。

当前没有外部消费者，因此整体回滚比长期兼容层更小、更可靠。

---

## 10. 实施前最终盘点

进入编码前执行一次有界搜索：

```text
rg -n --glob '!**/node_modules/**' --glob '!**/.git/**' \
  'recoverCommand|recover_command' tools/ multica/cr-prompts-revised/
```

把结果按以下类别归档到 CR-R 的实施计划：

- producer；
- code consumer；
- Prompt/Skill consumer；
- active test；
- active docs；
- historical evidence（排除）。

盘点只用于确保本次原子迁移不漏调用方，不新增持续观测机制。
