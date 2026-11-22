# 设计调整说明

> 基线：Phase 2 的 `design.md`、`specs/*/spec.md`、`test-plan.md`。下表汇总 BUILD 已实施调整；尚未实施的候选及风险见 [pending-adjustments.md](pending-adjustments.md)。定向结果见 [test-report.md](test-report.md)，不替代最终同次验证。
>
> **后续勘误**：第 5 项的 clean 日志还含断言失败和未处理异常，不能证明所有失败都是时序问题或排除清单内新回归。文件级例外维持已批准口径；检查器及冻结证据补全为 PA-005，Gate 2 已重签并已定向验证，最终同次证据仍待取得。

> **PA-009 冻结清单修订**：已改动的 `provision.test.mjs`、`ci-evidence.test.mjs` 和 `CUSTOM-LEDGER.md` 补入 `test-plan.md` 的证据输入，既有测试资产表补列 provision；不更改测试选择或业务／安全合同。用户确认后 Gate 2 已经 CLI 重签；调用者审计与原话见 [pending-adjustments.md](pending-adjustments.md)。

> **PA-011（Gate 2 已重签）**：只更新两条现有脚本测试中滞后的固定预期并补入相应冻结路径（定制台账 #392–393）；D2-A/D2-D 的批准值、测试义务和断言强度不变。正式同次证据见 [test-report.md](test-report.md)。
>
> **最终定向修复与验证**：PA-011 的首次正式运行发现检查器失败时截断管道日志。#394 保留退出码 1、等已排队日志写完，不改判定或业务；回归先红后绿。最终 `c7d6ab92-0988-46a8-a526-4cad1e5322e2` 四 CP 通过、C4 完成、回收清零；早前红项与未归因的历史 Views 错误保留在报告。

## 调整汇总

| # | 调整类型 | 涉及设计 | 严重程度 | 阶段 | 影响 TC | 用户已知 |
|---|---|---|---|---|---|---|
| 1 | 夹具供给与后端测试修复 | D2-B/C | Major | BUILD | TC-DQB-001/002 | 是 |
| 2 | Desktop 打包测试恢复 | D3 | Minor | BUILD | TC-DQB-003 | 是 |
| 3 | Chromium 运行历史时序 | D3 | Minor | BUILD | TC-DQB-004 | 是 |
| 4 | 回收 fail-closed：夹具文件为唯一持久记录 | D2-B | Major | BUILD | TC-DQB-001 | 是 |
| 5 | 平台 skip 补全 11→20＋前端上游已知红声明 | D2-D | Major | BUILD | TC-DQB-002/003 | 是 |
| 6 | 前端检查器混合失败与冻结输入补全 | D2-D | Major | BUILD | TC-DQB-003 | 是 |
| 7 | 前端测试 Turbo 包级串行 | D2-D | Major | BUILD | TC-DQB-003 | 是 |

### 1. 受限夹具供给与后端测试修复

- **原始设计**：Go 质量入口隔离 regular/admin/agent，regular 不用管理员凭据，agent 不接收数据库环境。
- **实际调整与原因**：原七例在受限角色下不能创建数据库；由现有 `ci-provision` 提供七份独立已迁移夹具，既有 `backend-tests` 与本地入口遵守同一合同。另更新八组迁移测试文件编号、删重复 Pi 技能参数、保留准备响应的 wire 断言而对运行时对象直接检查。未授予 `CREATEDB`，未改 SQL、owner 分组、生产收尾或访问控制。
- **影响范围与证据**：夹具生命周期、Make/hosted 接线、迁移用例与 Pi 定向通过。未触发 hosted；后续 `fc71831b` 曾执行后端全量，但其前端验收证据不完整，不能替代当前最终同次验证。Tools pin 已按后续单独裁定采用 `71d0587`。

### 2. Desktop 打包测试恢复

- **原始设计**：D3 保留 `pnpm test`；显式 Node 入口和现有打包断言不变。
- **实际调整与原因**：删除 Vite 留在包裹模块正文中的 CLI shebang；同一打包测试按已有惯例声明文件级 Node 环境，避免 jsdom 的 client 转换外置 Node 内建模块。任务口径、全局环境、依赖、测试选择及断言未改。
- **影响范围与证据**：`apps/desktop/scripts/{package,package.test}.mjs`，正常命令定向 30/30；不替代项目 Vitest。

### 3. Chromium 运行历史时序

- **原始设计**：唯一必跑现有 compact/own/subtree 运行历史场景。
- **实际调整与原因**：保留 UUID 初始导航；compact 后、打开对话框前等待同一 issue 的规范编号 URL，避免规范化导航重挂载使对话框消失。不改产品路由、用例断言或超时。
- **影响范围与证据**：`e2e/issue-task-history.spec.ts`，专用环境 1/1、清理完成；正式同次 E2E 仍待执行。

### 4. 回收 fail-closed：夹具文件为唯一持久记录（威胁模型重判＋C1 根因修复）

- **原始设计**：D2-B 外层 down 凭 marker/handle 回收，成功与失败路径逐库核验。
- **实际调整与原因**：用户裁定项目为个人使用、仅防人和 agent 误操作。C1 复核发现环境句柄与持久文件分裂是同一类根因：up 中途失败后环境句柄未发布导致无法重试；跨轮环境主库句柄错配导致误删他轮主库。改为夹具文件作唯一持久回收记录（`fixtures` 映射＋`handles` 主库/夹具句柄），up 随创建增量写入，down 只读文件句柄、逐库重读 marker、全部成功才删文件。删除环境句柄匹配机制与 FIXTURE_HANDLES_ENV，不逐异常加检查。没有恢复先前撤销的夹具消费者库名前缀检查或 MAKEFLAGS 清洗。
- **影响范围与证据**：`ci-provision.mjs` up/downAll、`provision.mjs` 部分回收重试、`isolated_db.go` 只读 `fixtures` 字段及对应测试；属 teardown 既有保证的机制修订，任务 2.22/2.25；Gate 1/2 已于 2026-11-20 12:45 重签并实施。marker 拒删外库/角色、凭据隔离、selector／断言不变；不额外信任未验证的资源名称。

### 5. 平台 skip 补全与前端上游已知红（D2-D）

- **原始设计**：D1 「不改表、不新增许可 skip」；TC-DQB-003 三命令退出 0。
- **实际调整与原因**：完整环境下 regular 0 功能失败，仅 9 条合法平台/helper skip 未登记→用户批准 allowed-skips 11→20；C1 将其中 pwsh 声明限定到实际子例，其他父级 skip 语义不变。前端 Views 六个基线失败文件经用户裁定不动，接受文件级 known-red；日志含断言失败/未处理异常，不能宣称已证明全部是 flake 或清单内无新回归。
- **影响范围与证据**：test-ownership.json +9 已实施、design/spec/test-plan 已同步并重签；backend5 regular 24571 pass/0 fail，前端 clean A/B 仅作历史基线。名单外 skip／集外失败仍红；子例声明边界修复见任务 2.23。

### 6. 前端检查器混合失败与冻结输入补全（PA-005）

- **原始设计**：6 个 Views 文件级例外之外的失败不得放行，完整运行并冻结实际验收输入。
- **实际调整与原因**：旧检查器在已识别清单内失败时可能放行其他任务失败、未处理异常或截断，且本身不在旧 run 冻结输入中。现收集并对账既有 Turbo 汇总与 Views 失败结果，补真实子进程正反例；检查器与测试均纳入证据计划。不改例外集合、上游测试或超时。
- **影响范围与证据**：`frontend-quality.mjs`、`frontend-quality.test.mjs`；Linux Node 22 测试 9/9，受控子进程正反例符合预期。C1 补 Vitest 终结摘要、失败数对账与精确路径匹配（任务 3.5）；另以真实 Vitest 4.1.0 复现一个失败测试多条 FAIL（断言＋afterEach 错误），将 FAIL 行数判定由严格相等改为不少于声明失败数，避免误拒清单内合法失败（同合同实现修复，仅 Gate 3）。最终同次 run 尚未执行。

### 7. 前端测试 Turbo 包级串行（PA-007）

- **原始设计**：检查器通过 `pnpm test` 完整执行测试，只允许已批准的六个 Views 文件失败；其他失败、未处理异常和不完整结果均拒绝。
- **实际调整与原因**：测试调用追加 `--concurrency=1 --continue=always`，减少包间竞争且失败后仍运行其他任务；底层退出及原对账不变。纯上游和候选对照见 `test-report.md`；一次串行诊断不能证明可重复绿。
- **影响范围与证据**：`frontend-quality.mjs` 与对应测试；Gate 2 于 2026-11-20 15:33:26 重签。真实调用参数测试先红后绿，Linux Node 22 定向 11/11；同次四 CP 仍待完成。未改上游测试、超时、例外或 hosted workflow。

## 尚未获批或未解决

> 以下为当前状态汇总（原 PA-001～004 快照已更新）；详细根因与证据见 `pending-adjustments.md`。

- PA-001：Tools main `71d0587` 已采用（用户接受 agent git show 对现有 5 形状开放），Gate 2 已重签、定向复验通过（任务 2.7 完成）。
- PA-002/004：Pi 自然退出 stderr 期限（2.8）与合法 claim 令牌补 owner＋负例期望对齐（2.9）已实施并定向通过。backlog C1–C6 已修（2.11–2.15、2.19），C7/C8 隔离重跑通过（2.16），9 条平台/helper skip 已登记（2.20），downAll fail-closed（2.18）。
- PA-003：Linux 项目 Vitest Desktop 89 文件/1,006 用例全过；Views 六个基线失败文件含超时、断言失败和未处理异常，原因未完全确定。用户裁定不动，接受文件级例外（D2-D）；这不证明清单内无新回归。
- PA-006：回收机制改为夹具文件唯一持久记录（任务 2.25），属 D2-B 机制修订；design/spec/test-plan/proposal 已同步，Gate 1/2 已于 2026-11-20 12:45 重签并实施。前端 FAIL 行数判定为同合同实现修复；提案另同步已批准的 hosted regular 串行与六文件例外可见性（不新增授权）。该项根因、重签和验证见 `phase-context.md` 的 PA-006 两条记录及 `test-report.md`，不在 `pending-adjustments.md` 中另设同名历史条目。
- PA-007：包级串行与失败后完整执行已实施并定向验证；保留六文件例外和全部失败判定，最终同次验证尚未完成。
- PA-010 任务 2.19：用户决定「保留并补入提案」，仅限台账 #373 的四个既有测试文件。已同步提案 C2 和设计 D2-C，未改候选代码、测试选择或验收；该文档差异已由用户确认并经 STDD CLI 分别重签 Gate 1／2。
- PA-010 终验前剩余项：路径别名、Vitest 关闭超时漏判、数据库环境与 claim 负例夹具已修（#386–389）。固定本地正式 `GOFLAGS`、S4 新增 Node 顺序回归和证据冻结、同步已裁定的 claim 期望为同轮设计／测试方案修订，Gate 2 已重签、已实施并定向通过（#390–391）；不改变验收的业务范围或单条 Chromium 用例。
- PA-008：用户接受归属不明时保留并报错、不自动删除；Gate 1/2 已分别重签，现有供给／回收入口已实施。C1 同合同修复进一步绑定有效 PostgreSQL 端点、核验文件内映射及保护凭据／输出路径；后续五类边界及软链接别名修复先 RED 后 GREEN，非 root Linux 关联测试最新 144/144；最终同次真实 PostgreSQL 的拒删与部分回收重试通过，回收后 `0|0`。
