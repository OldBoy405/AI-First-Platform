# AIFI-45 multica — BUILD 测试报告（C7，2026-11-10）

> 范围：只陈述当前 HEAD（multica `26f6c5b0a` + 未提交的 5 个小改动）上**实际执行**的检查。未执行的一律写「未验证」，不用组件证据冒充整链。
> 口径：不追求检查数量；用一组有限的保证，每条配一个职责清晰的入口。历史台账只作链接，不再合并重算。

## 一、结论

**Gate 3 不具备「全部 TC 通过」的条件。** 6 条保证有当前源码的真实通过证据；M005 生产者侧缺失，使整链放行（`ADMITTED`）在生产不可得，这是设计内的失败关闭，不是缺陷。剩余项见第四节，均需人工决定或属已移交载体。

## 二、保证 → 当前证据

执行入口：`scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json`，每个选择一个一次性库（本地 pgvector 容器，tmpfs、仅 127.0.0.1），整组 **11 个选择 / 207 PASS / 0 FAIL / 0 skip**，容器按 ID 删除、label 回读 0。`go build ./...`、`go vet`（governance、daemon、cmd/server、service）退出 0。

| # | 保证 | 唯一入口 | 结果 |
|---|---|---|---|
| G1 | 授权只来自认证路由；task-token、伪 header、越权成员、daemon token 都不能授权，敏感动作无专项授权不执行 | `cmd/server` TestTC_RUN_002 / TestTC_RUN_010 | PASS |
| G2 | 准入失败关闭：无已提交的可信 T 裁决、verdict 验签/主体/命令摘要不符、等待态都不放行，且等待不记为失败 | TestTC_RUN_003 + 003-A…N（49 例，governance） | PASS |
| G3 | 唯一永久派发根；崩溃恢复同根有界子链、不重复扣额；四阶段可恢复；漂移与同作者评审不推进 | TestTC_RUN_004/005、TestMDispatch001、RUN-009 三例（11 例） | PASS（RUN-004/005/007/009 为部分覆盖，不计整 TC） |
| G4 | 新旧合同不串用；daemon 仅在绑定与消费齐备后启动 | `daemon` TestStrictExecutionContract（18 例） | PASS |
| G5 | 通知：必要事件才通知、同 CR 同 Inbox ID、业务提交后写、故障后重投不丢不重 | NTF-001～007 + 角色 owner 路由（9 例） | PASS（DB 层）；客户端真实载荷仅局部 Vitest 48/48，**真实 OS/跨会话未验证** |
| G6 | 迁移 up/down/reapply 与受保护数据；结算同义重放返回原映射 | channel-migration 56、channel-protocol 46、WP4 两例 | PASS |

## 二之二、切片登记（B3.4 投影）

`.stdd.yaml#phases.build.slices_completed` 只登记本轮入口命令真实选中并通过的 4 个代码切片，`new_tests` 是该切片文件范围内新增的测试函数/用例数（口径写在各条 note）。**M-S4「全量回归与 Gate 3」本身不是代码切片**，其证据是本节第二节的整组 11 个选择与第三节的三路评审，不另列 `new_tests`，避免用重跑的既有用例充数。

## 三、C1 三路评审（配置：`stdd config models`，本轮已读最新配置）

| 代理 | 档位 / requested | actual |
|---|---|---|
| code | strong · `GB-JP/kimi-k3.1-pro:max` | unknown |
| test_config | balanced · `OpenAIPersonal/gpt-6.1-terra:xhigh` | unknown |
| docs_skills | economy · `Gobao/deepseek-flash:high` | unknown |

另有两个只读探查代理在用户更新 balanced 之前用旧配置派发（仅事实调查，非 C1，其结论已由主会话在源码核对）。

处置（按类别，不逐条加检查）：

| 类别 | 发现 | 处置 |
|---|---|---|
| 已修 | docs：10 条 ADJ 计数、「未运行」旧表述、class 取值注释缺第五类、CUSTOM #309 落在汇总表里/无 M30、#302/#310 文件清单 | 已改 |
| 已修 | test：`selections.json` 漏 CP-RUN 真实入口；runner 不判 skip；provision 未写 role 标记致 cmd/server TestMain 拒绝；NTF 恢复断言可空转 | 已改并整组复跑 |
| 记录，不修 | code：`crsync` 投影失败仍 ACK | 既定设计（注释明示「ACK 只确认接收记录」），属 E4/WP5 单调投影，未开工 |
| 记录，不修 | code：结算在撤销时降级为 no_effect 后，原样重投判 conflict | 无生产调用方；语义为「让调用方看到被降级」，M005 接线时再定 |
| 记录，不修 | code：`ReserveMergeEffectTx` 用 `FOR SHARE` 并发可多 attempt | 无路由/调用方，归 M008 真实恢复入口一并处理 |
| 记录，不修 | code：2^53 边界 Go 接受、JS 拒绝 | MINOR，v2 向量未触及该值，随 M005 协议修订 |
| 记录，不修 | test：governance TestMain 无 nonce 身份检查；provision 中途失败可能残留 | 唯一受认可入口是 run-selection；CI 形态归 `2026-10-30-aifi-45-ci-disposable-db-supervisor` |
| 记录，不修 | test：`failure_branch` 只数队列行、`four_phase_dispatch_cp` 用旧 fake 计数 | 前者为守卫用例，后者已声明非主证据 |

## 四、未完成项（名称｜原因｜影响｜补完计划）

| 项 | 原因 | 影响 | 计划 |
|---|---|---|---|
| M005 生产者侧（服务端 command 冻结/签发、task→command 关联、生产 ingest） | 生产无任何 control 写入方；无 pinned manifest/签名私钥；需新设计与 Gate 2 | `ADMITTED` 生产不可得；RUN-001 整链、RUN-006 无法真实验收 | **2026-11-10 用户采纳：移交 BACKLOG-M-RESIDUALS.md 的 M005 行（待开 change）** |
| TC-RUN-001 / TC-RUN-006 | 无测试函数，且依赖 M005 | 不计通过 | 随 M005 |
| M008 真实恢复入口证据 | T `planRecovery` 无生产调用方 | 条款已批准、证据缺 | 随 M005 |
| M009 客户端真实 OS/跨会话投递 | 需真实客户端 | 去重键兼容已裁定（不双读/回填）；本项为已接受残余 | 用户手动走查或随 Gate3 接受 |
| Windows 身份、M006/M007/M010 | 部署前置 / 已移交 backlog | 范围外 | 载体另开 |
| TC-EVD-008 | 2026-11-10 用户裁定 OUT_OF_SCOPE | 不是 PASS | legacy-migration |

## 五、失败模式检查（C4）与经验库（C5）

本轮实际核对：测试 exit 0 但零选中（runner 已要求 pass>0、skip=0）、测试连到共享库（cmd/server 有 nonce+marker 检查；governance 无，已记）、fixture 同库重跑（每选择一个新库）。**经验库写入：未执行（SKIPPED）**，本轮无新模式需要沉淀。
