# Spec: ci-backend-environment

> Change: 2026-11-12-fork-ci-test-evidence-trust | Auto-generated Human View

## Requirements

### Requirement: fork CI 的 backend-tests 为 nonce 门禁包提供真实的一次性库，且门禁每个拒绝条件都被独立测试；不放宽 nonce 门禁。

#### Scenario: SC-CBE-001

- **GIVEN** 给定一个可连接的 Postgres 管理员 URL（本地用注入的假连接），
- **WHEN** 执行 ci-provision up 再 down，以及 up 未完成时执行 down。
- **THEN** SHALL 由 up 用既有 createDisposableDatabase 建出符合 TestMain 全部身份检查的库与角色（库名 aifi45_tmp_<nonce>、角色 aifi45_role_<nonce>、库与角色 marker、非超级用户），并把 DATABASE_URL、AIFI45_DISPOSABLE_NONCE 写入环境文件且先对口令发出 ::add-mask::；SHALL 由 down 在 marker 匹配时删除库与角色；marker 不符 SHALL 拒绝删除并非 0 退出。
- **AND** handle 缺失（up 在写出前失败）时 down SHALL 以 0 退出并说明无资源可清理。
- **AND** 任何日志、stdout/stderr 与 handle 文件 SHALL NOT 含明文口令；GITHUB_ENV 中的 DATABASE_URL 承载 job 级一次性角色口令，写入前 SHALL 先对该口令发出 ::add-mask::，且该口令 SHALL NOT 被复用于任何非一次性资源。

#### Scenario: SC-CBE-002

- **GIVEN** cmd/server 与 governance 各自的 verifyDisposableTestDatabase，
- **WHEN** 对 nonce 格式、库名、角色名、session_user 不等于 current_user、库非所有者、库 marker、角色 marker、superuser、createdb、createrole、bypassrls 逐条单独构造失败。
- **THEN** SHALL 每一条单独退化都被拒绝，且该条件由独立命名的子测试逐条归因；合法的 nonce 库 SHALL 通过。
- **AND** 该测试 SHALL 在 runner 自建一次性库内真实执行，skip 为 0 且至少一个叶子 PASS。
- **AND** 门禁本身 SHALL NOT 被放宽。

### Requirement: tools 依赖只有一个 pin 来源；CI 与本地不依赖开发机路径；缺依赖是失败而不是 skip。

#### Scenario: SC-CBE-003

- **GIVEN** 仓库存在 .github/aifirst-tools-pin（单行 40 位 hex），ci.yml 的两个消费者从它读取 ref，
- **WHEN** 运行 tools-pin 的 read 与 check：pin 文件合法或非法，检出目录缺少 execution-control-protocol.mjs、control-vectors.json 或 crctl.mjs 之一。
- **THEN** SHALL read 对非 40 位 hex 或多行文件硬失败；SHALL check 在任一必需文件缺失时非 0 退出并打印 pin 与缺失文件名；全部存在时 SHALL 退出 0；ci.yml 中 SHALL 不再出现 tools 的字面 commit。
- **AND** 对 ci.yml 字面 ref 的检查 SHALL 逐行解析（split(/\r?\n/)），解析失败硬失败。

#### Scenario: SC-CBE-004

- **GIVEN** server/internal/governance 与 crosslang_test 下的 *_test.go，
- **WHEN** 静态契约检查：搜索 C:/Users/ 开发机绝对路径，以及依赖 AIFI45_TOOLS_ROOT 或 CRCTL_MJS 的测试在环境变量缺失时的处理。
- **THEN** SHALL 源码中不含开发机绝对路径默认值；SHALL 缺失 CRCTL_MJS 或 AIFI45_TOOLS_ROOT 的测试以 Fatal 结束而不是 Skip；契约检查本身 SHALL 能对注入了旧默认路径或 t.Skip 的样例变红。

#### Scenario: SC-CBE-005

- **GIVEN** CI 的 backend-tests 在修复后的 ci.yml 下运行（需推送授权与 tools pin 可用，见 design U1），
- **WHEN** 查看该 run 的 Test 步骤与 ci-evidence 步骤。
- **THEN** SHALL cmd/server、governance、crosslang_test、handler 各自有通过的测试且无名单外 skip；若走 U1 路径 β（tools 未推送），SHALL 如实记录 tools 相关测试未验证并使 pin 完整性检查失败，不得 skip 或报绿。
- **AND** 验收报告 SHALL 记录 run id、commit、各 job 结论。
<!-- merged 2026-11-16 from 2026-11-16-multica-execution-evidence-closure: appended SC-MEC-005/006/007; original requirements preserved -->

### Requirement: backend-tests 从唯一已发布 pin 加载权威 rules.json；缺规则文件在既有 pin 完整性入口失败，不能落回 fixture。

#### Scenario: SC-MEC-005

- **GIVEN** pin 为 7a0a2ab57f3f5e2c583c3523bc69d67e7be115c1，两个消费者仍读取该 pin；tools-pin 的必需文件增加 skills/shared/controlled-shell/rules.json
- **WHEN** 运行既有 tools-pin 和 ci-scope 离线测试，分别检查完整/缺文件夹具、两个 checkout 与 backend job env/step 顺序
- **THEN** SHALL 完整四文件夹具通过，缺任一文件非零并点名 pin/路径；backend env 的规则路径为同一 pinned checkout，pin-check 在 Test 前；两个消费者不含 main/字面 SHA 旁路
- **AND** 保留凭据诊断早于 checkout、受限一次性 DATABASE_URL、既有事件流/admin 对账及 always teardown；不新增 job、依赖或 overlay
- **AND** 规则 env 使用 github.workspace 的明确路径，不使用不能在 YAML env 中自动展开的 $AIFI45_TOOLS_ROOT 字面串
- **AND** 两个生成器只执行 --check，合同漂移即停止报告，不修改生成物/digest；callers 和 Git 对象类型既有边界不变

### Requirement: 最终业务提交的实际 CI 执行成功并证明六个既有快照测试实际读取权威规则，是权威目标合同；本地/fixture/skipped/自动 N/A 不能替代。本轮因平台账单/额度阻塞经用户明确裁定延期（TC-MEC-003 记 not_applicable，接受风险），权威 CI 验证仍未完成，额度恢复后另行验证。

#### Scenario: SC-MEC-006

- **GIVEN** 取得独立提交/push 和 CI 执行授权，实际 run 的 headSha 对应最终交付业务提交，pin 已发布且账单/凭据可用
- **WHEN** 人工核对同一实际 CI 的 metadata、backend-tests 及原始测试/对账流，不为每条断言重跑
- **THEN** SHALL backend-tests、pin 完整性及其 Test/共享与管理员证据对账实际执行成功；六个指定快照测试均有 pass，TestProposedSnapshotReadShapes 的真实 rules.json 加载日志出现；记录 run id/headSha/pin/job/结论
- **AND** 六个名称精确为 TestM26B2TestFactsPayload、TestM26B2TestFactsPreserveFailures、TestM26B4CollectorKeepsBothReviewStages、TestM26B4ScanEmitsIndependentTestEvent、TestM26B4ScanTestOnlyAndReviewOnly、TestProposedSnapshotReadShapes
- **AND** transitions-contract-check 的两生成器 --check 实际通过；不能用它的成功替代 backend-tests 或规则加载事实
- **AND** 本轮经用户明确裁定延期：实际 CI 因账单/额度阻塞（run 43752944966 runner_id=0、六测试 skipped，未启动有效执行），TC-MEC-003 记为 not_applicable（接受风险）并如实保留未验证与阻塞原因，不冒充通过、不继承旧 change 豁免；非用户裁定的自动 N/A 仍禁止，额度恢复后另行验证以满足本场景全部 SHALL

### Requirement: 本次定制与当前前三数可追溯，第四数明确未决；计数和历史记录不是产品验收结果。

#### Scenario: SC-MEC-007

- **GIVEN** 本次业务 diff、对应 STDD change/任务与验证事实，以及 CUSTOM 当前表结构
- **WHEN** 一次人工核对模块索引/CR索引/明细，并按明确的 git 跟踪文件与匹配行口径追加当前基线
- **THEN** SHALL 登记准确覆盖本次定制、真实流程标识、上游挂钩与 fork 文件边界；前三数带实际 tree/HEAD、时间及差值说明；第四数明确未决/本次未测，不沿用 314 冒充测量
- **AND** 统计范围仅 server/packages 的 .go/.ts/.tsx/.sql/.mjs，文件数及匹配行用 AIFIRST|CR-2026-[0-9]{3}，第三数用 AIFIRST；一行多次命中只计一次
- **AND** 保持 CUSTOM 的 CRLF、稳定明细 ID 与历史记录；计数下降按实际变动解释，不以单调增长作为正确性保证
- **AND** 未提交新增文件只说明为未计入，交付后按真实跟踪树核对；不擅自 stage 来改变测量范围，不修改归档
