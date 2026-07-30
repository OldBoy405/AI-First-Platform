# AGENTS.md — AI First Platform 工作区行为约束

本仓库是 AI First 研发协同平台的设计文档与知识库工作区，通过 sibling 目录 `../tools/`（`multica-ai` 生态之外的独立方法论包：9 Agent / 59 Skill / 8 Pipeline + `crctl` 状态机 CLI）驱动 CR（Change Request）全流程。

**读取顺序（所有 AI Agent 必须遵守）：**

```text
1. AGENTS.md（本文件）
2. dir-graph.yaml（本仓库的目录图与 repositories 声明）
3. ../tools/AGENTS.md + ../tools/agent-skill-matrix.yml（方法论包的行为约束与权限矩阵）
4. ../tools/README.md（完整使用流程、流程图、节点说明）
```

## tools 包的挂载方式

`../tools/` 是 sibling 目录，**不是**挂载在本仓库 `tools/` 子目录下——本仓库确实存在一个同名空壳 `tools/`，那是早前 Windows 文件锁导致删不掉的残留（已 `.gitignore`），与 sibling 的 `../tools/` 无关，不要混淆。

`crctl` 调用方式：

```bash
node ../tools/skills/shared/crctl/scripts/crctl.mjs status --workspace .
node ../tools/skills/shared/crctl/scripts/crctl.mjs advance <CR-ID> --to <status> --trigger <skill>
node ../tools/skills/shared/crctl/scripts/crctl.mjs approve <CR-ID> --stage <stage>   # 仅人类在终端运行
```

## 单一事实源

| 事项 | 权威文件 |
|---|---|
| 本仓库目录图与 repositories | `dir-graph.yaml` |
| CR 状态机与门禁 | `../tools/dir-graph.yaml#change-request-track.state_machine`、`../tools/skills/shared/crctl/gates.json`（本仓库不复刻副本，crctl 未在本地找到声明时自动回退到这两处） |
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
