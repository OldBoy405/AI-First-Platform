# 设计调整说明

> 变更：`2026-11-18-defensive-trim-multica`。原始基线为 Phase 2 `design.md`、Canonical specs 和 `test-plan.md`；调整来自 BUILD 评审及取证预检。

| 编号 | 调整类型 | 涉及文档 | 严重程度 | 阶段 | 影响 TC | 用户已知 |
|---|---|---|---|---|---|---|
| PA-001 | 同次取证输入修订 | `test-plan.md`、`design.md`、`canonical/specs/agent/ci-backend-environment.yaml` | Major（Gate 2 受审输入） | BUILD | 原 6 个 TC | 是，Gate 2 已重审 |
| PA-002 | 增加测试修复的冻结输入 | `test-plan.md` | Major（Gate 2 受审输入） | BUILD | 原 6 个 TC 不变 | 是，Gate 2 已重审 |

## PA-001：把实际选择和运行输入纳入证据

- **原始设计**：`test-plan.md` §六规定按 selection 的 `expected` 对账；预检时冻结清单未包含该 selection 文件及本轮改动的部分执行输入。
- **调整内容与原因**：现有清单增加 11 项（24 → 35），包含 selection、runner 入口、Tools pin 和其余 8 个改动的 Go 输入；不增加第二套验证机制。同步 S5 测试入口与 CBE 用例计数；原 6 个 TC/CP、业务保证和隔离边界不变。参见 [pending-adjustments.md](pending-adjustments.md)。
- **用户确认**：按原话「确认 PA-001 修订后的 Gate 2」，以 STDD CLI 重审。之后补齐原规格的坏详情矩阵，并在 TC-RUN-201 现有 selection 内对账 3 个已存在的生产 HTTP 拒绝用例。
- **验证**：[`a9eb2552-7233-419a-b476-b9daf95053a6`](validation/runs/a9eb2552-7233-419a-b476-b9daf95053a6/agent-verification-report.md) 冻结全部 35 项，6 个 CP 均通过。经验 `EXP-2026-0012`。

## PA-002：冻结新增测试修复

- **原始设计**：`test-plan.md` §六要求冻结本次修改的运行与测试输入；原清单有 35 项，不含后续授权修改的工作区并发测试。
- **调整内容与原因**：增加 `server/internal/handler/workspace_delete_concurrent_test.go`，清单变为 36 项，使后续取证能绑定该测试文件；台账仍不作为执行输入，6 个 TC/CP、业务保证和质量标准不变。
- **用户确认**：用户授权「授权将该测试文件加入冻结清单」，并明确回复「确认 PA-002 修订后的 Gate 2」；CLI 已重审 Gate 2。
- **验证与状态**：完整后端质量检查已在包含该测试修改的候选上通过；此前 35 项输入的 run 不包含该文件。官方预检 exit 0；新 run [`d6390f73-b7f7-4750-8369-b60d37526b95`](validation/runs/d6390f73-b7f7-4750-8369-b60d37526b95/tc-evidence.json) 冻结 36 项，6/6 CP 通过，同 run 自动化 C4 9/9，人工 C4 见 [test-report.md](test-report.md)。

项目级检查环境的限制不是设计调整，也未获豁免；单列在测试报告中。
