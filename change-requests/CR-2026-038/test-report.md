---
cr: CR-2026-038
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-14T22:45:08+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-038/test-evidence/cmd-01.log" }
  - { command: "node --test skills/writeback/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-038/test-evidence/cmd-02.log" }
  - { command: "node skills/shared/crctl/scripts/check-skill-matrix.mjs", exit: 0, log: "change-requests/CR-2026-038/test-evidence/cmd-03.log" }
  - { command: "node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-038/test-evidence/cmd-04.log" }
  - { command: "git diff --check c790b7e..HEAD", exit: 0, log: "change-requests/CR-2026-038/test-evidence/cmd-05.log" }
---

# 测试报告 · CR-2026-038

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-038/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-038/test-evidence/cmd-01.log |
| 2 | `node --test skills/writeback/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-038/test-evidence/cmd-02.log |
| 3 | `node skills/shared/crctl/scripts/check-skill-matrix.mjs` | 0 | change-requests/CR-2026-038/test-evidence/cmd-03.log |
| 4 | `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | 0 | change-requests/CR-2026-038/test-evidence/cmd-04.log |
| 5 | `git diff --check c790b7e..HEAD` | 0 | change-requests/CR-2026-038/test-evidence/cmd-05.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

### 测试摘要

- crctl 全量：274/274 通过；覆盖 writeback、merge、archive、fault/recovery、CRLF 与既有状态机回归。
- writeback generator：10/10 通过；三个版本化 generator 仅写内部 candidate 输出。
- Skill matrix：57 个 active Skill、8 个 actor 一致；Prompt lint：0 findings。
- 全部 Pipeline JSON 已独立 `JSON.parse`；changed-files、依赖、Multica 与旧公共调用面已完成静态审计。

### TASK 验收覆盖矩阵

| TASK | 结果 | 主要证据 |
|---|---|---|
| TASK-01 | pass | canonical business digest、固定 candidate 路径、单次 snapshot 与 advance preflight 测试 |
| TASK-02 | pass | baseline + `writing-back` 同 commit、journal-created 恢复、输入漂移、投影补偿测试 |
| TASK-03 | pass | backlog 目标条目字节级语义替换、并发 trunk 保留、最终双亲 ancestry 测试 |
| TASK-04 | pass | 业务参数公共 CLI、旧 candidate 参数 `BAD_ARGS`、fault 重放、traceability 全链路测试；Skill/Pipeline/索引迁移 |
| TASK-05 | pass | 两套全量测试、matrix、Prompt lint、JSON、diff、范围与依赖审计 |

### PRD AC-01～AC-12 覆盖

| AC | 结果 | 证据 |
|---|---|---|
| AC-01 | pass | `固定 generator 只在 ignored candidate 目录生成单次 snapshot` |
| AC-02 | pass | `内部 baseline 路径同一 commit 发布状态并在 origin-confirmed 后投影` |
| AC-03 | pass | `journal-created 恢复冻结 transitionAt` 与 writeback fault matrix |
| AC-04 | pass | `业务参数漂移硬阻断`，错误为 `TX_INPUT_CONFLICT` |
| AC-05 | pass | `writeback-after-commit fault` 同业务命令续跑且不重复 commit |
| AC-06 | pass | backlog 只替换目标完整条目并保留 trunk 其他内容 |
| AC-07 | pass | CRLF/LF 归一测试及 backlog blob 字节保真断言 |
| AC-08 | pass | semantic merge tree 最终 parents 为最新 base + 原 source |
| AC-09 | pass | origin-confirmed 后 status outbox/advance audit 幂等补偿 |
| AC-10 | pass | 公共 CLI 仅收业务输入，旧 `--candidate` 明确拒绝 |
| AC-11 | pass | active Skill/Pipeline/help 静态扫描无内部路径参数或独立 writing-back advance；Prompt lint 0 findings |
| AC-12 | pass | 274 项全量回归、10 项 generator 回归、changed-files/依赖/Multica 审计 |

### 新增或修改的测试文件

- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`
- `skills/shared/crctl/scripts/test/merge-tx.test.mjs`
- `skills/shared/crctl/scripts/test/archive-tx.test.mjs`

### 不适用与未覆盖风险

- build：不适用；本 CR 为 Node ESM 脚本、Skill 和 Pipeline JSON，无构建产物或 package build 脚本。
- package dependency：不适用；`package.json` 与 lockfile 零变更，未新增依赖。
- Ubuntu：本机仅完成 Windows 验证；Ubuntu 行为需 CI 实跑。CRLF/LF 输入和路径相关测试已在 Windows 通过，但不冒充跨平台结果。

### 下一步建议

测试结论为 pass；进入代码评审。评审应重点复核 journal 恢复输入绑定、baseline 状态原子提交、backlog semantic merge，以及 active 调用方是否确实只传业务参数。
