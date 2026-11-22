# 恢复 Multica 交付质量基线 — 测试方案

> 日期：2026-11-19。对应 `ci-backend-environment`、`ci-credential-and-frontend-typecheck` 的 Canonical 行为规格。

## 一、测试策略

单元契约用现有 Go wrapper shell 夹具；前端用现有 ESLint、TS 类型检查与 Vitest；后端用现有 Go race 路由、所有权对账与独立管理员库测试；E2E 仅一条真实运行历史场景。不再分别重跑相同检查来填质量门或证据计划。记录命令、正向观测和退出码，不以「无匹配但退出 0」为成功。

| 已有资产 | 保留覆盖 |
|---|---|
| `scripts/test-go.test.sh`、`scripts/aifi45-disposable/{ci-evidence,test-ownership,ci-provision,provision}*.mjs`、`scripts/ci-scope.test.mjs` | 包过滤、退出传播、owner、一次性角色／每例夹具、hosted 接线与回收。 |
| `TestRealRulesPrepareSurface`、execenv 准备、现有 Tools crctl 规则与 report 回归 | 换 pin 到 `71d0587` 后在其干净检出上定向验证真实合同与已知副影响，不用于替代正式检查。 |
| `server/cmd/migrate/migrate_workspace_seam_test.go`、agent 现有技能参数用例、`TestPiSkillDeliveryIdentitySurvivesPreparation` | 保留真实迁移与回滚断言；Pi JSON/RPC 显式路径只传一次且保序，OMP 原发现不变；实际准备响应和运行时选项中的交付身份、路径、内容摘要与清空断言均执行。 |
| `TestPiCleanupDetachedTool`、`TestPiCleanupSuccessfulBackgroundServiceSurvives`、`TestPiExecuteReportsRefusedResume`；`execution_start_claim_test.go`、`execution_task_claim_project_test.go` 及其终态/围栏负例 | Pi 自然退出 stderr 期限后：活动工具被回收、成功后台服务留存、resume 拒绝诊断可读；claim 合法令牌补 owner 后到达 stale-generation 判定；外部/空身份令牌保留无 owner，先前单独裁定的 start/terminal 对应负例期望现行 404 掩蔽，`ownership_change` 仍为 409，跨 workspace 权限及拒绝、零写入断言保留。 |
| `packages/views` 的组件用例、`packages/ui/icons/icons.test.ts`、`apps/desktop/scripts/package.test.mjs` | 保留图标与按钮行为覆盖、图标目录一致性；打包文件必须收集并执行既有用例，不用空测试通过。 |
| `e2e/issue-task-history.spec.ts`、`e2e/issue-task-history-trigger.mjs`、`scripts/aifi45-disposable/issue-task-history-trigger.test.mjs` | Node 测试验证精确匹配同一 issue 规范路径且等待完成前不定位 Runs 按钮；一条 Chromium 用例保留 UUID 入口的 compact 及 own/subtree 的真实响应断言。 |

## 二、详细测试案例

#### 案例 1：后端入口接线

| 字段 | 内容 |
|---|---|
| **ID** | TC-DQB-001 |
| **对应 Spec** | SC-DQB-CBE-001 |
| **优先级** | P0 |
| **预置条件／输入** | 用既有 shell/Node 夹具验证实际 Make 配方、`ci-provision` 和 hosted 接线（只选 `ci-scope.test.mjs` 内既有 backend-tests 生命周期用例）：完整输入、缺 nonce、缺失／重复夹具、夹具部分创建失败、注入 Go 非零；检查空 GOFLAGS 及调用方带选测 GOFLAGS 时的本地三组参数，并注入 `PG*`／`POSTGRES_*` 哨兵检验隔离。PA-008 在现有生命周期测试注入首写失败、创建后记录更新失败叠加回滚失败、创建结果不明时暂未发现对象、同 nonce／marker 既有对象、指定记录缺失或无效、库／角色 marker 不匹配、已删库后的角色重试；分别验证未指定夹具文件的原路径。另在一次本轮隔离 PostgreSQL 中核实真实角色 marker、未确认对象拒删和清理重试。 |
| **预期结果** | 三组各一次；本地三组固定 `GOFLAGS=-count=1 -mod=readonly`，regular 独有 `-p=1`；hosted 仍基于既有 job GOFLAGS 追加 regular `-p=1`。保留原 selector、race、skip、失败语义和 admin/agent 并发。管理员 DSN 仅用于外层或既有 admin 测试，本地清除继承的 `PG*`／`POSTGRES_*`；regular 只获受限连接，agent 无测试库／nonce／Redis；所有夹具绑定独立且不回退；缺必需输入零执行，注入失败保持红。首份记录未成功写入时零创建；后续更新失败保留上次完整记录，创建前有 `reserved` 身份、成功后有 `confirmed` 身份；`fixtures` 保持原映射格式且记录／临时文件保护密码。指定记录缺失、无效或必需身份缺失硬失败，不消费环境句柄；`confirmed` 身份的现存库／角色 marker 全部匹配后才可删除任一对象并可部分重试，`reserved` 无论 marker 相同或暂未发现对象均不得自动删除，须保留记录并失败，避免把尚在进行的创建误当已结束。全部身份无残留才移除记录；未指定 `--fixtures` 的原路径不变。测试实际断言并输出从观测计算的 `PA008 recovery: reserved=1 uncertain-drops=0`，CP 同时要求原 `test-ci wiring` 和 `test-ci fixtures: required=1 regular-only=1` 信号及 exit 0。真实 PostgreSQL 核实拒删、部分重试与资源回收；不以 fake 客户端代替。 |

#### 案例 2：全量后端结果

| 字段 | 内容 |
|---|---|
| **ID** | TC-DQB-002 |
| **对应 Spec** | SC-DQB-CBE-002 |
| **优先级** | P0 |
| **预置条件／输入** | 在非 root Linux 干净候选用锁定 Go/Tools、已迁移主库和本轮七个独立预置夹具、既有管理员环境运行实际正式入口。换 pin 时预先绑定单独采用授权、候选 SHA 与真实规则/crctl 定向验证。 |
| **预期结果** | regular 包级串行下 `make` exit 0；5 个必需包对账、20 条许可 skip（11 原有＋9 平台/helper 补全，见 D2-D）保持、管理员 3/3、agent package `pass`。核实七个夹具案例、迁移 seam、Pi 参数用例确有终结 `pass`；同 run 记 Tools 提交、常规/夹具迁移及每库/角色回收。缺执行、未回收、超时、失败或名单外跳过均非通过；串行不替代前端与其他 CP 的结果。 |

#### 案例 3：前端质量及按钮行为

| 字段 | 内容 |
|---|---|
| **ID** | TC-DQB-003 |
| **对应 Spec** | SC-DQB-CCF-001 |
| **优先级** | P0 |
| **预置条件／输入** | 对锁文件安装后的干净候选，先执行 `node --test scripts/aifi45-disposable/frontend-quality.test.mjs`，再通过检查器依次运行 `pnpm lint`、`pnpm typecheck`、`pnpm test --concurrency=1 --continue=always`。仅本次测试任务包级串行；测试选择、断言及超时不变。 |
| **预期结果** | 检查器测试 SHALL 验证实际传给 pnpm 的 test 参数，并覆盖全通过、仅清单内文件失败、清单外失败、清单内失败与其他失败并存、进程异常及 Vitest 未处理异常；仅前两种测试结果可放行，混合失败负例输出 `TC-DQB-003: mixed failure remains red`。`pnpm lint`、`pnpm typecheck` 退出 0，实际执行 `@multica/views` 三个任务；0 lint errors；presenter 按钮可按可访问名称找到并保持原动作。测试任务须完整执行，`pnpm test` 的可归属失败用例 SHALL 全部落在 D2-D 声明的 6 个 Views 文件内；其他任务失败、未处理异常、异常退出或结果不完整 SHALL 使检查失败。文件级例外不证明清单内无新回归；不改上游测试/产品、不放宽规则、不调超时来消除红项。 |

#### 案例 4：运行历史 E2E

| 字段 | 内容 |
|---|---|
| **ID** | TC-DQB-004 |
| **对应 Spec** | SC-DQB-CCF-002 |
| **优先级** | P0 |
| **预置条件／输入** | 先执行 `node --test scripts/aifi45-disposable/issue-task-history-trigger.test.mjs`，再在本次自建 web/backend 与独立一次性库执行指定的单一 Chromium spec。 |
| **预期结果** | Node 验证区分 UUID、其他路径及同一 issue 的规范路径，定位按钮不得早于等待成功。Chromium 实际执行一个用例且 1 pass、0 fail/skip；验证 compact、own、subtree 内容与请求范围，不扩大业务端点的 E2E。 |

## 三、测试执行矩阵

| 区域 | 单元／契约 | 项目集成 | 浏览器 |
|---|---|---|---|
| 后端入口 | 001 | 002：regular、admin、agent 与两个对账 | — |
| 前端质量 | 003：lint、typecheck、Vitest | 003：presenter 现有行为 | 004 |

外层 CI 生命周期由原有 helper 执行并记录 `up`、迁移、`down`/process cleanup；当前候选的投产质量结论需要 4 项通过且本次自建资源已回收。保留侧重点不同的已有独立测试 owner，不把未跑此类测试记成已跑。正式验收不跨运行拼接；本轮新变更与原精简变更各自有自己的证据和质量结果。

## 四、回归风险矩阵

| 风险 | 保护 | 风险 |
|---|---|---|
| 进入已有环境，admin 权限扩散到其他 Go 用例，或某 suite 漏跑 | CI job 边界 + stub 入口合同 + 真实事件对账；不检查两套身份。 | 高 |
| 正式基线与本地样本失败类别不同 | 干净非 root 代表性环境；重用红项日志，不改未复现失败或托管 CI 合同。 | 高 |
| 图标替换抹平状态或按钮无法识别 | 状态语义及交互不变，目的明确的按名称断言。 | 中 |
| Playwright 意外复用进程、路径未收集 | 新建专用资源，绑定显式地址，输出固定用例名与 1 pass。 | 中 |

## 五、执行顺序

1. 复用已完成的非 root Linux 红基线、原夹具接线与迁移/Pi argv 定向证据。用户已裁定采用 Tools main `71d0587` 并接受 agent git show 对现有 5 形状开放；换 pin 后在该提交干净检出上定向复验真实规则 allow/deny、execenv、crctl 多条目合并与 report 回归，不重跑已知红的后端全量。对本次三处调整只跑各自的既有检查：Desktop 打包 Vitest 文件、Go `TestPiSkillDeliveryIdentitySurvivesPreparation`、专用栈的唯一 Chromium spec。分别证明原打包断言实际执行、身份及清空断言通过、compact/own/subtree 原断言通过且资源回收。另跑 Pi 自然退出 stderr 期限的三个现有清理/诊断用例，以及 claim 合法令牌补 owner 后的定向用例（含原有负例）。其余红项仍只定向归因，不改跳过、超时或放宽断言。
2. 同一最终候选先执行既有 `pnpm test:scripts`；应全绿。既有 pin 测试精确断言 D2-A 已批准的 `71d05871a3f937f29a7f68fbf5b022741ab242e8`；现有允许跳过名单测试精确断言 D2-D 已批准的 20 条，并保留理由与实际用例可解析断言。不调整 pin、名单或运行选择。随后在一个 `stdd agent verify ci-backend-environment --change 2026-11-19-delivery-quality-baseline --run <id>` 中完成 001–004。环境先准备；若命令失败，取证如实红，修复后只用最终候选的完整 run 申请 Gate。运行阶段固定 `CI=1`，前端重跑任务而不是恢复旧 Turbo 结果。
3. 对同 run 执行 `stdd ci check-failures ... --run <id>`；保留现有 Go 事件流、资源生命周期日志及前端/E2E 的 CP 观测和 runner 已产出日志，不另跑一遍取日志。禁止凭据进入日志或记录仓。新改文件须进入候选和实际冻结清单；已声明目录按实际内容冻结，不得混入运行产物。

## 六、同次执行证据计划

Go/TS/Playwright 不使用 pytest-cov；不宣称覆盖率保证。冻结工作流/配置/入口、已声明后端源码与夹具、生命周期及 hosted 接线测试。外部 Tools 不在 STDD `project` / `data` 两根，不冒充直接冻结：冻结单一项目 pin 文件，记录候选与正式 run 中核对的同一完整 SHA、实际干净 Tools 检出和定向结果。夹具映射是固定用例合同；临时 DSN/密码、依赖安装产物和本轮临时资源不进入冻结或记录仓。全项目运行额外记录干净基点、候选差异、运行环境与真实结果；若任何计划外受影响路径未被已批准冻结范围覆盖，先按 revision 裁定，不声称该路径已有绑定证据。

```stdd-evidence-plan-v1
{
  "task": "ci-backend-environment",
  "tasks": ["ci-backend-environment", "ci-credential-and-frontend-typecheck"],
  "coverage": {"applicability": "not_applicable", "reason": "Go、TypeScript 与 Playwright，不适用 pytest-cov；无覆盖率保证。"},
  "inputs": [
    {"root": "data", "path": "config.d/quality.yaml"},
    {"root": "project", "path": ".github/workflows/ci.yml"},
    {"root": "project", "path": ".github/ci-paths.json"},
    {"root": "project", "path": ".github/aifirst-tools-pin"},
    {"root": "project", "path": "Makefile"},
    {"root": "project", "path": "CUSTOM-LEDGER.md"},
    {"root": "project", "path": "scripts/aifi45-disposable/ci-provision.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/ci-provision.test.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/frontend-quality.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/frontend-quality.test.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/provision.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/provision.test.mjs"},
    {"root": "project", "path": "scripts/ci-scope.test.mjs"},
    {"root": "project", "path": "scripts/ci-scope.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/ci-evidence.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/ci-evidence.test.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/test-ownership.json"},
    {"root": "project", "path": "scripts/aifi45-disposable/test-ownership.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/test-ownership.test.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/instance.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/tools-pin.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/tools-pin.test.mjs"},
    {"root": "project", "path": "scripts/go-test-with-agent-cli-guard.sh"},
    {"root": "project", "path": "scripts/test-go.sh"},
    {"root": "project", "path": "scripts/test-go.test.sh"},
    {"root": "project", "path": "server/cmd"},
    {"root": "project", "path": "server/internal"},
    {"root": "project", "path": "server/pkg"},
    {"root": "project", "path": "server/migrations"},
    {"root": "project", "path": "server/go.mod"},
    {"root": "project", "path": "server/go.sum"},
    {"root": "project", "path": "server/sqlc.yaml"},
    {"root": "project", "path": "package.json"},
    {"root": "project", "path": "pnpm-lock.yaml"},
    {"root": "project", "path": "pnpm-workspace.yaml"},
    {"root": "project", "path": "turbo.json"},
    {"root": "project", "path": "apps/desktop/scripts/package.mjs"},
    {"root": "project", "path": "apps/desktop/scripts/package.test.mjs"},
    {"root": "project", "path": "packages/views/package.json"},
    {"root": "project", "path": "packages/views/eslint.config.mjs"},
    {"root": "project", "path": "packages/eslint-config/base.js"},
    {"root": "project", "path": "packages/eslint-config/icon-button-name.js"},
    {"root": "project", "path": "packages/ui/icons/index.ts"},
    {"root": "project", "path": "packages/ui/icons/glyphs.ts"},
    {"root": "project", "path": "packages/ui/components/common/icon-button.tsx"},
    {"root": "project", "path": "packages/views/governance/spec-trace/spec-trace.tsx"},
    {"root": "project", "path": "packages/views/inbox/components/container-jump-banner.tsx"},
    {"root": "project", "path": "packages/views/projects/components/cr-gate-card.tsx"},
    {"root": "project", "path": "packages/views/projects/components/discussion-pane.tsx"},
    {"root": "project", "path": "packages/views/projects/components/project-chat-panel.tsx"},
    {"root": "project", "path": "packages/views/projects/components/project-chat-panel.test.tsx"},
    {"root": "project", "path": "packages/views/projects/components/project-private-ask.tsx"},
    {"root": "project", "path": "packages/views/projects/components/project-queue-bar.tsx"},
    {"root": "project", "path": "packages/views/projects/components/project-team-agent-chat.tsx"},
    {"root": "project", "path": "packages/views/skills/components/market-page.tsx"},
    {"root": "project", "path": "packages/views/skills/components/skill-market-card.tsx"},
    {"root": "project", "path": "apps/web/next.config.ts"},
    {"root": "project", "path": "apps/web/package.json"},
    {"root": "project", "path": "playwright.config.ts"},
    {"root": "project", "path": "e2e/env.ts"},
    {"root": "project", "path": "e2e/fixtures.ts"},
    {"root": "project", "path": "e2e/helpers.ts"},
    {"root": "project", "path": "e2e/issue-task-history.spec.ts"},
    {"root": "project", "path": "e2e/issue-task-history-trigger.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/issue-task-history-trigger.test.mjs"}
  ],
  "checks": [
    {"tc": "TC-DQB-001", "case_id": "entry-contract", "requirement": "REQ-DQB-CBE-001", "scenarios": ["SC-DQB-CBE-001"], "kind": "command", "cp": "CP-DQB-001", "applicability": "required"},
    {"tc": "TC-DQB-002", "case_id": "go-ci", "requirement": "REQ-DQB-CBE-002", "scenarios": ["SC-DQB-CBE-002"], "kind": "command", "cp": "CP-DQB-002", "applicability": "required"},
    {"tc": "TC-DQB-003", "case_id": "frontend", "requirement": "REQ-DQB-CCF-001", "scenarios": ["SC-DQB-CCF-001"], "kind": "command", "cp": "CP-DQB-003", "applicability": "required"},
    {"tc": "TC-DQB-004", "case_id": "run-history", "requirement": "REQ-DQB-CCF-002", "scenarios": ["SC-DQB-CCF-002"], "kind": "command", "cp": "CP-DQB-004", "applicability": "required"}
  ]
}
```
