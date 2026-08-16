---
cr: CR-2026-043
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-16T08:19:38+08:00"
command-digest: 2d4c7552c079ac01d08ea5c7aefa6e66a0c6bee4b86d694b1da68ea20956be70
commands:
  - repo: tools
    cwd: skills/shared/crctl/scripts
    executable: node
    args: [--test, test/archive-tx.test.mjs, test/check-agents-contract.test.mjs, test/checkpoint-tx.test.mjs, test/check-skill-matrix.test.mjs, test/contract-scan.test.mjs, test/crctl.test.mjs, test/durable-tx.test.mjs, test/fault-harness.test.mjs, test/lint-prompts.test.mjs, test/merge-tx.test.mjs, test/pipeline-structure.test.mjs, test/register-tx.test.mjs, test/test-cr.test.mjs, test/upgrade-check.test.mjs, test/workspace-resolver.test.mjs, test/workspace-freshness.test.mjs, test/writeback-tx.test.mjs]
    timeout-seconds: 1800
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-043/test-evidence/cmd-01.log
---

# 测试报告 · CR-2026-043

<!-- crctl:analysis-below -->

## 测试摘要

机器区由 `crctl test` 生成（attempt 3/3，status=pass）：代码评审 attempt 1 回修同步恢复不变量后重放同一计划，单条命令在 tools 仓 CR worktree 内运行全部 17 个 crctl 测试文件，**386 个用例全部通过，0 失败 / 0 超时**（耗时 ≈473s，证据见 `test-evidence/cmd-01.log`）。

## TASK 验收覆盖矩阵

| TASK | 验收条件 | 验证证据 |
|---|---|---|
| TASK-01 | 四类 freshness + 六类基础分类透传；ahead-only 稳定 fresh；CLI allFresh 零 audit / behind-clean 业务 audit / diverged 结构化结果+audit / trunk 不可确认失败 audit；既有回归 | `workspace-freshness.test.mjs` 13 个 TASK-01 用例全过；382 全量回归含 `workspace-resolver.test.mjs` |
| TASK-02 | ff-only 成功且 afterSha==target；全 fresh 零 journal；阻断零写入零 journal；故障注入续跑只用原 intent；complete 后新 trunk 新事务；外部回退/漂移硬失败；锁竞争；幂等；audit 前置 | `workspace-freshness.test.mjs` 15 个 TASK-02/代码评审回归用例全过（含全仓 intent、已完成仓恢复重核、ff-only 冲突映射、status 技术失败与两个故障点）；fault-harness/durable-tx 回归通过 |
| TASK-03 | 台账登记一致；Skill 静态扫描无 git/journal/lock/CAS/advance 字样；路由表四组合可核对 | check-skill-matrix（56 active skill 一致）/check-agents-contract/lint-prompts 全过；会话内词边界 grep CLEAN；SKILL.md 路由表六行对照 SDD §3.3 |
| TASK-04 | JSON 可解析；双 gate 位置/ref/onFail；replayNodes 恰 5 项含 …0017；_index 节点数一致；ref 全 active；prompt 无 git/journal；gates/state_machine 零耦合 | `pipeline-structure.test.mjs` 8 用例与 `contract-scan.test.mjs` AC-2c 全过；`crctl.test.mjs` 节点数断言更新为 17 后通过 |
| TASK-05 | 双 gate 四类集成场景；README 人读段；双平台回归 | 4 个 TASK-05 集成用例全过（implement/review × 可同步/人工轨）；README §3 流程图/节点表与新增 §3a；Windows 全量 386 通过 |

## 新增 / 修改的测试文件

- 新增 `test/workspace-freshness.test.mjs`（32 用例：分类单元 + 事务/恢复不变量 + CLI + 集成）。
- 更新 `test/pipeline-structure.test.mjs`（17 节点断言 + 双 gate 位置/卫生/索引一致性新用例）、`test/contract-scan.test.mjs`（AC-2c replayNodes 5 项快照）、`test/crctl.test.mjs`（节点数 15→17 守卫）。

## 未覆盖风险

1. **Ubuntu 侧回归未执行（环境故障，非代码结论）**：本机 WSL Ubuntu 发行版虚拟磁盘缺失（`ext4.vhdx` 不存在，`CreateInstance/MountDisk ERROR_FILE_NOT_FOUND`），本会话无法启动 Linux。Windows 全量 386 用例已绿；代码中跨平台敏感点（路径身份、CRLF 解析、`merge-base` 退出码）均有专项用例，但建议 merge 前在可用 Linux 环境补跑同一条命令（`node --test` 全量）补齐双平台矩阵。
2. **实施期漂移发现（已修正，非风险残留）**：`pipeline-templates/_index.yml` 既有 `nodes: 13` 与实际 JSON 15 节点不符（CR-2026-039 加节点后索引未同步）；本 CR 一并修正为 17 并新增索引一致性契约测试防止复发。SDD/TASK 中“nodes: 13→15”的表述基于旧索引值，实际口径为 15→17，结论（索引必须与实际节点数一致）不受影响。
3. **远端 trunk 竞态**：锁只串行化本机 crctl 事务，不锁远端 trunk；已由逐仓重核 + 既有 release-subjects/approve-code 重核兑底（SDD §7.1），无新增风险。
4. lint/build：tools 仓无独立 build 步骤（纯 Node ESM 脚本，零生产依赖）；lint 面由 lint-prompts/check-skill-matrix/check-agents-contract/contract-scan 四项静态检查覆盖，均已含在机器区命令内——不适用说明完毕。

## 下一步建议

按 pipeline 顺序：push-progress 推送代码+证据 checkpoint → workspace-freshness（review-start gate）→ review-code 代码评审。Ubuntu 补跑建议在 review-code 取证时一并说明。