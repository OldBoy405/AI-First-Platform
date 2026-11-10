# 新 disposable PG 第一阶段：Go 测试选择对账切片

## 范围

实现一个纯内存组件，比较调用方提供的完整预期测试事件名清单与一份 Go `test2json` 事件流，避免将 exit 0、零选中、父测试 PASS / 子测试 SKIP 或漏测误作匹配。该切片在 [第一阶段决定](new-disposable-pg-first-stage-confirmation.md) 范围内；不是可运行的新 PG runner，不操作容器、数据库、文件、网络或子进程，不导入旧 runner。新组件不创建权威账本。

**文件：** 新增 `../multica/scripts/aifi45-disposable/selection.mjs` 和相邻纯内存测试；按当时 `CUSTOM.md` 结构登记。具体状态及测试证据在实现后记录。

**接口：** `verifyGoTestSelection({ expected, ndjson, exitCode, signal, streamEnded })`；`expected` 为非空且不重复的 `{ package, test, leaf }` 数组，包含父和子测试，`leaf` 为调用方对该项是否叶子的布尔断言，每个包至少一个 `leaf:true`；`ndjson` 为完整事件字符串，`exitCode`、`signal`、`streamEnded` 为调用方提供的结果。返回固定、不包含被测输出或原异常的 `matched`/`blocked` 和原因枚举。每个预期包及每个运行测试须有唯一的合法开始及终态；实际全部测试事件名与清单必须精确一致。包失败、任何测试 fail/skip、未知事件、解析不完整、重复事件、零声明叶子、信号或退出未知均不得匹配；不支持重复 `-count` 运行或额外 benchmark/build 事件时应阻断而非忽略。

接口只针对同进程可信的普通数据；它没有拒绝或隔离会执行副作用的 getter、Proxy 或被篡改的同 realm 内建对象，未来调用方不得把不受信任的 JS 对象直接传入。输入中预期清单、事件与退出回执的来源和完整性必须由未来调用方另行绑定；`leaf` 是调用方声明，不能从含 `/` 的名字简单推断：一个子测试名字可自身含斜杠，平行兄弟亦可能有前缀关系。该函数不能证明叶子标记或清单已获批准、原 TC 全部覆盖、原始流未被替换/中途截断、进程树真实退出或数据库正确。`streamEnded` 是调用方断言，不是 OS 退出证明。真实入口需要在接收时限制输出总量和保护敏感数据；组件不输出 event 内容，也不宣称管道/调用者副本擦除。

## 验证

使用 Node 内建 `node:test`、合成事件和内存参数，预先逐文件检查导入及副作用；不依赖文件夹、共享临时文件或其他进程（Node 测试运行器自身进程除外）。至少覆盖正例、多个包及 CRLF、子测试层级、父 PASS 子 SKIP、缺包/缺叶/额外叶、重复终态、零选中、失败/未知 action、不完整或非 JSON 行、无 EOF、非零/未知退出和合成 secret 不回显。先确认行为断言的 RED，再最小实现并 GREEN；新增能力的 RED 是显式 stub 而非对旧业务行为的复现。独立静态复核后再谈扩大范围。

## 作者的受限结果

已新增上述两个文件，`CUSTOM.md` #302 已登记；关联 CR 编号在主工作区 CR 记录中未找到，不据其他条目臆造。在普通数据与未篡改内建对象的前提下，预检未发现测试或组件自身的文件、网络、环境、动态导入或业务子进程调用；测试仅引用 `node:test`、`node:assert/strict` 和本组件。Node 测试运行器自身可创建子进程，环境裁剪并非沙箱。

首轮使用显式“总是 matched” stub，Node 24 观察到 18 项中 15 个行为断言失败、3 个正例通过；这是**新组件的 stub RED**，不声称复现了既有 runner 的行为。随后实现并补强测试后，Node 20.20.2、22.23.4、24.15.0 各 **21/21 PASS，0 fail/cancelled/skip/todo**；完整 TAP 未留存。LF SHA-256：`selection.mjs` `5a9797cfd341fe85c61bcc1e7639643a826223c1e1b23e0eeab8803b6cb4bd59`，测试 `8222077ab867e0a414c3e6f257b1afe6607c41de0f217a64e8d102f736e25f22`。已针对重复终态、异常事件和 duplicate-key 反例补强阳性背景与输入替换断言，并增加真实形态 output 事件、双包交错和抛异常 getter 的合成例。另在 Node 24 使用内存 `SourceTextModule`、替代 `node:test` 注册器与真实断言，原模块 21/21 通过；分别只在内存禁用 fail/skip、重复 JSON 键、未知包、清单重复、未知事件字段和进程回执六项检查，或阻断双包交错、改变异常处理，各自命中对应测试失败。该变异探针不是 Node 原生测试 runner 的独立复跑，也未写仓库源码或保留原始 TAP。

独立静态审查会话 `01a1a93a-b218-7374-9f4d-473e53acfdfb` 请求 strong 档 `OpenAIPersonal/gpt-6.1-sol:high`，在限定接口合同内未确认 P1/P2；指出 output/异常和双包交错的两项测试缺口；作者随后按上文补强，同一审查会话只读复核认为补充测试可静态辨识，原限定结论仍适用。无 actual backend 回执记 unknown。它未运行测试、不证明清单可信、缓存新鲜性、完整 Go 事件兼容、进程树或业务 TC。

下一切片筛选 `01a1a974-f9c9-7374-9f4d-475bd6225304` 请求 balanced 档，建议用单次调用标识比对计划与回执；该方案仍以同次事件及回执的可信采集者为前提，而当前尚无已核实的实际采集接线。仅比对调用方自报 ID 不能建立同次来源或进程树退出，因此本轮不新增一层自报比对或称其为来源证明；待实际生产采集边界设计和验证时再决定。草案 §7 已补充同次调用、EOF/退出结果和防缓存重放的待满足要求；`01a1a948-cd44-7374-9f4d-474ce5d3e2d1` 只读复核认为未降低 TC，也未暗示采集已实现或真实资源已获批。两次审查均未运行测试，actual backend 无回执记 unknown。

不修改原 TC、Gate、`.stdd.yaml` 或历史记录；M006 仍 unresolved。真实资源、迁移路径/文件集冻结、全量清单生成、进程监督和新入口仍需完成，资源操作仍须另行审批。

## 现存测试来源候选（静态，未冻结）

以下路径相对 `../multica/server`。名称相同不代表真实入口或整条业务 TC 已覆盖；原 RUN CP 以 `../canonical/specs/agent/authorized-runner.yaml`、NTF CP 以 `../canonical/specs/agent/attention-routing.yaml` 为准。未运行这些测试或建立数据库。

| TC | 源码中现存的候选顶层测试 | 限制 |
|---|---|---|
| RUN-001 | `./internal/governance:TestExecutionAuthorizationBuildsSignedStructuredSource` | 原 `./cmd/server:TestTC_RUN_001` 未找到，缺授权跨阶段真实链。 |
| RUN-002 | `./cmd/server:TestTC_RUN_002` | 路由负例，不代表整链验收。 |
| RUN-003 | `./cmd/server:TestTC_RUN_003`；`./internal/governance` 的 CP-RUN-003-A～N | 使用 fixture 和直接 wake，缺真实 periodic scheduler 与可信 T 链。 |
| RUN-004 | `./internal/governance:TestTC_RUN_004` | 原 `./cmd/server` 同名入口未找到，缺真实 TaskService 跨 run 入队。 |
| RUN-005 | `./internal/governance:TestTC_RUN_005` | 原 `./cmd/server` 同名入口未找到，缺真实 Git、T 扣额与恢复链。 |
| RUN-006 | `./internal/governance:TestChannelPolicyResume`；`./internal/daemon:TestExecutionAdmissionMissingConsumptionReceiptRefuses`、`TestExecutionAdmissionRevocationRefuses` | 原 `./cmd/server` 同名入口未找到，缺故障、收尾、撤销与签名恢复联合链。 |
| RUN-007 | `./internal/governance:TestMDispatch001`、`TestRunnerStartupAndEventWakeSourcesConvergeOnReconcile` | 原 `./cmd/server:TestTC_RUN_007` 未找到，fake enqueuer 不能证明四阶段真实闭环。 |
| RUN-008 | `./internal/governance:TestRunnerDigestMismatchIsRecoverableOnSameRun`；`./internal/daemon:TestStrictExecutionContractTreatsLegacyAsLegacy`、`TestStrictExecutionContractRefusesUnsupportedAndAmbiguous` | 原 `./cmd/server:TestTC_RUN_008` 未找到，缺切换、回退与历史保护联合矩阵。 |
| RUN-009 | `./internal/governance:TestRequirementReviewRunsOnASeparateAgent`、`TestRequirementSameAgentForBothRolesIsRefused`、`TestRequirementDigestDriftKeepsRunResumable` | 原 `./cmd/server:TestTC_RUN_009` 未找到，缺逐字段身份漂移和交付证据联合入口。 |
| RUN-010 | `./cmd/server:TestTC_RUN_010` | 路由验证 scope 和 receipt，不证明真实外部敏感动作恰好一次。 |
| NTF-001 | `./internal/governance:TestTC_NTF_001` | 手工事件静默测试，未证明运行记录可查的真实链。 |
| NTF-002 | `./internal/governance:TestTC_NTF_002` | 事件与受众由 fixture 构造，未证明三类真实生产事件完整接线。 |
| NTF-003 | `./internal/governance:TestTC_NTF_003` | 未驱动维护故障的有界恢复耗尽。 |
| NTF-004 | `./internal/governance:TestTC_NTF_004` | 未证明实际业务授权权限及完整分流。 |
| NTF-005 | `./internal/governance:TestTC_NTF_005` | 缺跨 commit 生产路径、广播及客户端可见提醒的联合证明。 |
| NTF-006 | `./internal/governance:TestTC_NTF_006` | 未独立覆盖真实受众变化、各类新失败和交付事件。 |
| NTF-007 | `./internal/governance:TestTC_NTF_007` | 未联合证明业务副作用不重复及客户端幂等；写前分支亦未验证从已提交事实重建。 |

NTF 七项原 CP 均声明 `./cmd/server`，该包未找到同名函数；不能用 governance 组件测试替代。当前仅能识别现存来源候选，尚未冻结源码快照、每次调用的完整父／叶事件、初态与可信回执，故不能形成可执行清单或计任何 TC PASS。各包 `TestMain` 与调用必须逐文件预检，特别是 service 的 `TestChannelTaskTx` 存在默认数据库回退；不运行任何可能连库的入口。只读核查及独立复核均请求 balanced 档 `OpenAIPersonal/gpt-6.1-terra:xhigh`，actual 无回执记 unknown。独立复核确认 17 行候选函数及 RUN-003 补充 CP A～N 存在、原主 CP 均指向 `./cmd/server`、所列同名入口缺失声明属实；可运行性和业务覆盖仍为 unknown。

## 每选择一个一次性数据库（2026-11-10）

`scripts/aifi45-disposable/provision.mjs` 提供两个操作：按 nonce 建 `aifi45_tmp_<16hex>` 库与 `aifi45_role_<16hex>` 非 superuser 角色、写 `AIFI45_DISPOSABLE:<nonce>` 注释并建 pgcrypto/pg_trgm/vector；删除前回读该注释，标记不符即拒绝。`run-selection.mjs` 把「建库 → `go run ./cmd/migrate up` → 初态（`migrated` / `648-down` / `648-down-up`）→ `go test -run … -json` → 精确删库」串成一个选择一条链，退出码非 0 或零选中都不算通过。

真实容器实测（本地镜像、`--pull=never`、tmpfs、仅绑 127.0.0.1、按 ID 删除并回读 label 为 0）：

| 选择 | 结果 |
|---|---|
| notice-routing | PASS 9 |
| channel-migration-up | PASS 19 |
| channel-migration-down | PASS 22 |
| channel-migration-reapply | PASS 15 |
| channel-protocol | PASS 46 |
| wp4-original-mapping | FAIL 1（`execution_authorization_head_test.go:41` 同 CR 被重复播种，rows=2） |
| wp4-concurrent-replay | FAIL 1（`execution_wp4_slices_db_test.go:196` 用新生成的 VerdictID 断言原映射） |

前两组把 5 个此前互相污染的用例变成可独立复现的绿色；WP4 两条是既有测试夹具缺陷（改造前首轮同样失败），本轮未改动，也不据此宣称 M008 恢复链通过。初态仍是闭集，不提供任意 SQL 入口；进程树退出与持久化证据仍由调用方负责。

## WP4 夹具修复后复跑（2026-11-10）

`TestWP4OriginalMappingAndMergeReportDB` 与 `TestWP4ConcurrentControlSettlementReplayDB` 的两处失败均为夹具缺陷，已修：

1. **OriginalMapping**：用例在授权头夹具已创建 CR 之后，又经 `readerProject` 再次进入「scope 必须为空」的创建路径。改为读取已有 CR 的 project，不再重复创建；产品断言全部保留。
2. **ConcurrentSettlement**：失败并非 VerdictID 不同（实测输入与返回同一 UUID），而是 `EffectRef` 的字节比较受 JSONB 规范化影响（`{"task":"original"}` vs `{"task": "original"}`）。改为按 JSONB 输出格式构造并保留 VerdictID 相等、字节相等、恰好一次首写、仅一行 settlement 的全部断言。

修复后在各自一次性库上正序、反序各跑一次均 PASS，排除两条之间的顺序依赖。

整组复跑（每个选择独立建库，单次运行，0 skip）：

| 选择 | 结果 |
|---|---|
| notice-routing | PASS 9 |
| channel-migration-up | PASS 19 |
| channel-migration-down | PASS 22 |
| channel-migration-reapply | PASS 15 |
| channel-protocol | PASS 46 |
| wp4-original-mapping | PASS 1 |
| wp4-concurrent-replay | PASS 1 |

容器按 ID 删除，`--label aifi45-run` 回读 0；既有 `multica-postgres`/`multica-backend` 未受影响。

## 全包回归（2026-11-10，干净库单次）

修完 WP4 夹具后，在同一一次性库上跑 `go test ./internal/governance -count=1 -v`：**405 PASS / 3 FAIL**。3 项失败全部是 `TestChannelMigrationAfter{Up,Down,Reapply}`——它们断言「648 之前 / 648 down 后 / 648 重放后」三种互斥初态，在**同一个库**里必然互相冲突；按选择隔离后（`migrated` / `648-down` / `648-down-up`）三条各自 PASS，已在上一节列证。

同行 PASS 的包括 `TestTC_NTF_001～007`、`TestOwnersEventProjectsRoleOwners`、`TestNoticeGoesToTheRecordedRoleOwnerAndItsConversation`、`TestWP4OriginalMappingAndMergeReportDB`、`TestWP4ConcurrentControlSettlementReplayDB`、`TestChannelMigrationProtectedData`。

结论：全包运行对这三条是**结构性不适用**，不是缺陷；验收以「每选择一个一次性库」为准，并在记录中同时给出全包数，避免只用一种口径。
