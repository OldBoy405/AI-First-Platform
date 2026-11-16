# SPEC 阶段上下文

- Change：2026-11-15-crctl-report-status-integrity；项目 tools；记录根按业务仓 binding 解析。
- 2026-11-16 用户确认原文：「tools：重审 Gate 1，并确认本轮 Gate 2；multica：确认上述 Gate 1 提案范围，包括第四数暂不收口。」
- Gate 1 重审与 Gate 2 已通过 STDD CLI 分别登记；原批准保留，回执以 CLI 查询为准。本文件不是额外批准或验收证据。

## 已确认决策

- 目录/history 状态在同一边界校验，缺失与类型错误区分；未声明状态明确失败，不新增半成功输出。
- 直方图使用无原型字典，恢复合法动态键正确计数的原承诺。
- report 复用已发布归档事实，保留 history 优先级与 archived/period/sla 原有含义。
- 看板引用 report，不复制状态分类规则。
- 保留六个 Requirement、八个 Scenario；验收为三组自动检查与两项人工核对，不按异常增加独立入口。

## 产出与验证边界

- 提案：canonical/proposals/2026-11-15-crctl-report-status-integrity.yaml；proposal.md 由 CLI 生成。
- 设计：design.md；测试计划：test-plan.md。
- 行为与验证源：canonical/specs/code/、canonical/specs/agent/；两份 specs/*/spec.md 在 Gate 2 由 CLI 生成。
- validate、canon verify、agent verify --dry-run 已通过；这些不证明业务代码实现或验收通过。
- 本阶段未执行产品验收、未修改业务代码、未提交或推送。BUILD 执行模式尚未选择，不自行启动实现。
