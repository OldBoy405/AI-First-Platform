# writeback 流水线耗时分析与优化方案

> 平台级治理文档：基于 CR-2026-019 实测的 writeback 流水线耗时拆解与优化提案。
> 关联：`docs/analysis/CR-2026-012-合并回写归档复盘.md`（问题源起）、CR-2026-019（账本操作收敛，本方案是其自然延伸）。

---

## 1. 背景

CR-2026-019（YAML 账本操作收敛为 crctl 子命令）走完整 writeback 流水线，实测耗时 **约 30 分钟**。其中 merge/archive 的 git 操作本身快速，大量时间消耗在**会话内现写回写脚本与调试**上。这与此前 CR-2026-012 复盘沉淀的纪律 #7（YAML 账本操作禁止会话内现写脚本）同源：账本已收敛为 crctl 子命令，但 specs/delivery 回写的机械步骤仍靠每次现写。

## 2. 时间线实测（CR-2026-019，2026-08-04）

| 阶段 | 耗时 | 组成拆解 |
|---|---|---|
| ① merge-feature-branch | ~7 min | 参与仓调研 ~3 min（dir-graph.yaml 仅声明 docs+multica，tools 仓需对照 CR-2026-018 先例确认参与、trunk=custom/main；multica 空分支判定）+ 执行 ~4 min（push×2、merge-tree 预检、本地合并、push trunk、advance + merge-metadata） |
| ② writeback-prd-sdd | ~8 min | **写回写脚本 ~5 min + 调试修复 ~2 min**（brief 锚点措辞与实际不符 → 改脚本重跑；脚本非幂等首跑成功重跑失败 → 写补丁脚本）+ 备份/执行/验证 ~1 min |
| ③ writeback-tasks | ~4 min | **写脚本 ~2.5 min + 调试 ~1.5 min**（编辑器把 `\n` 字面转成真实换行 → 改 String.fromCharCode 构造重跑） |
| ④ writeback-traceability | ~4 min | **写脚本 ~3 min + 调试 ~1 min**（target-version 锚点在顶层与 CR-2026-018 条目重复出现 2 次 → 改行首锚定） |
| ⑤ cr-archive + cleanup | ~6 min | 执行 ~3.5 min（gate 预检、advance、archive-move 自举、账本提交推送）+ **sandbox 权限拒绝 git worktree 命令 → Remove-Item 兜底重试 ~2.5 min** |

**关键观察**：纯执行（git 操作、advance、子命令调用、提交推送）约 10 min；**"造工具"与"调试工具"约 20 min**，占三分之二。

## 3. 根因分析

### 3.1 每个节点现场写一次性脚本（最大头，约 15 min）

writeback-prd-sdd / writeback-tasks / writeback-traceability 三个节点的机械操作全部靠会话内现写脚本完成：

- PRD/SDD 增量回写：frontmatter 更新（cr-ref/cr-history/target-version/version/fr-list）、回写历史表追加、里程碑节构造（原文 H 下沉一级）
- tasks 回写：文件拷贝 + frontmatter 补 spec-id/version + 全局索引追加
- traceability 回写：顶层字段更新 + milestone 条目追加

SKILL.md 只提供**描述性步骤**，精确文件结构、锚点、格式每次都要现场勘察与试错。

### 3.2 脚本脆弱性导致调试循环（约 5-6 min）

三个脚本各踩一次坑，均为"跑 → 报错 → 改 → 重跑"循环：

| 坑 | 表现 | 代价 |
|---|---|---|
| 锚点语义措辞不匹配 | brief 实际文本与脚本断言不一致 | 改脚本重跑 1 次 |
| 锚点命中多次 | target-version 在顶层与 milestone 条目重复 | 改行首锚定 1 次 |
| 编辑器转义 | `\n` 字面被转成真实换行 | 改 String.fromCharCode 1 次 |
| 脚本非幂等 | 首跑成功后重跑失败 | 另写补丁脚本 1 次 |

### 3.3 现场调研重复（约 4-5 min）

每个节点都要读 SKILL、勘察基线结构（里程碑命名、_index 格式、frontmatter 字段）、对照先例（CR-2026-018 回写形态）。这些事实在 SKILL 里没有"已核实基线"段，每次现查。

### 3.4 环境与验证开销（约 4.5 min）

- sandbox 权限拒绝 git worktree 清理命令，走 Remove-Item 兜底（~2.5 min，一次性环境因素）
- 每个回写单独写 verify 脚本，且断言文本自身写错过 2 次（~2 min）

## 4. 优化方案

### 4.1 P0 — 回写机械步骤固化为入库脚本（预计省 12-15 min）

把三个节点的机械步骤沉淀为 `tools/skills/shared/scripts/` 下的版本化脚本（或扩展为 crctl 子命令），SKILL.md 改为"调用脚本 + 核对输出"：

| 脚本 | 职责 | 对应 SKILL |
|---|---|---|
| `writeback-prd-sdd.mjs` | PRD/SDD 增量回写：frontmatter 更新、历史表追加、里程碑节构造（H 下沉）、备份 + metadata.yml、_index.yml 维护 | writeback-prd-sdd |
| `writeback-tasks.mjs` | 任务文件拷贝 + frontmatter 补 spec-id/version + delivery/task/_index.yaml 追加（按 id 判重幂等） | writeback-tasks |
| `writeback-traceability.mjs` | specs traceability.yml 顶层更新 + milestone 条目追加 | writeback-traceability |

**本质上是 CR-2026-019 精神的延续**：账本操作已收敛为 crctl 子命令，specs/delivery 回写是同一类"机械 + 易错"操作，应收敛为同一通道。适合作为下一个治理工具链 CR（CR-2026-020）的立项题材。

### 4.2 P1 — 脚本设计三原则（消除调试循环，预计省 5 min）

1. **幂等**：已应用（如 cr-history 已含本 CR、索引已登记任务 id）则跳过并输出 noop，杜绝"首跑成功、重跑失败"的补丁脚本。
2. **结构锚点**：优先锚定 frontmatter 字段名 + 行首/缩进（如顶层 `^target-version:` 行、`cr-history: [` 数组尾），避免语义措辞匹配；锚点唯一性断言失败即硬失败（纪律 #1）。
3. **自带验证**：脚本 dry-run 模式（打印将产生的 diff 不落盘）+ 末尾自检断言（回写后 grep 关键字段），不再单独写 verify 脚本。

### 4.3 P1 — 调研一次化（预计省 3-4 min）

流水线启动时一次性读取全部 SKILL 与基线结构，各节点共享。更彻底：把已核实事实写进 SKILL 的"事实基线"段（参照 SDD §0 先例）：

- 里程碑命名惯例：`## {标题}（v{version} · CR-{id}）`，节内 H 下沉一级
- specs/_index.yml 字段约束（features/name/since/updated，SKILL 已含）
- delivery/task/_index.yaml 条目格式
- 参与仓规则（见 4.4）

### 4.4 P2 — merge-feature-branch 参与仓规则明确化（预计省 3 min）

在 SKILL 中固化以下事实，免去每次对照先例推断：

- tools 仓（`phase0-tools`，dir-graph.yaml 自声明）参与合并，trunk=**custom/main**（非 main）
- 无提交的分支（如 CR 无该仓代码改动时 multica 空分支）自动跳过合并与 merge-commits 记录
- 合并前需补齐 `origin/requirement/{cr_id}`（开发期未 push 时）

### 4.5 P2 — 环境兜底预案（预计省 2 min）

worktree 清理的 sandbox 权限问题属环境因素，保留既有兜底链即可：`git worktree remove --force` → `Remove-Item -Recurse -Force` → `git worktree prune`（三步缺一不可，见 docs/Windows-已知问题清单.md）。

## 5. 预期收益

| 项 | 现状（CR-2026-019 实测） | 优化后（估算） |
|---|---|---|
| writeback 总耗时 | ~30 min | **~10-12 min** |
| 其中"造工具/调试" | ~20 min | ~2-3 min（仅调用与核对输出） |
| 脚本调试循环 | 3 次（每次 1-2 min） | 0（幂等 + 结构锚点 + 自带验证） |
| 现场调研 | 每节点重复 | 启动一次 + SKILL 事实基线 |

merge/archive 的 git 操作 ~8 min 为流程刚性成本（fetch/merge/push 网络往返），优化空间有限。

## 6. 与既有纪律的关系

- **纪律 #7**（YAML 账本类操作禁止会话内现写脚本）：本方案将其适用范围从"账本"扩展为"specs/delivery 回写"，入库脚本版本化、可测试、可复用。
- **纪律 #1**（行尾纪律 + 硬失败）：入库脚本继续遵守 CRLF 归一、锚点唯一性断言、匹配不到硬失败。
- **CR-2026-019 精神**：单一写入通道（CAS + 审计）从账本扩展到回写产物；回写脚本若收敛为 crctl 子命令，可复用 casWriteMulti 与审计基础设施。

## 7. 落地建议

1. 以本方案为 PRD 素材立项下一个治理工具链 CR（建议编号 CR-2026-020，前置 CR-2026-019 已归档定型）。
2. 范围建议：三脚本入库 + 三份 SKILL.md 改调 + 幂等/自检 + 事实基线段补充；不含状态机与账本结构改动。
3. 验收指标：下一个走完整 writeback 的 CR，流水线耗时 ≤15 min，回写环节零脚本调试循环（基线：CR-2026-019 三次调试循环 + 30 min）。
