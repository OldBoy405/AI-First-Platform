---
id: CR-2026-018-test-report
type: TEST_REPORT
cr-ref: CR-2026-018
tester: Ray
tester-assigned-at: "2026-08-04T17:00:00+08:00"
status: pass
blockers: []
repair-target: implement-code
repair-instructions: []
review-loop:
  pass-condition:
    allOf:
      - path: status
        equals: pass
      - path: blockers
        isEmpty: true
  on-block: route-to-repair-node
  max-attempts: 3
  current-attempt: 0
  attempts:
    - attempt: 0
      generated-at: "2026-08-04T17:00:00+08:00"
      result: pass
      blocker-count: 0
      repair-target: implement-code
created: "2026-08-04T17:00:00+08:00"
updated: "2026-08-04T17:00:00+08:00"
---

# CR-2026-018 测试报告 — 状态推进单写 cr.md，_backlog.yml 退化为注册索引（T1-full）

## 1. 测试摘要

10 个 TASK 全部完成（`tasks/_index.yml` 已即时登记 done），PRD AC-1~AC-11 全部通过。判定依据全部为实际执行的命令输出与结构化断言：`crctl` 测试套件 **32/32 全绿**（基线 21 → 新增 11 个 CR-2026-018 用例）、claude-code 适配器三种布局 fixture 回归 PASS、端到端 `git merge-tree --write-tree` 对 `_backlog.yml` **零冲突**（核心目标 AC-9）。无 blockers。

## 2. 验证命令与结果

| 命令 | 执行目录 | 结果 | 说明 |
|---|---|---|---|
| `node --check crctl.mjs` | tools 仓 | pass | 语法检查（每任务落地后执行） |
| `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | tools 仓 | 32/32 pass | 全量套件；基线 21 用例回归线保持 + 新增 11 用例（AC-1/2/3/5/9/10/11） |
| TASK-09 fixture 回归脚本（v1 回退读 / v2 权威读 / 混版 cr.md 胜） | 临时目录 | 3/3 PASS | claude-code 适配器 `inject-cr-status.mjs` 三种布局 |
| TASK-10 merge-tree 演练脚本（注册在共同祖先 → 分支推进 3 次 cr.md → master 注册新 CR） | 临时 git 仓 | AC-9 PASS | `git merge-tree --write-tree` 对 `_backlog.yml` 零冲突、exit 0 |
| `crctl migrate-backlog --workspace . --no-commit` | 平台仓（演练后回滚） | pass | 11 条目迁移：schema→v2、删除 16 行 status/updated-at、0 残留；`git checkout` 回滚 |
| `grep backlog[].status / _backlog.*status` | tools/skills/**/SKILL.md | pass | 9 处命中全部为迁移说明/权威源说明/兼容回退类表述，无活体消费（AC-6） |
| `dir-graph.yaml` scope 字段核对 | tools 仓 | pass | `state_machine.scope` = `change-requests/{CR-ID}/cr.md`（AC-7） |
| tools 仓 pre-commit 钩子（skill matrix / agents.contract） | tools 仓 | pass | 每次 commit 自动执行 |

## 3. AC 验收覆盖矩阵

| AC | 验证方式与证据 | 结果 |
|---|---|---|
| AC-1 advance 单写 | 测试用例 `AC-1：advance 后 _backlog.yml 内容不变`：diff 断言 + `result.files` 仅含 cr.md | ✅ |
| AC-2 双向读 | `AC-2a`：v1 布局（backlog 有 status、cr.md 无）→ 回退读 + `legacySource` + `MIXED_LAYOUT_WARN`；`AC-2b`：v2 布局 → cr.md 权威读、无告警 | ✅ |
| AC-3 validate 三态 | `AC-3a` v1 一致无告警；`AC-3b` v1 漂移 → warning + 退出码 0；`AC-3c` v2 含 status → `LEGACY_STATUS_FIELD` 告警 | ✅ |
| AC-4 探测不变 | `:289` 零改动；既有 21 用例（含 workspace 探测路径）回归线全绿 | ✅ |
| AC-5 迁移命令 | `AC-5a` 成功（2 条目 → v2 + 无 status 行）；`AC-5b` 不一致 → `MIGRATE_STATUS_MISMATCH` 硬失败不写文件；`AC-5c` 幂等 `already-migrated`；真实 workspace 演练 11 条目 | ✅ |
| AC-6 skill 文档 | 17 个文档修订 + 2 次补漏（list-remote-checkpoints、cr-status-set/cr-inbox）；grep 断言仅命中迁移/权威源说明 | ✅ |
| AC-7 scope 声明 | `dir-graph.yaml:210` scope → `change-requests/{CR-ID}/cr.md`；`crctl status` 的 `source.stateMachine` 不变、`source.crMd` 新增 | ✅ |
| AC-8 适配器回归 | claude-code 三种布局 fixture 3/3 PASS；CI 模板零改动（全部经 `crctl validate`/`crctl gate`，随 crctl 升级自然切换） | ✅ |
| AC-9 merge-tree 零冲突 | 端到端演练：注册 CR-X/CR-Y 于共同祖先 → 分支仅推进 cr.md ×3 → master 注册 CR-Z → `merge-tree --write-tree` 对 `_backlog.yml` 零冲突、exit 0 | ✅ |
| AC-10 回归 | 21→32 用例全绿；新增用例覆盖 FR-1/2/3/5 | ✅ |
| AC-11 混版告警 | `AC-11`：cr.md 与 backlog 双写不一致 → cr.md 胜 + `MIXED_LAYOUT_WARN` + 退出码 0 | ✅ |

## 4. TASK 验收覆盖

10/10 done（`tasks/_index.yml` 已登记，纪律 #8 即时标记）：

| TASK | 内容 | 提交 |
|---|---|---|
| TASK-01+02 | `resolveCrState` 收敛 5 处读取点 + advance 单写 cr.md（删 `updateBacklogStatus`） | `c1e47db` |
| TASK-03 | schema v2 + validate 规则调整（`LEGACY_STATUS_FIELD`/漂移告警） | `dd70bc1` |
| TASK-04 | `crctl migrate-backlog` 子命令（预检硬失败 + 行级定点删除 + 幂等） | `d71e304` |
| TASK-05 | 测试套件 21→32（AC-1/2/3/5/9/10/11 全覆盖） | `b83a53b` |
| TASK-06 | `inject-cr-status.mjs` 改读 cr.md（v1 回退/v2 权威/混版 cr.md 胜） | `cd07555` |
| TASK-07 | `dir-graph.yaml` scope 更新（FR-7） | `a3a581e` |
| TASK-08 | 17 个 skill 文档修订（FR-6+FR-9） | `eecf6a1` + `092e2ed` + `d93816c`（含 2 次盘点补漏） |
| TASK-09 | 双适配器回归（claude-code 3 布局 + CI 零改动） | `cd07555`（随 TASK-06 验证） |
| TASK-10 | 端到端 merge-tree 零冲突演练（AC-9） | 验证脚本（不入库，一次性演练） |
| — | fixture 契约同步（F3+F5 复盘落地：`writeBacklog`/`writeCrMd` 默认 owners + `writeCrEntry`） | `fb85faf` |

分支累计 10 个 commit，21 个文件，+490/-112 行（tools 仓 `requirement/CR-2026-018`）。

## 5. 未覆盖风险与不适用说明

1. **AC-9 演练为会话内一次性脚本**（`_scratch/patch-task10b.mjs` 变体），未沉淀为入库测试——演练验证了 `merge-tree` 行为，但未纳入 CI 回归。建议后续 CR 将该演练固化进测试套件（P2 范围）。
2. **迁移演练在真实 workspace 上执行后已回滚**：主工作区 `_backlog.yml` 仍是 v1 布局（11 个 status 行），等正式迁移时机（本 CR 合并后按发布说明统一迁移）。演练证明迁移命令可用，但迁移本身不在本 CR 实施。
3. **TASK-09/TASK-10 验证脚本不入库**：均为一次性 fixture 回归/演练，结果记录于本报告 §2；核心逻辑已有入库测试用例覆盖（AC-2a/2b/3a-c/5a-c/11 等）。
4. **AC-4（workspace 探测）无独立新用例**：该行为零改动（SDD 明确 `:289` 不动），由既有 21 用例回归线覆盖。
5. **混版布局的运维风险**（SDD §7 残余风险）：迁移窗口期内新旧 crctl 混用会重新引入双写——`MIXED_LAYOUT_WARN` 已提供告警，发布说明需明示"迁移后必须统一 crctl 版本"。

## 6. 下一步建议

代码审批按用户指示暂缓（不执行 `crctl advance` 至 code-reviewing）。建议下一步：

1. 由人类在交互式终端运行 `crctl approve --stage code`（tools 仓 `requirement/CR-2026-018` 分支 10 个 commit 为评审对象）；
2. 审批通过后合并分支，并在发布说明中给出 `crctl migrate-backlog` 迁移指引（含"统一 crctl 版本"警告）；
3. 后续 CR 建议：① AC-9 merge-tree 演练沉淀为入库测试；② P2（账本操作 crctl 子命令化）立项——本 CR 是其前置，现已定型。
