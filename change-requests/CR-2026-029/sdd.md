# SDD — 发布联调移交 merge pipeline 完成证据

- **版本**：v0.1.0
- **cr-ref**：CR-2026-029
- **状态**：tech-designing

## 1. 架构概览

### 1.1 模块边界

本 CR 修改两处 active executable surface（tools 仓）与一处知识库迁移（knowledge-base 仓）：

| 模块 | 文件 | 变更 |
|---|---|---|
| merge 编排 | `skills/writeback/merge-feature-branch/SKILL.md` | 新增"发布联调走查"步骤 + 发布类任务约定 |
| pipeline 模板 | `pipeline-templates/feature-writeback.pipeline.json` | merge-feature-branch 节点 prompt 同步 |
| 迁移对象 | knowledge-base `change-requests/CR-2026-028/`（tasks/_index.yml、TASK-10.md、sdd.md 变更记录） | 移除 TASK-10 |

不新增 crctl 子命令、不改 `task done` 前置态、不改归档门禁判定（PRD 范围排除）。

### 1.2 关键流程（改动后 merge-feature-branch 完整步骤）

```text
Step 1  前置校验（code-approved、worktree clean、远端新鲜）
Step 2  全仓预检（fetch + merge-tree --write-tree dry-run）
Step 3  全仓本地 no-commit merge + 逐仓 commit
Step 4  远端新鲜度复核 + 统一 push（补偿路径保留）
Step 5  更新 CR status（advance --to merging --embedded + merge-metadata + metadata commit/push）
Step 6  ★ 发布联调走查（本 CR 新增）：
        a. 各仓 trunk 拉取后，主 checkout 与 linked worktree 分别执行
           crctl status / worktree-path / next，确认无 STATUS_DIVERGED、嵌套路径异常
        b. multica CUSTOM.md 台账核账（grep CR-ID 与实际代码一致）
        c. 走查结果结构化写入 change-requests/{cr}/merge-verification.md，
           提交到 knowledge-base trunk
Step 7  输出摘要
```

### 1.3 依赖方向

merge-feature-branch →（消费）crctl status/worktree-path/next（只读）、merge-metadata（既有）；无新增依赖。迁移 CR-2026-028 不依赖 crctl 新命令（定点账本编辑 + git 提交）。

## 2. 数据与文件契约

### 2.1 merge-verification.md（新增完成证据）

位置：`change-requests/{cr}/merge-verification.md`（knowledge-base 仓，提交到 trunk）。

frontmatter：

```yaml
---
cr: CR-YYYY-NNN
verified-at: "ISO-8601"
verified-by: {identity}
repos:
  - repo: tools
    trunk: custom/main
    merge-sha: {sha8}
  - repo: multica
    trunk: main
    merge-sha: {sha8}
  - repo: ai-first-platform-docs
    trunk: master
    merge-sha: {sha8}
---
```

正文（`<!-- crctl:analysis-below -->` 以下模型补充）：

- 走查命令与结论：主 checkout `status`、linked worktree `status/next`、三仓 `worktree-path`（确认无 STATUS_DIVERGED/嵌套路径）；
- multica CUSTOM.md 台账核账结论；
- 异常与处理（若走查发现异常，按对应纪律回写：SDD 修订走 review-tech-design；不得手改评审记录）。

### 2.2 发布类任务约定

merge-feature-branch SKILL.md 明示："发布联调、merge 验证类工作归 merge pipeline（本 Skill 联调走查步骤），不创建开发 TASK；开发期 `task allocate` 不产生发布/联调类任务。"

## 3. 接口契约

### 3.1 merge-feature-branch skill 步骤变更

- 现有 Step 5 不变（advance --embedded + merge-metadata + metadata commit/push 同批发布）。
- 新增 Step 6（见 §1.2），随后原"输出摘要"顺延为 Step 7。
- Step 6 命令全部为既有只读 crctl 命令 + `git add/commit/push`（受控 shell），无新命令面。

### 3.2 pipeline prompt 同步

feature-writeback.pipeline.json 中 merge-feature-branch 节点 prompt 增加：

```text
在状态推进与 merge-metadata 发布后执行发布联调走查：
1. 主 checkout 与 linked worktree 分别验证 crctl status / worktree-path / next（无 STATUS_DIVERGED、无嵌套路径）；
2. multica CUSTOM.md 台账核账；
3. 把走查结论写入 change-requests/{cr}/merge-verification.md 并提交 knowledge-base trunk。
```

### 3.3 迁移 CR-2026-028

实施阶段在 knowledge-base 仓执行（CR-2026-029 分支内，随 CR-2026-029 merge 带至 trunk）：

1. 从 `change-requests/CR-2026-028/tasks/_index.yml` 移除 `CR-2026-028-TASK-10` 条目（定点块删除，保留其余 9 个任务块原样）；
2. 删除 `change-requests/CR-2026-028/tasks/TASK-10.md`；
3. `change-requests/CR-2026-028/sdd.md` 变更记录追加：发布联调移交 merge pipeline（CR-2026-029）——删除的 TASK-10 不再作为 CR-2026-028 交付物；
4. CR-2026-028 test-report.md 的 TASK 覆盖矩阵同步（TASK-10 移除说明）。

> 定点编辑采用与既有 migrate-backlog 一致的 CRLF 容错文本处理（读入后 `\r\n → \n` 归一，编辑后整体落盘；跨行解析失败必须硬失败，禁止静默降级——纪律 #1）。

## 4. 关键算法与流程

### 4.1 迁移定点编辑

```text
read tasks/_index.yml（CRLF 归一）
删除包含 TASK-10 的条目块：
  - 锚定 `  - id: CR-2026-028-TASK-10` 起始行
  - 块结束 = 下一个 `  - id:` 起始行 或 文件尾
  - 删除后校验：TASK-10 不再出现、其余 id 集合不变（TASK-01..09）
写回（CAS 复核 sha256）
```

### 4.2 联调走查判定

- `status`：主 checkout 出现 `STATUS_DIVERGED` 属预期（worktree 分支与 trunk 快照分离），不视为异常；**linked worktree 本身**不得有 STATUS_DIVERGED；
- `worktree-path`：三仓路径以主 checkout 为根，`path` 不含 `.rayai-worktrees/.rayai-worktrees` 嵌套；
- `next`：返回结构正常即可（写回期以 `crctl next` 为准，不手写映射）。

## 5. 技术选型与替代方案

| 决策 | 采用 | 否决 | 理由 |
|---|---|---|---|
| 发布联调归属 | merge pipeline 完成证据（merge-verification.md） | 把 `merging` 加入 `task done` LEGAL | 放宽账本语义、掩盖"发布类任务不落开发 TASK"的根因 |
| 证据强制 | skill/pipeline 步骤 + 提交证据，不加门禁 | merging→writing-back 门禁加 fileExists 检查 | 本 CR 范围排除改门禁；证据先落盘，强制留待实际需求 |
| 迁移方式 | 定点编辑 + 提交 | crctl 新增删任务命令 | 一次性迁移，不新增命令面 |

## 6. FR 到技术实现映射

| FR | 实现 |
|---|---|
| FR-1 merge pipeline 联调走查 | merge-feature-branch SKILL.md Step 6 + merge-verification.md 契约 |
| FR-2 pipeline prompt 同步 | feature-writeback.pipeline.json merge-feature-branch 节点 prompt |
| FR-3 发布类任务约定 | SKILL.md 约定段 + write-dev-tasks 无发布类拆分确认 |
| FR-4 迁移 CR-2026-028 TASK-10 | §3.3 定点编辑 + 变更记录 |
| FR-5 验证 | 新增 skill/pipeline 文本静态断言（无 crctl 门禁改动）；既有 158+9 测试回归 |

## 7. 安全与性能考量

- 迁移删除 TASK-10 只影响任务索引与单个任务文件，不触碰 CR-2026-028 的审批/评审证据（approval.yml、review-annotations、traceability）与已 merge 代码；
- 走查全部使用只读 crctl 命令，无副作用；
- merge-verification.md 只含合并事实与走查结论，不含敏感路径（示例相对路径）。

## 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-10 | v0.1.0 | Ray | 初稿 |
