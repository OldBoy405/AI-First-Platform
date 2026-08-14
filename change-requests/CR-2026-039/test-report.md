---
cr: CR-2026-039
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-15T04:04:48+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-039/test-evidence/cmd-01.log" }
  - { command: "node skills/shared/crctl/scripts/lint-prompts.mjs", exit: 0, log: "change-requests/CR-2026-039/test-evidence/cmd-02.log" }
  - { command: "node --check skills/shared/crctl/scripts/crctl.mjs", exit: 0, log: "change-requests/CR-2026-039/test-evidence/cmd-03.log" }
---

# 测试报告 · CR-2026-039

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-039/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-039/test-evidence/cmd-01.log |
| 2 | `node skills/shared/crctl/scripts/lint-prompts.mjs` | 0 | change-requests/CR-2026-039/test-evidence/cmd-02.log |
| 3 | `node --check skills/shared/crctl/scripts/crctl.mjs` | 0 | change-requests/CR-2026-039/test-evidence/cmd-03.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

### 测试摘要

全量套件 321 个用例全部通过（0 失败），其中本 CR 新增 26 个用例（TASK-01 digest 4 + TASK-02 freshness 4 + TASK-03 updated 3 + TASK-04 release-subjects 1 + pipeline-structure 5 + contract-scan 5，另有 4 个既有夹具断言随行为变更同步更新）。lint-prompts 0 findings；crctl.mjs 语法检查通过。

### SDD §9.2 用例矩阵映射

| §9.2 需求 | 覆盖用例 |
|---|---|
| FR-02 写入 | crctl.test.mjs `CR-2026-039 TASK-01 AC-1～AC-4`（两轨 digest 与独立重算相等；plan/TASK/增删/`_index.yml`/CRLF 向量；plan 缺失、TASK 集为空、tasks/ 缺失 → `SUBJECT_NOT_FOUND` + repairTarget 且三账本零写入；拼接边界不碰撞） |
| FR-02 next | crctl.test.mjs `CR-2026-039 TASK-02 AC-1～AC-4`（fresh→approve dev-start；drift/legacy→review-dev-plan；TASK 删除→write-dev-tasks）+ 更新后的 `CR-2026-027 FR-16 next task-breakdown 路由` |
| FR-02 gate | crctl.test.mjs `CR-2026-039 TASK-02 AC-1～AC-4`（grant 放行到 developing；drift/legacy/subject 不完整 → GATE_BLOCKED，passCondition why 含 digest/subject 说明，approval.yml/cr.md 零写入） |
| FR-03 | crctl.test.mjs `CR-2026-039 TASK-03 AC-1～AC-3`（refreshCrMdUpdated/crMdStatusText 纯函数四态 + CRLF；owner-set 刷新 updated 且与移交时间同源；advance 产物单一 updated）+ `owner-set AC-3` 扩展断言 + writeback-tx `journal-created 恢复冻结 transitionAt`（writing-back 写 updated） |
| FR-01 | pipeline-structure.test.mjs `AC-1～AC-4` + approvalPrompt 断言；crctl.test.mjs `CR-2026-039 TASK-04 AC-5`（KB 白名单后继放行；非白名单路径 → post-review-path-drift 零写入）+ 既有 `TASK-06 ①～⑥` release-subjects 回归（非 KB HEAD 前移/artifact 漂移/远端 ref 漂移均拒绝） |
| FR-04 | contract-scan.test.mjs `AC-1`（3 Pipeline + 11 SKILL.md 零命中，product-planning 与 skills/planning 显式白名单排除）+ `AC-2a/b/c`（三 Pipeline reviewLoop 结构快照）；既有 review-record schema 用例（CR-2026-026 ② SCHEMA_INVALID 等）保持全绿 |
| 回归 | 全量 321/321；requirement/tech-design/code 三阶段 passCondition 行为由 `CR-2026-030 四 stage grant`、`CR-2026-027 FR-16 tech-design freshness`、`TASK-06 release-subjects` 等既有用例覆盖 |

### TASK 验收覆盖

- TASK-01（digest 写入）：AC-1～AC-4 全部落入 crctl.test.mjs 同名用例 ✔
- TASK-02（双消费点 freshness）：AC-1～AC-4 同名用例 ✔（含零写入断言）
- TASK-03（updated 统一）：AC-1～AC-3 同名用例 ✔（AC-4 既有依赖 cr.md frontmatter 用例全绿：CAS/状态读取/merge finalize）
- TASK-04（checkpoint 节点）：AC-1～AC-4 入 pipeline-structure.test.mjs，AC-5 入 crctl.test.mjs ✔
- TASK-05（文本收敛）：AC-1/AC-2 入 contract-scan.test.mjs，AC-3 由全量绿覆盖 ✔
- TASK-06（采纳与回归）：两处 SKILL 修订与实现行为逐句核对（digest 口径/消费点/失败语义）；本 Windows 平台全量绿；M0 集成以 fast-forward 完成（162fdf0）✔

### 新增/修改测试文件

- 新增：`test/pipeline-structure.test.mjs`、5 个用例；`test/contract-scan.test.mjs`、5 个用例
- 修改：`test/crctl.test.mjs`（新增 12 个 CR-2026-039 用例 + 既有夹具携 subject-sha256 适配）、`test/merge-fixture.mjs`（dev-plan annotation 携 digest）、`test/writeback-tx.test.mjs`（updated 字段断言）

### 未覆盖风险

1. **Ubuntu 平台未在本会话执行**：本机 WSL Ubuntu 分发磁盘镜像损坏（ext4.vhdx 缺失）无法启动；按 TASK-06 AC-2 约定，Ubuntu 回归以合入前 CI workflow 结果为准。测试套件历史双平台全绿，本 CR 改动未引入平台敏感 API（仅 path/fs/spawnSync 既有模式）。
2. **checkpoint 节点未做端到端执行验证**：新增 Pipeline 节点的真实运行依赖 pipeline runtime（本仓不含）；结构性强制（顺序 + onFail:abort）已由结构测试断言，push-progress Skill 本身行为不变（零新契约）。
3. **lint/build 不适用说明**：tools 仓无独立 build 步骤（纯 Node ESM 脚本）；`node --check` 作为语法等价检查，lint 由 lint-prompts + pre-commit skill matrix 校验承担。

### 下一步

status=pass：按 code-implementation pipeline 进入 push-progress 与 review-code；本会话按用户指示不执行代码评审，停在测试证据完备态，后续以 `crctl next CR-2026-039` 为准。
