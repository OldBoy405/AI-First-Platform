# RUN-009 评审轮次绑定候选（方案 A 进入评审，非实施授权）

独立只读设计请求 strong；actual backend receipt unknown。无代码变更、测试、DB、容器或真实 CR。本文件不选择协议版本、不批准 Gate2 调整、不计 TC-RUN-009 通过。后续 strong 复审新增服务端 attempt 兜底、同轮覆盖、终态写者和审批归属问题，见 `run009-binding-strong-review-20261029.md`；其结论为实施前 BLOCK。有限字段与终态写者盘点分别见 `run009-producer-inventory-20261029.md`、`run009-terminal-writer-inventory-20261029.md`，均不构成全局覆盖或授权。

用户已确认按方案 A 开展评审；此确认只选择评审方向，不批准具体权威源、签名契约变更、实施、部署或 Gate。

## 已选评审方向 A：权威执行绑定 + 可恢复待决

评审投影不再自行 `findOrCreateRun`，而是解析平台受控启动的 `pipeline_run.id` 与 tools/crctl 已提交的 cycle/attempt 的**经验证绑定**。绑定范围还须覆盖可信 workspace/project/CR、控制根或 lineage、node、subject、template/policy 及适用 receipt；真实 reviewer UUID 必须关联受控任务与实际执行 generation。字段存在、git 作者、非空 SHA 或调用方自报均不自动构成可信事实。当前 outbox、annotation、commit-scan 并无上述完整共同绑定，且不同接收路径的主题/字段不能假定等价。

- 将**事件持久摄入去重**与**业务 effect 适用性**分开；最少区分已应用、仅历史、等待权威绑定、不可判终结、冲突。同一身份同事实重放原结果；同身份的已核验绑定或裁决确有矛盾时不覆盖。当前 `crsync.go:280–287` 以 `(workspace_id, cr_id, commit_sha, event_kind)` 先到先占，后来来源只补部分 evidence；候选须另设计追加式来源记录和经核验的缺失事实补齐，保留双方原文和来源。不能把“先到的不完整”和“后来携带的新事实”一概当冲突，否则较全副本永远无法解除 pending；也不能让后到内容静默替换已核验事实。
- 绑定尚未出现且有合法恢复路径时保持可恢复 pending，不得推进，也不得标成永不重判的 processed。ACK 前必须持久保存重试责任；绑定到达时重判，并有启动及周期补扫。何时转不可判终结、如何避免有界资源耗尽或过早丢失新轮事件须由明确证据和策略裁定，不能仅凭超时假定完成。设计待验证，不能把内存队列或 daemon 自行重投当作可靠持久责任。
- 仅与被冻结的原始 run/node/cycle 绑定；旧轮迟到只存历史。新轮评审先于开轮信息到达时不得误杀或换事件身份。同 commit 的 review/test 和不同 stage 应有独立子事实身份，防止父事件去重互相吞掉。
- 资格重验、绑定解析、节点 effect、处置须同一事务内形成一致结果；事务不执行网络调用。pending 重判及最终副作用前须重读可信撤销 head、AdmissionDecider 结果和 STOP_NEW/部署准入，禁止停新后重放产生新的未授权 effect；显式 resume 须满足可信 resume receipt/精确恢复规则。终态、受控开轮及显式 resume 必须共享跨进程同步域，并逐项覆盖 projection 的 complete/cancel、Runner 各终态写者、无标记 run 收编及 rereview 开轮；现有进程内锁与 advisory lock 未证明属于同一域。现有 deployment→activation→CR/head→业务行→cursor/command→root/task 锁序仅为评审起点，须逐写者核对，不能当已证明的全局锁图。
- 不得把严格合同缺失的可信 cycle 补造为 `1`、绑定到当前 run 或静默重签。现有 tools 对自身 legacy 数据确有缺 cycle 按 1 解释的兼容语义（`crctl.mjs:1253–1257`），不能误称全局不存在；它是否可作为某条旧合同事件的权威归属须结合版本、来源及合同核实。按可信、冻结的 contract selection 区分 strict 与已 pin 的 legacy/人工评审，保留旧合同和历史，不能因新绑定缺失把所有旧 run 永久挂起，也不能因字段缺失自动降级到 legacy。可证旧轮只留历史，不能证明的明确不可判。真实历史 inventory、迁移/豁免、pending 堆积与恢复责任均待裁定。

## 替代项及未决

- **B：git 开轮锚点到 run 的永久映射。** 可评审，但需先确定开轮/reset、历史改写、控制根及 outbox 与 commit-scan 的匹配语义。仅凭 git 时间、当前分支或 subject 非空不可当权威。
- “没有活跃 run 就丢”已被撤回：新轮评审可早于开轮发现；单靠排序或加锁只能串行化错误归属，不能创建缺失的身份。
- 方案 A 的权威来源和签名域是否可由现有已批准契约表达、cycle 物理键、旧数据策略、用户交互及 Gate2 调整范围仍未决定；用户选择 A 不自动决议这些细节。outbox 加字段属于跨仓 wire 变化，但不当然属于签名协议变化；须先核实生产者、签名覆盖与兼容。任何确需修改的已归档签名协议须另行评审；不可先改再补批准。

## 后续验证最小集

1. **late old**：真实终态后摄入旧评审，核服务端 accepted、无 rejected、`processed_at` 与处置一致，保留历史、零新 run/节点污染/派发；重投不生效。
2. **early new**：新轮评审先于开轮 scan，待决后开轮信息出现并经重启恢复，仅应用一次且事件身份不变。
3. **concurrent terminal**：使用确定性 barrier 覆盖终态与投影两种提交顺序及真正共享同步域；不以 sleep、假事务或全 skip 冒充真实锁证据。
4. 先收到不完整 outbox，再收到带额外字段的 commit-scan 副本：可核验时能补齐且不覆盖既有绑定；冲突、错误来源和重复投递不得推进。包括同 commit 不同阶段、review/test 子事实的身份隔离；真实产生范围尚待调查。
5. pending 重判与 revoke/STOP_NEW/resume 竞争、各终态写者/收编/新轮开轮，以及严格合同和明确 pin 的旧合同路径。另测 scope、run/node/cycle、subject、template/policy、receipt、reviewer 与实际 diff/测试证据的错配和正例；完整 SC-RUN-009 不能只凭 run 复活修补判通过。

可先做不触及真实 DB 的纯模型/断言与生产者字段清单；这只验证模型，不证明数据库互斥、真实入口或行为已实现。真正 SQL 并发测试须使用受批准的独占隔离库和可审计回执。

## 独立静态复核及处置

第二位只读复核者（实际 backend receipt unknown）指出：先到的不完整副本会被现有去重键固化、漏列终态写者及 run 收编、pending 重判须重新检查撤销与 STOP_NEW、strict 改造不能破坏 legacy、缺字段兼容与 tools 的 cycle 默认规则可能冲突。以上已纳入待决设计约束；未重新跑数据库、未证明方案可实施，也未将候选晋升为已批准设计。
