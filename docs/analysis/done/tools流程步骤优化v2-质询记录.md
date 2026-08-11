# tools 全流程优化方案 v2 — 质询记录

> 日期：2026-08-09  
> 状态：进行中  
> 被质询方案：`docs/analysis/tools流程步骤优化v2.md`  
> 原则：优先复用 `../tools` 已有设计；新增结构必须由真实功能缺口证明；未拍板事项不得当作实施授权。

## 1. 已核实基线

### 1.1 状态机当前口径

`../tools/dir-graph.yaml` 当前声明：

- 15 个具名状态 + 注册前 `(new)`；
- 27 条声明转换；
- wildcard 展开后 49 条转换。

25/47 是 CR-2026-022 后、CR-2026-026 前的历史口径。当前仍使用旧口径的位置包括：

- workspace `AGENTS.md`；
- workspace `CONTEXT.md`（本次质询已修正）；
- `../tools/ARCHITECTURE.md` §3 与 §5。

`../tools/ARCHITECTURE.md` §8 的 CR-2026-026 维护记录已经写明 27/49，因此该文件当前前后矛盾。

### 1.2 crctl 已有目的型原语

当前 `crctl.mjs` 已提供：

```text
status / gate / advance / approve / validate / attempt / next
review-record / review-note
checkpoint-add / owner-set / backlog-set / inbox-emit
cr-init / worktree-path
task done / task allocate
merge-metadata / archive-move
test / git
report / cr-metrics / migrate-backlog
```

后续设计必须优先组合这些原语，不得为 Runner 再造同义的
`stage-context`、`register-preflight`、`registration-check`、`branch-base-set`
或通用账本命令。

### 1.3 已有机械脚本

`../tools/skills/writeback/scripts/` 已存在并有回归测试：

```text
lib.mjs
writeback-prd-sdd.mjs
writeback-tasks.mjs
writeback-traceability.mjs
test/writeback.test.mjs
```

其中 `lib.mjs` 已提供 LF 规范化、结构化成功/失败输出、文件读取、hash/diff、
frontmatter 定点处理、参数解析和账本路径保护。若未来出现 Runner 公共库，必须先证明
这些能力不能直接复用或小幅下沉；不得在 `shared/runner/lib.mjs` 无条件复制一套。

### 1.4 engineering-docs 的当前边界

`engineering-docs` 当前是被动 Skill，不再依赖 MCP；其模板、schema、命名约定仍是工程
文档的一套通用契约。`scripts/` 仅作历史参考。

但进一步核验发现，这套通用契约与当前 CR 阶段 PRD 不兼容：

| 项目 | engineering-docs PRD schema/template | 当前 CR PRD |
|---|---|---|
| id | `PRD-NNN` | `{CR-ID}-prd` |
| 必填字段 | `name`、`refs` | `cr-ref`、`target-version`、`owner-role` |
| 时间 | `YYYY-MM-DD` | 带 `+08:00` 的 ISO 时间戳 |
| 文档定位 | 产品区活文档 | 单个 CR 的审批阶段产物 |

此外：

- `crctl validate` 当前不支持 `prd.md`，会返回 `UNKNOWN_ARTIFACT`；
- `validate-doc` 仍只有自然语言检查步骤，没有确定性实现；
- engineering-docs 的历史 TS validator 依赖 Ajv/gray-matter/yaml 等第三方包，且校验的
  正是上述不兼容 schema，不能直接恢复使用。

**最小结论：**

1. PRD Runner 不恢复旧 MCP/CLI，也不直接调用历史 validator；
2. 复用 `write-requirement-prd/SKILL.md` 已形成的 CR PRD frontmatter、章节与回修语义；
3. 复用 `backlog-set`、`next`、`review-record`、`crctl git` 等现有原语；
4. PRD 垂直试点只实现 CR 阶段 PRD 的最小确定性校验；
5. 不顺手统一“通用产品 PRD”和“CR 阶段 PRD”两套模型；若未来确需统一，单独立项。

### 1.5 Pipeline Runner 与 typed outputs 当前均未实现

现有 Pipeline JSON 有 typed inputs、reviewLoop、replayNodes、passCondition 和 onFail，
但没有节点 `outputs` 声明。进一步核实 `../multica`：

- `server/migrations/162_aifirst_pipeline_runs.up.sql` 明确注明尚无 orchestrator/Runner；
- `pipeline_run` / `pipeline_node_run` 当前只是从 crctl 事件流生成的只读投影；
- `pipeline_node_run.output_note` 仍定义为 `node-N.md` 路径；
- `detail` 只承载 review event payload，不是通用 typed outputs；
- `../multica/CUSTOM.md#未做` 明确写明“真正的 Runner（执行非 human 节点、驱动流水线）未做”；
- multica 源码中不存在 `PipelineDefinition`、节点 outputs schema 或跨节点 output mapping 实现。

因此，在 tools 包单独增加：

```json
{
  "outputs": {
    "cr": "string",
    "workspace": "path",
    "status": "string",
    "next": "string"
  }
}
```

当前不会获得运行时语义，只会产生一份无人消费的声明。`.crctl/runs/...` 也会成为新的
持久化协议和第二套上下文载体。

**最小结论：** typed outputs 必须由未来真正的 Pipeline Runner 设计一起定义；本轮
tools 流程优化最多要求各确定性脚本向 stdout 输出稳定 JSON，供人工或未来 Runner
消费，不提前修改 Pipeline schema，也不创建 `.crctl/runs` 协议。

### 1.6 archive `_index.yml` 的现有语义证据

当前事实：

- `cr-init` 将 CR 登记进 `change-requests/_index.yml`；
- `cr-archive` Skill 声称 `archive-move` 会同步 `_index.yml`；
- `cmdArchiveMove` 实际只原子修改 `_backlog.yml` 与 `_history.yml`；
- workspace `_index.yml` 保留所有历史 CR，并对早期条目标记
  `status: archived`、`archived-at`、`writeback-spec-id`；
- 最近归档的 CR-2026-024～026 已进入 `_history.yml`，但 `_index.yml` 仍显示
  `status: drafting`。

这说明 `_index.yml` 的实际历史形态更接近“全生命周期目录”，不是 active-only 索引。
在三个候选方案中，当前证据最支持：

```text
归档时保留条目，并更新现有终态摘要字段，不复制完整历史记录。
```

最终字段集仍需用户拍板；在此之前不得实施 Archive Runner。

## 2. 初步重用审计

| v2 提案 | 已有可复用设计 | 初步判断 |
|---|---|---|
| approve 原子提交 | `writeApprovalSection`、`cmdAdvance(...embedded)`、`crctl git` | 是真实正确性缺口；应在现有 `approve` 内组合，不新增命令 |
| TASK 完成门禁 | `task done`、`deliveryIndexComplete` gate | 修复现有 gate 判定，不新增 reconcile |
| archive payload 文件 | `inbox-emit --payload` | 先证明命令行长度/转义缺口；若仅 Runner 内部调用，可由 Runner 读取 JSON 后调用现有原语 |
| archived status 查询 | `status`、`resolveCrState`、`_history.yml` | 扩展现有只读命令，不新增 archive-status 命令 |
| review-record 深化输出 | `review-record` 已返回 file/verdict/trace/attempt | 仅补调用方确实需要且尚未返回的字段；禁止重复返回可由现有结果直接得出的整份账本 |
| Runner 公共库 | writeback `lib.mjs`、crctl 的 `fail/ok` 与受控进程约束 | 先做垂直试点；第二个真实调用者出现后再抽公共库 |
| Pipeline typed outputs | multica 仅有投影表，真正 Pipeline Runner 尚未实现 | 从本轮删除；未来与 Pipeline Runner 同一 Spec 定义 |
| Requirement Register Runner | `cr-init`、`worktree-path`、`crctl git`、repositories | 适合薄编排；不得新增上下文型 crctl 命令 |
| repo/base/checkpoint context | repositories、worktree-path、checkpoint-add | 先扩展现有 checkpoint 语义；不得新建平行账本 |
| PRD Runner | write-requirement-prd 的 CR PRD 契约、backlog-set、next、review-record、crctl git | 适合作为首个垂直试点；不恢复不兼容的 engineering-docs 历史 validator |
| Review Runners | review-record、attempt、reviewLoop/passCondition | 只统一机械调用形态，评审维度仍归各 Skill |
| Implement Runner | task done、test、git、review evidence | 应按 TASK 试点，不预先建设通用执行框架 |
| Structured Test | 现有 `crctl test --cmd` | 是否新增 `--plan` 必须由多命令结构、timeout/cwd 复现需求证明 |
| Merge Runner | merge-feature-branch Skill、merge-metadata、crctl git | 高风险；应在前序试点稳定后再做，且不新增大型 merge ledger |
| Writeback Runner | 三个现有 writeback 脚本 | 只能做薄编排，不重写现有算法 |
| Archive Runner | inbox-emit、advance、archive-move、crctl git | 先解决 `_index.yml` 契约和 publish/cleanup 恢复边界 |

## 3. 已拍板决策与延后议题

### Q1：Phase 2～6 是承诺设计还是候选路线？

**建议答案：候选路线。**

近期只承诺：

1. Phase 0 基线统一；
2. Phase 1 正确性修复；
3. 一个 PRD Runner 垂直试点。

其余 Runner、typed outputs、公共库和固定 JSON schema 只保留目标、边界与触发条件。
只有垂直试点证明至少两个 Skill 共享相同机械逻辑后，才抽公共 Runner 能力。

**用户决策（2026-08-09）：同意。**

### Q2：archive `_index.yml` 的生命周期语义

当前证据最支持 `_index.yml` 是全生命周期目录：

- 历史 CR 条目没有在归档时删除；
- 早期归档条目已有 `status: archived`、`archived-at`、`writeback-spec-id`；
- CR-2026-024～026 已进入 `_history.yml`，但 `_index.yml` 因 `archive-move` 未更新而仍
  显示 `status: drafting`；
- `cr-archive` Skill 已承诺归档时同步 `_index.yml`，只是实现没有兑现。

消费者核验进一步确认：

- `cr-query`、`cr-show`、`cr-dashboard` 均以 `_backlog.yml` + `_history.yml`（以及
  `cr.md`）作为查询事实源，不从 `_index.yml` 读取状态；
- Multica 当前没有读取 `change-requests/_index.yml` 的运行时代码；
- `cr-init` 使用 `_index.yml` 与 `_backlog.yml` 扫描最大 CR 编号，并在注册时写入最小
  `{id,title,status,created}` 条目。

因此 `_index.yml` 不应升级为新的查询事实源，也不需要复制 history 内容；它只是需要
维持注册目录的一致性和编号连续性。补写终态字段不会改变现有查询链路。

**建议答案：**

`_index.yml` 保留全生命周期轻量目录；归档时由 `archive-move` 与 backlog/history 同一
次 `casWriteMulti` 更新对应条目：

```yaml
status: archived | rejected | withdrawn
archived-at: <timestamp>
writeback-spec-id: <spec-id>   # 有则写
```

不新增 `history-ref`：`_history.yml` 路径固定，按 CR-ID 即可查询，且现有索引没有该
字段先例。不把完整 history 条目复制进 `_index.yml`，也不从 `_index.yml` 删除 CR。

**用户决策（2026-08-09）：同意。**

### Q3：所有可写仓是否完全来自 repositories

核实结果：

- workspace repositories 只有 docs 与 multica；
- tools 已参与 10 个历史归档 CR；
- `merge-feature-branch` 明文承认 tools 不在声明范围，却以 `custom/main` 特例参与；
- requirement-register、checkpoint、resume、merge 的正式规则均声称只遍历 active
  repositories。

候选：

1. 将 tools 加入 active repositories，继续沿用“所有 active repo 参与每个 CR”；
2. 新增每 CR 仓库选择模型，避免无关 worktree，但需新增注册字段、恢复和合并语义。

**建议答案：方案 1。**先消除隐藏特例，不新增第二套参与模型；实际证明全仓 worktree
成本不可接受后再立项优化。

**用户决策（2026-08-09）：同意。**

最终口径：

```yaml
- id: tools
  path: "../tools"
  trunk: custom/main
  role: code
  active: true
```

删除 merge Skill 的 tools 特例；所有生命周期操作只从 repositories 解析参与仓。

### Q4：approve 的最小原子性边界

当前 `cmdApprove` 先写 approval，再调用 `cmdAdvance`；`cmdAdvance` 的普通提交只 stage
`cr.md`，造成 approval/status 分提交，并可能留下单文件半状态。

候选：

1. 只要求同一 Git commit；
2. 预检后在内存生成 approval/cr.md，复用 `casWriteMulti` 两文件写入，再单次 commit。

**建议答案：方案 2。**复用现有 CAS，不新增通用事务框架；TTY 与 grant 共用内部
helper。gate/CAS 失败零写入，commit 失败两文件共同留存且不发 status outbox。

**用户决策（2026-08-09）：同意。**

### Q5：归档事件的原子性边界

CR-2026-026 已证明独立 `inbox-emit --payload <中文 JSON>` 会发生 Shell 转义失败，并在
后续归档继续时永久丢失事件。仅增加 `--payload-file` + fail-fast 仍留下“emit 成功、
archive CAS 失败、重试重复通知”的窗口。

候选：

1. 独立 inbox-emit，并新增 payload-file 与幂等机制；
2. archive-move 根据现有 final-status/reason/spec-id 构造事件，复用 editInboxEmit，
   与 backlog/history/index 同一 CAS。

**建议答案：方案 2。**接口更少，事件与归档要么同时发生、要么同时不发生；普通通知
仍使用 inbox-emit。

**用户决策（2026-08-09）：同意方案 2。**

### Q6：归档 CR 的最小只读查询契约

当前 `resolveCrState` 强制从 backlog 加载条目，导致归档后 `status/next` 都失败。

**建议答案：**新增只读 resolver，仅供 status/next：

- history `final-status` 为终态查询权威；
- `terminal:true`、`legalNext:[]`、`next:null`；
- 写命令继续使用 active resolver；
- backlog/history 冲突、history 重复或缺 final-status 均硬失败；
- cr.md 漂移只告警；
- 不新增命令或非必要归档字段。

**用户决策（2026-08-09）：同意。**

最终口径：

- `_index.yml` 是全生命周期轻量目录；
- `archive-move` 复用现有 `casWriteMulti`，原子更新 backlog/history/index；
- 只写 `status`、`archived-at`、可选 `writeback-spec-id`；
- 不新增 `history-ref`，不复制 history 详情，不改变查询事实源。

### Q7：review-record 的最小返回契约

核验消费者后，`verified`、subject digest、next 均无必要；真实缺口是实际写入文件、
完整 attempt 信息和 dev-plan route。

**建议答案：**

- 新增 `files[]`、`attempt.{current,max,bumped}`、`route`、`repairTarget`；
- 保留现有 `file/trace` 兼容；
- files 只列本次实际写入；
- 删除 review Skill 的 traceability 二次读取；
- next 仍唯一调用 `crctl next`。

**用户决策（2026-08-09）：同意。**

已同步回主方案：

```text
Phase 0
→ Phase 1
→ PRD Runner 垂直试点
→ 最小公共能力与 Registration
→ 其余 Authoring/Review（逐项）
→ Implement/Test/Code Review（逐项）
→ Merge/Writeback/Archive
```

后续阶段采用证据晋升门槛，不按日期或原 Phase 编号自动获得实施授权。Pipeline typed
outputs 已从本轮删除；公共 Runner 库必须等待第二个真实调用者。

**边界修订（2026-08-09，用户纠正）：**当前实施范围只包含 Phase 0 和 Phase 1。
PRD 垂直试点虽是后续第一个候选，也不属于当前承诺；Phase 0/1 完成后必须重新确认并
另写 Spec。此前“近期承诺 PRD 试点”的表述已从主方案撤回。

### Q8：TASK 归档门禁是否允许隐式 no-task

当前 `deliveryIndexComplete` 在 task index 缺失或所有 TASK pending 时都会得到空
doneIds 并放行。状态机证明正常 archived 必经 developing，而 developing 已要求 task
index 和非空 TASK；20 个现有归档 CR 也全部有任务。

**建议答案：**

- archived 必须存在非空 task index，全部 done 后再校验 delivery index；
- 缺失/空/pending 均不得推断成 no-task；
- rejected/withdrawn 可无 TASK，但 archive-move 的 final-status 必须等于 cr.md 当前
  终态；
- 不新增 no-task 字段或 task reconcile。

**用户决策（2026-08-09）：同意。**

### Q9：Phase 0/1 的最小修改与验证集合

初版误把所有已有检查器都列成当前必跑项。核验实际触及范围后收缩为：

- 修改核心：workspace dir-graph/AGENTS、tools ARCHITECTURE、crctl.mjs 与现有
  crctl.test.mjs；
- 只修改确有过时指令的 merge/archive/review Skill 与 feature-writeback pipeline；
- 不改 gates、matrix/index、approve Skill、engineering-docs、writeback scripts 或检查器
  本身；
- 只运行 diff-check、pipeline JSON parse、crctl tests、lint-prompts enforce 和两项
  grep；
- 不新增 validator/schema/test runner。

**用户决策（2026-08-09）：同意。**

### Q10：归档事件收件人

`cr-archive` 原文使用不存在的 submitter/reviewer 字段，而现有 21 条历史记录均已有
三角色 owners；普通 inbox-emit 的 Skill 契约要求 `to` 必填，但 crctl 当前允许空列表。

**建议答案：**

- archive 收件人取 requirement/development/test owner ID 并去重；
- legacy 数据仅回退顶层 owner；
- 最终为空时 CAS 前硬失败；
- 普通 inbox-emit 同步拒绝缺失或空 `--to`；
- 不新增身份字段。

**用户决策（2026-08-09）：同意。**

### 延后议题 R1：公共 Runner 能力如何复用 writeback `lib.mjs`

三个候选：

1. 让 requirement/develop Runner 直接 import `skills/writeback/scripts/lib.mjs`：复用直接，
   但形成 requirement → writeback 的反向领域依赖；
2. 现在创建 shared lib 并复制通用函数：依赖方向正确，但重复实现且过早抽象；
3. 首个 PRD 试点保留最小局部 helper；第二个 Runner 出现后，把 writeback `lib.mjs`
   中已证明通用的函数**移动**到 `skills/shared/runner/lib.mjs`，writeback 与新 Runner
   都从 shared import，writeback 专属逻辑继续留在原文件。

**建议答案：方案 3。**它既复用已有实现，又不让上游领域依赖 writeback，也不会在第二
个调用者出现前预建公共 API。迁移必须是提取而非复制，并用现有 writeback 回归测试防止
行为变化。

**状态：延后。**该问题属于 Phase 2+，不在当前 Phase 0/1 质询范围；不得现在冻结方案。

## 4. 后续质询队列

以下问题按依赖顺序逐个提出，不并行拍板：

1. ~~Q1：收缩 Phase 2～6 的承诺强度~~（已同意）；
2. ~~Q2：archive `_index.yml` 是否确认为全生命周期目录~~（已同意）；
3. ~~Q3：所有可写 repo 是否必须完全来自 `dir-graph.yaml#repositories`~~（已同意）；
4. ~~Q4：approve 原子提交的最小事务边界~~（已同意）；
5. ~~Q5：归档事件是否进入 archive-move CAS~~（已同意方案 2）；
6. ~~Q6：archived status 查询的最小返回契约~~（已同意）；
7. ~~Q7：review-record 还需补哪些真实消费字段~~（已同意）；
8. ~~Q8：TASK 归档门禁是否允许隐式 no-task~~（已同意）；
9. ~~Q9：Phase 0/1 最小修改与验证集合~~（已同意）；
10. ~~Q10：归档事件收件人~~（已同意）；
11. Phase 2+（延后）：公共 Runner 库、PRD 契约、checkpoint kind、retry mode。

Pipeline typed outputs 已通过事实核验收口：当前 Runner 不存在，本轮不设计该协议。
