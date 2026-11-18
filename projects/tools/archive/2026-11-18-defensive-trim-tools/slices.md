# 2026-11-18-defensive-trim-tools 切片执行计划

## Dependency Graph Summary

```
S1 output-guard-escape-hatch ─┐
S2 evidence-delivery-contract ┼─→ 全量回归 / Part C
S3 writeback-generator-read ──→ S4 writeback-apply-resume ─┘
```

**并行化说明**：S1、S2、S3 无依赖，可并行；本次单会话顺序执行（共用 crctl 测试资源）。S4 依赖 S3 的 `readWritebackBase` 口径。

## Slice Execution Plan

| # | 优先级 | 风险 | 预估工时 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|--------|------|---------|--------|---------|---------|------|
| S1 | P0 | 🟢 Low | S | 组1 | TC-OGE-001, TC-OGE-002 | 删除 `singleLine` 条件与配置键 | 无 |
| S2 | P0 | 🟡 Med | M | 组1 | TC-EVD-101, TC-EVD-102, TC-EVD-103, TC-EVD-104 | 读失败/非列表 → 配置错误；交付合并 findings | 无 |
| S3 | P0 | 🟡 Med | M | 组1 | TC-WSC-001, TC-WSC-002, TC-WSC-003 | `readWritebackBase` + 三个生成器 | 无 |
| S4 | P0 | 🟡 Med | L | — | TC-WSC-004, TC-WSC-005, TC-WSC-006, TC-WSC-007, TC-WSC-008, TC-WSC-009 | `readHashRaw` 收紧、`fresh` | S3 |

## Rationale

### S1：OutputGuard（P0，先行）
- **依赖关系**：独立；删除类变更，行为不变，先以表征测试固定首行契约，再删。
- **风险分析**：EXP-2026-0001（helper 恒传生产不传的参数）适用于 S2/S4 夹具；S1 无。
- **工作量估算**：S，一个源文件、一个配置键。

### S2：交付配置（P0）
- **风险分析**：夹具必须真实省略 `components`（EXP-2026-0001）；合同诊断优先于配置错误。
- **工作量估算**：M，3 个源文件、2 个测试文件、registry。

### S3：回写生成侧（P0）
- **风险分析**：摘要口径（UTF-8 解码文本、不归一换行）不得变；任务索引空内容与缺失区分。
- **工作量估算**：M，lib + 3 个生成器 + 生成侧测试。

### S4：回写应用侧（P0）
- **依赖关系**：与 S3 共用同一摘要口径；先 S3 后 S4。
- **风险分析**：续办不得读当前脚本 SHA；在途 journal 摘要口径不变。
- **工作量估算**：L，事务文件 5.5k 行但改动面窄，6 个事务用例。
