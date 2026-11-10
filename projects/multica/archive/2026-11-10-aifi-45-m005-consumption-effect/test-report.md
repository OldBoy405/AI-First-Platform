# AIFI-45 M005 consumption-effect — BUILD 测试报告（C7，2026-11-10）

> 范围：只陈述本轮**实际执行**的检查。未执行的写「未验证」。长程模式只用于 Gate 2 之后的 BUILD，Gate 3 仍待你确认。

## 一、结论

4 个新增 TC 全部真实通过，整组一次性库回归 12 个选择 **227 PASS / 0 FAIL / 0 skip**。首个 consumption 之后，生产准入可得 `ADMITTED`。该 effect 只表示「平台已核实并提交 consumption」，**不是** T 的业务提交；整条链的 RUN-006 停止/额度、M008 恢复入口、T verdict 入口、历史回填、密钥/manifest 轮换仍在 proposal 的 non_goals，未做。

## 二、新增 TC 覆盖（planned 4 / actual 4）

| TC | Scenario | 入口 | 结果 |
|---|---|---|---|
| TC-CE-001 | SC-CE-001 | `TestTC_CE_001`：真实路由 + 真实库；查存储行：command(settled_effect)/verdict(command_digest、request_id)/settlement(effect_kind=consumption、receipt=库内回执 id)、commit_ref 与 reservation 指向回执、两个 envelope 用平台公钥验签通过、准入由 WAIT_CONSUMPTION 变 ADMITTED | PASS |
| TC-CE-002 | SC-CE-002 | `TestTC_CE_002`：占位同 request_id 的 command，断言 500、日志含「effect not issued」与 `EXECUTION_CONTROL_STORE_CONFLICT`，回执行、verdict、settlement、cursor 均无 | PASS |
| TC-CE-003 | SC-CE-003 | `TestTC_CE_003`：CR-A 第二个 task 得 seq=2，command 与 verdict 的 prev 都指向首条 verdict digest；CR-B 独立从 seq=1 起，两者准入均 ADMITTED | PASS |
| TC-CE-004 | SC-CE-004 | `TestTC_CE_004`：重放 200/changed=false；新 generation 201 且回执行 +1；整条 lineage 的行数与 cursor 快照均不变；准入仍 ADMITTED | PASS |

另有既有回归 TC-RUN-003 / SC-RUN-003，`run-routes` 选择通过。它直接种入回执和 `dispatch` 结算，并未验证真实 consumption effect 后的 wake；TC-CE-001 单独验证真实签发后的准入。两项未在同一条 wake 流程中串测。

## 三、切片验证（B3.4）

| 切片 | TC | RED | GREEN | 备注 |
|---|---|---|---|---|
| S1 签发 + 原子 | TC-CE-001/002 | 4 个 TC 首跑 pass=0 fail=4（缺 effect） | 实现后 3/4 绿 | CE-003 首轮失败是测试夹具问题（同 challenge 复用），已改为按 task 派生 challenge |
| S2 链连续 + 守卫 + 新 generation | TC-CE-003/004 | **未单独 RED**：实现一次写成含守卫与按 lineage 派生的 store，首跑即绿 | 绿 | 用变异证明测试能抓：① store_id 改回常量 → CE-003、CE-004 失败；② 去掉「同 task consumption effect 则跳过」→ CE-004 新 generation 失败；变异均已还原并复跑 |

## 四、回归（整组 `selections.json`，每个选择一个一次性库，本地 pgvector 容器、tmpfs、仅 127.0.0.1）

| 选择 | pass / fail / skip |
|---|---|
| run-routes（含 TC-RUN-002/003/010） | 16 / 0 / 0 |
| run-admission-support | 49 / 0 / 0 |
| run-root-and-dispatch | 11 / 0 / 0 |
| run-daemon-contract | 18 / 0 / 0 |
| notice-routing | 9 / 0 / 0 |
| channel-migration-up / down / reapply | 19 / 22 / 15，均 0 fail / 0 skip |
| channel-protocol | 46 / 0 / 0（首跑缺 `AIFI45_TOOLS_ROOT` 致跨语言向量 2 例失败，设该环境变量指向 sibling tools 后重跑通过；与本 change 无关） |
| wp4-original-mapping / wp4-concurrent-replay | 1 / 1，均 0 fail / 0 skip |
| **m005-consumption-effect**（新 4 例 + 既有 TestExecutionConsumption* 四族） | 20 / 0 / 0 |

合计 227 PASS / 0 FAIL / 0 skip。`go build ./...`、`go vet`（governance、cmd/server、daemon、service）退出 0；新增与改动文件 `gofmt -l` 无输出。

## 五、C1 三路评审（`stdd config models` 本轮已读，派发前重读）

| 代理 | 档位 | configured | requested | actual |
|---|---|---|---|---|
| code | strong | GB-JP/kimi-k3.1-pro:max | 同左（model 与 effort 均传） | unknown（无运行元数据） |
| test_config | balanced | OpenAIPersonal/gpt-6.1-terra:xhigh | 同左 | unknown |
| docs_skills | economy | Gobao/deepseek-flash:high | 同左 | unknown |

处置：
- code：无发现。
- docs_skills：7 条 MINOR。已改 `execution_admission.go` 三处陈旧注释、`execution_consumption.go` 头注释补一条、CUSTOM #313 行与 M27 索引（路径并入花括号组）、CUSTOM 第 183 行状态；`test-report.md` 现已存在；按用户要求，`test-plan.md` 已补既有 TC-RUN-003 的 Scenario 映射；覆盖边界已展示，Gate 2 于 2026-11-10 23:14 重新确认。执行状态记在本报告，TC-RUN-002/010 与 NTF 回归已在上表。
- test_config：6 条 MAJOR + 1 条 MINOR。已采纳并改测试：CE-002 断言 500 并捕获日志证明失败原因；CE-001 用库内回执 id 对账并验 command/verdict 的 envelope 签名；CE-003 同时查 verdict.prev_digest；CE-004 改为整条 lineage 的行数与 cursor 快照。**未采纳**：`run-selection.mjs:131` 用 `reconciliation?.matched`，而 `selection.mjs` 返回的是 `status`——这是上一个 change 已有的脚本缺陷，且没有任何选择配置 `expected`，当前不生效；不在本 change 范围，记为已知问题。cursor 按 `consume:<crID>` 查询：crID 由夹具计数器生成且每次用一次性库，保留。

## 六、失败模式检查（C4，`stdd ci check-failures` 确定性子集 + 人工项）

- 通过：(a) 必需文件、(d) TC-ID 唯一（5，包括既有回归 TC-RUN-003）、(f) THEN 含 SHALL、(g) AND 数量、(k) 契约一致（2 个 capability）、(l) 无需锚定、2 个切片均有验证证据。
- (b) 范围蔓延警告：9 个文件。本轮实际改动只有 `CUSTOM.md`（AGENTS.md 要求登记）与 `scripts/aifi45-disposable/selections.json`（proposal C4 已声明），其余是该工具对基线的比较结果，不是本轮改动（`git status` 仅 6 个路径）。
- 仍有两个错误：缺少 `coverage.json`；当前执行覆盖为 0/5，因为没有调用方独立选定的 run。上表是 run-selection 的实际测试结果，但不能代替这两个检查的签收，也不代表检查通过。
- 人工项：Agent CP（CP-CE-001..004、CP-RUN-003）对应的测试均已由 harness 真实选中并 PASS；跨系统一致性（spec↔design↔代码↔CUSTOM 的 ID/名称）由 docs_skills 核对通过；锚定、经验库命中为 0 条。
- 经验库：新增 EXP-2026-0001（常量 id 撞不含分链维度的唯一键）、EXP-2026-0002（check-then-act 的守卫放在序列化锁之前）。

## 七、已知问题与未完成项

| 项 | 原因 | 影响 | 计划 |
|---|---|---|---|
| effect 不是 T 业务提交 | proposal 已划定：服务端核实不了 T 的工作 | 整条链仍无 RUN-006 停止/额度与 M008 恢复入口证据 | 后继 change（未注册）；Gate 3 展示 |
| 签发与验签同进程、manifest 进程内生成，非独立信任根 | 设计决策 3；边界是私钥与库凭据不到 agent | 部署边界检查（`.env`/私钥/库凭据对 agent 不可读）未验证 | 上线就绪清单 |
| 历史回执不回填 | 设计决策 2；回填无法重新证明历史事实 | 旧 CR 仍停在 WAIT_TRUSTED_T_COMMIT | 如需放行旧 CR，另行裁定 |
| 并发 generation 形态未测 | 设计决策 5 已由锁序与守卫位置保证；压力用例不在本期 | 并发路径仅靠设计与既有 `TestExecutionConsumptionIsRaceFree`（同 generation）保护 | test-plan §五「本期不补」 |
| 真实 consumption effect 后的 wake 未串测 | TC-RUN-003 直接种入回执和 `dispatch` 结算；TC-CE-001 单独验证真实签发及准入 | 无同一条流程从真实 consumption 路由到 wake 派发的测试证据 | 已向用户展示覆盖边界；本轮未补串测 |
| `run-selection.mjs` 的 `reconciliation?.matched` 判定无效 | 上一 change 的脚本缺陷，`expected` 未被任何选择使用 | 当前无影响 | 另行修复 |
| 真实客户端、跨主机、生产部署未验证 | 本轮只在一次性库内走真实路由 | 无生产放行证据 | 随后继 change 与上线检查 |

## 八、环境与清理

一次性库容器 `cd303b9ee18b…`（label `stdd.change=2026-11-10-aifi-45-m005-consumption-effect`，127.0.0.1:55433，tmpfs）仅用于本轮；完成后按 ID 删除，不碰 `multica-postgres`、`multica-backend`、`aifi45-disposable`（后者是上一个 change 遗留的容器，未核实归属，未动）。
