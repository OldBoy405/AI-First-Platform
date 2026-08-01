---
id: CR-2026-005-sdd
type: SDD
cr-ref: CR-2026-005
title: 治理工具链补丁 — delivery/task 回写一致性门禁 + writeback-tasks 原子化 Skill 技术设计
status: draft
created: "2026-08-01T13:40:00+08:00"
updated: "2026-08-01T13:40:00+08:00"
---

# SDD — delivery/task 回写一致性门禁 + writeback-tasks Skill

> 落点仓：`tools` 包（`crctl.mjs`、`gates.json`、新 skill 目录）。`tools` 不在 `dir-graph.yaml` 的 `repositories` 声明范围内（只声明 knowledge-base + multica），历史上 CR-2026-002/003 对 crctl 的改动都是直接提交到 tools 的 `custom/main` trunk，不走 CR worktree——本 CR 沿用同一先例，无 multica 代码改动。

## 1. 架构概览

```
crctl.mjs runGateChecks()
  │
  ├─ 既有 5 类 check（fileExists / globNonEmpty / passCondition / approval / attemptsWithinLimit）
  │
  └─ 新增 check type: "deliveryIndexComplete"（FR-1）
       读 change-requests/{cr}/tasks/_index.yml（status=done 任务 id 集合）
       读 delivery/task/_index.yaml（全局已登记 id 集合）
       集合差 = done 任务 id 集合 − 全局登记 id 集合
       集合差非空 → ok:false，why 列出缺失 id 清单

gates.json statusGates.archived[] 追加一条 { "type": "deliveryIndexComplete" }

tools/skills/writeback/writeback-tasks/SKILL.md（新增，FR-2）
  输入 cr_id + spec_id + version
  → 读 tasks/_index.yml 筛 done
  → 对每个缺失于全局索引的任务：拷贝 md + 追加索引行
  → 幂等：已存在的 id 跳过，不重写
```

## 2. 数据模型

无新增持久化结构。涉及的既有两份文件均为纯文本 YAML/Markdown，本 CR 只新增读取逻辑，不改其 schema：

- `change-requests/{cr}/tasks/_index.yml`：`tasks[].{id, title, status, estimate, depends-on}`（`write-dev-tasks` skill 既有产出）。
- `delivery/task/_index.yaml`：`- {id, file, title, status, cr-ref, target-version, estimate}`（人工维护，本 CR 起改为 skill 维护）。

**关键事实核实**（评审建议 1）：抽查 CR-2026-004 的两份索引，`id` 字段完全同名同值（如 `CR-2026-004-TASK-01`），两处均是 `{cr_id}-TASK-{NN}` 格式。门禁实现是**简单集合差**，不需要映射表。

## 3. 接口契约

### 3.1 新 gate check type：`deliveryIndexComplete`

```js
// crctl.mjs runGateChecks() 内新增一个 else-if 分支
} else if (check.type === 'deliveryIndexComplete') {
  const r = checkDeliveryIndexComplete(ws, cr);
  out.checks.push({ type: check.type, ok: r.ok, missing: r.missing, why: r.ok ? null : `delivery/task 索引缺失 ${r.missing.length} 项: ${r.missing.join(', ')}` });
}
```

```js
function checkDeliveryIndexComplete(ws, cr) {
  const tasksIdx = readEvidenceDoc(ws, cr, 'change-requests/{cr}/tasks/_index.yml');
  const doneIds = tasksIdx.exists
    ? (tasksIdx.data?.tasks || []).filter(t => t.status === 'done').map(t => t.id)
    : [];
  if (doneIds.length === 0) return { ok: true, missing: [] };            // FR-3 边界①：无 done 任务
  const globalPath = path.join(ws, 'delivery/task/_index.yaml');
  const globalIds = fs.existsSync(globalPath)
    ? (parseYaml(fs.readFileSync(globalPath, 'utf8'))?.tasks || []).map(e => e.id)
    : [];                                                                 // FR-3 边界②：全局索引不存在
  const missing = doneIds.filter(id => !globalIds.includes(id));
  return { ok: missing.length === 0, missing };
}
```

> **实现期修正**：初版误以为 `delivery/task/_index.yaml` 顶层是裸列表（`- id: ...`），实际和 `tasks/_index.yml` 一样有 `tasks:` 包裹键——`grep` 抽查历史数据时只看了深层条目，没确认顶层结构，导致首次真机重放（AC-1，对 CR-2026-001~004 四个历史 CR）时直接抛 `TypeError: .map is not a function`。用真实历史数据做 AC-1 验证的价值正在于此：fixture 自造数据很容易无意中假设成"我以为的格式"而不是"实际的格式"，两者一致时测试全绿但没测出问题。已改为 `?.tasks || []` 并用真实 4 个 CR 数据重新验证通过。

`readEvidenceDoc` 的 `{cr}` 占位替换与已有的 `evaluatePassCondition` 复用同一惯例（`.replaceAll('{cr}', cr)`）；`delivery/task/_index.yaml` 是仓根全局路径，不经过 `{cr}`/`{spec}` 占位替换。

### 3.2 gates.json 改动

```jsonc
"archived": [
  { "type": "fileExists", "path": "change-requests/{cr}/traceability.yml" },
  { "type": "fileExists", "path": "specs/{spec}/PRD.md" },
  { "type": "fileExists", "path": "specs/{spec}/SDD.md" },
  { "type": "fileExists", "path": "specs/{spec}/traceability.yml" },
  { "type": "fileExists", "path": "delivery/task" },
  { "type": "deliveryIndexComplete" }   // 新增，FR-1
]
```

**NFR-4（向后兼容）核实**：门禁只在 `--to archived` 转移时求值，历史已归档的 CR-2026-001~004 不会被本次新增检查追溯触发——`runGateChecks` 只在状态转移动作发生时调用一次，不存在批量重跑机制。

### 3.3 writeback-tasks Skill 契约

```yaml
---
name: writeback-tasks
description: 将 change-requests/{CR-ID}/tasks/ 下 status=done 的任务原子回写到 delivery/task/（拷贝+frontmatter+全局索引），供 archived 门禁的 deliveryIndexComplete 检查通过。
---
```

参数：`cr_id`（必填）、`spec_id`（必填，写入 frontmatter）、`version`（必填，写入 frontmatter 与索引 `target-version`）。

执行步骤：

1. 读 `change-requests/{cr_id}/tasks/_index.yml`，筛 `status=done`。
2. 读 `delivery/task/_index.yaml`（不存在则视为空列表），求出**已登记 id 集合**。
3. 对每个 done 任务、且 `id` 不在已登记集合内（**幂等关键**，NFR-2）：
   a. 读源 `change-requests/{cr_id}/tasks/TASK-{NN}.md`。
   b. 派生文件名 `TASK-{version}-{cr_id}-{NN}-{slug}.md`；`slug` 算法（评审建议 2）：取任务 `title` 中文/英文混排时，优先取 frontmatter 无标准字段，**改为要求任务作者在 TASK-NN.md frontmatter 补一个可选字段 `slug:`**（write-dev-tasks skill 同步小改，非本 CR 必需——若缺失，回退用 `id` 小写去前缀作 slug，如 `task-01`，牺牲可读性但保证确定性，不做中文分词猜测）。
   c. 在源文件 frontmatter 后追加 `spec-id: {spec_id}` / `version: "{version}"` 两行，写入目标路径。
   d. 追加一行到 `delivery/task/_index.yaml`：`{id, file, title（取自任务 frontmatter title 或正文首个 H1）, status: done, cr-ref: {cr_id}, target-version: {version}, estimate（取自任务 frontmatter estimate）}`。
4. 已登记的 id 直接跳过（不重写文件，不重复追加索引行）——这是 NFR-2 幂等性的完整保证：**判断幂等的依据是全局索引里是否已有该 id，不是文件内容比较**，避免"文件内容 diff 判定"的复杂度。

### 3.4 slug 确定性算法（评审建议 2 落地）

```
若 TASK-NN.md frontmatter 存在 slug 字段 → 直接使用（人工可控，历史 4 个 CR 的现有命名就是这样人工拟定的，行为不变）
否则 → slug = "task-{NN}"（如 task-01），保证同一输入永远同一输出，不引入分词/截断等有歧义步骤
```

## 4. 关键流程

```
crctl advance {cr} --to archived --spec-id {spec} :
  ...既有 5 项 fileExists/traceability 检查...
  → deliveryIndexComplete(cr):
       doneIds = tasks/_index.yml 中 status=done 的 id 列表
       if doneIds为空: pass
       globalIds = delivery/task/_index.yaml 的 id 列表（文件不存在则空集）
       missing = doneIds - globalIds
       if missing非空: GATE_BLOCKED，展示 missing 清单
       else: pass
```

## 5. 技术选型与替代方案

| 决策 | 选择 | 放弃项与理由 |
|---|---|---|
| 门禁实现位置 | crctl.mjs 内新增 check type（与既有 5 类同一 `runGateChecks` switch） | 独立校验脚本外挂：违反"gate 逻辑统一在 crctl 声明式门禁"的既有架构原则（见 gates.json 文件头注释） |
| id 匹配方式 | 简单集合差（字符串相等） | 模糊匹配/映射表：已核实两份索引 id 同名同值，模糊匹配是不必要的复杂度 |
| slug 生成 | frontmatter 显式字段优先，否则 `task-{NN}` 兜底 | 中文分词算法：引入歧义与依赖，且 4 个历史 CR 的 slug 都是人工语义拟定，无法用算法逆向重现，与其猜不如约定新字段 |
| writeback-tasks 幂等判据 | 全局索引 id 是否存在 | 文件内容 hash 比较：多一层复杂度且不解决"索引行本身是否写全"这个核心问题——本 CR 要修的恰恰是索引同步，用索引自身做判据最直接 |

## 6. FR → 技术实现映射

| FR | 实现 | 触点文件 |
|---|---|---|
| FR-1 | `deliveryIndexComplete` check type + gates.json archived 追加一条 | `tools/skills/shared/crctl/scripts/crctl.mjs`、`tools/skills/shared/crctl/gates.json` |
| FR-2 | 新 skill：读 done 任务→拷贝+frontmatter→追加索引，幂等靠索引 id 判重 | `tools/skills/writeback/writeback-tasks/SKILL.md`（新增） |
| FR-3 | 空 doneIds 直接 pass；全局索引文件不存在时视为空集而非报错 | 同 FR-1 触点，函数内两个早退分支 |

## 7. 安全与性能考量

- **性能**：两份索引文件均为小体量 YAML（当前最大 4 个 CR、约 20 行/CR），门禁检查是一次性内存集合差，不引入可观测开销。
- **不影响既有门禁**：新 check 是 `archived` 门禁列表里追加的第 6 项，既有 5 项检查逻辑与顺序不变；`runGateChecks` 对未知/新 check type 采用"顺序执行、全部 ok 才 pass"的既有模式，无需改动整体判定逻辑。
- **诚实边界**：本 CR 不治理 backlog→history 手工归档迁移的同类空白（PRD §7 范围排除已声明），但该问题若后续立项，可直接复用本 CR 建立的"声明式 gate check + 集合差校验"模式，不需要重新设计（回应评审建议 3）。
