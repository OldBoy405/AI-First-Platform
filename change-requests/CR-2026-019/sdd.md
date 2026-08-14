---
id: CR-2026-019-sdd
type: SDD
cr-ref: CR-2026-019
title: 治理工具链 — YAML 账本操作收敛为 crctl 子命令（P2）+ AC-9 演练入库 技术设计
status: draft
created: "2026-08-04T17:09:39+08:00"
updated: "2026-08-04T17:25:00+08:00"
---

# SDD — YAML 账本操作收敛为 crctl 子命令（P2）+ AC-9 演练入库

## 0. 事实基线（已核实，纪律 #4）

| 事实 | 位置 | 对设计的影响 |
|---|---|---|
| 单文件 CAS 原语 `casWrite(p, expectedHash, newText)`：读→sha256 比对→写，不一致 `CAS_CONFLICT` | `crctl.mjs:667` | 三个子命令的单文件写直接复用 |
| YAML 写入范式 = **定向正则替换指定行**（无序列化器）；`updateCrMdStatus` 即样板 | `crctl.mjs:674-687` | 账本编辑一律行级正则改写 + CAS，匹配不到硬失败（纪律 #1） |
| `auditLog(ws, record)` 追加 JSON 行到 `.crctl/audit.log` | `crctl.mjs:358-364` | 三子命令统一留审计 |
| `loadBacklogEntry` 返回 `{entry, text, hash, path}`，hash=全文 sha256 | `crctl.mjs:334-344` | 直接作为 backlog 写入的 CAS expectedHash |
| outbox 原子写 = temp 文件 + rename | `crctl.mjs:397-399` | archive-move 双文件写沿用 temp+rename 收窄崩溃窗口 |
| dispatch 分发在 `main()` switch | `crctl.mjs:1419-1431` | 新增三个 case |
| `tasks/_index.yml` 结构：`tasks: [{id,title,status,estimate,depends-on}]` | `change-requests/*/tasks/_index.yml` | task done 按 id 锚定块内 `status:` 行改写 |
| **`merge-commits[]` 是结构化条目 `{repo, trunk, sha}`，非裸 sha** | `_backlog.yml:56-59` | **修订 PRD FR-2**：入参细化为 `--repo/--trunk/--sha`；PRD"追加进 merge-commits[]"意图不变，结论不受影响 |
| `_history.yml` 顶层 `history: [...]`，条目含 `final-status/archive-reason/writeback-spec-id/archived-at` | `_history.yml` | archive-move 追加富化条目到 history[]、从 backlog 删除同 id 块 |

## 1. 架构概览

### 1.1 模块边界

三个子命令全部落在 `crctl.mjs` 单文件内，**不新增文件、不建脚本库**（PRD FR-4）。新增一层"账本写入原语"，位于现有 CAS/审计原语之上、dispatch 之下：

```
main() dispatch (:1419)
  ├── case 'task'          → cmdTaskDone(ws, cr, flags)      ─┐
  ├── case 'merge-metadata'→ cmdMergeMetadata(ws, cr, flags) ─┤ 新增
  └── case 'archive-move'  → cmdArchiveMove(ws, cr, flags)   ─┘
                                    │
              ┌─────────────────────┼─────────────────────┐
      ledger 编辑纯函数        casWrite / casWriteMulti      auditLog
      （行级正则，纯 string→string） （复用 :667 + 新增多文件）  （复用 :358）
```

### 1.2 单一写入路径不变量（PRD FR-4 / NFR-3）

- **状态写入**唯一入口仍是 `advance`（纪律 #5 不变）——三个子命令**不改 CR status、不发 status 事件**，只做账本编辑。
- **账本写入**收敛为这三个子命令：任何对 `tasks/_index.yml` status / `_backlog.yml` merge-commits / backlog↔history 的写入，改造后都过 CAS + 审计，会话内手写/现写脚本被工具层根除（PRD FR-6 由文档强制）。
- 每个子命令 = 前置态守卫（precondition，不是状态转移）→ 行级编辑纯函数 → CAS 写 → 审计。

### 1.3 关键流程

```
cmdX(ws, cr, flags):
  1. resolveCrState(ws, cr)            # 读权威状态（复用 :704）
  2. 守卫：status ∈ 合法前置态集合？   # 否 → fail(ILLEGAL_LEDGER_STATE, 当前态/期望态)
  3. 读目标账本文件 text + hash        # readFileChecked + sha256
  4. newText = editPure(text, ...)     # 行级正则；匹配不到 → fail（硬失败，纪律 #1）
  5. casWrite(path, hash, newText)     # 单文件；archive 用 casWriteMulti
  6. auditLog(ws, {kind:'ledger', op, cr, before, after})
  7. ok({...})                         # 不发 status outbox 事件
```

## 2. 数据模型

不新增持久化实体，只编辑既有三类账本文件的既有字段。

| 文件 | 编辑字段 | 编辑语义 |
|---|---|---|
| `change-requests/{cr}/tasks/_index.yml` | `tasks[].status`，追加 `tasks[].done-at` | pending→done + 时间戳 |
| `change-requests/_backlog.yml` | 条目 `merge-commits[]` | 追加 `{repo,trunk,sha}`，按 sha 去重保序 |
| `change-requests/_backlog.yml` + `_history.yml` | 条目整体移动 | backlog 删块 + history 追加富化块（+final-status/archived-at） |

审计记录（`.crctl/audit.log` 追加行）字段：`{at, kind:'ledger', op:'task-done'|'merge-metadata'|'archive-move', cr, actor, before, after}`；`before/after` 为受影响字段摘要（如 task-done 记 `{taskId, from:'pending', to:'done'}`），不含全文。

## 3. 接口契约

CLI 契约（`--workspace` 沿用全局探测，`crctl.mjs:281`）：

```
crctl task done <CR-ID> --task <TASK-ID> [--workspace <dir>]
  前置态: developing（开发中）
  行为  : tasks/_index.yml 中 <TASK-ID> status pending→done + done-at
  错误  : TASK_NOT_FOUND | TASK_ALREADY_DONE | ILLEGAL_LEDGER_STATE

crctl merge-metadata <CR-ID> --repo <r> --trunk <t> --sha <sha> [--workspace <dir>]
  前置态: merging | writing-back（合并/回写期）
  行为  : _backlog.yml 条目 merge-commits[] 追加 {repo,trunk,sha}，sha 去重
  错误  : MERGE_COMMIT_DUP（同 sha 已存在，幂等返回 ok 不重复写）| ILLEGAL_LEDGER_STATE

crctl archive-move <CR-ID> --final-status <status> [--archive-reason <s>] [--spec-id <id>] [--workspace <dir>]
  前置态: archived（advance 已把状态推到 archived 后调用）
  行为  : 原子地 _backlog.yml 删条目 + _history.yml 追加富化条目
  错误  : ENTRY_NOT_IN_BACKLOG | ENTRY_ALREADY_IN_HISTORY | CAS_CONFLICT | ILLEGAL_LEDGER_STATE
```

出参统一 `ok({op, cr, ...摘要})`；失败走既有 `fail(code, message)`（非零退出，`crctl.mjs:29`）。

## 4. 关键算法与流程

### 4.1 task done — 块内锚定行替换（单文件 CAS）

```js
function editTaskDone(text, taskId) {
  const norm = text.replaceAll('\r\n', '\n');            // 纪律 #1 行尾规范化
  // 锚定 "- id: <taskId>" 起到下一个 "  - id:" 或 EOF 的块
  const block = matchTaskBlock(norm, taskId);
  if (!block) fail('TASK_NOT_FOUND', `${taskId} 不在 tasks/_index.yml`);
  if (/^\s*status:\s*done\b/m.test(block.text)) fail('TASK_ALREADY_DONE', taskId);
  // status 行替换与 done-at 插入一次完成：replace 回调直接产出两行（同缩进）
  let hit = false;
  const nb = block.text.replace(/^(\s*)status:\s*\S.*$/m, (_, indent) => {
    hit = true;
    return `${indent}status: done\n${indent}done-at: "${nowIso()}"`;
  });
  if (!hit) fail('TASK_INDEX_SHAPE', `${taskId} 块内无 status 行`);   // 匹配不到硬失败（纪律 #1）
  return norm.slice(0, block.start) + nb + norm.slice(block.end);
}
```
> matchTaskBlock 用块锚定正则；**匹配失败硬失败**，禁止静默返回原文（纪律 #1，T04 教训）。

### 4.2 merge-metadata — 幂等追加结构化条目（单文件 CAS）

```
1. loadBacklogEntry(ws, cr) → {entry, text, hash}
2. 若 entry.merge-commits 已含相同 sha → ok(MERGE_COMMIT_DUP 幂等，noop 返回)
3. 定位条目的 merge-commits: 块；无则在条目内创建该键
4. 在块尾按缩进插入 "- repo/trunk/sha" 三行
5. casWrite(backlogPath, hash, newText)  # hash 来自 loadBacklogEntry
```
去重键 = sha；保序追加（不排序，保留合并时间序）。

### 4.3 archive-move — 双文件原子写（新增 casWriteMulti）

```js
function casWriteMulti(writes) {           // writes: [{path, expectedHash, newText}]
  for (const w of writes)                  // 阶段一：全部 CAS 校验
    if (sha256(readFileChecked(w.path)) !== w.expectedHash)
      fail('CAS_CONFLICT', w.path);
  const staged = writes.map(w => {         // 阶段二：全部写 temp
    const tmp = w.path + `.tmp-${process.pid}`;
    fs.writeFileSync(tmp, w.newText, 'utf8'); return { tmp, dst: w.path };
  });
  for (const s of staged) fs.renameSync(s.tmp, s.dst);  // 阶段三：连续 rename
}
```

archive-move 流程：
```
1. 守卫 status===archived
2. 读 _backlog.yml(text_b,hash_b) + _history.yml(text_h,hash_h)
3. entryBlock = 从 backlog 抽取 "- id: {cr}" 块（抽不到→ENTRY_NOT_IN_BACKLOG）
4. history 已含 {cr} → ENTRY_ALREADY_IN_HISTORY（防重复归档）
5. newBacklog = 删除该块；newHistory = history[] 追加富化块
        （原块缩进下沉一级 + final-status/archive-reason/writeback-spec-id/archived-at）
6. casWriteMulti([{backlog,hash_b,newBacklog},{history,hash_h,newHistory}])
7. auditLog(op:'archive-move', before/after 摘要)
```

> **残余窗口（ponytail 天花板）**：casWriteMulti 的两次 rename 之间若进程崩溃，留 backlog 已删、history 未写的半状态。缓解：① rename 窗口为微秒级；② 账本变更随 `--embedded` 进同一 git 提交，工作树可 `git checkout` 回滚；③ 单写者不变量（纪律 #5）下无并发 crctl。判定为可接受天花板，不引入 WAL/两阶段提交（YAGNI）。升级路径：若未来出现并发写者，改文件锁。

## 5. 技术选型与替代方案

| 决策点 | 选型 | 替代方案与否决理由 |
|---|---|---|
| 账本写入落点 | crctl 子命令 | ❌ 独立脚本库（`tools/skills/shared/scripts/`）——复盘明确否决：开第二写入通道绕开 CAS/审计/门禁，长期必然漂移（PRD §7） |
| YAML 编辑方式 | 行级定向正则 + CAS | ❌ 引入 YAML 序列化库——新依赖（违 NFR-4）、且全量重排会打乱注释/字段序、扩大 diff 面；沿用 `updateCrMdStatus` 既有范式 |
| 双文件原子性 | casWriteMulti（全校验→全 temp→连续 rename） | ❌ WAL / 事务日志——对单写者场景过度设计（YAGNI）；❌ 直接顺序 casWrite×2——窗口更大 |
| 状态职责 | 三子命令不改 status，仅账本 | ❌ 让 archive-move 兼做 advance→archived——破坏 advance 单一状态写者不变量（纪律 #5） |

## 6. FR 到技术实现映射

| FR | 技术实现 | 覆盖 |
|---|---|---|
| FR-1 task done 子命令 | §4.1 `editTaskDone` + case 'task' 分发 + casWrite | ✅ |
| FR-2 merge-metadata 子命令 | §4.2（入参细化为 `--repo/--trunk/--sha`，见 §0 修订） | ✅ |
| FR-3 archive-move 子命令 | §4.3 + casWriteMulti 双文件原子 | ✅ |
| FR-4 单一写入路径不变量 | §1.2 复用 casWrite/casWriteMulti/auditLog，无独立脚本、零新依赖 | ✅ |
| FR-5 门禁与非法调用防护 | §1.3 步骤 2 前置态守卫 + `fail(ILLEGAL_LEDGER_STATE,...)`；缺参/CR 不存在/workspace 失败均硬失败 | ✅ |
| FR-6 skill 文档同步 | implement-code / merge-feature-branch / cr-archive 三 SKILL.md 改调子命令 + 明文禁手写（文档改动，随 TASK 落地） | ✅ |
| FR-7 AC-9 演练入库 | §7.2 固化为 crctl.test.mjs node:test 用例 | ✅ |

## 7. 安全与性能考量

### 7.1 边界与正确性

- **行尾纪律（纪律 #1）**：所有 edit 纯函数读入先 `replaceAll('\r\n','\n')`；块锚定/字段定位正则**匹配不到一律 fail**，禁止静默返回原文（直接对标 T04"匹配不到→空数组→静默丢数据"）。
- **幂等**：merge-metadata 同 sha、task done 已 done、archive-move 已在 history —— 均检测并给确定性结果（幂等 ok 或专用错误码），不产生重复/破坏写。
- **前置态守卫**引用状态机唯一事实源判断合法态（`../tools/dir-graph.yaml`），本 CR **不复刻**状态机声明（禁止事项）。
- **审计完整性**：每次账本写入前后摘要落 `audit.log`，可追溯 actor/时间/字段变更。

### 7.2 测试设计（含 AC-9 入库，FR-7）

新增 `skills/shared/crctl/scripts/test/crctl.test.mjs` 用例（node:test，无框架，临时目录 fixture）：

| 用例 | 覆盖 AC | 断言 |
|---|---|---|
| task-done 正常/不存在/已done | AC-1 | status=done+done-at；后两者非零退出且文件无变更 |
| task-done 非法前置态 | AC-5 | fail(ILLEGAL_LEDGER_STATE)，无写 |
| merge-metadata 追加/去重 | AC-2 | merge-commits[] 含 {repo,trunk,sha}；重复 sha 不新增 |
| archive-move 正常 | AC-3 | 条目从 backlog 消失、history 出现带 final-status |
| archive-move history 侧 CAS 冲突 | AC-3 | CAS_CONFLICT 且**两文件均无变更** |
| archive-move 非法前置态 | AC-5 | fail，无写 |
| **AC-9 merge-tree 零冲突**（固化 `_scratch/patch-task10b.mjs` 演练） | AC-7 | 共同祖先注册→分支推 ≥3 次 cr.md→master 注册新 CR→`git merge-tree --write-tree` 对 `_backlog.yml` 冲突数=0、exit 0 |

回归：既有套件（基线 32 用例，CR-018 定型）保持全绿（AC-8）。

### 7.3 性能

账本文件均为 KB 级、条目数十量级；全量读+正则改写+写回单次 <10ms，无性能约束。casWriteMulti 仅两文件，rename 为文件系统元数据操作，可忽略。
