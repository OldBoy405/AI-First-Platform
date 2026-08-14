# CR-2026-020 writeback 流水线复盘

> 对象：CR-2026-020（治理工具链 — writeback 机械步骤固化为入库脚本）的 writeback 阶段（feature-writeback pipeline 全链）
> 范围：approve-code → merge-feature-branch → writeback-prd-sdd → writeback-tasks → writeback-traceability → cr-archive → cleanup
> 复盘日期：2026-08-05
> 结论先行：总耗时约 **16.5 min**（01:22:39 → 01:38:59），其中失败返工约 **8-9 min（占一半）**。回写三节点脚本调试循环 **0 次**（脚本一次跑通）；返工分三类：参数遗漏（缺 --spec-id，同坑两次）、子命令顺序颠倒（两次）、**真实缺陷 1 个**（merge-commits 字段假设与 merge-metadata 实际输出不符，自举发现并修复）。流水线框架健康，剩余摩擦集中在参数/顺序类流程返工，可在工具层根治。

---

## 一、事件经过（2026-08-05，git 提交时间戳）

| 时间 | 步骤 | 结果 | 提交 |
|---|---|---|---|
| 01:22:39 | 人工 approve-code（OldBoy405） | ✅ | approval.yml code 段 |
| ~01:24 | merge-feature-branch：docs + tools 两仓合并、merge-metadata | ✅（一次顺序纠正：先 advance merging 再 metadata） | ae7581f / 518a45c / 7e36b60 |
| 01:29:32 | writeback-prd-sdd（脚本自举）→ writing-back | ✅（一次 GATE_BLOCKED：缺 --spec-id） | da8371e |
| 01:30:17 | writeback-tasks（脚本自举） | ✅ 一次通过 | fc06202 |
| 01:34:56 | **真实缺陷修复**：merge-commits 必填字段收敛 {repo,trunk,sha} | ✅ tools 仓 | ee177a5 |
| 01:35:46 | writeback-traceability（脚本自举）→ T1.2 段 | ✅（修复后重跑通过） | 7690c4f |
| 01:37:17 | cr-archive：advance archived + archive-move | ✅（一次 GATE_BLOCKED：缺 --spec-id，同坑第二次；一次顺序纠正：先 advance 再 archive-move） | 3babdab |
| 01:38:59 | cleanup：worktree/分支清理 + cleanup-report | ✅（multica 远端分支 SSL 失败记 pending） | c3fb3b1 |

**失败步骤清单**：

| # | 步骤 | 失败表现 | 返工代价 | 类别 |
|---|---|---|---|---|
| 1 | advance → writing-back | `GATE_BLOCKED`：缺 `--spec-id`（specs 落点门禁无法校验） | ~1 min | 参数遗漏 |
| 2 | advance → archived | `GATE_BLOCKED`：同样缺 `--spec-id`，**同坑第二次** | ~1 min | 参数遗漏（重复） |
| 3 | merge-metadata | `ILLEGAL_LEDGER_STATE`：要求 merging/writing-back，当前 code-approved | ~1 min | 顺序错误 |
| 4 | archive-move | `ILLEGAL_LEDGER_STATE`：要求 archived，当前 writing-back | <1 min | 顺序错误（#3 同类） |
| 5 | writeback-traceability | `MERGE_COMMITS_MISSING`：脚本要求六字段，merge-metadata 实际只写三字段 | ~6 min（修脚本+测试+推送+重跑） | **真实缺陷** |
| 6 | multica 远端分支清理 | SSL 证书错误（环境因素） | 记 pending | 环境 |

---

## 二、根因分析

### 2.1 参数遗漏类：--spec-id 同坑两次（工具层提示不足 + 文档纪律防不住）

`advance` 目标为 writing-back / archived 时门禁需校验 specs 落点，必须带 `--spec-id`。AGENTS.md 纪律 #5 已明文记载（"回写期 --to writing-back 还需带 --spec-id"），但：

- crctl 的 `GATE_BLOCKED` 首屏只显示 checks 摘要，缺参原因埋在 `why` 字段，第一次执行未看全；
- 文档纪律依赖 Agent 每次检索，**同坑犯两次证明"文档防不住，需要工具层 fail-fast"**——参数缺失应在命令入口即报，而不是等到门禁检查。

### 2.2 顺序颠倒类：子命令状态前置 vs 执行直觉（SKILL 顺序依赖未显式标注）

- `merge-metadata` 要求状态 merging/writing-back（先 advance 后写入）；
- `archive-move` 要求状态 archived（先 advance 后移动）。

crctl 的状态前置校验本身明确（`expect` 列表），错误可一次纠正、代价低；但 SKILL 步骤为描述性顺序，执行者直觉"先准备数据后推进状态"与 crctl 强制顺序冲突——**顺序依赖应显式标注（"必须先 advance"），不靠执行者读状态机**。

### 2.3 事实基线类（代价最高）：SDD 六字段假设未核实 merge-metadata 实际输出

- SDD §0 事实基线写"merge-commits[] 六字段（repo/trunk/sha/branch/source-sha/merged-at）"，依据是早期 CR（007/008）手工写入形态；
- CR-2026-019 交付的 `merge-metadata` 子命令实际只写最小字段集 {repo,trunk,sha}（`crctl.mjs` 的 `editMergeMetadata` 注释明示）——**写 SDD 时该子命令已存在，读源码注释即可核实，纪律 #4（事实断言先核实）执行不到位**；
- 测试 fixture 按六字段自造——**评审 CODE-BLOCK-001 的元教训（"自造 fixture 掩盖真实数据形态"）只应用到了 tasks 索引场景，未推广到 merge-commits 场景**，元教训推广不彻底。

### 2.4 环境类：multica 远端 SSL（已知问题，非流程失败）

SSL 证书错误属既有环境问题（Windows-已知问题清单已记录）；cleanup-report.yml 记 `pending` 并注明"空分支无内容影响"是正确姿势。

---

## 三、影响与代价

- 失败返工约 8-9 min，占 16.5 min 总耗时的一半；其中 #1-#4（参数/顺序类）约 3 min 本可避免，#5（真实缺陷）约 6 min 属自举发现价值。
- 对照方案 §7 验收指标（≤15 min / 零脚本调试循环）：**脚本调试循环 0 次达成**；总耗时 16.5 min 略超——超时全部来自流程返工而非脚本调试。
- 正向收益：自举发现并修复了"SDD 事实基线错误 + fixture 掩盖真实形态"的复合缺陷（ee177a5），并固化为三字段回归用例——这是"用自己交付的工具跑真实数据"（AC-10）的核心价值，后续 CR 不再发生同类问题。

---

## 四、改善方案（分层）

### 4.1 工具层（crctl，可立项）

| # | 改进 | 预期收益 |
|---|---|---|
| T1 | `advance` 目标为 writing-back/archived 时缺 `--spec-id` 直接 `BAD_ARGS` fail-fast（命令入口校验，不等到门禁检查） | 消除 #1/#2（~2 min）；"参数即校验" |
| T2 | `GATE_BLOCKED` 输出把"缺参/补参"类 `why` 提升为错误摘要首行 | 与 T1 互补，覆盖其他缺参场景 |

### 4.2 文档层（SKILL / 纪律）

| # | 改进 | 预期收益 |
|---|---|---|
| T3 | merge-feature-branch SKILL 显式标注：Step 5 "必须先 advance 到 merging，再 merge-metadata（crctl 状态前置强制）" | 消除 #3 |
| T4 | cr-archive SKILL 显式标注：先 advance archived（带 --spec-id）再 archive-move | 消除 #4 |
| T5 | 纪律 #4 强化：SDD 事实基线中"已有工具/命令的输出形态"类条目必须列**核实命令**并实际执行（本案例核实命令 = `grep editMergeMetadata crctl.mjs`） | 防 #5 类事实错误 |

### 4.3 测试层

| # | 改进 | 预期收益 |
|---|---|---|
| T6 | fixture 黄金样例：真实 `_backlog.yml` 三字段 merge-commits 片段已固化进回归用例（ee177a5 已实现），后续 fixture 一律从真实文件采样构造 | 防 #5 重演 |
| T7 | 评审元教训沉淀为测试编写规范："自造 fixture 必须按真实文件实测形态构造"（CODE-BLOCK-001 与 #5 的共同教训） | 全局测试质量 |

### 4.4 行为层

| # | 改进 | 预期收益 |
|---|---|---|
| T8 | 每次 crctl 子命令前先 `crctl status` 看 `legalNext` / `gateBlockers`（本次查过但未形成每次前置习惯） | 行为兜底 |
| T9 | "同坑两次"信号：第一次 GATE_BLOCKED 后即把 `--spec-id` 模板化进后续命令 | 防重复 |

---

## 五、沉淀纪律（建议 AGENTS.md #10 文案）

> **10. crctl 状态前置与参数模板化**：回写期 advance（writing-back/archived）必带 `--spec-id`；merge-metadata 必须先 advance 到 merging、archive-move 必须先 advance 到 archived（crctl 状态前置强制，SKILL 显式标注，不靠执行者读状态机）。任何涉及"已有工具输出形态"的文档断言（纪律 #4），必须用命令/源码核实并列出核实命令（先例：CR-2026-020 SDD 六字段假设与 merge-metadata 三字段实际输出不符，自举时以 ~6 min 返工发现）。

---

## 六、后续动作清单（可作治理 CR 立项素材）

1. 将 T1/T2（crctl fail-fast）与 T3/T4（SKILL 顺序标注）整理为治理工具链 CR（可挂 CR-2026-021 或并入漂移治理 CR），验收指标：同一 CR 回写期参数/顺序类返工为 0。
2. T5 的"核实命令"列可作为 SDD 模板的强制字段（engineering-docs SDD 模板补一列）。
3. 本次 6 个失败场景（2 参数 + 2 顺序 + 1 事实 + 1 环境）可作为 crctl 错误提示质量的回归用例素材。
