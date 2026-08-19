# AGENTS.md — AI First Platform 工作区行为约束

本仓库是 AI First 研发协同平台的设计文档与知识库工作区，通过 sibling 目录 `../tools/`（`multica-ai` 生态之外的独立方法论包：9 Agent / 56 Skill / 8 Pipeline + `crctl` 状态机 CLI；计数口径与旁证见 `docs/references/tools.md`）驱动 CR（Change Request）全流程。

**读取顺序（所有 AI Agent 必须遵守）：**

```text
1. AGENTS.md（本文件）
2. dir-graph.yaml（本仓库的目录图与 repositories 声明）
3. ../tools/AGENTS.md + ../tools/agent-skill-matrix.yml（方法论包的行为约束与权限矩阵）
4. ../tools/README.md（完整使用流程、流程图、节点说明）
```

## tools 包的挂载方式

`../tools/` 是 sibling 目录，**不是**挂载在本仓库 `tools/` 子目录下——本仓库确实存在一个同名空壳 `tools/`，那是早前 Windows 文件锁导致删不掉的残留（已 `.gitignore`），与 sibling 的 `../tools/` 无关，不要混淆。

`crctl` 调用方式（Tools Root = `workspace.tools_package_path` 指向的 tools 包，Agent 运行时解析；本工作区当前为 `../tools/`）：

```bash
node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs status --workspace .
node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs advance <CR-ID> --to <status> --trigger <skill>
node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs approve <CR-ID> --stage <stage>   # 仅人类在终端运行
```

## 单一事实源

| 事项 | 权威文件 |
|---|---|
| 本仓库目录图与 repositories | `dir-graph.yaml` |
| CR 状态机与门禁 | `{TOOLS_ROOT}/dir-graph.yaml#change-request-track.state_machine`、`{TOOLS_ROOT}/skills/shared/crctl/gates.json`（本仓库不复刻副本；Tools Root 由 `dir-graph.yaml#workspace.tools_package_path` 唯一解析，无回退，CR-2026-028） |
| 完整使用流程 | `../tools/README.md` |
| Agent/Skill 权限矩阵 | `../tools/agent-skill-matrix.yml` |

## 工作区布局

```text
AI First Platform/
  AGENTS.md                 # 本文件
  dir-graph.yaml             # 本仓库目录图 + repositories 声明
  change-requests/           # 在途 CR 工作台（_backlog.yml + {CR-ID}/）
  specs/                     # CR 回写后的 baseline 产物（当前为空，见下）
  delivery/                  # CR 回写后的交付任务索引（当前为空，见下）
  docs/
    product/                 # 平台级设计文档（P0-P3、Wiki 子系统设计等），跨 CR，不进 specs/
    analysis/                # 架构评审、方案对比等分析文档
    references/               # sibling 仓库（multica/openwiki/tools）的 commit SHA 指针，不 vendor 全量 clone
```

**`specs/`、`delivery/` 为什么现在是空的**：`docs/product/`、`docs/analysis/` 里的既有设计文档是跨 CR 的平台级资产，不是某一个 CR 的交付物，不强行套 `specs/{id}/PRD.md+SDD.md` 模型。`specs/`、`delivery/` 只承接未来真正通过 CR 流程（`requirement-authoring` → `architecture-design` → `code-implementation` → `feature-writeback`）跑完并 writeback 的产物。

## CR 状态推进规则

- 状态推进只能通过 `crctl advance`（或对应 Skill 级联调用），禁止手改 `change-requests/_backlog.yml` 或 `change-requests/{CR-ID}/cr.md` 的 status 字段。
- 人工审批节点（需求/架构/开发启动/代码）只能通过 `crctl approve`（仅限交互式终端，非 TTY 调用一律拒绝，无旁路）。
- 创建新 CR 不是 crctl 的子命令，而是 `requirement-authoring` pipeline 的 `requirement-register` 节点（`../tools/skills/requirement/requirement-register/SKILL.md`），由 Agent 按 Skill 提示词执行，写 `cr.md` + `_backlog.yml` 条目并按 `dir-graph.yaml#repositories` 派生 worktree。

## 禁止事项

- 禁止跳过 `review-*` 与 `approve-*` 直接把 CR 推进到后续状态。
- 禁止在本仓库 `dir-graph.yaml` 里复制一份状态机或 gates 声明（唯一事实源在 `../tools/`）。
- 禁止把 `docs/product/`、`docs/analysis/` 下的既有设计文档强行搬进 `specs/`。

## 工程纪律（实战教训固化，违反必返工）

1. **行尾纪律（已三次咬人：M0 证据哈希误报 → T03 canonical digest → T04 生成器静默丢 wildcard 转移）**：任何对仓库文件做哈希、跨行正则、逐行解析的代码，读入后必须先 `\r\n → \n` 规范化（Windows autocrlf 会改写检出内容）；解析器用 `split(/\r?\n/)`；**跨行正则解析失败必须硬失败报错，禁止静默降级**——T04 的 bug 正是"匹配不到 → 空数组 → 静默丢数据"。
2. **状态数口径**：状态机 = **15 个具名状态 + 注册前 `(new)`**（口语“16 态”含 (new)）；转移 = **28 条声明，wildcard 展开后 50 条**（CR-2026-022 新增两条 reject 转换：`approve-requirement:reject -> write-requirement-prd`、`approve-dev-start:reject -> write-dev-plan`；CR-2026-026 再新增两条开发计划评审转换：`review-dev-plan:block -> write-dev-plan`、`review-dev-plan:upstream-design-blocker`；CR-2026-031 再新增一条发布漂移回退转换：`code-approved -> developing`，trigger=`merge-feature-branch:release-drift -> implement-code`）。写文档/断言/DDL 注释时必须写明用的是哪个口径，正式断言以 `../tools/dir-graph.yaml#change-request-track.state_machine` 当前内容为准（CR-2026-027 Phase 0 统一）。
3. **multica 仓代码注释一律英文**（其 CLAUDE.md 硬规则）；本仓库与 tools 仓的文档、CR 产物用中文。进 multica 写代码前先读其 CLAUDE.md。
4. **事实断言先核实**：写进 PRD/SDD 的"某仓库有/没有某包、某行为"类断言，落笔前用命令核实（ls/grep），实施期发现不符须以 revision 修订并注明"结论是否受影响"（先例：SDD 0.1.2 更正 internal/service 论据）。

5. **状态推进一律走 crctl，禁止手改 `_backlog.yml`/`cr.md` 的 status**（CR-2026-002 merge 期咬过一次）：需要把状态与其他文件放进同一个提交时，用 `crctl advance --to X --trigger Y --expect Z --embedded`——它会跑门禁、发状态事件、把文件留给调用方一起提交。手改的后果是**门禁没跑 + 投影漂移**（当次靠 reconcile 安全网自愈，但那是兜底不是流程）。回写期 `--to writing-back`（及 `--to archived`）还需带 `--spec-id`，否则 specs 落点门禁无法校验（crctl 现会在缺 `--spec-id` 时于命令入口 `BAD_ARGS` fail-fast，不再把缺参原因埋进门禁检查——CR-2026-020 复盘 FR-4）。
6. **specs/ 基线是累积文档，不是最近一次 CR 的副本**（历史注脚，危害已消除）：CR-2026-002 回写时 `writeback-prd-sdd` Skill 曾字面写 `cp` 覆盖，直接照做用单阶段文档覆掉整个平台基线（v0.10 基线被 cp 成了 CR-2026-001 原文）。**CR-2026-020 起该步骤已脚本化**（`writeback-prd-sdd.mjs`）：按里程碑分节累积（节内保留该 CR 原文、H 级下沉一级）、FR/AC 跨节引用加里程碑前缀（`M0-FR-3`/`P1-AC-5`），且不再产生 `writeback-backups/` 备份目录（git commit 本身即历史与审计，见 CR-2026-020 FR-6）；此条仅作历史背景保留，新会话按脚本行为执行即可，无需再手动核对"是否误 cp"。
7. **YAML 账本类操作禁止会话内现写脚本，一律使用入库的版本化脚本**（CR-2026-012 收尾期咬过一次）：`_backlog.yml`、`traceability.yml`、任务 `_index.yml` 这类账本文件，会话内现写 PowerShell/Python 脚本处理会被转义问题反噬——当次一次坏脚本把 9 个 rebase 冲突块原样提交进历史，事后手工修复。正确做法：账本操作沉淀为入库脚本（如 `../tools/skills/shared/scripts/` 下），版本化、可测试、可复用；会话内只做调用，不现写。
8. **任务完成即时在 `_index.yml` 标记 done，不积压到回写期补标**（CR-2026-012 回写期咬过一次）：8 个任务做完了但 `_index.yml` 全 `pending`，回写期被迫中断流程补账。正确做法：`implement-code` 完成标志里包含"任务状态已登记 done"，做完一个标一个——回写期补账既打断流程又容易漏标。
9. **CR 事实以 worktree 分支为源，主工作区 cr.md 可能是陈旧注册快照**（会话工作区漂移复盘，已三次咬人）：注册后 CR 的全部状态推进都发生在 `.rayai-worktrees/{bucket}/requirement/{CR-ID}` 分支上，主工作区 `cr.md` 的 status 可能长期停在注册值，**禁止据主工作区视图判断在途 CR 进度**。`crctl status` 现会在主工作区视图与该 CR 的 worktree 分支 `cr.md` 不一致时输出 `STATUS_DIVERGED` 告警并指向权威 worktree（工具层强制暴露，不靠会话记忆自觉——CR-2026-020 复盘 FR-2）；承接在途 CR 一律以该告警指向的 worktree 为准。
10. **改 multica 仓代码必登记其 CUSTOM.md 台账**：凡在 multica 仓落代码（新文件、`// AIFIRST:` 挂钩点、迁移、governance 等自研包），必须在 `../multica/CUSTOM.md` 对照**其当时实际结构**登记（编号顺延、原因追溯含 CR 编号与 TASK）。具体表格划分与字段以 CUSTOM.md 现状为唯一事实源，本文件不复刻格式细节——台账结构日后变更无需同步本条目，登记时以彼时 CUSTOM.md 为准。该台账是双周 rebase 前核对 fork 定制的唯一清单（CUSTOM.md 文件头明示），漏记的后果是 rebase 时定制无法逐条核对、`// AIFIRST:` 标记可能静默丢失。
