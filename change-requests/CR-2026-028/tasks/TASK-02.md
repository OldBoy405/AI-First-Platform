---
id: CR-2026-028-TASK-02
type: TASK
cr-ref: CR-2026-028
plan-ref: "change-requests/CR-2026-028/plan.md"
sdd-ref: "change-requests/CR-2026-028/sdd.md"
title: 新增 resolveToolsRoot 与 Tools Root 唯一契约（M2a）
slug: add-resolve-tools-root
status: pending
estimate: 6h
depends-on: [CR-2026-028-TASK-01]
created: "2026-08-10T18:10:38+08:00"
---

# TASK-02 新增 resolveToolsRoot 与 Tools Root 唯一契约

## 1. 任务描述

在 `crctl.mjs` 单文件内新增 module-scope `resolveToolsRoot(opWs)`（SDD §3.1/§4.2），实现 Installation Workspace 派生 + `workspace.tools_package_path` 读取 + 四标志身份验证 + `TOOLS_PACKAGE_NOT_FOUND` 硬失败契约。这是 FR-1/FR-3 的核心。

## 2. 涉及文件 / 模块

- tools 包 `skills/shared/crctl/scripts/crctl.mjs`：新增 `resolveToolsRoot`、完善 `deriveInstallRoot`、新增 `fail('TOOLS_PACKAGE_NOT_FOUND', ...)` 分支

## 3. 实现要点

- SDD §3.1 签名：`let toolsRootCache; // undefined=未解析, string=成功`；成功值缓存，失败即进程退出（不缓存失败）。
- SDD §4.1 `deriveInstallRoot`：`git rev-parse --git-common-dir`（`spawnSync`，cwd=opWs）→ `path.resolve(opWs, stdout.trim())` 的 dirname；失败/非 git 回退 opWs。
- SDD §4.2：YAML 解析前 CRLF→LF 归一（纪律 #1）；字段缺失/非字符串/空、路径不存在、四标志任一缺失 → `TOOLS_PACKAGE_NOT_FOUND`，detail 含 `instRoot`/`field`/`reason`/`resolved`/`missing`。
- 四标志（SDD §2.2）：`AGENTS.md`、`dir-graph.yaml`、`skills/_index.yml`、`skills/shared/crctl/scripts/crctl.mjs`。
- **绝不回退**：不尝试 `opWs/tools`、cwd、`PACKAGE_ROOT`（D-3）。

## 4. 验收条件

1. 表驱动：相对路径、绝对路径、空壳 `tools/`、缺配置、非字符串、路径不存在、四标志逐一缺失——缺失/无效场景均返回 `error.code = TOOLS_PACKAGE_NOT_FOUND` 且 exit 1，无静默回退。
2. 成功场景：`resolveToolsRoot` 返回 realpath 归一后的 Tools Root；同一命令内第二次调用命中 `toolsRootCache`（代码审查断言 AC-8）。
3. 非 git 临时目录：`deriveInstallRoot` 回退 opWs，解析仍成功。

## 5. 完成标志

表驱动用例绿 + 失败即退出无回退 + 缓存断言成立 + commit 完成。

## 6. 接口契约

- **消费**：TASK-01 产出的最简 `deriveInstallRoot`（本 TASK 完善为正式版）。
- **产出**：
  - `resolveToolsRoot(opWs: string): string` — 成功返回 Tools Root 绝对路径；失败 `process.exit(1)` 输出 `{error: {code: "TOOLS_PACKAGE_NOT_FOUND", message, instRoot, field?, reason, resolved?, missing?}}`。
  - 错误码 `TOOLS_PACKAGE_NOT_FOUND` 契约（SDD §2.3）。
  - 下游 TASK-03 四个 loader 消费 `resolveToolsRoot(ws)`。
