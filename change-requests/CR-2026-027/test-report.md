---
cr: CR-2026-027
status: pass
tester: "OldBoy405"
generated-by: crctl-test
generated-at: "2026-08-10T05:57:06+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/crctl.test.mjs", exit: 0, log: "change-requests/CR-2026-027/test-evidence/cmd-01.log" }
  - { command: "node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-027/test-evidence/cmd-02.log" }
---

# 测试报告 · CR-2026-027

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-027/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | 0 | change-requests/CR-2026-027/test-evidence/cmd-01.log |
| 2 | `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | 0 | change-requests/CR-2026-027/test-evidence/cmd-02.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

## 测试摘要（TASK 验收条件）

- **136/136 用例全绿**（TASK-03~08 新增 15 个向量 + 既有 121 个回归）：覆盖 approve 原子提交（单次 commit/GATE_BLOCKED/CANDIDATE_STATUS_MISMATCH/漂移零写入）、archived 门禁五步判定、migrate-backlog 幽灵清理（删除/幂等/orphaned）、archive-move 三账本 CAS（三终态/中文 reason/收件人矩阵/重复调用）、终态只读查询（冲突/缺 final-status 硬失败）、next 路由（task-breakdown 五态 + tech-design freshness/upstream 重入）、review-record 输出契约与 review cycle、inbox-emit 空 to 校验。
- TASK-01/02/09 为文档/声明层（bootstrap、ARCHITECTURE、SKILL 同步），由 grep 断言与 lint-prompts enforce 覆盖（AC-1/AC-5/AC-6 判定）；TASK-10 五项最小验证全绿。

## 验证命令与结果解读

| 命令 | 结果 | 解读 |
|---|---|---|
| `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | exit 0 | 136/136 通过（含 15 个 CR-2026-027 新增向量）；日志 cmd-01.log |
| `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | exit 0 | 0 findings（TASK-08/09 改 prompt 后无漂移）；日志 cmd-02.log |
| `JSON.parse(feature-writeback.pipeline.json)` | 通过 | TASK-10 已执行（未被本 CR 触及） |
| `git diff --check`（workspace + tools worktree） | 无告警 | TASK-10 已执行 |
| `migrate-backlog` 幂等 | already-clean | TASK-05 实测（幽灵条目已清理，重复运行零写入） |

## TASK 验收覆盖矩阵

| TASK | 验收证据 | 覆盖方式 |
|---|---|---|
| 01 bootstrap | worktree 存在 + base-sha 记录 + 口径 27/49 grep | 实施记录 + AC-1/AC-22 断言 |
| 02 ARCHITECTURE | grep 无 25/47 现状表述 + 三句依赖描述 | AC-1/AC-3 grep |
| 03 approve 原子化 | 单次提交断言 + GATE_BLOCKED/CANDIDATE_STATUS_MISMATCH 零写入 | 测试向量 ①-③ |
| 04 TASK 门禁 | 五步判定 6 用例（含混合状态） | 测试向量 ④ |
| 05 幽灵清理 | 删除/幂等/orphaned 3 用例 + 主工作区实测清理 | 测试向量 ⑤ + 实景 |
| 06 archive 原子化 | 三终态/中文 reason/收件人矩阵/重复调用 | 测试向量 ⑥-⑧ |
| 07 status/next 路由 | 终态查询/五态路由/freshness/inbox-emit | 测试向量 ⑨-⑫ |
| 08 review-record 深化 | 输出契约/cycle=2 attempt=1/三 Skill 无二次读取 | 测试向量 ⑬-⑭ + grep |
| 09 Skill 同步 | merge 无特例 grep + cr-archive 契约 + §8 登记 | AC-4/AC-5 grep |
| 10 五项验证 | 全部通过 | 本节 + TASK-10 记录 |

## 新增/修改测试文件

- `skills/shared/crctl/scripts/test/crctl.test.mjs`：+15 个 CR-2026-027 向量（FR-8/9/10/11/12/13/16 覆盖），既有 121 个用例同步适配（attempt 对象契约、tech-design subject digest、pass 轨 repair-target 省略、archive-move 三账本）

## 未覆盖风险

1. **TTY 审批路径**（FR-8）：非 TTY 环境无法自动化走 TTY 交互；以 `--grant` 等价路径 + 代码审查覆盖（approveAndAdvance 为共用 helper，TTY/grant 收敛后同一实现）。**不适用自动化**——需在真实终端人工验证一次四 stage 审批。
2. **commit 失败恢复路径**（FR-8）：受控环境难以注入 git commit 失败；以代码审查 + 结构化恢复信息契约覆盖（两文件共同保留、不发 outbox）。
3. **真实多仓 merge**：本 CR 尚未走 merge 阶段；tools 作为新参与仓的 merge/cleanup 行为将在本 CR 自身 merge 时实景验证（AC-22）。
4. **CAS 并发冲突**：单写者不变量下无并发场景；casWriteMulti 组件级三阶段语义已有既有测试（SDD §4.3 判定可接受）。

## 下一步建议

- 按用户要求跳过 review-code；建议在真实终端人工验证一次四 stage approve 原子提交（未覆盖风险 1）后进入 approve-code。
- merge 阶段验证 tools 仓 worktree 合并与清理（AC-22 断言）。
