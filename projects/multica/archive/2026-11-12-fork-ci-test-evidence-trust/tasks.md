# fork CI 与测试证据可信性修复 — 任务清单

> change：`2026-11-12-fork-ci-test-evidence-trust`｜切片顺序与风险见 `slices.md`｜TC 映射见 `test-plan.md`
> 每个任务完成后勾选；勾选前必须通过 B3.4 切片验证（TC 覆盖 + 产出物核对 + 测试通过）。

## 1. selection-reconciliation（P0，Slice 1）

- [x] 1.1 写 `selection-decision.test.mjs`：用 `verifyGoTestSelection` 真实返回值覆盖 matched / 非 matched / EXPECTED_INVALID（TC-SEL-001、TC-SEL-003），确认 RED
- [x] 1.2 实现 `selection-decision.mjs::decideSelection`，确认 GREEN
- [x] 1.3 `run-selection.mjs` 改为调用 `decideSelection`，删掉不存在的 `.matched`/`.blocked` 读取；未配置 `expected` 的输出行逐字不变（TC-SEL-002）
- [x] 1.4 变异验证：把 blocked 判断改回旧写法，对应单测必须变红；恢复后复跑，证据记入 `validation/`
- [x] 1.5 `run-selection.test.mjs` 与 `selection.test.mjs` 既有断言全部保持通过且不被改弱

## 2. ci-backend-environment / tools pin（P0，Slice 2）

- [x] 2.1 写 `tools-pin.test.mjs`：read 对非 40 位 hex/多行硬失败；check 缺任一必需文件非 0 并打印 pin 与缺失名；`ci.yml` 无字面 tools commit（逐行 `split(/\r?\n/)`）（TC-CBE-003），确认 RED
- [x] 2.2 新增 `.github/aifirst-tools-pin`（单行 40 位 hex）与 `tools-pin.mjs`，确认 GREEN
- [x] 2.3 `ci.yml` 两处 tools 检出改为先读 pin 再 `actions/checkout`，加 pin 完整性检查步骤（上游文件，标 `AIFIRST`）
  - 口径澄清：核实后 `ci.yml` 当前只有 **1 处** tools 检出（`transitions-contract-check`），已改为读 pin 并加完整性检查。第二个消费者 `backend-tests` 的 tools 检出尚不存在，由 Slice 13 新建并读同一 pin（见 13.x）。非设计偏离。
- [x] 2.4 核实 pin 目标提交在 origin 上是否存在；未推送则如实记"CI tools 相关测试未验证"，不 skip、不报绿（依赖 U1 推送授权）
  - 结论：pin = `e52b8081f159d581bf62f82447c76f818fc52426`（tools 本地 HEAD），`origin/main` = `f774ffb30770659cab31dcd72a413d872a78e4da`，**该提交未推送**。CI tools 相关测试记为**未验证**，推送前真实 CI 的 tools 检出必然失败。未推送任何内容。

## 3. ci-backend-environment / 环境契约（P1，Slice 3）

- [x] 3.1 写 `go-test-env-contract.test.mjs`：扫描开发机绝对路径、缺 `CRCTL_MJS`/`AIFI45_TOOLS_ROOT` 时须 Fatal 而非 Skip；对注入旧写法的样例必须变红（TC-CBE-004），确认 RED
      → 11 项测试；RED 另用真实改前状态取证（沙箱 + `git show HEAD:` 覆盖 4 文件 → `4 violation(s) in 118 file(s)`，退出 1），见 `validation/s3-env-contract/red-before-fix.txt`
- [x] 3.2 删 `execution_authorization_test.go`、`execution_authorization_revoke_interop_test.go`、`execution_trust_install_test.go` 三处 `CRCTL_MJS` 开发机默认值，缺失即 `t.Fatalf`
      → 实现用 `t.Fatal`（无格式参数，故不需要 `f` 变体）；SC-CBE-004 原文要求「以 Fatal 结束」，口径一致，非设计偏离
- [x] 3.3 `execution_binding_issue_test.go` 的 `t.Skip` 改 `t.Fatal`，与同类测试一致
- [x] 3.4 确认 GREEN，并跑受影响包的既有测试无回归
      → 真实扫描 `118 file(s), 0 violations` 退出 0；11/11 PASS；目录全量 86 PASS/0 fail/0 skip；`go vet ./internal/governance/` 退出 0（0 字节）。
      **改后守卫的运行时行为未观测**：governance `TestMain` 无一次性 `DATABASE_URL` 即退出 1，推迟到 S4/S7 实跑验证。
      范围外 5 处 skip 已上报未改（`CRCTL_PATH`、node、git init、知识库凭据、人工 Windows 探针），见 S3 README。

## 4. test-ownership-and-ci-reconciliation / 基线与归属表（P0，Slice 4）

- [x] 4.1 运行前后核对 `podman ps -a`，经 `run-selection.mjs` 自建一次性实例跑整包基线（governance / cmd/server / handler / daemon / crosslang_test），记录每个失败与 skip 及证据
  - 证据：`validation/s4-baseline-ownership/{podman-before,podman-after,baseline-run}.txt`、`events/*.{ndjson,json}`、`events/classification.txt`、`baseline-findings.md`
  - 结果：5 个 selection 各用独立一次性数据库，**8645 pass / 75 fail / 135 skip**，runner exit 1；前后清单去表头后逐字节相同，`multica-postgres`/`multica-backend` 全程 Exited、卷未触碰，`released instance 48d027ce582a remaining=0`
  - 逐项定性：29 个顶层失败 / 75 帧分 6 类（A 状态敏感 3、B Windows 时钟粒度 2、C manifest 缺口 1、D tools 契约缺口 6、E Windows-only 16、F 未定性 1）；135 个 skip 中 46 个 Redis 缺失 + 86 个平台守卫均**不声明**
  - 为取证新增 `--evidence-dir`（改前 runner 丢弃 `-json` 流，无法逐项取证）；弱 RED 已如实记录（`parseArgs` 静默忽略未知参数）
- [x] 4.2 定位 `TestMTick003` 挂住原因（design 未验证事实 #2），按判定树处理：环境→修、真实缺陷→修或上报、仅慢→写设计调整
  - 证据：`validation/s4-baseline-ownership/mtick003-elapsed.txt`（取自 `events/baseline-governance.ndjson`）
  - 结论：`pass TestMTick003 elapsed=0.06` —— **无挂住、无超时**，不属环境失败也非真实缺陷；不需要改超时，无需设计调整。design 未验证事实 #2 就此关闭
- [x] 4.3 写 `test-ownership.test.mjs`：check 对不存在/缺 reason/重复条目非 0 并指名；skip-regex 输出 `^(A|B|…)$` 且转义元字符（TC-TOR-001），确认 RED
  - RED：`red-test-ownership.tap`（检查器不存在，`ERR_MODULE_NOT_FOUND`，1 tests / 0 pass / 1 fail）
  - GREEN：`green-test-ownership.tap` **16 tests / 16 pass / 0 fail / 0 skipped**
  - 精度：整名匹配（`TestAlphaExtended` 不满足 `TestAlpha`）、元字符转义（`TestA.B`/`TestC+D`/`TestE(x)`）、CRLF 归一化、`""`/`null`/`undefined`/`42` → `throw`、空/坏 JSON 对两个命令都硬失败、缺目录或包内无 `*_test.go` 报"无法核实"
  - 变异：`mutation-typo-entry.txt`（拼错名 → exit 1 点名）、`mutation-allowed-skip-pin.txt`（删一条声明 → 钉住用例红；真实表按 sha256 逐字节还原）
- [x] 4.4 新增 `test-ownership.json`（初始 3 项：`daemon.TestChannelIsolation`、`governance.TestChannelMigrationAfterDown`、`TestChannelMigrationAfterReapply`）与 `test-ownership.mjs`，确认 GREEN
  - 真实 `check` exit 0：`test ownership OK: 4 entry(ies)` + `allowed skips: 4`（`real-ownership-check.txt`）
  - `skip-regex` = `^(TestChannelIsolation|TestChannelMigrationAfterUp|TestChannelMigrationAfterDown|TestChannelMigrationAfterReapply)$`
  - 目录全量回归 **106 tests / 106 pass / 0 fail / 0 skipped**（`regression-directory.tap`）
  - 偏离：初始 3 项 → **4 项**，`TestChannelMigrationAfterUp` 同样状态敏感（:513 断言空表，基线 12/14 子测试失败），已记入 `pending-adjustments.yaml`
- [x] 4.5 仅把 4.1 中带证据的项追加进归属表，每项必填 reason；无证据不得排除
  - `entries` 4 条全 `owner=independent`；3 个状态探针在各自独立入口下实测 PASS（up 19 / down 22 / reapply 15，0 fail 0 skip，`independent-entries.txt`，容器纪律同样满足）
  - `TestChannelIsolation` 依据**源码**（`//go:build linux` + `requireIsolationProfile` 为 `t.Fatalf`，CI 无获批 profile），WSL 实跑属 TC-TOR-004（manual，未执行）
  - `allowed-skips` 4 条：3 条基线观测（`TestReconcileLiveGitHub`、`TestFetchFromSkillsSh_AnthropicPptxIntegration`、`TestExecutionBindingRelayHelperProcess`）+ 1 条源码推导（`TestChannelIsolationChild`，reason 中明确标注 source-derived）
  - **未排除**：B/D/E/F 四类失败与 132 个平台/Redis skip 一律不入表；`allowed-skips` 只是下界，CI-linux 真实集合须由 TC-CBE-005 确认
  - 上报 7 项范围外发现（见 `baseline-findings.md` 第 5 节），含 tools `show` 形状缺口与 `TestHandleRuntimeGone_…` 未定性；均未静默修复

## 5. test-ownership-and-ci-reconciliation / CI 对账（P0，Slice 5，依赖 #4）

- [x] 5.1 `scripts/test-go.test.sh` 补用例：`--skip-regex` 原样透传、`--json-out` 落盘且退出码透传、缺参数值拒绝、不带新参数行为不变（TC-TOR-002），确认 RED
  - RED：`--skip-regex returned 2, want 0`，usage 行仍是上游原文（`validation/s5-ci-evidence/red-test-go.tap`）
  - 新增 8 个用例（4 行为 + 4 usage 拒绝）；假 `go` 增加 `MULTICA_TEST_GO_TEST_OUTPUT`/`_STATUS` 注入，既有任何用例未改
- [x] 5.2 `scripts/test-go.sh` 增加两个可选参数（上游文件挂钩点，标 `AIFIRST`，保证 pipefail 退出码），确认 GREEN
  - 3 处 `# AIFIRST:` 挂钩；`pipefail` 只在 `--json-out` 分支内开启，不带新参数时调用与改前逐字节一致
  - GREEN：`bash scripts/test-go.test.sh` exit 0，`TC-TWG-001/002/003` + `TC-TOR-002` 全 PASS（`green-test-go.tap`）
  - 变异：去掉 `set -o pipefail` → `--json-out returned 0, want go test's 3`；sha256 逐字节还原（`mutation-pipefail.txt`）
- [x] 5.3 写 `ci-evidence.test.mjs`：必需包 0 通过、包无事件、名单外 skip、排除项出现在流、半截 JSON/缺包级结论，五种各自单独非 0；合规流 0；逐行解析硬失败（TC-TOR-003），确认 RED
  - RED：`ERR_MODULE_NOT_FOUND: …ci-evidence.mjs`，1 tests / 0 pass / 1 fail（`red-ci-evidence.tap`）
  - 22 项用例，含「五种失败各自单独红」的组合用例、CRLF 等价、声明本身校验、CLI 参数与坏表拒绝
- [x] 5.4 实现 `ci-evidence.mjs` 与 `required-packages` 声明，确认 GREEN
  - GREEN：22 PASS / 0 fail / 0 skip（`green-ci-evidence.tap`）；目录全量 **128 PASS / 0 fail / 0 skip**（`regression-directory.tap`）
  - `required-packages` 沿用 S4 的 `test-ownership.json`（5 项），未另立声明
  - 变异：9 条守卫逐条中和 **全部 DETECTED**，sha256 前后一致（`mutation-rules.txt`）
  - **第一轮探针发现真实缺口**：21 项用例下「每个包都必须有结论」NOT DETECTED，补第 22 项（非必需包无结论）后 9/9；原始输出留档 `mutation-rules-first-pass.txt`
  - 真实数据：5 个 S4 基线流拼接（40390 events）→ exit 1、138 problems（3 包级 fail + 132 名单外 skip + 3 排除未生效）；2 个真实全绿包正向对照 → exit 0（`real-baseline-reconcile.txt`）
  - 未验证：`TestChannelIsolation*` 为 `//go:build linux`，5 个流中事件数 0，rule 3 覆盖待 CI-linux / WSL；`make test` 未执行（U5）；CI 接线属 S13
  - CUSTOM.md 登记 M31 **#321**（汇总行与章节标题同步为 5 行 #317–#321）

## 6. ci-backend-environment / ci-provision（P0，Slice 6）

- [x] 6.1 写 `ci-provision.test.mjs`：up 产出符合 TestMain 全部身份检查的库与角色、先 `::add-mask::` 再写 `GITHUB_ENV`；down marker 匹配才删、不符拒绝非 0；handle 缺失 down 以 0 退出；日志与 handle 不含明文口令（TC-CBE-001，按 R1），确认 RED
  - RED：`ERR_MODULE_NOT_FOUND: …ci-provision.mjs`，1 tests / 0 pass / 1 fail（`validation/s6-ci-provision/red-ci-provision.tap`）
  - 26 项用例，成功/失败/安全边界分别覆盖；`log` 与 `appendEnv` 共用一个 journal，mask 与写入的**先后顺序**可观测
  - 安全边界用例：handle 键集合恰好 5 个且 adminUrl 去口令、除 mask 命令外无任何一行携带两种口令、handle 单行、down 只用 job 管理员 URL 连接、驱动报错脱敏（管理员口令 + `PASSWORD '…'` 字面量）
- [x] 6.2 实现 `ci-provision.mjs`（复用 `createDisposableDatabase`/`dropDisposableDatabase`，handle 存去口令管理员 URL），确认 GREEN
  - `provision.mjs` **一行未改**，身份规则仍只有一份；坏 handle（解析失败/非对象/缺字段）硬失败，不降级成 no-op；缺 handle 时 0 退出且**零连接**
  - GREEN：26 PASS / 0 fail / 0 skip（`green-ci-provision.tap`）；目录全量 **154 PASS / 0 fail / 0 skip**（= S5 的 128 + 26，`regression-directory.tap`）
  - 变异：8 条守卫逐条中和 **全部 DETECTED**，sha256 前后一致 `2718a61f…22fef51`（`mutation-guards.txt`）
  - **本切片未运行任何数据库**（全部注入假连接）；唯一真实网络尝试是 CLI 用例连 `127.0.0.1:1`（被拒）；结束后 `podman ps -a` 仍只有两个 Exited 容器、无新增
  - 未验证：未对真实 Postgres 跑过 up/down（真实服务容器全链路属 S13 后的 TC-CBE-005）；`ci.yml` 本切片未改；`make test` 未执行（U5）
  - CUSTOM.md 登记 M31 **#322**（汇总行与章节标题同步为 6 行 #317–#322；`git diff --numstat` = 12 insertions / 0 deletions）
- [x] 6.3 `pg` 依赖经 `npm install --prefix` 取得，版本取自根 `package.json`；不跑全仓 `pnpm install`
  - 根声明 `^8.20.0` → `npm install --prefix <tmp>/aifi45-s6-pg 'pg@^8.20.0'` 实装 **8.23.1**（14 packages / 15s），**未跑全仓 `pnpm install`**（`pg-node-path-probe.txt`）
  - **实测 NODE_PATH 只被 CJS 解析器读取**：无 `node_modules` 的探针目录下，有 NODE_PATH 时 `await import("pg")` 仍 `ERR_MODULE_NOT_FOUND`，`createRequire` OK；故 `pgConnect()` 用 `createRequire(import.meta.url)("pg")`，并由第 25 项静态契约用例钉住（先滤 `//` 注释行再断言）→ ADJ-008
  - 如实记录：`::add-mask::<口令>` 本身必然把口令送到原始 stdout（runner 只遮蔽已见过的值），R1 的「日志不含明文口令」指 mask 生效后的 runner 日志 → ADJ-009

## 7. ci-backend-environment / nonce 门禁逐条件（P0，Slice 7，依赖 #4）

- [x] 7.1 为 `cmd/server` 与 `governance` 各写表驱动测试：11 个条件逐条单独退化必须被拒，条件名由 `t.Run` 子测试承载（TC-CBE-002，按 R2），确认 RED
  - 新增 `server/cmd/server/disposable_identity_conditions_test.go` 与 `server/internal/governance/disposable_identity_conditions_test.go`（各 214 行，除 `package` 子句外逐字节相同，脚本生成并核对）；`gofmt -l` 无输出、`go vet ./cmd/server ./internal/governance` exit 0
  - RED 以**门禁变异**取证（测试-only 切片的 RED 就是「门禁失去某条拒绝时测试必须红」）：11 条拒绝逐条从两份门禁各删一项，在一次性库真跑两个包 → **11/11 DETECTED**，每条都变红于对应子测试（`mutation-gate-conditions.txt`、`mutation-fail-events.txt`）
  - 第一轮 `role-name` NOT DETECTED 是**真实覆盖缺口**：`sessionRole != role` 兜住了「只改角色名」。修为该条件同时移动 `Role` 与 `SessionRole`（`columns []string` + `slices.Sort`/`slices.Equal` 断言变化列集合），修后 11/11 → ADJ-011
  - 新增叶子用例 14/包 × 2 包 = **28**（11 条件 + 3 nonce 变体 − 1 合并 + 1 读失败）
- [x] 7.2 新增 identity selection（`ci-gate-identity`）到 `selections.json`/`selections.identity.json`，经一次性库真跑，skip=0 且至少一个叶子 PASS
  - 因 run-selection 是「一个 selection = 一个包」，登记**两条**：`ci-gate-identity`（governance）与 `ci-gate-identity-server`（cmd/server）→ ADJ-010
  - 各自建一次性 podman 实例真跑：各 **pass=16 fail=0 skip=0**、runner exit 0、实例 released `remaining=0`（`4f3f92bc42d2`、`2ad8a85e936d`）；两个包的流里都出现全部 11 个条件名
- [x] 7.3 确认门禁实现一行未改（`git diff` 核对），不放宽任何拒绝条件
  - `git status --porcelain -- server/cmd/server/integration_test.go server/internal/governance/crsync_test.go` 输出为空
  - sha256 前后一致：`899f8ddf7d6ef3328bc11a144295b44635bbc0e79c5e6eb838ae7e2adf83eb21`（cmd/server）、`04221be49c5c236605ecc17e4521573ea8856bfdd6622224d4c141c6ab4497eb`（governance）
  - 容器清单运行前后按排序集合比对无差异（`containers-compare.txt`），未连 localhost:5432、未操作 `multica-postgres`
- [x] 7.4（补验 S3 遗留）S3 守卫的运行时行为在一次性库上观测
  - 同一 selection 两次跑，只改环境变量：均缺失 → **0 pass / 8 fail / 0 skip**（三条各不相同的 Fatal 报文）；均注入（tools `e52b8081f159`）→ **18 pass / 0 fail / 0 skip**，流里带真 crctl 源 SHA256 与真实 node argv
  - 证据 `validation/s3-env-contract/runtime-env-absent/`、`runtime-env-present/`，S3 README 的未验证项 1 已关闭

## 8. workspace-delete-execution-tables / 清单（P0，Slice 8，依赖 #4）

- [x] 8.1 核实 19 张 `cr_execution_*` 表的 `workspace_id`、DELETE 触发器、指向 workspace 的外键现状
  - 逐张读迁移 643–648 并用脚本复核 `CREATE TABLE … );` 区块：**7 张**有 `workspace_id`（activation / binding_issue / code_source_freeze / consumption / contract_selection / dispatch_root / notice），12 张没有；**19 张全部 `REFERENCES workspace` 计数为 0**（648 头部注明 no-FK / no-cascade 约定）
  - 触发器与外键另由新测试在真库上按 `pg_trigger.tgtype`（1=ROW / 2=BEFORE / 8=DELETE）与 `pg_constraint.contype='f'` 对账：16 张带拒绝 DELETE 的触发器，notice / dispatch_root / tool_cursor 没有
  - 决策 7 分类落地为 **2 delete / 11 retain / 6 keep = 19**，逐表依据见 `validation/s8-wsd-manifest/README.md` §2.1
- [x] 8.2 清单测试新增 `workspaceDeleteRetain` 分类并按 design 决策 7 逐表登记；retain 断言查 `pg_trigger`/`pg_constraint`（TC-WSD-001），确认 RED
  - 上游 `workspace_delete_manifest_test.go` 只追加两处并标 `// AIFIRST:`（常量 + 19 条登记）；新增 fork 独有 `workspace_delete_retention_test.go`（1 个测试函数 `TestWorkspaceDeletionRetentionGuards`，独立复述分类作为评审映射）
  - selection 名按 **canonical 优先**取 `handler-wsd-manifest`（design 决策 8 写的 `handler-workspace-deletion` 与锁定的 CP-WSD-001 冲突）→ ADJ-012；S9/S10 据此用 `-delete`/`-retain`/`-atomic`/`-no-recreate`
  - RED（保留常量、移除 19 条登记，**断言级**非编译级）：exit=1、`FAIL handler-wsd-manifest pass=0 fail=2 skip=0`，19 张全部点名 unclassified + 逐表分类不符
  - GREEN：exit=0、`PASS handler-wsd-manifest pass=2 fail=0 skip=0`，实例 `292534b3ebff` released `remaining=0` → **CP-WSD-001 两条断言均满足**
- [x] 8.3 确认既有规则不变（KEEP 不带 `workspace_id`，DETACH/SETTLE 带），删任一登记或回退 retain 断言必须变红
  - 既有测试体一行未改；`git diff -w --numstat` = **28 插入 / 0 删除**（`--numstat` 的 38/10 中那 10 行「删除」全是 gofmt 因新键更长而重排 #87 那 10 张表的对齐空格，动作值不变）
  - **变异 4/4 DETECTED**：删登记 → `unclassified=[cr_execution_notice]`；retain 回退 keep → 点名决策 7；**真库**删 retain 表触发器 → `has no BEFORE DELETE row trigger`（`pg_get_triggerdef` 逐字节还原）；**真库**加指向 workspace 的外键（`NOT VALID`）→ `references workspace via [aifi45_probe_workspace_fk]`（随后删除）
  - baseline 与还原后各 exit=0；manifest sha256 前后一致 `e71ecfb1…`；`gofmt -l` 无输出、`go vet ./internal/handler` exit 0
  - 回归：node 目录全量 **154 PASS / 0 fail / 0 skip**；handler 整包一次性库真跑 **4506/5/47** vs S4 基线 4507/3/47，按测试名对账 → 本切片**修好** manifest 测试，`TestSearchIndexChangesScopeToWorkspace` 同名同因，presenter 家族变化经 `-run '^TestPresenter'` **单独连跑两次**证明为既有 Windows 时钟 flake（受害子测试在两次间移动）→ 补证入 **ADJ-006**，未改上游 presenter 测试
- [x] 8.4 `CUSTOM.md` 补登 #87 条目（上游文件只追加、标记）
  - #87 行**严格追加**：脚本核对 HEAD 版原文 871 字符是当前行的前缀，新增 1284 字符，6 单元格不变；补登内容含 19 张表逐张分类与依据
  - 新行 **#324**（6 单元格）+ M31 头/汇总 → **8 行 #317–#324**；`git diff --numstat` = 15 插入 / 1 删除（M31 整节相对 HEAD 为新增，故头/汇总改动不另计删除），CRLF 保持
  - 容器边界：探针前后 `podman ps -a` 排序集合逐字节相同（compare 为 0 字节），全部运行结束复查仍只有两个既有 Exited 旧容器；未连 localhost:5432、未操作旧容器、未放宽 nonce 门禁、未读取凭据

## 9. workspace-delete-execution-tables / 删除行为（P0，Slice 9，依赖 #8）

- [x] 9.1 写 handler 行为测试：A/B 两 workspace 各写每类至少一行，删 A 后 delete 类 A 行消失、B 行不变（TC-WSD-002），确认 RED
  - 新增 fork 独有 `server/internal/handler/workspace_delete_execution_test.go`（`// AIFIRST:` 英文头）：19 张表 × 2 个 workspace 各一行夹具，跨表引用走真实链；所有 id 用 crypto 随机 UUID（**不用 UnixNano**，ADJ-006）；整行 `SELECT t::text` 逐字节快照（含 digest 列）；期望分类直接读 `workspaceDeletionManifest`，不第三次复述（S8 独立评审映射已钉住）。
  - `selections.json` 追加 `handler-wsd-delete` / `handler-wsd-retain` / `handler-wsd-atomic`，名字取自锁定 canonical CP-WSD-002/003/004（不是 design 决策 8 的写法，沿用 ADJ-012）。
  - **RED 实测**：三条均 `pass=0 fail=1 skip=0`、runner exit 1、实例 released `remaining=0`。**断言级而非夹具级**：19×2 行全部播种成功、`DeleteWorkspace(A)` 返回 204、atomic 走过 503 与回滚断言后只在末尾「必须真删」处红。证据 `validation/s9-wsd-behaviour/red/`。
- [x] 9.2 实现 `governance.DeleteWorkspaceExecutionRows`（两条参数化 DELETE，走现有 tx），在 `DeleteWorkspace` 的 `deleteSteps` 追加一步（上游文件挂钩点，标 `AIFIRST`），确认 GREEN
  - 新增 fork 独有 `server/internal/governance/workspace_delete_execution.go`：`DeleteWorkspaceExecutionRows(ctx, tx pgx.Tx, workspaceID string) error`，两条 `DELETE … WHERE workspace_id = $1::uuid`（notice、dispatch_root），错误逐条 wrap，不自开事务、不加锁。
  - 上游 `workspace.go` **净增 11 行 / 0 删除**：1 行带 `// AIFIRST:` 的 governance import + 10 行新步骤 `delete execution control routing`。位置在 `delete chat pins` 之后、`lock task usage rollup` 之前（**ADJ-013**：design 未指定位置，而 SC-WSD-004 要求其后存在可失败步骤；此处使既有 advisory 4246 竞争成为真实生产失败注入器）。`requester.WorkspaceID` 是 `pgtype.UUID`，按 handler 惯例 `uuidToString` 转换。
  - **GREEN / CP 按锁定命令原样取证**：CP-WSD-002 **exit 0** `PASS handler-wsd-delete pass=1 fail=0 skip=0`；CP-WSD-004 **exit 0** `PASS handler-wsd-atomic pass=1 fail=0 skip=0`。证据 `validation/s9-wsd-behaviour/cp/`。
  - `gofmt -l` 三个 Go 文件无输出；`go vet ./internal/governance ./internal/handler` exit 0。
- [x] 9.3 retain 类 A 行逐字节不变（含 digest）、keep 类不变、retain 表普通 DELETE/TRUNCATE 仍被拒（TC-WSD-003）
  - **最终结果：通过**。CP-WSD-003 **exit 0** `PASS handler-wsd-retain pass=23 fail=0 skip=0`（11 `plain_delete_` + 11 `truncate_` + 父测试）。缺口由 9.6 的迁移 649 修复，证据 `validation/s9-wsd-behaviour/green-649/`。
  - **发现当时（未修复前，保留原记录）**：CP-WSD-003 **exit 1** `FAIL handler-wsd-retain pass=20 fail=3 skip=0`。已通过的部分：retain 类 A 行逐字节不变（含 digest）、keep 类不变、B 全部 19 行不变；**11 张 retain 表的普通 DELETE 全部被拒**且报文含表名；9 张表的 TRUNCATE 被拒。（20 pass = 11 `plain_delete_` + 9 `truncate_`）
  - **未通过（2 项）**：`truncate_cr_execution_binding_issue`、`truncate_cr_execution_consumption` —— 数据库**接受** TRUNCATE。
  - **根因是既有 schema 缺陷，非本切片造成**：迁移 643/644 各只有一个 `BEFORE UPDATE OR DELETE … FOR EACH ROW` 触发器，**无 `BEFORE TRUNCATE` 语句级守卫**；645/648 的其余表都有。TRUNCATE 不触发行级触发器。648 头注释（第 11–12、406 行）自己声明「every retained table needs this statement guard」。grep 全部迁移确认无后续迁移补过；发现当时 `git status --porcelain -- server/migrations/` 为空。
  - **锁定规格内部冲突**：canonical SC-WSD-003 要求 TRUNCATE 也被拒，SC-WSD-002 明文「不新增迁移」→ 补守卫与不新增迁移二者不可兼得。design 决策 7 行为测试段只写普通 DELETE，未含 TRUNCATE。
  - **未自行选边**：发现当时未改 canonical、未放宽或删改断言、未新增迁移、未改触发器、未加排除名单；记 **ADJ-014（major）** 并停下上报，由用户裁定「补迁移修缺口（修订 SC-WSD-002）」后才执行 9.6。证据 `validation/s9-wsd-behaviour/README.md` §7、§11。
- [x] 9.4 追加步骤之后某步失败时事务回滚，A 行不半删（TC-WSD-004）
  - `TestWorkspaceDeletionRollsBackExecutionRowsWithTransaction`：pinned 连接持 advisory 4246 + `setWorkspaceDeleteLockTimeoutForTest(t, 100ms)` → **503**；释放后断言 A/B 全部 19 行**逐字节不变**、workspace A 仍在。
  - **正向对照**：随后把超时调回 5s 再删一次，要求 **204 且 A 的 delete 类行真消失**——防止「缺 sweep」空洞地满足「什么都没变」。
  - **CP-WSD-004 exit 0** `PASS handler-wsd-atomic pass=1 fail=0 skip=0`。**变异 m4**（把 sweep 改成自开事务并立即 Commit）→ 该测试变红 `cr_execution_notice (delete) row for workspace A changed`，证明「在既有事务内」是被断言的保证。
- [x] 9.5 确认除迁移 649（R4 裁定）外不新增迁移、不新增触发器例外、不改 sqlc 查询；测试数据用随机唯一键（EXP-2026-0001）
  - 发现当时 `git status --porcelain -- server/migrations/`、`-- server/pkg/db/`（含 `queries/` 与 generated）**均为空**；R4 裁定后 `server/migrations/` 只多出 `649_cr_execution_truncate_guard.{up,down}.sql` 两个新文件，`server/pkg/db/` 仍为空，643/644/645/648 一行未改，**未开任何删除／更新例外**。
  - 夹具所有 id 用 `uuid.NewString()`（crypto 随机），slug 用 UUID 去连字符前 12 位；**未使用 `time.Now().UnixNano()`**（S4 探针已证伪本机时钟粒度，ADJ-006）。
  - **变异验证 4/4 DETECTED**：m1 删 notice DELETE、m2 删 dispatch_root DELETE、m3 把 sweep 加宽到 retain 表（触发器拒绝、204→500）、m4 sweep 脱离 teardown 事务。四次各自新建并释放一次性实例，每次按原字节还原并核对 sha256（`eaf5ce61…` / `61006566…`），脚本末尾总核。
  - **回归（发现当时）**：node 目录全量 **154 pass / 0 fail / 0 skip**；handler 整包一次性实例真跑 **4529 pass / 7 fail / 47 skip**，按测试名逐条对账（ADJ-006 口径）：新增 4 个失败名 = 3 个 TRUNCATE 缺口 + 1 个 presenter 新受害者，不再失败 2 个均为 presenter，`TestSearchIndexChangesScopeToWorkspace` 与基线同名同因，skip 集合不变。**UUID 规范化复核：新增恰好 25 名（本切片 3 顶层 + 22 子测试）、移除 0 名**，6 个内嵌随机 workspace UUID 的 plugin 子测试名属改名而非覆盖变化。
  - **回归（649 之后，见 9.6）**：node 目录全量复跑 **154/0/0** exit 0（`selections.json` 改后必须复跑，证据 `regression-directory-649.tap`，前后容器清单 `INVENTORY_UNCHANGED`）；handler 整包 **4533 pass / 3 fail / 47 skip**，**新增失败名 0**、不再失败 4（3 个 TRUNCATE + 1 个 presenter 受害者），UUID 规范化名集合 4583→4583 **新增 0 移除 0**；governance 整包（补齐 tools 环境变量后）**1344 pass / 48 fail / 1 skip**，与 S4 基线**失败名集合逐条相同（新增 0、消失 0）**、skip 相同，名集合 +16 恰为 S7 的身份门禁子测试。
  - **容器与凭据边界**：运行前后 `podman ps -a` 排序集合比对无差异（只有两个既有 Exited 旧容器）；未连 localhost:5432、未操作旧容器、未放宽 nonce 门禁、未读取或打印凭据；tools HEAD `e52b8081f159` 与 pin 一致且其未提交改动未触碰，multica HEAD `903a46c5a`。
- [x] 9.6 按用户裁定补迁移 649 修 TRUNCATE 缺口（R4 / ADJ-014），并把 649 纳入 down/up 生命周期证明（ADJ-016）
  - **修订流程先于实现**：design.md 修订记录新增 **R4**（原文／核实依据／用户裁定／修订后／影响范围），canonical SC-WSD-002 该条改为「除补 TRUNCATE 守卫的迁移 649 外不新增迁移、不新增触发器例外（不得为 append-only 触发器开任何删除例外）、不改 sqlc 查询；649 SHALL 只加语句级 TRUNCATE 拒绝、复用两张表各自已有的 append_only 函数，并 SHALL 配套 down 迁移」；`specs/…/spec.md` 与 `test-plan.md` TC-WSD-002 同步镜像；**Gate 2 以用户裁定原文为 evidence `--reapprove` 重签**（旧回执 superseded）。SC-WSD-003 与 CP-WSD-003 原文未动。
  - **工具限制如实登记（ADJ-015）**：`stdd canon generate --type spec <change>` 单变更模式忽略 `--type`，只重渲染 proposal.md（源码 `canon.py:330 → _generate_one:688-712`）；spec human view 只在 `--all` 分支生成，而 `--all` 会以当前时间重渲染项目内每个 change 的 proposal.md，会改写他人未提交记录，故**未使用**，改为手工镜像。generate 前后对变更目录 195 个文件取 sha256 快照，逐字节相同。`canon verify` 仍 2/2，但它只核对 proposal，**不得当作双轨全量一致的证据**。
  - **新增 `server/migrations/649_cr_execution_truncate_guard.{up,down}.sql`**：up 只加 `cr_execution_binding_issue_no_truncate`、`cr_execution_consumption_no_truncate` 两个 `BEFORE TRUNCATE … FOR EACH STATEMENT`，复用 643/644 各自的 `append_only` 函数（拒绝报文与行守卫一致）；down 只 `DROP TRIGGER IF EXISTS` 这两个。无新函数／表／索引，无 sqlc 改动，LF 行尾与既有迁移一致。
  - **生命周期测试扩围（ADJ-016）**：`execution_migration_roundtrip_test.go`（fork 独有，#204 登记）的 `executionMigrationFiles` 追加 649、对象清单两行各追加 `_no_truncate`，净 7 插入 3 删除。理由：649 的触发器挂在 643/644 的表上，down 阶段 `DROP TABLE` 会连带删掉，而 re-apply 只跑 643–647 的 up → 不纳入循环就会把守卫静默留在库外。`selections.json` 追加 `governance-migration-roundtrip`。
  - **GREEN 实测**：`PASS handler-wsd-retain pass=23 fail=0 skip=0`、`PASS handler-wsd-manifest 2/0/0`、`PASS handler-wsd-delete 1/0/0`、`PASS handler-wsd-atomic 1/0/0`（同一实例，`green-649/`）；`PASS governance-migration-roundtrip 1/0/0`、`channel-migration-up 19/0/0`、`channel-migration-down 22/0/0`、`channel-migration-reapply 15/0/0`（`green-649-governance/`）。
  - **变异 3/3 DETECTED**（`mutations-649/`）：m1 去掉 binding 守卫 → **只有** `truncate_cr_execution_binding_issue` 红（21 pass/2 fail）；m2 去掉 consumption 守卫 → **只有** `truncate_cr_execution_consumption` 红；m3 把 `649.down` 改成对错误表 `DROP TRIGGER`（无 `IF EXISTS`）→ 生命周期测试红于真实 apply（SQLSTATE 42704），**证明 down 文件确被执行**。两个迁移文件按 sha256 逐字节还原（up `95507243e32b003d…`、down `5b29747463f695a7…`）。
  - **一处环境差异如实记录**：首次 governance 整包重跑时本 shell 未设 `AIFI45_TOOLS_ROOT`/`CRCTL_MJS`，出现 11 个 `CRCTL_MJS is required` 失败（S3 的缺环境硬失败，非 649 回归）；按 S4 基线条件补齐两个变量指向已核实 tools 检出（HEAD `e52b8081f1`）后重跑，失败名集合与 S4 逐条相同。两次运行的流都留证（`regression-governance-649/`、`regression-governance-649-toolsenv/`），对账见 `regression-649-reconcile.txt`。
  - **CUSTOM.md**：新增 **#326** 登记迁移与生命周期测试改动，M31 计数 9→10 行（#317–#326），#325 末尾补一句指向 #326 的后续说明（原记录保留）；#324 逐字节未变，全文 CRLF 无裸 LF。
  - **Slice 9 已写入 `.stdd.yaml` `slices_completed`**：9.1–9.6 全部通过，`status: done`、`tc_coverage: 3/3`（本切片 TC-WSD-002/003/004；TC-WSD-001 属 Slice 8、TC-WSD-005 属 Slice 10）、`new_tests: 25`、`verified_at: 2026-11-12T23:01:31`。能力累计 TC-WSD-001～004 = 4/4。YAML 可解析性已复核。

## 10. workspace-delete-execution-tables / 禁新建探针（P1，Slice 10，依赖 #9）

- [x] 10.1 写探针：为已删 workspace 保留的 selection 新建 reservation/command 必须被拒（TC-WSD-005）
  - 新增 `server/internal/handler/workspace_delete_no_recreate_test.go`（4 子测试 + 父测试），`selections.json` 追加 `handler-wsd-no-recreate`（31 条，CRLF 保持）。`go vet ./internal/handler` 无输出。
  - 先用生产入口 `TransitionControlCommandTx` 结算 A/B 的 open 槽（不用 DELETE 绕 append-only 守卫），真实删除 A（204），核对 workspace 行消失且 A 的 selection 行逐字节保留；B 上同样构造的请求作正向对照。
  - 实测 **RED**：`FAIL handler-wsd-no-recreate pass=2 fail=3 skip=0`，exit 1。pass=2 是两个正向对照（均成功并在事务内核对 `count(*)=1`），fail=3 是 A 的两个子测试加父测试。**TC-WSD-005 不得报通过，CP-WSD-005 不满足。**
  - 证据：`validation/s10-wsd-no-recreate/`（README 7 节 + `red/` + 两组容器清单 + `regression-directory-s10.tap`）。
- [x] 10.2 若当前代码放行：红灯即为发现，停下向用户上报，由用户裁定是否在本 change 内修（U3）；不静默放宽断言、不改触发器
  - **裁定前（原文保留）**：已放行，已停下上报，等待裁定（ADJ-017，major，当时 `resolved: false`）。根因：`execution_control_reservation.go:70` 不查 `workspace` 表，`:89-91` 只对保留下来的 selection 行做过滤；`execution_control_store_state.go:148` 全文件 `workspace` 零引用。当时未改任何生产代码、未放宽或改写任何断言、未改任何触发器、未改 canonical，`.stdd.yaml` 未写 `'10'` 条目。
  - **用户裁定原文**：「只修reservation半句，command做好记录，待以后可以找回并修订」。**先修订后实现**：design.md 新增 **R5**，canonical SC-WSD-005（置信度 low→medium、两半分别处置）与 SC-TOR-001（允许 `owner=known-finding`）修订，agent CP-WSD-005 的 `action` 与两条断言**一字未改**，spec.md / test-plan.md 手工镜像，**Gate 2 以裁定原文 `--reapprove` 重签（2026-11-12T23:54:09）**。
  - **reservation 半句已修**：`CreateReservationTx` 新增哨兵 `ErrReservationWorkspaceGone` + 一次独立 workspace 存在性检查（**13 插入 / 0 删除**，纯追加）。实测 `PASS handler-wsd-no-recreate pass=3 fail=0 skip=0` **exit 0**，**CP-WSD-005 两条锁定断言均满足**。变异 DETECTED（中和守卫 → 只有 `reservation_for_deleted_workspace` 红），按原字节还原并核对 sha256 `543ace58…`。
  - **command 半句保持红灯并登记**：`FAIL handler-wsd-no-recreate-command pass=1 fail=2 skip=0` exit 1，与登记声明逐字相符；`test-ownership.json` `entries` 第 5 条 `owner=known-finding`（含根因、契约障碍、后继议题、三处找回路径）。**断言与触发器一字未改，红灯未被洗绿，不计为覆盖。** `test-ownership.mjs` 与 `ci-evidence.mjs` **一行未改**（既有机制已够）。
  - ADJ-017 → `resolved: true`（附完整处置）。
- [x] 10.3 确认本 change 未实现 command/cursor 收敛转移；收敛作为后继议题登记
  - 生产改动仅 `workspace.go` 的 11 插入 0 删除 sweep 挂钩与新增 `workspace_delete_execution.go`（`grep cursor|converg|收敛` 无命中）；迁移 649 只加两条 TRUNCATE 守卫；S10 再加 reservation 的 13 行边界。与 SC-WSD-005 的 SHALL NOT 一致。
  - 裁定前回归：node 目录全量 **154/0/0 exit 0**；`test-ownership check` 当时 `OK: 4 entry(ies)`、`allowed skips: 4`。边界：一次性实例 `65a37a694e96` 已释放（`remaining=0`），两轮 `INVENTORY_UNCHANGED`，未连旧库、未放宽 nonce、未读凭据、未提交未推送。
- [x] 10.4 夹具修正与探针拆分（裁定后连带改动，不放宽断言）
  - `execution_contract_selection_test.go` 的 `insertSelectionWithMode` 补一行真实 workspace（**10 插入 / 0 删除**，事务内、随探针回滚、`ON CONFLICT DO NOTHING`）：该夹具的 `selectionWorkspace` 常量在库里从来没有对应行，新边界会让它红——补前提，不是降断言。
  - 探针拆成 `TestWorkspaceDeletionRefusesNewReservation` 与 `TestWorkspaceDeletionRefusesNewCommand` 两个独立函数（两半裁定不同，CI 须能分别纳入/排除）；拒绝断言额外要求 `errors.Is(err, ErrReservationWorkspaceGone)`，防止「因别的原因被拒」空洞变绿；两半各带活 workspace 正向对照。
  - `selections.json` 31 → **32 条**（CRLF 127 / 裸 LF 0）；`test-ownership.test.mjs` 新增 2 项用例（**RED 18/16/2 → GREEN 18/18/0**），其中一项钉住「已知发现不享受宽松校验」（拼错名 / 空 reason / 空 entry 全部必须失败）。
- [x] 10.5 裁定后复验、整包回归与记账
  - **环境差异如实区分**：`channel-protocol` 首轮 FAIL 39/2 全为 `AIFI45_TOOLS_ROOT is required`（S9 已定性，**非回归**）；注入 tools env（HEAD `e52b8081f159`，与 pin 一致）后 **PASS 46/0/0**，两次流都留证。**S13 硬结论：CI backend-tests 必须显式注入这两个变量。**
  - **整包回归逐名对账**（`regression-reconcile.txt`，UUID 规范化）：handler **4535/7/47**（S9 post-649 4533/3/47），PASS 新增恰好 4 名全是本切片探针，FAIL 新增 4 = 2 个声明内 command 名 + 2 个 presenter 受害者移动，**FAIL 移除 0、SKIP 逐名不变**；presenter 同因 `user_email_key`（**ADJ-006 范围外，未改上游测试**）。governance **1344/48/1**，与 S9 toolsenv **FAIL 新增 0 / 移除 0 / SKIP 不变** → **夹具修正零回归**。
  - node 目录全量 **156/0/0**（= 154 + 2）；`gofmt -l` 首轮点名探针缺末尾换行 → `gofmt -w` 后无输出，并**按最终字节复跑两条 selection**（`final/`）结论相同；`go vet ./internal/handler ./internal/governance` exit 0；`test-ownership check` `5 entry(ies)` + `allowed skips: 4`、`skip-regex` 含第 5 个名字。
  - **边界**：裁定后 9 个一次性实例全部 `released … remaining=0`，每轮前后 `podman ps -a` diff 为空，只有两个既有 Exited 旧容器；未连 localhost:5432、未操作旧容器、未放宽 nonce、未读凭据；multica `HEAD = origin/main = 903a46c5ae9f`；**未提交、未推送、未部署**。
  - **记账**：`CUSTOM.md` **#327**（M31 头与汇总改 11 行 / #317–#327，全 CRLF）；`pending-adjustments.yaml` **18 条**（ADJ-017 resolved，新增 **ADJ-018** 四数基线表台账欠债，`resolved: false` 待裁定）；`phase-context.md` 新增「Slice 10 续」；`.stdd.yaml` `slices_completed['10'] = {done, 1/1, new_tests 8, 2026-11-13T00:22:40}`；README 扩至 **14 节**（§1–§7 裁定前原文保留）。
  - **B3.4 三项**：TC 覆盖 **1/1**（TC-WSD-005 预期结果全部成立——command 半句的预期结果本身就是「保持红灯 + 可找回登记」）；产出物核对通过；新增 **8** 项测试，但 **「新增测试全部通过」不成立**：`TestWorkspaceDeletionRefusesNewCommand` 及其 deleted 子测试**是红的**，这是 R5 / ADJ-017 与重签后 canonical **明文要求保留**的状态（授权来自 Gate 2 以裁定原文重签，非 AI 自行放宽），经 `owner=known-finding` 声明排除、不计为覆盖。**不得据此声称 SC-WSD-005 的安全目标已全部达成。**
  - **不得报通过**：command 半句红灯是已声明发现、**不计为覆盖**，产品缺口仍在；收敛转移未实现；未在 ubuntu-latest 跑过（TC-CBE-005 须推送另行授权）；`make test` 未执行（U5 排除）；`TestChannelIsolation*` 未在 WSL 实跑（TC-TOR-004）；**ADJ-005（major）仍未决**，S13 前须裁定；**ADJ-018** 四数基线表台账欠债待裁定。

## 11. ci-credential-and-frontend-typecheck / 凭据诊断（P0，Slice 11）

- [x] 11.1 写 `tools-access.test.mjs`：空/401/403/404/200/网络异常/其他状态分别映射 missing、rejected、no-access-or-pin-not-found、ok、inconclusive；非 ok 非 0；输出不含 token（TC-CCF-001），确认 RED
  - **RED 如实定性为导入级**：新模块尚不存在，`node --test --test-reporter=tap scripts/aifi45-disposable/tools-access.test.mjs` → `ERR_MODULE_NOT_FOUND`、exit 1、`# fail 1`（`red/red.tap`）。为让 RED 对应**最终测试字节**，把模块临时移开重跑取 `red/red-final-testbytes.tap`，再移回并 `sha256sum -c` 核对逐字节还原。**导入级 RED 不足以证明断言有 teeth，真实 teeth 由 11.3 的 16 条变异验证提供。**
- [x] 11.2 实现 `tools-access.mjs`（可注入 fetch），确认 GREEN
  - 导出 `TOKEN_ENV`/`TOOLS_REPO`/`checkToolsAccess`/`runToolsAccessCli`；**pin 规则复用 `tools-pin.mjs` 的 `parsePin`**，不另写一份，且在发请求前校验。凭据只进 `Authorization: Bearer` 头、**不进 URL**；返回值恰好 `outcome/message/exitCode` 三键；`fetch` 被拒时**绝不回显 `error.message`**。CLI 支持 `--pin`/`--pin-file`（默认 `.github/aifirst-tools-pin`），拒绝未知参数与缺值 flag，**凭据缺失先于读 pin 文件报出**，带 main-module 守卫。
  - **GREEN**：15 pass / 0 fail / 0 skip、exit 0、输出含 `# fail 0` → **满足 CP-CCF-001 两条锁定断言**（`exit_code 0`、`stdout_contains '# fail 0'`）。
  - **首轮 GREEN 抓到两处自身缺陷并修正，未放宽任何断言**：①测试夹具 `withPinFile` 未 `await` 异步 body，`finally` 先删临时目录 → `generated asynchronous activity after the test ended`；改 async/await，真实子进程用例改 async。②报文原不含结论名，`no-access-or-pin-not-found` 的 CLI 输出断言红 → 引入 `verdict()` 让每条报文以结论名前置（CI 日志可 grep 结论）。
- [x] 11.3 变异验证、整包回归、记账与 B3.4
  - **变异 16/16 DETECTED、0 SURVIVED**：missing 短路、空白 trim、401 映射、404 映射、ok 的 exit 0、网络 catch、其余状态兜底、Authorization 头带凭据、凭据不进 URL、不回显 error.message、pin 先于请求校验、CLI 凭据先于 pin 文件、未知参数拒绝、缺值 flag 拒绝、结果不暴露 token 字段、main-module 守卫。每条留 `patch.txt`/`red.tap`/`restored-sha256.txt`，每条后按原字节还原并核对 sha256 `e997d65a2df2ff50…`（`mutation/summary.json`）。
  - **整包回归逐名对账**：目录全量 **171 pass / 0 fail / 0 skip**（= S10 的 156 + 15）；S10 基线是 spec reporter、本轮是 TAP，对账脚本两种都解析 → **新增恰好 15 名全是 TC-CCF-001、移除 0 名**（`final/regression-reconcile.txt`）。
  - **边界**：本切片**未运行任何数据库、未发出任何真实网络请求**（fetch 全注入；两个真实子进程用例分别在凭据为空与 pin 文件不可读处短路）；运行前后 `podman ps -a` 完全相同，只有两个既有 Exited 旧容器；未连 localhost:5432、未操作旧容器、未放宽 nonce 门禁；**未读取或打印任何真实凭据**（token 为自造 fixture）；multica HEAD = origin/main = `903a46c5ae9f`，工作区仅含本 change 文件。
  - **记账**：`CUSTOM.md` **#328**（M31 头与汇总改 12 行 / #317–#328，全 CRLF，#327 逐字节未动）；`phase-context.md` 新增 Slice 11；`.stdd.yaml` `slices_completed['11'] = {done, 1/1, new_tests 15, 2026-11-13T00:48:42}`；证据 `validation/s11-tools-access/`。
  - **B3.4 三项**：TC 覆盖 **1/1**（TC-CCF-001）；产出物核对通过（两个新文件均存在、fork 独有、英文 `// AIFIRST:` 头）；新增 **15** 项测试**全部通过**，无声明偏离。
  - **不得报通过**：`ci.yml` **本切片一行未改**，新诊断尚未被任何 CI 步骤消费（替换「Require the tools read credential」属 S13）；**从未对真实 GitHub API 发过请求**，真实凭据行为属未验证，不得据此声称 transitions job 已修好；SC-CCF-003（管理员更新 PAT）未闭合；TC-CBE-005 须推送另行授权；`make test` 未执行（U5 排除）；**ADJ-005（major）仍未决**，S13 前须裁定；**ADJ-018** 四数基线表台账欠债待裁定。

## 12. ci-credential-and-frontend-typecheck / views typecheck（P0，Slice 12）

- [x] 12.1 核实 `core/package.json` 新增 `./platform/storage` exports 是否被 lint/knip/`check-ui-wildcard-exports` 接受（design 未验证事实 #5）
  - **已用证据回答，三项均接受，无需走 design.md:163 的退路**：①**knip 输出前后逐字节相同**（`green/knip-diff.txt` **0 行**；两次均 exit 1，来自既有发现）——其 `include: ["files","dependencies","unlisted"]` **不含 `exports`**，新增 export 不进入检查面；②`scripts/check-ui-wildcard-exports.mjs` **结构上不可能受影响**：`uiRoot`/`pkgName` 硬编码只守 `packages/ui` 的四个通配 export，core 的具名 export 不在其扫描范围，exit 0 前后不变；③lint core 与 views 均 **exit 0、0 错误、0 次提及被改文件**（`green/lint-core.txt`、`green/lint-views.txt`）。
  - `platform/storage.ts` 早已存在并经 `./platform` 间接导出，本次只是补一条具名入口，**+1/-0**，未新建文件、未改任何实现。
- [x] 12.2 `use-logout.test.ts` 的 4 条相对导入改包导入，`createAuthStore` 改 `vi.importActual`；断言不删除不放宽（TC-CCF-002），确认 RED（typecheck 60 条 TS6059）
  - **RED 实测 60 条 TS6059**（`red/typecheck-before.txt`），逐条溯源到那 4 条相对 `../../core/...` 导入把 core 的 .ts 源拉进 views program；机制是 `packages/views/tsconfig.json` 的 `rootDir: "."`，包 specifier 经 node_modules 解析故豁免。grep 证实该文件是 **views 中唯一**含相对 core 导入者。
  - 改动 **7 插入 / 5 删除**：4 条相对导入 → 3 条包导入（`@multica/core/platform/storage`、`@multica/core/api`、`@multica/core/types`）；首条测试改 `async` 并以 `await vi.importActual<typeof import("@multica/core/auth")>("@multica/core/auth")` 取真实 `createAuthStore`——该模块被下方 `vi.mock` 整体替换，静态 import 只会拿到 mock。
  - **断言等价双重证明**：`git diff` 中 **0 条 `expect(` 改动、两条 `it()` 标题不变**（`green/use-logout-diff.txt`）；另把 HEAD 版本存为临时文件独立跑亦 **2/2 通过**（`red/use-logout-before.txt`），临时文件已删除并核实不存在。`vi.mock("../../core/analytics")` 与 `vi.mock("../../core/platform/workspace-storage")` **故意保留相对路径**：tsc 不解析 `vi.mock` 字符串，改它们无收益。
- [x] 12.3 确认 `@multica/views` typecheck 0 条 TS6059、该测试文件全过
  - **GREEN**：`pnpm --filter @multica/views typecheck` **exit 0**，`grep -cE "error TS"` = **0**（不只 TS6059 归零，是任何错误码归零，`green/typecheck-after.txt`）→ **满足 CP-CCF-002**。
  - `auth/use-logout.test.ts` **2/2 通过**（`green/use-logout-after.txt`）。
  - **按最终字节复跑确认**（A/B 期间两文件被覆盖过两次，还原并 `sha256sum -c` 均 OK 之后再跑）：`final/typecheck-final.txt` **exit 0、0 条 `error TS`**；`final/use-logout-final.txt` **exit 0、2/2**。
- [x] 12.4 本地跑 views/core 全量 vitest 并记录结果；超出 TS6059 的失败先报告再裁定（U4）
  - **core 全量 2552/2552 通过（180 文件）exit 0**（`full/core-vitest.txt`）。
  - **views 全量 A/B（U4 上报点，已报告，范围不扩大）**：HEAD（两文件还原、`sha256sum -c` 均 OK）**6 失败/6366 通过（6372）、4 失败文件/506**；带改动 **11 失败/6361 通过（6372）、5 失败文件/506**；把带改动失败的 5 个文件单独成组重跑 **146/146 通过 exit 0**。按名字对账 **4 共有 / 2 仅 HEAD / 7 仅带改动**，**受害者移动而执行总数不变** → HEAD 已存在的 Windows 506 文件并行负载 flake，**非 S12 回归、非 typecheck 修复新暴露**。对账脚本 `full/reconcile.mjs` 可重跑（exit 0），结果 `full/regression-reconcile.txt`。
  - 原因以 `Test timed out in 5000ms` 为主；两条 `TypeError: rejectCreate is not a function` 是同次停顿下游（`create-issue.test.tsx:1097/:1125` 的 `let rejectCreate!` 只在 `mockImplementationOnce` 的 promise executor 内赋值）。**未改任何断言、未调 timeout/retry/并行度、未加 skip**。登记 **ADJ-020**（未决）：两次运行不足以测量 flake 率，未在 ubuntu-latest 跑过，不得声称 CI 不受影响。
- [x] 12.5 记账与 B3.4（含新增测试数为 0 的如实偏离声明）
  - **记账**：`CUSTOM.md` **#329**（M31 头与汇总改 **13 行 / #317–#329**，汇总文件列表追加两个上游文件；全 CRLF 1096/0 bare LF；**#327 4987 字符、#328 3304 字符逐字节未动**；`git diff -U0` 证实本切片纯追加）。**四数基线表零影响**：两文件 `AIFIRST|CR-2026-[0-9]{3}` 匹配数 HEAD 与工作区**均为 0**（实测；`packages/**/*.ts` 在《核对命令》口径内、`package.json` 不在），ADJ-018 的既有台账欠债不变。
  - `phase-context.md` 新增 Slice 12；`.stdd.yaml` `slices_completed['12'] = {done, 1/1, new_tests 0, 2026-11-13T01:32:59}`；证据 `validation/s12-views-typecheck/`；`pending-adjustments.yaml` 新增 **ADJ-019 / ADJ-020**（YAML 解析通过，20 条无重号）。
  - **B3.4 三项如实分记**：①TC 覆盖 **1/1**（TC-CCF-002，command 型，由 typecheck/vitest/diff 证据覆盖）；②产出物核对通过（两处改动均落地、均为上游文件、JSON 不带 AIFIRST 注释故以 CUSTOM.md 登记）；③**新增测试数 = 0，长程约束 #3 与 B3.4 第 3 项未满足** → **登记 ADJ-019，不报「三项全过」**。理由：TC-CCF-002 在锁定证据计划里是 `kind: command`，断言对象是 tsc 退出码与错误码计数；回归守卫已由 `tsc --noEmit` 本身承担，另造「禁止相对导入」测试与之重复。约束 #5 的降级条件是**连续 3 切片**无新增测试（S11 新增 15、S13 计划新增），**不触发降级**。
  - **边界**：本切片**未运行任何数据库、未创建 podman 实例、未发出网络请求**；未连 localhost:5432、未操作旧容器、未放宽 nonce 门禁；**未读取或打印任何凭据**；multica HEAD = origin/main = `903a46c5ae9f`，工作区仅含本 change 文件；记录仓他人未提交改动未清理未混入；**未提交、未推送、未部署**。
  - **不得报通过**：未在 ubuntu-latest 跑过 views typecheck/vitest（真实 CI 属 TC-CBE-005，须推送另行授权）；`make test` 未执行（U5 排除）；views 全量负载 flake **未修**（ADJ-020 未决）；**ADJ-005（major）仍未决**，S13 前须裁定；**ADJ-018** 四数基线表台账欠债待裁定。

## 13. CI 接线与独立入口（P0，Slice 13，依赖 #2 #5 #6 #7 #8 #9 #10 #11 #12）

- [x] 13.1 `scripts/ci-scope.test.mjs` 补"仅改 `scripts/aifi45-disposable/**` 命中 scripts 与 backend"用例（TC-SEL-004），确认 RED
  - **先取干净基线**：改前本机 44 pass / 1 fail（45 tests），失败点是既有第 208 行跨行正则对 CRLF 工作树假红（`core.autocrlf=true`，HEAD blob 是 LF）。按业务仓 `AGENTS.md` 加 1 行 `// AIFIRST:` 归一化挂钩后基线 **45/45**（ADJ-021）。
  - RED 实测 **47 tests / 45 pass / 2 fail / 0 skipped**，exit 1，219.4 ms（`red-ci-scope.txt`）；2 个失败全是新断言。
- [x] 13.2 `.github/ci-paths.json` 的 scripts 与 backend scope 加入该路径；`script-checks` 增加 `node --test scripts/aifi45-disposable/*.test.mjs`（先取 pg，失败即步骤失败），确认 GREEN
  - `ci-paths.json` **+2 / −0**（第 26、99 行），其余 6 个 scope 未动；JSON 解析通过，8 scope。
  - GREEN **47 / 47 / 0 / 0**，exit 0，236.1 ms（`green-ci-scope.txt`）。
  - **fail-closed 实跑证明**（不是断言）：`pg_version="999.999.999"` → `npm error code ETARGET`、exit 1、**零条测试输出**；`pg_version="$(node -e "process.exit(3)")"` → exit 3、`REACHED_INSTALL` 未打印（`script-checks-pg-fetch-fails.txt`、`script-checks-version-read-fails.txt`）。
- [x] 13.3 `ci.yml` backend-tests 接线：tools-access 诊断 → pin 检出与完整性检查 → `ci-provision up` → migrate → `test-go.sh --skip-regex --json-out` → `ci-evidence`（always）→ `ci-provision down`（always）→ `test-ownership check`
  - **实际顺序按 design.md:40 收口，与本行草图有两处差异（ADJ-023）**：`ci-evidence` → `test-ownership check` → **`ci-provision down`（`if: always()`，最后一步）**；前两步条件是 `!cancelled() && steps.go-test.outcome != 'skipped'` 而非 `always()`（缺流仍硬失败，已实测）。
  - 另**删除** job 级 `DATABASE_URL` 字面量、新增 `AIFI45_CI_ADMIN_URL` / `AIFI45_TOOLS_ROOT` / `CRCTL_MJS`（ADJ-022）；`transitions-contract-check` 的旧「Require the tools read credential」换成诊断步；`backend-tests` 加 `Setup Node.js`。
  - RED **49 / 47 / 2 / 0** exit 1 → GREEN **49 / 49 / 0 / 0** exit 0（`red-backend-wiring.txt`、`green-backend-wiring.txt`）。新增 3 个独立测试属计划外守卫（ADJ-026）。
  - `ci.yml` 累计 +113 / −12（S13 占 8 个 hunk，另 2 个属 S2）；YAML 解析通过，**17 job**；含 `AIFIRST` 的行 7 → 19。
- [x] 13.4 本地等价验证全部新增步骤；核对 `ci.yml` 改动触发的 scope 与预计分钟数
  - **7 项逐项真实执行**（`local-step-equivalence.txt`）：诊断（`env -u` 剔除凭据）exit 1 `missing`；pin read 输出 `e52b8081f159…` exit 0；pin check `complete (3 required files present)` exit 0；skip-regex 输出 5 个名字 exit 0；`down` 无 handle **exit 0 空转**；`ci-evidence` 缺流 **exit 1 ENOENT**；`test-ownership check` **exit 0，5 entry(ies) + allowed skips: 4**。
  - **3 条变异全 DETECTED**（内联 skip-regex / 去掉 `always()` / 恢复 job 级 `DATABASE_URL`），各只打中第 46 号测试，`ci.yml` 逐字节还原、sha256 `72c16f6b…` 一致（`mutation-wiring.txt`）。
  - scope：48 个改动文件 → **全部 8 个 scope**（改 `ci.yml` 的既有行为，非回归）；反事实「只改 harness」→ **backend + scripts**；17 job 的 runner 与条件逐个列出，`full=false` 故 windows/macos 腿不触发（`scope-and-jobs.txt`）。
  - **真实分钟数未测量**：没有推送就没有 Actions 计时，属 TC-CBE-005，不报通过。
- [x] 13.5 独立入口真实执行（TC-TOR-004）：两个状态敏感 selection 经 `run-selection --only channel-migration-down|-reapply`；`TestChannelIsolation` 经 WSL `AIFI-ISO`（root + `AIFI45_ISOLATION_PROFILE`）。执行前说明、前后核对容器清单；profile 失效则如实列未覆盖
  - **前半通过**：`channel-migration-down`（state `648-down`）**PASS pass=22 fail=0 skip=0**；`channel-migration-reapply`（state `648-down-up`）**PASS pass=15 fail=0 skip=0**；两条 `ok=true`、`stage=test`、packages=1，实例 `2841871c7e35` / `60b25a7d67dd` 均 `released … remaining=0`；ndjson 92 / 64 事件、**0 行不可解析**。这两条未声明 `expected`，故 `reconciliation=null`，**不冒领 S1 的逐名对账**。
  - 容器清单**前 / 后 / 收尾三次一致**，只有两个既有 Exited 旧容器，卷未触碰；未连 localhost:5432、未放宽 nonce 门禁、未传 `--admin-url`。
  - **后半 UNCOVERED（ADJ-024，不得报通过）**：只读探针实测 AIFI-ISO **无 Go 工具链**、**无 uid 995 / gid 994**（只有 1500/1501）、`/var/lib/aifi45/daemon-iso` 不存在、无仓库 checkout；`requireIsolationProfile` 是 `t.Fatalf` 不是 skip。补齐四项超出 U5，**未安装未创建**，**未做同 uid 替代对照**（SC-TOR-004 明文禁止）。WSL 探针后已自动回到 Stopped，无残留。
- [x] 13.6 `CUSTOM.md` 登记本轮全部上游文件挂钩点
  - 新明细行 **#330**（2699 字符，**7 未转义竖线 / 6 单元格**），覆盖 `ci-paths.json` 2 行、`script-checks` 新步、transitions 凭据替换、backend-tests env/Node/接线块/Test/收尾、`ci-scope.test.mjs` 挂钩与 helper 与测试五组。
  - M31 头 → 「**14 行：#317–#330**」；汇总行 → `#317–#330 | 14 |`，文件清单追加 `scripts/ci-scope.test.mjs` 与 `.github/ci-paths.json`（1557 字符 / 5 单元格）。
  - **完整性实测**：全文件 1098 行（**1097 CRLF / 裸 LF 0**）；**#327=4987、#328=3304、#329=2524 与改前逐字相同**；#317–#330 共 14 行与头/汇总一致；`git diff --numstat` = **21 / 1**，3 hunk（+111 汇总行、743→744 属 **S8** 的 #87 补登、+1079,19 明细段），1+1+19=21 自洽。
  - **四数基线**：实测 **611 文件 / 1678 命中行**、`AIFIRST` **477 文件 / 755 行**，与 S10 **逐位相同**；S13 四个路径全在口径外，**贡献 0**。**仍不补表行**（ADJ-018 三点理由沿用，待裁定）。

## 14. 测试与验证（Part C）

- [x] 14.1 C1 三路并行技术评审（代码 / 测试配置 / 文档），按 `stdd config models` 派发，逐条处置发现
  - **派发**：`stdd config models --format json` **exit 0 / `schema_version=1` / `kind=configured`**，派发前重读。configured：code `strong`/`GB-JP/kimi-k3.1-pro`/`max`、test_config `balanced`/`GB-JP/deepseek-flash`/`max`、docs_skills `economy`/`Gobao/deepseek-flash`/`high`。**requested = 无**（`Agent`、`create_chat_session`、`create_team_task` 三者 inputSchema 均不暴露原生 `model`/`effort`，按共同规则第四档不指定并说明）；**actual = unknown**（宿主无运行元数据，不声称已按档位执行）。**三路独立派发保留**，未合并/未跳过/未补造第四代理。
  - **返回**：code 0/1/2/2、test_config 0/1/1/3、docs_skills 0/0/4/2 → **16 条原始发现、14 条处置**（两对合并）。**FIXED 7 / 部分 FIXED+RECORDED 1 / RECORDED 5 / ALREADY-COVERED 1**。
  - **Gate 2 复核**：docs_skills 重算 **20 个 manifest 哈希 + fingerprint 全部匹配**、18 处 raw 逐字节匹配、3 张旧回执 superseded，当前批准 `phases.spec` **2026-11-12T23:54:09**；本轮编辑的 4 个文件不在 gate 输入内。
  - **MAJOR-1 已修（ADJ-027）**：`CRCTL_PATH` → 受管 `CRCTL_MJS`，删两条相对回落、`t.Skip` → 两条 `t.Fatal`；`git diff --numstat` **9/19**；**四个扫描正则一字未改**、受管集未扩围 → **不需重签 Gate 2**。RED **exit 1，12/11/1** → GREEN **exit 0，12/12**；契约 CLI **exit 0「119 file(s), 0 violations」**；`go vet` 两包 **exit 0**。**真库两条件**：齐备 **pass=13 fail=0 skip=0 exit 0**（与 S4 基线逐名一致，零回归）；`env -u CRCTL_MJS` **pass=0 fail=3 skip=0 exit 1**（三调用方各自 Fatal，`skip=0`）。变异改回别名 **DETECTED**，还原 sha256 `043054f75b5f1e65…` 一致。
  - **MAJOR-2 已修（ADJ-034）**：pin `ref` 断言**就地加强、0 个新增测试函数**。缺口实测证明：`ref: main` 变异下旧用例仍 **15/15 exit 0**。四步：变异+旧 **exit 0，15/15** → 变异+新 **exit 1，15/14/1** → 还原 **exit 0，15/15**（`ci.yml` sha256 `72c16f6b9302bb97…` 一致）→ 回归。
  - **回归**：harness **172/172/0/0 exit 0**（171→+1）、`ci-scope` **49/49 exit 0**。**C1 新增测试合计 +1 个函数**（别名守卫），如实计数。
  - **6 项只记录不修**：ADJ-028（reservation 非锁读，**只加 2 行英文注释、SQL 未改**，待裁定）、029（SC-SEL-002 锁定）、030（不可达，不加防御）、031（扩围超 SC-CBE-004，仓库 119 文件 0 违规）、**032/033（Gate 2 锁定输入，无重签授权故不改）**。
  - **5 处记录更正（原文保留）**：ADJ-018 枚举（`phase-context.md:245` + CUSTOM.md #327）、`slices.md:57` 规划断言、s13 README `:42/:175`「最后一个数据库步骤」与 `:177` 计数 **22 modified + 27 untracked**、CUSTOM.md CR 索引补行 + M31 头/汇总 `#317–#332 / 16`。**test NIT-2 = ALREADY-COVERED**（s6 README:4-6）。
  - **`gofmt -l` 定性**：既有 CRLF 现象（`server/` 下 **2466 `.go` / 2206 CRLF**，governance 点名 **65 个**含从未触碰的 `cmd/migrate/main.go`），`gofmt` 输出与去 `\r` 原文逐字节一致，numstat 9/19 非 432；**未执行 `gofmt -w`**；「`gofmt -l` 无输出」在本机**不成立**。
  - **边界**：容器清单前后一致、两实例 `released … remaining=0`；未连 localhost:5432、未操作旧容器、未放宽 nonce 门禁、未读取/打印/创建凭据；tools 6 处未提交改动未触碰；记录仓他人改动未混入；**未提交、未推送、未部署**。
  - **记账**：CUSTOM.md **#331/#332**（**1101 行**，#317–#332 **16 行连续、每行 7 未转义竖线 / 6 单元格**；#331 曾因 Go 的 `||` 多出 2 个已转义修正，#317–#330 未改）；`pending-adjustments.yaml` **34 条**（未解决 17、major 7）；四数基线 **611 文件 / 1679 行**（#332 贡献 0），**仍不补表行**（ADJ-018 待裁定）。
  - 证据：`validation/c1-review/`（`triage.md` 6 节 + §5.1，12 个证据文件均带实测退出码）。**C1 完成不等于 Gate 3 通过**；C2–C7 尚未执行。
- [x] 14.2 C2 质量检查：`node --test` 全量、受影响 Go 包经一次性库、`pnpm typecheck`/`pnpm lint`；**`make test` 不执行**（U5 排除旧容器与 localhost:5432），如实标注替代口径
  - **真实执行且通过**：harness **tests 173 / pass 173 / fail 0 / cancelled 0 / skipped 0 / todo 0**、`duration_ms 2584.8845`、exit 0（`gate3-followup/harness-after-adj042.txt:174-181`）；ci-scope **49/49/0/0** exit 0（`ci-scope-after-adj042.tap:297-304`）；`pnpm typecheck --force` **10/10 Tasks、Cached 0/10、exit 0、零 TS 错误**；`pnpm lint --force` **7/7 Tasks、Cached 0/7、exit 0、零 error**（仅 unused eslint-disable 类 warning）。
  - **首轮是缓存回放，已更正**：不带 `--force` 时返回 `Cached: N cached, N total` + `>>> FULL TURBO`，**tsc/eslint 根本没跑**；首轮两份日志保留并标注「**缓存回放，不作为真实执行证据**」，`--force` 透传给 turbo、**未改根 script**。
  - **已执行但未通过（不得报绿）**：views 全量 vitest **1 failed / 6371 passed、`VITEST_EXIT=1`**（`c2-quality-round3/views-vitest.txt:8735`）。单跑复现为 `Test timed out in 5000ms`（`vitest-single-chat-window.txt`），全量里是 `AssertionError`，**两者不是同一现象、不合并叙述**；与 ADJ-020 同族但**未宣称 flaky 无影响**（U4 如实报告）。
  - **Go 侧**：本轮未改任何 `.go`，Go 证据由 **18 条命令 CP 在一次性 podman 实例真实执行**承担（14.3）；真库 **46 个叶子 fail 0 / skip 0**、与基线**逐名一致 → 零回归**。**`make test` 未执行**，替代口径已标注、**不声称等价**。
  - **覆盖率＝豁免不是测量**：证据计划 `coverage: not_applicable` + 理由（Go/Node/CI 配置/前端类型检查，采集只支持 pytest-cov；`quality.coverage.enabled=false`）→ (j) **✓ 已声明无覆盖义务**，**无覆盖率保证**。
  - **边界**：6 个一次性实例全部 `released … remaining=0`；`podman ps -a` 前后 `diff` **IDENTICAL**（只有 `55e215cf1066 multica-postgres`、`4d2f95af6982 multica-backend` 两个既有 **Exited (0)**），卷只有 `multica-pgdata`；未连 localhost:5432、未操作旧容器、未触碰卷、未放宽 nonce 门禁、未读取/打印/创建/轮换凭据、未改 secret。
- [x] 14.3 C2 同次执行证据：自生成 run id，`stdd agent verify` 与 `stdd ci check-failures` 用同一值，中间不插入其他 verify
  - **run id `dfb7aad8-7539-486b-aa59-297d57a87d1a`**，同一值传给两条命令，**中间未插入任何其他 verify**。verify **Results: 18 passed, 0 failed**、`VERIFY_EXIT=1`（**源于 `REVIEW_PENDING` 4 项人工 TC，不是 CP 失败**，`agent-verify-round3.txt:86/88/94`）；check-failures **✅8 ⚠1 ⏭0 ❌1**、(l) `Anchoring: L4 >= L4`、自动化检查覆盖 **10/10**、`CHECKFAILURES_EXIT=1`。新 run 实测 **checks 18 / inputs 823 / coverage [] / manual 0**。
  - **两个旧 run 均不可复用**：`97da35cc…` **KeyError 崩溃**（ADJ-036）；`7cd120df…` 曾真实 18/18，但 `evidence.py:735-739` 在 confirm 时**重新快照冻结输入**，本轮编辑 `scripts/aifi45-disposable` 使其失效 → **以新 run id 全量重跑**。新 run 报告与旧 run **sha256 相同**属正常：CP-only 确定性产物**不嵌 run id**（`grep -c` → 0），run 身份由 `tc-evidence.json` 的 `run_id` 与目录名区分，**不是复用旧证据**。
  - **两个数字必须同时呈报（ADJ-040，major，未决）**：命令 CP **18/18 通过** ／ CLI 覆盖判定 **0/22**。`evidence.py:1033-1034` 要求 `len(checks) == len(plan["checks"])`，**18 != 22 即整个 run 无效、覆盖归零**；**新 run 上逐字复现同一判定**，证明是 CLI 口径问题而非执行失败。**不得以 18/18 冒充覆盖通过，也不得把 0/22 说成执行失败。**
- [x] 14.4 C3 逐文件 Diff 审查：无调试残留、无死代码、无注释掉的旧逻辑、与 spec 一致
  - `validation/c3-diff/README.md` **49/49 逐文件**（22 modified + 27 untracked）；**§4.1 新发现 ADJ-042**（parseArgs fail-open，用户裁定纳入本 change 后已修）；§4.2 不重复记录既有发现；**§4.3 保留两条已撤回的误报**；§4.4 观察项不立 ADJ。
  - **§5 事故与恢复如实登记**：审查中途业务仓被外部清理删除，按用户「先护副本，再原地恢复」执行；三份副本（D04 原件**从未写入**、`D:\multica-rescue-20261113`、C: 工作树）。还原后 **22/22 `git diff --numstat` + 27/27 行数**逐项指纹核对，实测 **0 deleted**、tracked **7336**。**ADJ-045**：恢复未覆盖 `node_modules` 与 pnpm store，故须重建依赖。
- [x] 14.5 C4 失败模式检查全量执行（EXP-2026-0001…0005 + 锚定缺失 / Agent CP 失败 / 跨系统不一致），未执行的标 SKIPPED
  - `validation/c4-failure-modes/README.md` **143 行**，逐项实读代码与目录取证、**无占位符**；**8 项检查完成、2 项命中、1 项观察**。**命中 1**＝EXP-2026-0002 `execution_control_reservation.go:88-96` check-then-act（`CreateReservationTx` grep `pg_advisory|Lock|FOR UPDATE` **零命中**，ADJ-028 只加 2 行英文注释、**SQL 未改**）；**命中 2**＝EXP-2026-0004 `provision.mjs` 部分失败不清理已建资源（**不改未申报范围的既有文件**）；**观察项**＝`run-selection.mjs:82` 静默 `catch { continue; }`（ADJ-029，SC-SEL-002 锁定）。EXP-0001/0003/0005 **PASS**（含 retention 测试 uuid 零命中后**实读确认**为纯 schema 测试）。
  - **§4 SKIPPED 表**：4 个 `//go:build linux` daemon 文件 **SKIPPED（本机不可编译）**；**TC-CBE-005 真实 CI run SKIPPED**；**TC-CCF-003 管理员 PAT SKIPPED**。两项命中均按 **U3「停下报告并由用户裁定」**处理，**未自行修改代码**。
  - **口径缺口（ADJ-044，minor，未决）**：资源根内**无「14 类」权威逐项定义**；CLI 确定性子集 **10/10**，其余语义类由 README 人工执行，**两者不混算、不声称 14/14**。
- [x] 14.6 C5 新模式记录到经验库，更新既有命中次数
  - `validation/c5-experiences/README.md`：新增 **EXP-2026-0006**，既有经验命中次数已更新。
- [x] 14.7 C6 汇总 `pending-adjustments.yaml` → `design-adjustments.yaml`
  - **产物名按资源根 3.0.7 口径＝`design-adjustments.md`，不生成同名 `.yaml`（ADJ-043，minor，未决）**：技能层与资源根**都自称 3.0.7 却给出冲突口径**，本轮按资源根模板生成 **649 行**：45 条汇总行 + 45 条详细说明 + **25 行修订需求清单（§A–§E）** + **12 条 Gate 3 呈报要点**。**本行字面的 `.yaml` 按此更正，不为对齐字面伪造第二份产物。**
  - **`pending-adjustments.yaml` 逐字保留，未迁移、未删除、未双写**。实测 **45 条（ADJ-001…045）／resolved true 25 / false 20**；未决 **4 major = 005/024/038/040** + **16 minor = 002/003/006/007/009/018/019/020/028/029/032/033/037/041/043/044**；已解决 major **014/017/025/027/034/035/036**。`.stdd.yaml` `design_adjustments.count: 45` **与台账实测相等**。
  - **三种处置严格分开，`resolved: true` 不得读成「缺口已消除」**：**已修**（025/027/034/035/036/042/045）／**决定不做**（**030** 不可达不加防御、**031** 扫描器不扩围，用户已知＝是）／**移交后续 change**（stdd 侧 037/038/040/041/043/044，用户明示「以后单独完成」）。**031 的理由**：G1 由 `ci-evidence.mjs` 对 `go test -json` skip 事件的**运行时对账**承担，四个扫描正则一字未改、受管集仍 `{CRCTL_MJS, AIFI45_TOOLS_ROOT}`，CLI **exit 0「119 file(s), 0 violations」**。
- [x] 14.8 C7 写 `test-report.md` 与 `validation/acceptance-report.md`（TC-TOR-005）：逐项命令、退出码、pass/fail/skip、未覆盖项与原因
  - `test-report.md` **538 行**、`validation/acceptance-report.md` **482 行**，两份互相一致。**三分类严格分开**：已执行且通过／**已执行但未通过**（views vitest 1 失败 exit 1）／未执行或 SKIPPED，另单列**缓存回放 vs 真实执行**。已知问题与未完成项逐条含名称/原因/影响/补完计划。
  - **验收报告已产出但用户尚未人工逐项核对 → TC-TOR-005 本轮未确认**。
  - **第三轮修复**：本 change **未触发** B3.4 第三轮 strong 派发，故无「切片 N：第三轮…」行；长程约束 #5 需**连续 3 切片**无新增测试，S11=15 / S12=0 / S13=4 **未触发**。
- [x] 14.9 manual TC 确认：TC-CBE-005（真实 CI run，依赖推送）、TC-CCF-003（管理员 PAT）；前置未满足的如实记未闭合，不冒充通过
  - **本轮实际确认数 = 0，未调用 `stdd agent confirm`**。4 项人工 TC（**TC-CBE-005 / TC-TOR-004 / TC-TOR-005 / TC-CCF-003**）全部如实记未闭合：CBE-005 需真实 CI run（**multica 推送未授权**，tools pin 前置虽已闭合但本轮 **CI run 次数 = 0**）；TOR-004 需 WSL AIFI-ISO 独立入口（ADJ-024 四项前置全缺）；CCF-003 需管理员更新 PAT（外部依赖）；TOR-005 需用户人工审阅验收报告原文。
  - **`confirm_manual` 是计划级、全有或全无、一次性**（`evidence.py:740/745-748/754-759/761-764`），**不支持部分确认**；`result` 固定写 `manual-pass`，**确认即等于断言通过** → **不得为凑覆盖伪造确认**。此前「TOR-005 可单独确认」的口径已被证伪并在全部产物中更正。
  - **本行 `[x]` 的含义是「如实记未闭合」这项义务已完成，不是「人工 TC 已通过」**。
- [ ] 14.10 展示 Gate 3 确认框，等待用户明确确认后才执行 `stdd gate approve --gate 3`
  - **确认框已展示、用户已明确确认**，裁定原文：「以「命令 CP 18/18 + 4 个人工 TC 未闭合」确认 Gate 3。」
  - **已按该原文执行 approve，但被 CLI 拒绝批准（ADJ-046，major，未决）**：`stdd gate approve … --gate 3 --confirmed-by dialog --evidence "以「命令 CP 18/18 + 4 个人工 TC 未闭合」确认 Gate 3。" --run dfb7aad8-7539-486b-aa59-297d57a87d1a` → **`APPROVE_EXIT=1`**，stderr「当前执行证据无效: 缺少或重复必需 check（当前运行未完成）」「Gate 3 拒绝批准：选定 run 证据不足。」（`gate3-followup/gate3-approve-refused.txt`）。**批准前无任何写入**：复跑后 `gate status` 仍 **Gate 3 ⬜ pending**（Gate 1/2 保持 `2026-11-13T09:46:15/16`），`.stdd.yaml` 内 `selected_evidence` **零命中**。
  - **根因（实读源码 + 实测解析冻结 fence）**：`gate.py:815-822` 把 `evidence.py:1033-1034` 的「checks 条数必须恰等于计划 22 条」直接作为批准前置 → **18 条命令 CP 全通过也判整个 run 无效**；22 条 check 的 `applicability` 取值集合实测**只有 `["required"]`**，4 条 manual 全为 required，故 `:1055-1060` 的 `not_applicable` 分支**无豁免出口**；`confirm_manual`（`:697-699/740/761-768`）**计划级全有或全无**、每条 `result` 硬编码 **`manual-pass`**、`:748` 拒绝静默覆盖 → **既不能只确认 TC-TOR-005，也不能记录「已审阅但未通过／被外部前置阻塞」**。**这更正了 ADJ-040 的影响范围**：不只是覆盖指标 0/22，而是**硬阻断 Gate 3**。
  - **未采取任何绕过手段**：**未调用 `stdd agent confirm`（4 项人工 TC 确认数 = 0）**、未改 stdd 仓（本会话写入次数 **0**）、未改 `test-plan.md` 或任何 Gate 1/2 manifest 项、未伪造 evidence、**未把拒绝写成通过**。3 项外部前置未满足（真实 CI run／WSL AIFI-ISO／管理员 PAT），确认即等于为未执行项断言通过，被用户「任何未执行、跳过或外部依赖未满足的检查，都不得报通过」与 Skill Gate 3 硬防线禁止。
  - **本行保持未勾选**：approve 未成功即不得标记完成。**三条合法路径待用户裁定**（A 闭合 3 项外部前置后一次性如实确认 4 项；B 正式缩小范围移交后续 change 并重签 Gate 2；C 修 stdd 支持非 pass 人工结论——用户已明示 stdd 项不在本次完成）。详见 `design-adjustments.md` ADJ-046。
  - **用户已裁定 B 路径并已执行（ADJ-047，major，已处置；原文「选B，将需要移交到后续change的项记录在案，供以后能找回修订。」）**：① `test-plan.md` §六 fence 移除 TC-CBE-005 / TC-TOR-004 / TC-CCF-003 三条 manual check，分母 **22 → 19**（18 command + 1 manual TC-TOR-005）；② 3 个 TC 原定义**原位 HTML 注释保留**（实测 `tc_definition_ids` = 19，`check_tc_coverage` 分母同为 19，**移交项不会被算成 100%**），§三/§五 同步标注，新增 §七 移交表；③ `canonical/specs/code` 的 3 个 Scenario **未删**（它们是后继 change 的验收对象）；④ 新建 `validation/handoff/handoff-to-successor-change.md`（3 个 Scenario 与 3 个 TC 定义经脚本逐字比对）；⑤ **Gate 2 于 `2026-11-13T18:33:41` 以 `--reapprove` + 用户原文重签**（`GATE2_EXIT=0`，`gate status` 无 stale；manifest 20 项，`test-plan.md` sha256 `3f7f0ea8…` 与当前文件一致；`stdd canon verify` 复跑 **2/2**）。
  - **第 5 轮证据（同 run 纪律，实测）**：计划变更使旧 run `dfb7aad8…` 按 `_materials_match` 失效 → 新 run **`add97e96-1676-4191-ae65-2ebd6524d585`**（18:33:30 启动）→ **`Results: 18 passed, 0 failed`**，`VERIFY_EXIT=1` **仅因 `REVIEW_PENDING`**（待确认项只有 **TC-TOR-005/main**）；同 run `ci check-failures`：✅8 ⚠1 ⏭0 ❌1，❌ **TC 覆盖 0/19**，理由「当前执行证据无效: 缺少或重复必需 check」——**结构原因同 ADJ-040**（18 ≠ 19，须先 `agent confirm`）；`CHECKFAILURES_EXIT=1`。容器清单运行前后一致（两条旧容器始终 `Exited (0)`），6 个一次性实例全部 `released … remaining=0`。
  - **仍未完成，故本行仍不勾选**：**TC-TOR-005 未 confirm（本会话确认数仍为 0）**；**Gate 3 仍 pending**。范围收窄**不等于**通过，`current_phase` 仍 `build`，**不得进入 DELIVER**。证据：`validation/gate3-followup/agent-verify-scopeB.txt`、`ci-check-failures-scopeB.txt`、`podman-after-scopeB.txt`。
  - **用户已给出核对原文与 Gate 3 确认原文，但 `agent confirm` 被 stdd 缺陷挡住（ADJ-048，major，未决）**：`stdd agent confirm … --run add97e96… --statement "已核对验收报告 §0/§2/§9.3，未发现未执行项被标为通过"` → **`KeyError: 'cp'`（`evidence.py:762`）、`CONFIRM_EXIT=1`**。根因：`_CHECK_FIELDS` 含 `cp`，`confirm_manual` 用 `item[key]` 强取，而 manual 计划项无 `cp`（ADJ-036 同源，第二处实例）。**无任何写入**（run 仍 18 条、`manual` null）。**修法一行 `item.get(key)`，由用户在 stdd 侧执行**（本会话对 stdd 写入数 0）。
  - **代码已提交（用户授权）**：`371e53167`（49 files, +4848/−69），工作树干净；提交后 `ci check-failures` 仍报 18 ≠ 19（输入校验通过）。**分支合并不适用**（改动直接在 `main`，无 change 分支）。**归档、推送未执行**，均等 ADJ-048 修复后继续。