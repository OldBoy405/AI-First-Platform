---
id: CR-2026-038-TASK-01
type: TASK
cr-ref: CR-2026-038
plan-ref: CR-2026-038-plan
sdd-ref: CR-2026-038-sdd
title: 构建失败优先的 Writeback preflight 基础
slug: writeback-preflight-foundation
status: pending
estimate: 10h
depends-on: []
owner: Ray
created: "2026-08-14T21:22:00+08:00"
updated: "2026-08-14T21:41:17+08:00"
---

# TASK-01：构建失败优先的 Writeback preflight 基础

## 1. 任务描述

以失败优先方式冻结固定 generator/candidate、manifest 内存快照、baseline 无写入 advance preflight 与 `fileExists` planned-existing 的内部契约。先让内部 seam/validator 新测试失败，再实现最小基础能力；本 TASK 不切换公共 `writeback-apply` dispatch，不接通最终 baseline 发布和投影，现有生产调用在 TASK-04 前继续可用。

输入为已审批 SDD §2.1～§3.4、§4.1、§9.1。输出为 TASK-02 可直接消费的 preflight snapshot 与 callback 契约。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`
- 必要时仅复用/最小下沉至现有 `skills/shared/crctl/scripts/lib/yaml-subset.mjs`

## 3. 实现要点

1. 红测通过内部 test seam/validator 覆盖固定 stage/spec/version、generator 选择、candidate snapshot 和非法 manifest；公共 CLI 的参数切换与 BAD_ARGS 黑盒测试留在 TASK-04 同批完成。
2. 增加固定 `WRITEBACK_GENERATORS` 常量和 `{txws}/.crctl/candidates/{cr}/{stage}` resolver；逐段检查 containment、symlink/junction parent 与 `git check-ignore`，但不从现有公共 dispatch 启用新路径。
3. 用 `process.execPath + spawnSync(shell:false)` 调固定 generator；只读取固定 candidate 目录的 `manifest.json`。
4. manifest 仅读取一次并 `CRLF -> LF`，一次读取每个 blob；完成 schema、stage、CR、spec、规范化 version、path、allowlist、排序/唯一、hash、generator hash、input digest、before anchor 和目标矩阵校验，产出内存 snapshot。
5. 实现无 I/O 的 `canonicalWritebackBusinessInput(options)`，固定 key/null/v-prefix/POSIX path，返回 canonical JSON 与 SHA-256 digest。
6. 从 `performAdvance()` 提炼 baseline 无写入 preflight，继续读取权威状态机/gates；`runGateChecks(...,{plannedExisting})` 只在 `fileExists` 分支消费严格 Set。
7. 所有 manifest/gate 失败断言 lock/journal/目标/index/commit/push/outbox/audit 零新增；candidate 可丢弃。

## 4. 验收条件

- [ ] `node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs` 中内部 preflight 组通过，且红测提交可证明实现前失败；现有公共 CLI 回归保持通过。
- [ ] 非法 JSON/schema/stage/CR/spec/path/symlink/allowlist/order/hash/generator/input/目标矩阵每例均断言零 journal 与零 authority 写入。
- [ ] manifest 与每个 blob 各只读一次；预检后的 apply 输入只来自同一 snapshot，不二次读取 candidate。
- [ ] baseline planned-existing 精确路径只放行 `fileExists`；其他 gate、额外路径和非法 Set 均拒绝。
- [ ] 三个 stage 只使用固定 ignored candidate 路径，Git staged/tree 不含 `.crctl/candidates`。
- [ ] 修正预检失败的业务源后同命令可继续，不受失败输入 journal 阻断。

## 5. 完成标志

定向内部 preflight 测试与现有公共 CLI 回归全绿，TASK-02 所需 snapshot 与 advance candidate 接口可用；新路径尚未接入公共 dispatch，旧参数的拒绝和调用方迁移由 TASK-04 同批完成。

## 6. 接口契约

**消费**：无上游 TASK；复用现有 `applyWriteback()`、`performAdvance()`、`runGateChecks()` 与三个 generator 内部 ABI。

**产出给 TASK-02**：

```text
canonicalWritebackBusinessInput(options) -> { canonicalJson: string, digest: string }
validateBaselineAdvance({ workspace: string, plannedExisting: Set<string> }) -> {
  from: "merging", to: "writing-back", trigger: "writeback-prd-sdd",
  path: string, beforeSha256: string, beforeText: string
}
preflight snapshot -> {
  textLf: string, digest: string, parsed: object,
  files: Array<{path:string,beforeSha256:string,afterSha256:string,blobText:string}>,
  plannedExisting: Set<string>
}
```

TASK-02 消费字段名、参数与返回类型必须保持一致；若实现因现有内部命名调整，需在本 TASK 与 TASK-02 同步更新卡片后再编码。
