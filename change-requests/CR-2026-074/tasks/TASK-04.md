---
id: CR-2026-074-TASK-04
type: TASK
cr-ref: CR-2026-074
plan-ref: "change-requests/CR-2026-074/plan.md"
sdd-ref: "change-requests/CR-2026-074/sdd.md"
target-version: 0.47
title: buildIndex 缺文件首写 + features 前置校验
slug: buildindex-firstwrite-features-check
status: pending
estimate: 3h
depends-on: []
created: 2026-10-01T00:55:00+08:00
---

## 任务描述

实现 baseline generator 对缺 `specs/_index.yml` 的首写与全部既有索引的 features 前置校验（SDD §2.2/§4.3；FR-5；AC-05 结构负例侧），结构错误全部在 writeCandidate 前返回。

## 涉及文件 / 模块

- `skills/writeback/scripts/writeback-prd-sdd.mjs` — `buildIndex`（dep-7）及主流程 `writeCandidate` 调用边界。
- `skills/writeback/scripts/test/writeback.test.mjs` — baseline 缺/畸形/已有索引定向用例。

## 实现要点

- `buildIndex` 顺序固定三步（SDD §4.3）：
  1. 读取原索引；仅 `readFile(indexPath)===null` 才使用首部 `schema: specs-index/v1\n\nfeatures:\n`（LF 转义仅说明字符串值，实际文件保留真实换行）；任何已存在文件（含空文件）都按其原文处理，不得被替换为模板。
  2. 对选定文本先查 features 行，判据精确 `line.trimStart()==='features:'`；未找到立即 STRUCTURE_MISMATCH。此检查位于目标 spec 提取/分支选择之前，对全部既有索引生效（包括已有目标 spec 且含 cr-history 的文件），不依赖末尾 selfCheck。
  3. 校验成功后，目标不存在则用已定位的 features 行插入；目标存在则沿用原字段更新及历史累积，缺 cr-history 仍 STRUCTURE_MISMATCH。不新增 schema、重复 features 等额外收紧项，不重建旧索引或删除旧条目。
- 错误边界（SDD §2.2/§4.3）：以上结构错误全部在 `writeCandidate` 前返回——无 baseline blobs/manifest 输出、无 authority 改写、无本阶段 journal；只读/内存中的 PRD/SDD 候选不算落盘。
- before 从原索引路径读取而不是从内存模板推导，缺文件保持 null（beforeSha256:null，dep-8）。candidate 后他人创建索引时由 apply 拒绝，不写 authority、不修改 CAS 函数；同事务重放沿 dep-9/dep-10，durable-tx/apply 零改动。
- 正常索引继续累积历史，重复事务不新增相同 spec/CR；新索引不增加顶层 updated。

## 验收条件

1. 在 tools CR worktree 执行 `node --test skills/writeback/scripts/test/writeback.test.mjs`（证据 cmd-03）全绿，且 AC-05 结构负例四类均断言 STRUCTURE_MISMATCH、原索引不变、不输出 candidate/本阶段 journal：空文件；缺 features 且无目标；缺 features 但已有目标 spec/cr-history；含 features 但目标缺 cr-history。负测先满足合法 merging/writing-back authority 及其他证据，使用独立空 candidate 输出路径，只变索引以触达 buildIndex。
2. 缺文件首写正例：before=null，candidate 含插入的新 spec 条目与 manifest；索引内容起始为 §2.2 首部（真实换行）。
3. 正常索引旧历史保留：已有目标 spec 更新走原字段更新与历史累积，重复事务不新增相同 spec/CR，不重建/不删除旧条目。

## 完成标志

- cmd-03 全绿含上述断言；buildIndex 三步序落盘，selfCheck 位置/行为不变（不以其兜底结构检查）。
- diff 限 `writeback-prd-sdd.mjs` 指定路径与 `writeback.test.mjs`；`durable-tx.mjs` 全文件、writeback-apply/CAS 零 diff（zero_diff）。

## 接口契约

**消费**：dep-7 `buildIndex`/`selfCheck`/主流程 `writeCandidate` 调用（现状：仅新 spec 分支检查 features，已有目标且含 cr-history 的无 features 索引会进入更新分支——本 TASK 改为全部既有索引前置校验）；dep-8 `readFile`/`readHashRaw`/`writeCandidate`（before 锚点按磁盘字节，缺文件 before 为 null，candidate 输出 blobs/manifest 且缺文件不写 authority）。

**产出**：`buildIndex` 三步序语义——输入原索引路径与内存 spec 文本，输出内存索引文本或 STRUCTURE_MISMATCH（前置于 writeCandidate）；首部文本 `schema: specs-index/v1\n\nfeatures:\n` 仅用于缺文件分支。下游消费方 TASK-08（writeback-tx 集成变体的端到端断言）与 TASK-05/TASK-06（同测试文件顺序编辑基线）引用同一语义，不得缩写。
