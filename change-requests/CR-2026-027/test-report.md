---
cr: CR-2026-027
status: pass
tester: "OldBoy405"
generated-by: crctl-test
generated-at: "2026-08-10T11:42:31+08:00"
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

## 代码评审二轮回修后重测（b10，146/146）

- **146/146 全绿**（143 既有 + 3 个代码评审二轮 b10 新增向量），`lint-prompts enforce` 0 findings。
- 针对代码评审二轮 2 个 P1 blocker 逐项回修：
  - **b10a FR-10/一致性**：幽灵清理审计事件从 `migrateGhostCleanup` 内预写移出——先 `casWrite` 成功、后由调用方 `auditGhostCleanup` 补记；CAS_CONFLICT 时 `_backlog.yml` 不变且 audit.log 零成功记录。回归用例：成功路径恰一条成功审计、幂等不重复、migrateGhostCleanup 源码不含 auditLog、三处调用点均为 casWrite 后补审计。
  - **b10b 开发启动门禁**：新增受控历史审批迁移 `crctl approve <cr> --stage <stage> --resign <reason>`（TTY 人类在环、无旁路）：gates.json evidence 定义变更（dev-start 剔除 task-index）导致既有 approval digest 漂移时，按当前定义重算并只改写该段（保留 approver/approved-at/via/target-status），追加 resign 审计子块与 audit 事件，幂等。回归用例：迁移前 gate 报 EVIDENCE_DRIFT、迁移后 gate 复绿、幂等迁移不破坏、非 TTY 一律 APPROVAL_REQUIRES_HUMAN。
- **developing gate 复验**：b10 迁移机制落库后，CR-2026-027 开发启动审批的 digest 漂移（记录 28db7b7c… vs 复算 fd513fe9…）可由人工执行 `crctl approve CR-2026-027 --stage dev-start --resign "evidence-definition-change（gates.json dev-start evidence 剔除 task-index）"` 闭环（仅限交互式终端）；迁移后 gate 复算即与记录一致，review-code:block 回流不再被 EVIDENCE_DRIFT 拦截。
- **下一步**：人工执行上述 --resign 迁移后重新进入 review-code（回修后需重新代码评审，不再跳过）。
