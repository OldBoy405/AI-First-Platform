# 第四轮 strong 复核：TC-RUN-003 能否记 PRESENT（范围：增量 77–81）

## 对象与冻结
- cwd：`C:/Users/GOBAO/Downloads/AI/AI First Platform`；被审代码在 **multica** 仓 `C:/Users/GOBAO/Downloads/AI/multica`。
- 被审范围：multica `6eb5b7f7f..a929e4438`（5 个提交，11 文件，+888/-32）。冻结 HEAD **`a929e4438db069cdaf672f53dfcb23d3f11a3c12`**，工作树干净、未 push。
- 台账：`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/tc-coverage-20261025T153000Z.md` 的**增量 77–81**（以及附录 A 的阅读提示——附录 A 是早轮残段，其中的 41/49、43/49 为当时口径，**不是**现行事实）。
- 规格：`canonical/specs/code/authorized-runner.yaml:26`（SC-RUN-003）；CP 在 `canonical/specs/agent/authorized-runner.yaml`：`go test ./cmd/server -run ^TestTC_RUN_003$ -count=1 -v`。
- 设计依据：`validation/dispatch-admission-design-20261026.md`（历史草案，**未经 Gate3 批准**）。

## 本轮要判的一件事
**TC-RUN-003 能否记 PRESENT？** 判据是台账口径：CP 命令本身跑通且四条断言满足。若判可以，请同时指出哪些主张必须写进披露、哪些必须继续留作未闭合。

第三轮复核（`01a1806a-…`）判 BLOCK 并列出缺失项，本轮五个提交就是为了逐条闭合它们：

| 提交 | 闭合项 |
|---|---|
| `9d0f6f556` | G-1 分支级回归（增量 77） |
| `ff5263a0d` | human approval helper 四格（增量 78） |
| `78485c7a7` | verdict 写入者验签——**改动生产代码**（增量 79） |
| `f1d02997f` | RUN003 派发 task 身份 + 重复唤醒同 id（增量 80） |
| `a929e4438` | requirement 独立入队门控（增量 81） |

## 已定事项（不得重开）
- 判定器位置在 server Runner，经 `RunnerOptions.AdmissionDecider` 注入；`RouterOptions.AdmissionDecider` 仅供测试；**生产为 nil，`main.go` 接线是 Gate3 事项**。
- 第三路线由（持锁而非共享事务）已定：持 `lockExecutionAuthorizationHead`（cr FOR SHARE + approval_record FOR SHARE）跨越入队效果，措辞必须是**“对撤销线性化，非单事务原子”**； pinned 前提“入队路径不得写 cr”。
- 等待不是失败：拒绝返回哨兵 `errAdmissionWaiting` 并停走，公开入口翻回 nil；approve 步的 reject 分支必须先判哨兵。
- F-1“rebind”已定：消费 → 结算(`kind='effect'`) → verdict + cursor `last_seq >= seq`；**不**与链尾 digest 比较。
- M001/M002/M003 unresolved、Gate NO-GO、原库 HOLD、台账 44/49 均不变。RUN-001/007 受 M002 限制不变。
- 授权边界：本地 commit 已授权；**push / deploy / 真实 CR 操作未授权**。

## 我自己的弱点（请优先打这些）
1. **`verifyVerdictAttestation` 是我这轮唯一的生产逻辑改动**，我对他人的密码学代码只做了“接线式”使用，没有独立审计 `VerifyControlEnvelope` 本身。请判：把验签放进唯一写入者，是否真的让“有行即已验签”成立，还是我在某个位置引入了可绕过的缝隙。
2. **帧位置未纳入签名**：seq/prev_digest 是否在签名覆盖内，取决于生产者的 payload schema，而该 schema 尚未定义。我把它登记为未闭合，没有实现。请判这是否足以阻止 PRESENT。
3. **夹具两次“看着对、实际测了别处”**：增量 80 的 `taskAgent` 断言最初是同义反复（源任务作者与解析出的 executor 是同一行）；增量 81 的 inputs 只写进 DB 行、结构体留空。两处都是变异不红逼出来的，不是我事前发现的。请判**还有没有第三处**。
4. **正向对照依赖我自己构造的可信链**（`admitTrustedConsumption` 等 helper 直接写库）。请判这些 helper 是否让门控测试变成自证。

## 已登记的边界（重复提出不算新发现，但可判“是否足够”）
- 生产判定器为 nil；两腿分测未串联（真实路由→DB / 真实 CLI→假平台）。
- 准入按 CR 计数，未按代（generation）钉死——留给 RUN-006，这是安全保证的上限。
- completion / ensure-writeback 交接、settlement 捷径（`completeRequirementRun` 在已 approve 时的短路）未门控。
- command 路径（`ApplyControlCommandTx`）仍只查签名字段非空。
- **verdict 入库链路未接线**：`AppendVerdictFrameTx` 唯一调用方 `ControlWorker.ApplyTx` 无生产调用方，Node 侧亦无 verdict 签发方。若 Gate3 只接判定器不接入库，生产会对所有 CR 恒停 `WAIT_TRUSTED_T_COMMIT`。已列为 Gate3 并列项（disposition 步 35）。
- 锁池耗尽、持锁跨越 service 调用的无界撤销延迟未测。
- 撤销不取消已入队任务（RUN-006）。
- 能直接写表的一方不在威胁模型内。

## 行为与边界
1. 全新非作者、独立上下文；不读其他 lane 输出，不委派。
2. **只读静态复核**：不编辑任何文件、不跑 DB/测试/迁移、不操作真实 CR、不 commit/push。
3. 可读 multica 源码与 multica `CUSTOM.md`（本轮登记 #245–#247）核实事实；引用时给文件行号或符号。
4. 不代规范选语义；若发现合同不完备（缺字段/缺失败码/缺判定点/内部矛盾），指出具体位置。
5. **不得把“未接线”本身当缺陷**（已登记）；缺陷指**保证不成立**或**测试不能证明它成立**。
6. 变异记录以台账增量 77–81 与 multica 提交信息为准；证据目录 `validation/todo-a-20261026/`（只读）。

## 三路分工
### strong（本轮）— 安全与可实现性
- `verifyVerdictAttestation` 与 `AppendVerdictFrameTx`：三道守卫（链绑定 / manifest 验签 / 逐字节）是否可绕过；nil manifest 是否真的 fail-closed；错误包装 `%w: %w` 后 `errors.Is` 两条哨兵是否都成立；`ControlWorker.ApplyTx` 传 `AttestationScope` 的路径是否与 fence 覆写 `LineageID/StoreID` 的顺序自洽（覆写在验签前还是后，结论是否不同）。
- 门控四处（`markNode` / `passHumanApprovalNode` / `enqueueNodeFor` / `enqueueRequirementNode`）的持锁边界：拒绝时是否真的零副作用、零行；`errAdmissionWaiting` 是否可能泄漏到调用方被当成业务失败。
- 用例质量：增量 77–81 的断言是否打到业务事实，还是只打到 helper 自身；正向对照是否真的能区分“恒拒绝”与“正确门控”。
- 明确回答：**TC-RUN-003 能否记 PRESENT**；若不能，还缺什么才算能。

### balanced — 可验证性
- 每个新增用例能否各写出一条可执行 leaf 与一条 mutation；台账记录的变异是否真的命中对应断言（不是夹具错误、不是代码先报错）。
- 夹具从 registry 派生 actor 的做法是否真的能随 registry 变更而失败，还是只是看起来如此。
- 指出仍然无法写测试的表述，并给最小可测化要求。

### economy — 文档与一致性
- 台账增量 77–81 与 multica `CUSTOM.md` #245–#247、disposition 步 35 是否互相矛盾；计数口径（44/49、leaf 994、1112/1111）是否各处一致。
- 是否把“测试函数存在”写成“覆盖已验收”；是否残留已被改写的旧口径（43/49、41/49）出现在非附录位置。
- 附录 A 的标注是否准确（它是否真的早于增量 66、内容是否确为历史残段）。

## 返回格式
- 首行：`TC-RUN-003 裁决：PASS | BLOCK | INCOMPLETE`，第二行一句话理由。
- 然后按 **[阻断]** / **[应改]** / **[可登记]** 三档列 findings，每条带文件:行号 或 提交号。
- 若判 PASS，必须列出**披露清单**（记 PRESENT 时必须同时写清的限定）与**未闭合清单**。
- 只给结论与证据，不写报告文件。
