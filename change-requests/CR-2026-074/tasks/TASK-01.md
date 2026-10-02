---
id: CR-2026-074-TASK-01
type: TASK
cr-ref: CR-2026-074
plan-ref: "change-requests/CR-2026-074/plan.md"
sdd-ref: "change-requests/CR-2026-074/sdd.md"
target-version: 0.47
title: kb init 入口/CLI/前置/发布重入
slug: kb-init-entry-preconditions-publish
status: pending
estimate: 6h
depends-on: []
created: 2026-10-01T00:55:00+08:00
---

## 任务描述

实现显式 `crctl kb init` 初始化入口（SDD §1/§3.1/§3.2/§4.1；FR-1～FR-3；AC-01/AC-02/AC-03）。目标：维护者提供 dir-graph 与 Git 主 checkout 后，一条命令创建两本空 CR 账本并完成普通 Git 提交与首次 push，支持 noop/补提交/补推三种重入形态。输入仅 `--workspace <KB 主 checkout>` 与 positional `['init']`。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs` — `main` 接线与私有 `cmdKbInit`；`requireExplicitWorkspace`/`detectWorkspace`/`resolveToolsRoot` 既有行为不变（dep-1）。代码 HELP 追加属 TASK-09，本 TASK 不改 HELP。
- `skills/shared/crctl/scripts/test/crctl.test.mjs` — init 定向用例（happy/noop/前置优先级/失败残留与恢复/普通命令 workspace 守卫），将 dep-16 fixture 局部裁剪为仅 dir-graph、KB 无账本/远端 trunk。

## 实现要点

- 接线（SDD §4.1）：`main` 在 `requireExplicitWorkspace` 后、`detectWorkspace/loadGates` 前，将 cmd=kb 派到私有 `cmdKbInit(path.resolve(flags.workspace), positional, flags)`；其他分支逐字沿用检测/gates，不扩展隐式根。
- 形态校验先行（SDD §3.1）：只接受 positional=`['init']` 与 workspace flag；未知子命令、额外位置参数/flag → BAD_ARGS。先验证 workspace 非空字符串，再验证 kb 形态；help 保持无根可用。
- 前置顺序与错误（SDD §3.2，依 PRD FR-2 固定优先级）：WORKSPACE_REQUIRED → kb 形态 BAD_ARGS → `resolveToolsRoot`/`resolveRepositories` 透传原错误 → repo-invalid（主 checkout/仓根/origin/代码仓远端 trunk 只读核验失败）→ trunk-mismatch（KB symbolic-ref 不等声明 trunk，允许 unborn HEAD）→ dirty（status --porcelain -z 工作树/index 夹带三文件外变更）→ remote-diverged（远端核验失败/有远端无本地 HEAD/远端非 HEAD 祖先）→ KB_INIT_CONFLICT（已有账本规范文本异内容，paths 列冲突相对路径）→ CAS_CONFLICT/INTERNAL_ERROR/TX_GIT_FAILED(stage=add|commit|push)。前置失败不写业务文件/index/commit/远端/audit/CR 状态。
- 流程（SDD §4.1）：`real(ws)==real(ctx.installRoot)==real(KB.rootPath)` → 逐 active repo 核验（show-toplevel 等于 rootPath、非 bare、有 origin；逐 active code repo ls-remote 有声明 trunk）→ dirty 白名单仅 dir-graph 与两账本（rename/copy 检查源与目标，不按空格截断路径）→ 查询 KB remote trunk（成功空结果允许；存在则 fetch 明确 trunk；有 remote 无 HEAD 拒绝；有 HEAD 用 `merge-base --is-ancestor <remoteSHA> <HEAD>`）→ 逐账本比对（只做 CRLF→LF 后与完整模板逐字比较，不 trim、不解析重写；有条目即冲突）→ 全部通过后才 mkdir 账本父目录并 `createFileExclusive` → `git add -- dir-graph.yaml change-requests/_backlog.yml change-requests/_index.yml` → `diff --cached --quiet`：0 跳过 commit、1 `commit -m 'kb init'`、其他 exit 视 Git 失败 → remote 缺失或不含 HEAD 时普通 push `HEAD:refs/heads/<trunk>` → 成功 audit 一行 → ok(result)。
- 两账本模板（SDD §2.1）：`change-requests/_backlog.yml` 内容为 `schema: cr-backlog/v2\nchange-requests:\n`；`change-requests/_index.yml` 内容为 `change-requests:\n`；UTF-8/LF、末尾换行、null 根。初始化不生成 specs/delivery 索引、根 .gitignore、CR/task/outbox、journal/锁/故障点。
- Git 约束：固定 argv、shell=false，导入 dep-3 已导出的 `gitRun`/`gitMust`；不经 `cmdGit`（dep-4），不扩展 controlled-shell 的 commit 白名单；不 force、不 pull/reset；网络失败不得当空远端；账本父目录不得经 symlink/junction 逃逸主 checkout（归 repo-invalid）。
- 重入（SDD §4.1）：两账本正好模板但未提交 → add/commit/push；本地 init 提交未推 → 无新 commit 仅 push；远端已包含 HEAD → noop。远端 HEAD 领先即 remote-diverged，不自动 pull/reset。

## 验收条件

1. 在 tools CR worktree 执行 `node --test skills/shared/crctl/scripts/test/crctl.test.mjs`（证据 cmd-01）全绿，且 init 定向用例覆盖：AC-01（精确模板、提交 tree 只含三候选文件、远端首 trunk、五字段输出、无 CR/task/outbox；二次 changed=false/无新 commit/push）；AC-02（每项前置固定 code/reason，双重错误 fixture 验证最先失败，前置前后业务文件/index/HEAD/remote/audit 相同）；AC-03（wx 并发 EEXIST → CAS_CONFLICT 且并发内容保留；经测试专用 preload/PATH shim 注入 create 与 add/commit/push 失败后断言残留与无成功审计，去注入同命令续跑）。
2. 普通（非 help、非 kb）入口 workspace 守卫负测保持原行为：缺根语义不被 kb 特判改变；help 无根可用。
3. 文件集检查经受控入口（本运行时禁止原生 Git；argv 固定于本卡）。执行目录为 tools CR worktree 根（与验收条件 1 相同）；占位绑定：`<tools-worktree>` 取 Pipeline `resources[]` 中 repo=`tools` 的 `worktreePath` 原样值，`<operational-workspace>` 取 `crctl workspace inspect` 返回的 `operationalWorkspace` 原样值，不拼接、不回退主工作区：

   `node skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <tools-worktree> --workspace <operational-workspace>`

   断言输出仅含本 TASK 声明的两个文件（`skills/shared/crctl/scripts/crctl.mjs`、`skills/shared/crctl/scripts/test/crctl.test.mjs`）。status 仅证明文件集，内容正确性由验收条件 1 的定向用例证明。

## 完成标志

- cmd-01 全绿且 init/守卫定向用例覆盖 AC-01/AC-02/AC-03 断言。
- `cmdKbInit` 为 crctl.mjs 私有函数、无新增导出/模块；其他非 help 入口的检测路径 diff 为零。
- 产物提交落盘；不夹带 TASK-09 的 HELP/文档修订。

## 接口契约

**消费**（逐字对齐 SDD/目标仓现状）：
- dep-1 `resolveToolsRoot(ws)`、`resolveRepositories(ws)`：tools 解析失败码原样输出，不把 tools 缺失改成 graph 错误。
- dep-2 `createFileExclusive`：wx 独占创建；EEXIST → CAS_CONFLICT；自身写失败关闭 fd 并清理自身新文件，不删除他人先建文件。
- dep-3 `gitRun`（返回 `{status, stdout, stderr}`）与 `gitMust`（非零抛 TX_GIT_FAILED），自 `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 导入。
- dep-4 `auditLog(ws, {op:'kb-init', actor, ...result})`：追加一行 JSONL 到自忽略 `.crctl`，无 CR outbox。

**产出**：
- 私有函数 `cmdKbInit(path.resolve(flags.workspace), positional, flags)`（SDD §4.1 原样调用形态；不新增导出）。
- 成功 stdout 的 KbInitResult（SDD §3.1 逐字）：

```typescript
type KbInitResult = {
  op: 'kb-init';
  changed: boolean; // 本次创建、提交或推送至少发生其一；成功审计不使 noop 变 true
  created: string[]; // 本次独占创建的两账本相对路径，按固定路径顺序；重跑通常 []
  commit: string; // 成功后的完整 HEAD SHA，noop/补推也返回同一 HEAD，不用 null
  pushed: boolean; // 本次是否实际普通 push；远端已含 HEAD 时 false
};
```

- 失败 stderr 形态 `{error:{code,message,...}}`，错误码集合：BAD_ARGS / WORKSPACE_REQUIRED / KB_INIT_PRECONDITION(reason=repo-invalid|trunk-mismatch|dirty|remote-diverged) / KB_INIT_CONFLICT(paths) / CAS_CONFLICT / INTERNAL_ERROR / TX_GIT_FAILED(stage)。
- 下游消费方 TASK-02（init 后首 CR 场景）、TASK-09（HELP/命令发现/文档入口契约）、TASK-10（ARCHITECTURE 地图）引用同一份 KbInitResult 与错误码集合，不得缩写。
