# Gate3 测试/配置轴与文档轴评审结果 — 2026-10-26

非作者只读评审。不给 Gate 结论；actual 无后端回执记 unknown。

- 测试/配置轴 session `01a177c6-c315-77b9-a3c5-0f66461af0d8`（requested `Gobao/deepseek-flash:max`）：**INCOMPLETE**
- 文档轴 session `01a177c6-c334-77b9-a3c5-0f6b540e1c5b`（requested `GB-JP/deepseek-flash:high`）：**INCOMPLETE**

## 测试/配置轴 findings

| 严重度 | 文件/证据 | 反例 | 最小修复 | 本轮处置 |
|---|---|---|---|---|
| blocker | `lib/workspace-transactions.mjs:2037-2049` vs `evd-009-wiring-20261026/meta.json` | 证据记录的变异锚 `if (payload.releaseReceipt) {` 在当前文件不存在；照 meta 复跑会得到语法错误型 RED 或 replace 空转→假 GREEN；"还原逐字相同"只是自述 | 对当前字节重做 RED→还原→GREEN，meta 记 pre/post sha 与锚点存在性 | **已修**：`meta-current.json` + `red-drop-remote-published.tap` / `red-drop-pinned-guard.tap` / `green-current.tap`，两条变异各 fail=1（4 例中），green 4/4，还原 sha 一致 |
| major | `:2041-2049`、`:2143-2147`、`:2170-2174` | `pushed` 只在 push 后落盘；崩溃窗口或 `classifyRemoteCommit='confirmed'`（只置 confirmed）时远端已发布但本地 false → 用新审批覆写 receipt | 判据改 `pushed || confirmed` 或"远端已含 mergeSha"，并补两条恢复路径负例 | **已修**：改用远端祖先核对（`git merge-base --is-ancestor`），新增用例「push 成功但 journal 未落盘」并做变异验证（去掉远端判定即 fail=1） |
| major | `test/merge-release-recovery.test.mjs:52` + `delivery-contract.test.mjs:456-484` | 两用例都不校验析取项，删掉仍全绿；TC-EVD-009 的 CP 用合成 receipt，不经过 `releaseReceiptOf`，mergeCr 未接线时照样 PASS（cp tap 仅 1 条 1.3ms） | 加"删条件必须变红"的变异；CP 增端到端断言 | 变异已补；**CP 端到端断言未补**（见 closeout 待办） |
| major | `scripts/aifi45-db/run.mjs::assertVerifiedTests`（只判 `leaf_pass>0`）+ `run.test.mjs`「all skipped leaves…」 | 自测明确断言"1 pass + 1 skip = 合格"，`-skip=` 也在合法 flag 内；实证 `f4-headrecord-20261026-green.meta.json` `skip:1` 仍被接受 | 断言 `counts.skip===0`（或白名单）；拒绝 `-skip` 覆盖关键 TC | 未修（待办） |
| major | `governance/approval_gate_binding_test.go:157` 等 10 处、`gate_review_test.go:41`… | `if testPool == nil { t.Skip }`：裸 `go test ./internal/governance` 的包级 ok 掩盖全部 DB 用例 SKIP；`scripts/test-go.sh` 不统计 skip | 新用例改 `t.Fatal("dedicated database required")`；脚本解析 `-json` 断言 skip==0 | 未修（待办） |
| major | `governance/crsync_test.go:34-40` | `DATABASE_URL` 为空时回退 `postgres://multica:multica@localhost:5432/multica`，裸 `go test` 可能写到非 disposable 共享库 | 无 `DATABASE_URL` 即 `t.Fatal`，禁 localhost 默认回退 | 未修（待办） |
| major | `server/migrations/643..647_*.{up,down}.sql`；证据只出现 `.up.sql` | 643-647 的 **down 从未被执行**；无 up→down→up 往返；`run.test.mjs:42,66` 只验路径正则 + 虚构 `644_followup.down.sql` | 用 `-migration=…down.sql` 跑一次往返（含 645 TRUNCATE 触发器 drop 顺序），纳入 TC 证据 | 未修（待办） |
| minor | `643/644 up.sql` | 只有 `BEFORE UPDATE OR DELETE`；645 有 `BEFORE TRUNCATE` 且有用例，643/644 无守卫也无用例 | 644 补守卫与用例，或明确记录允许 truncate | 未修（记录） |
| minor | `scripts/aifi45-db/run.test.mjs`、`f4-*.meta.json` argv | runner 固定 `-timeout=180s` 再拼用户值，meta 记两个互相矛盾的 flag | 只在用户未给时注入默认 | 未修（记录） |
| minor | 两仓 `.stdd.yaml`（traceability 全 0）、`config.d/quality.yaml` | 台账称 41/49，但 `.stdd.yaml` 的 spec_scenarios/tc_cases/test_functions 仍 0/0/0；项目 quality.yaml 的 review.agents 无 tier 字段，分层只在 user defaults | 更新 traceability 或注明"不采用该计数"；项目配置显式写 tier 或注释指向 defaults | 未修（记录） |

测试轴正向核实：`evd-009` 旧证据计数自洽（RED 2 测 1 fail 且为 `ERR_ASSERTION`、正对照仍 pass、GREEN 2/2、回归 23/23、邻接 69/69、skip 0）；governance 包未见包级可变测试状态；拒绝侧与正例两侧都有，未见 vacuous 断言。

## 文档轴 findings

| 严重度 | 问题 | 位置 | 处置 |
|---|---|---|---|
| major | 记录把 EVD-009 守卫写得比代码宽（说"重入已有 receipt 即拒"），未写"远端已发布"这一前提；读者会以为 pre-publish 重做审批也被拒 | `tc-coverage` 增量 20；`evd-009-wiring-plan-20261026.md` 实施段 | **已修**（本文件同批更正） |
| major | EVD-009 动态证据与 HEAD 源码不对应（旧 green 2 例、旧锚点） | `evd-009-wiring-20261026/` | **已修**：`meta-current.json` + v3 tap |
| major | CUSTOM 漏登记：`CUSTOM.md` 止于 #200，`EVD-009|releaseReceipt|mergeCr` 全文 0 命中 | `multica/CUSTOM.md` | **已修**：#201 |
| major | 另一处 AIFIRST 改动无登记：`tools/lib/execution-sensitive-action.mjs:1`（SC-AUTH-005/006）在两份 CUSTOM 均无 | `tools/CUSTOM.md`、`multica/CUSTOM.md` | **待办**（需先定登记载体：该文件属 tools 内部能力或跨仓定制） |
| major | RUN-009 剩余缺口枚举不完整：`run-r2-prerequisite-finding.md` 含 policy/receipt/UUID，`tc-coverage` 增量 20 写成"4→3 项"漏了 run 维度、policy、receipt | `tc-coverage` 增量 20 | **已修** |
| minor | 已被推翻的前提留在权威台账：增量 15「测试内打开准入」与 run-r2「不存在可打开的准入开关」相悖；正文「执行授权端点被显式禁用/503」与抬头更正并存 | `tc-coverage` 增量 15、`run-r2-prerequisite-finding.md` | **已修**（加作废标注） |
| minor | EVD-009 覆盖面两处结论不同（一处说 writeback 是"授权可接"缺口，一处说"按构造无必要"） | `evd-callsite-audit` vs `evd-009-wiring-plan` | **已修**（标注前者是"授权"、后者是"无必要"） |
| minor | 引文计数错：更正段引「缺的 40 条」实为「39 条 + 1 条」，「40」出自 `CUSTOM.md:823`（#182） | `tc-coverage` 更正段 | **已修** |

文档轴正向核实：`增量15` 起 41/49 算术一致（AUTH10+EVD10+RPR12+NTF7+RUN2）；`run-r1-…meta.json` 9/9/leaf9、`ntf-n3-…meta.json` 7/7/leaf7 与增量相符；`TestTC_RUN_004/005`、`TestTC_NTF_001–007` 真实存在；`evd-callsite-audit` 抽查行号全部真实；M003「通道搁置/未注册」与 plan 头部及目录实际一致；未发现"把计划评审写成实现验证"。
