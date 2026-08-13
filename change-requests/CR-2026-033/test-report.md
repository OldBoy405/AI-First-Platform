---
cr: CR-2026-033
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-13T22:52:13+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-033/test-evidence/cmd-01.log" }
  - { command: "node --test skills/writeback/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-033/test-evidence/cmd-02.log" }
  - { command: "node --check skills/shared/crctl/scripts/crctl.mjs", exit: 0, log: "change-requests/CR-2026-033/test-evidence/cmd-03.log" }
---

# 测试报告 · CR-2026-033

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-033/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-033/test-evidence/cmd-01.log |
| 2 | `node --test skills/writeback/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-033/test-evidence/cmd-02.log |
| 3 | `node --check skills/shared/crctl/scripts/crctl.mjs` | 0 | change-requests/CR-2026-033/test-evidence/cmd-03.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

### 结果摘要

- crctl tests：276/276 pass；writeback tests：10/10 pass；CLI 语法检查通过。
- checkpoint 专项：23/23 pass（含新增粘行回归）；`lint-prompts --mode enforce` 0 findings、Pipeline JSON 可解析、`git diff --check` 通过。

### merge dogfood 发现并修复（本轮回评重点）

- **`editLatestCheckpoint` 粘行 bug**：当 CR 不是 `_backlog.yml` 最后一条时，追加的 `latest-checkpoint` 块会把下一条目（如 CR-2026-034）粘到 `remote-ref` 行尾，产生畸形 YAML。此前测试 fixture 中目标 CR 总是最后一条，未触发；merge 时 `readCheckpointSnapshot` 正确 fail-closed 拒绝（validator 本身无误）。
- 修复：编辑返回路径补回条目末尾换行（`out.join` 丢尾换行 + `block.end` 指向下一条目行首）；新增回归测试覆盖“条目后仍有其他条目 / 末尾条目”两种形状。
- 私钥头 fixture 改为动态拼接，避免敏感预检在未提交变更时误拦（测试语义不变）。

### 代码评审 blocker 回归覆盖（同前）

- 首次发布、恢复矩阵、remote 三关系、安全零副作用、CRLF/Windows、T05 reader 迁移、固定错误 JSON 均由 23 项 checkpoint 专项覆盖；275→276 仅因新增粘行回归。

### 范围外风险

- 未模拟真实托管平台权限策略、网络代理和跨设备文件系统；本地三 bare-remote 覆盖 Git graph/lease/replay 语义，真实 installation workspace 已完成统一 checkpoint dogfood。
- 未新增通用事务框架、schema engine、消息队列或第三方依赖；修复继续复用 `durable-tx.mjs`、Git 与现有 YAML 子集解析。
