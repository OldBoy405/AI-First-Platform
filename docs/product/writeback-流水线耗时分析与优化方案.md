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

### 4.1 P0 — 回写机械步骤固化为入库脚本

把三个节点的机械步骤沉淀为 `tools/skills/shared/scripts/` 下的版本化独立脚本，SKILL.md 改为"调用脚本 + 核对 dry-run diff"：

| 脚本 | 职责 | 对应 SKILL |
|---|---|---|
| `writeback-prd-sdd.mjs` | PRD/SDD 增量回写：frontmatter 更新、历史表追加、里程碑节构造（H 下沉）、specs/_index.yml 全量重建 | writeback-prd-sdd |
| `writeback-tasks.mjs` | 任务文件拷贝 + frontmatter 补 spec-id/version + delivery/task/_index.yaml 全量重建 | writeback-tasks |
| `writeback-traceability.mjs` | specs/{spec_id}/traceability.yml 全量重建（唯一权威版本，详见 4.6） | writeback-traceability |

**不做成 crctl 子命令，不接入 casWriteMulti / CAS 审计基础设施。** 账本（`_backlog.yml`）需要 CAS 是因为它承载状态机、有并发写入语义；specs/delivery 回写的对象是 git 仓里的 markdown/yaml 文件，git 本身就是它们的 CAS 和审计——每次回写一个 commit，diff 可查、可 revert。三个脚本作为独立 `.mjs`（可 import crctl.mjs 中现成的 YAML 解析函数，不重复造轮子）即可，无需借用账本的并发控制机制。

这类机械操作沉淀为版本化脚本，是纪律 #7（YAML 账本操作禁止会话内现写脚本）向 specs/delivery 回写场景的自然延伸，适合作为下一个治理工具链 CR（CR-2026-020）的立项题材。

### 4.2 P1 — 根因是"增量补丁"而非"脚本没写好"：能重建就不打补丁

CR-2026-019 踩的四个坑（锚点措辞不符、锚点命中两次、非幂等、编辑器转义）表面看是脚本细节问题，根因其实是**对结构化索引文件采用了增量文本补丁模式**。补丁模式天然需要"找到旧内容的位置再改"，位置判断一旦跟实际文本有偏差就会出错；而 `specs/_index.yml`、`delivery/task/_index.yaml`、`specs/{spec_id}/traceability.yml` 这三类文件的内容可以完全从其他来源（各 spec 目录的 frontmatter、delivery/task 目录扫描、_backlog.yml 的 merge-commits[]）重新推导，不需要"读旧文件 + 找锚点 + 局部改写"。

按文件类型分两类处理，而不是对所有回写文件套同一套"锚点纪律"：

| 文件类型 | 处理方式 | 理由 |
|---|---|---|
| `delivery/task/_index.yaml` | **全量重建**：脚本扫描 delivery 目录、整份重新生成文件 | 天然幂等（重跑结果不变）、没有锚点、不存在"命中两次"，四个坑里三个直接消失 |
| `specs/_index.yml` / `specs/{spec_id}/traceability.yml` | **头部/结构化字段更新 + 追加**：字段行级更新（cr-ref/cr-history/current 等）、本 CR 条目/段末尾追加 | 这两个文件是跨 CR 累积产物（含编辑性字段与手工注释），全量重建会摧毁历史（据 CR-2026-020 SDD §8 D3 核实修正：traceability.yml 曾在 PRD 阶段误判为可全量重建，架构设计阶段核实真实文件形态为 989 行跨 CR 累积后修正） |
| `specs/{spec_id}/PRD.md` / `SDD.md` 的里程碑节追加 | **保留结构锚点纪律**：锚定 frontmatter 字段名 + 行首/缩进，不做语义措辞匹配；锚点唯一性断言失败即硬失败（纪律 #1） | 这是真正的累积性正文，历史里程碑节必须原样保留、无法重建，只能追加 |

对仍需锚点追加的 PRD/SDD 环节，脚本仍应带 dry-run 模式（打印将产生的 diff 不落盘）+ 末尾自检断言，不再单独写 verify 脚本。

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

### 4.5 P2 — 环境兜底预案

worktree 清理的 sandbox 权限问题属环境因素，保留既有兜底链即可：`git worktree remove --force` → `Remove-Item -Recurse -Force` → `git worktree prune`（三步缺一不可，见 docs/Windows-已知问题清单.md）。

### 4.6 P0 — 删掉 writeback-backups 步骤，收敛 traceability.yml 为单一权威文件

流水线现存两处冗余设计，会持续制造维护负担和调试面，借本次入库一并去掉：

**删掉 writeback-backups 步骤。** writeback-prd-sdd 现要求回写前把旧版 `specs/{spec_id}/PRD.md`、`SDD.md` 拷到 `change-requests/{cr_id}/writeback-backups/{spec_id}/{timestamp}/` 并写 `metadata.yml`（记录 SHA、时间戳）。回写本身就是一次 git commit，旧版本已完整存在于 git 历史中（`git log`/`git show`/`git revert` 均可直接取用），手工再拷一份是在 git 之上重复实现 git 自带的能力，只会新增文件操作与出错点，且长期无人查阅。`writeback-prd-sdd.mjs` 不再实现此步骤，SKILL.md Step 2 与 Step 6 输出中的"备份位置"一并删除。

**收敛双份 traceability.yml 为单一权威文件。** 现状 `change-requests/{cr_id}/traceability.yml`（需求期/开发期产出）与 `specs/{spec_id}/traceability.yml`（writeback-traceability 节点生成）两份并存、约定后者权威、pipeline 要求二者"保持一致"——这是标准的"两份数据、一份权威"反模式，一旦有人只改了其中一份就会静默分叉，且没有机制能检测分叉。改为：`change-requests/{cr_id}/traceability.yml` 仅作为该 CR 开发期的工作稿，归档后不再维护、不再要求与 specs 侧同步；`specs/{spec_id}/traceability.yml` 是唯一的、跨 CR 累积的权威文件，由 `writeback-traceability.mjs` 全量重建生成（见 4.2）。writeback-traceability 节点不再需要"与 change-requests 侧一致性校验"这道工序。

## 5. 预期收益

| 项 | 现状（CR-2026-019 实测） | 优化后（预期） |
|---|---|---|
| writeback 总耗时 | ~30 min | 见 §7 验收指标 |
| 其中"造工具/调试" | ~20 min | 仅调用脚本与核对 dry-run 输出 |
| 脚本调试循环 | 3 次 | 0（增量补丁改全量重建后，四个坑中三个不再存在；PRD/SDD 锚点追加仍需锚点纪律兜底） |
| 现场调研 | 每节点重复 | 启动一次 + SKILL 事实基线 |
| 冗余数据维护 | writeback-backups 备份、双份 traceability 各自独立更新 | 两处均去除，无需再维护 |

以上为方向性预期，不作逐项分钟估算（现有数据仅来自 CR-2026-019 单次实测，n=1 不足以支撑精确到分钟的拆分）；实际收益以 §7 验收指标衡量。merge/archive 的 git 操作 ~8 min 为流程刚性成本（fetch/merge/push 网络往返），优化空间有限。

## 6. 与既有纪律的关系

- **纪律 #7**（YAML 账本类操作禁止会话内现写脚本）：本方案将其适用范围从"账本"扩展为"specs/delivery 回写"，入库脚本版本化、可测试、可复用，但作为独立脚本落地，不并入 crctl 子命令体系（见 4.1）。
- **纪律 #1**（行尾纪律 + 硬失败）：入库脚本继续遵守 CRLF 归一、锚点唯一性断言、匹配不到硬失败——仅适用于 PRD/SDD 里程碑追加这一无法重建的环节（见 4.2）。
- **CR-2026-019 精神**：单一写入通道从账本延伸到回写产物，靠的是 git commit 本身的可追溯性 + 全量重建的天然幂等，而非借用账本的 CAS/审计基础设施——两者面对的并发与状态机语义不同，不应共用同一套机制。

## 7. 落地建议

1. 以本方案为 PRD 素材立项下一个治理工具链 CR（建议编号 CR-2026-020，前置 CR-2026-019 已归档定型）。
2. 范围建议：三脚本入库（索引/traceability 类全量重建，PRD/SDD 类锚点追加）+ 三份 SKILL.md 改调 + 事实基线段补充 + 删除 writeback-backups 步骤 + 收敛 traceability.yml 为单一权威文件；不含状态机与账本结构改动，不引入 crctl 子命令或 CAS 机制。
3. 验收指标：下一个走完整 writeback 的 CR，流水线耗时 ≤15 min，回写环节零脚本调试循环（基线：CR-2026-019 三次调试循环 + 30 min）。
