# 2026-11-15-controlled-shell-snapshot-read-shapes 切片执行计划

## Dependency Graph Summary

```
controlled-shell-git-show-shapes（zero_dependency，单节点无边界）
  └─ 切片 1：rules.json + 新测试 + SKILL.md + CUSTOM.md
```

**并行化说明**：只有 1 个 capability、1 个切片，无并行组。

## Slice Execution Plan

| # | 优先级 | 风险 | 预估工时 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|--------|------|---------|--------|---------|---------|------|
| 1 | P0 | 🟡 Med | M | — | TC-CSS-001、TC-CSS-002、TC-CSS-003、TC-CSS-004、TC-CSS-005 | `rules.json#git[sub=show].shapes` 追加 3 条形状；`controlled-shell-rules.test.mjs`；SKILL.md `show` 行；CUSTOM-TODO-017 | 无 |

## Rationale

### Slice 1: git show 只读形状放行与文档同步（P0）

- **依赖关系**：`dependency-graph` 只有 1 个节点、0 条边；规则文件是唯一权威输入，测试与文档都消费它，所以只能顺序执行，没有可拆的独立分支。
- **风险分析**：风险来自「放宽安全白名单」——EXP-2026-0001（夹具掩盖真实调用形态）与 EXP-2026-0003（CP 判定面窄于 spec 措辞、0 用例也退出 0）都指向同一处：只写正例或只判退出码会假绿。缓解：拒绝表 11 种近似形状与放行表同一用例内断言，CP 另断言 `pass 1 fail 0`。
- **工作量估算**：M——5 个 TC 但只有 4 个文件、约 90 行；拆成「规则+测试」和「文档」两个切片会让第二个切片 `new_tests = 0`，与 B3.4 的每切片新增测试要求冲突，且文档与规则必须同次一致才有意义，故不拆。
