# WP5：outbox 拒收计数探索与撤回（2026-11-04）

## 结论：修正未保留，缺陷仍 OPEN

`multica/server/internal/daemon/crevents.go` 的现有三次拒收计数仅按文件名保存：不同 root 的同名文件可能串计；文件在完整 ACK 中已 accepted，但同批另一个文件 rejected 或后批失败时，旧计数可能保留。这两种情况可能造成非连续第三次拒收时错误移入 `dead/`。这不是本次引入的问题，也没有因本次探索解决。

一度尝试按 `filepath.Clean(outboxDir)` 与文件名计数，并在已校验 ACK 后清除 accepted 文件的计数。独立只读复核 `01a1a916-e0fa-7374-9f4d-4732cfae46a7` 指出条件性 P2：同一物理 root 可以经不同路径别名进入 collector；A 拒两次、B 接受并删除、同名事件重建后，A 首次拒收可能沿用 A 的旧计数而误隔离。旧的纯文件名键在 B 成功删除时会清除该计数。部署中是否出现目录别名尚未实测。

**已逐项精确撤回本次路径键与 accepted 提前清零改动，以及为该尝试新增的两个测试。** 其他既有的 ACK occurrence 校验、跨批屏障、cursor/源文件行为及此前脏改不撤回。本次试验临时登记的 `CUSTOM.md` #302 亦已移除，因为该修改不再存在；此前 #299/#300/#301 均保留。复核会话对撤回后的相关源码与登记面只读检查未发现该试验已知残留，但没有试验前字节快照，不能独立证明完整字节级还原。不能将试验时 GREEN 用作当前源码通过证据。

## 已做的受限试验

- 先针对两个新增 helper 测试运行离线 `go test -buildvcs=false -count=1 -json -run '^(TestRejectionCountsAreScopedToOutbox|TestMixedAckResetsOnlyAcceptedFileRejections)$' ./internal/daemon`：旧代码两条行为 RED，分别为 B 首次拒收继承 A 的两次、mixed ACK 接受 A 后再次拒收仍将其移入 `dead/`。Go `go1.27.1 windows/amd64`，`GOPROXY=off GOSUMDB=off GOTOOLCHAIN=local GOWORK=off`。
- 后试验版本连同既有 `TestValidateCRAckRequiresCompleteExactBatch` 为 3 个顶层和 4 个子测试 PASS，零 fail/skip；该结果仅属于已撤回的试验版本，不能覆盖独立复核发现的别名 P2。没有留全量 Go JSON，也未在撤回后重跑上述已移除的测试。
- 撤回后的当前快照单独重跑 `TestValidateCRAckRequiresCompleteExactBatch`：1 个顶层 + 4 个子测试 PASS、零 fail/skip；此项只证明所测 ACK 数量形态，不能证明拒收计数修复。当前 `crevents.go` LF SHA-256 `bef8ec3d2b9a123c27488c37e86501b7a90f78afaecd3e4d16ddba4fa0f7b1fe`，`crevents_test.go` 为 `c5df2d87ffe61ea3e98687a1076163b93a24dd07abe4229c9d4ab51784391f6e`；没有原始试验前 hash，不能将当前 hash 当成字节级还原证明。
- 当时新测试仅对 `t.TempDir` 自建文件调用真实 `applyAckRejections`，执行自建目录内 `os.Stat`/`MkdirAll`/`Rename`。`daemon/testmain_test.go` 使用 `IsolateUserHome` 创建并清理随机 scratch home；所选测试不调用完整 collector、真实 Git、DB、网络或 HOLD。环境裁剪不是沙箱；测试没有证明完整生产链或强隔离。

## 为什么不能只换成 realpath

`normaliseForContainment` 在 `EvalSymlinks` 失败后回退字符串，不能用作已核实物理身份；即便成功求值，检查后到 `rename`/`remove` 前目录、链接或同名文件仍可能改变。当前扫描只保留文件名与事件内容，未将读取时的对象身份固定至 ACK 和最终副作用。`ResourceID` 不证明唯一物理 outbox；同一物理目录跨 workspace 的归属不明时也不能直接合并计数。`os.SameFile` 或再查一次 `stat` 单独不能关闭最终操作前的替换窗口。

主会话补充源码级普通并发路径：tools 的 `crctl.mjs#emitDriftAudit` 给相同漂移使用确定性文件名，`emitOutboxEvent` 在目标存在且比较相同时复用，但注释明确采集后同一漂移的下一次观测可再次发射；M 侧 `c.mu` 只串行化单个 collector 实例。若两个实例读到同一物理 outbox 的旧文件、两者旧事件均获完整持久 accepted ACK 且其他批次及必要 cursor 屏障通过，A 删除后生产者按原名发出新观测，B 随后处理迟到的旧 ACK 可使 `deleteAccepted` 对该名字再次 `os.Remove`，误删新观测；拒收达到阈值时的 `os.Rename` 同样只按名字作用。该交错是依据 `crctl.mjs:491–528,549–559` 和 `crevents.go:675–677,1123–1153,1106–1114` 的条件性静态推论；balanced 只读复核 `01a1aa28-3c82-7374-9f4d-479007b4612e` 确认推理需上述前提，而多实例部署、旧事件重投是否 accepted 与生产者实际重建均未实证。它不是已观察到的事故或多进程实测，不需要假设任意同权限恶意替换，也不能用多加一次身份检查消除最终操作窗口。

另一个相邻的收集完整性缺口：`scanOutboxDir` 枚举后对 `os.ReadFile` 的所有错误直接 `continue`（`crevents.go:1143–1147`）。在文件确实不可读、commit scan 成功且其余事件为空或正常 ACK 等条件下，`collectRootWithOptions` 无法察觉该遗漏，可能返回成功而该源文件仍未报告。文件并发消失、非 `ENOENT` 不可读和真正已持久化须分开分析；此处是静态可达的条件性风险，未进行真实权限、完整 collector 或终态流程测试，不能据此称已发生事故。它不等价于拒收计数，也不能靠给每种 errno 单独加补丁解决所有并发与 ownership 问题。balanced 只读复核 `01a1aa28-3c82-7374-9f4d-479007b4612e` 确认在已 watch、commit scan 成功、无其他待发送事件及本轮无需 snapshot 的条件下 `settleRoot` 可返回成功；其授权范围不足以确认任务终态实际如何消费该结果，也未运行测试或命令。请求 `OpenAIPersonal/gpt-6.1-terra:xhigh`，实际后端无回执。

## 最少职责的待审候选（不等于实现或批准）

balanced 只读复核 `01a1a99a-6db5-7374-9f4d-476f30e4a299` 请求 `OpenAIPersonal/gpt-6.1-terra:xhigh`，仅读本记录与 `crevents.go`/`crevents_test.go`，未运行命令或测试；无实际 backend 回执记 unknown。其结论是在当前证据下不能证明存在满足全部约束的可实施修复；以下只是假设满足后才有意义的进程内派生计数，不另建权威账本：

- 按已证明的物理 outbox、文件生命周期及 workspace 归属关联真实发送条目；不同物理 root 同名分开，同一归属下被证明是同一 outbox/条目的别名共享。仅凭路径、`ResourceID` 或 hash 不证明归属；跨 workspace 有歧义则停止。
- 每批 ACK 经完整 occurrence 校验并可唯一归因后，立即清除该批真实 accepted 条目的旧拒收序列，对真实 rejected 才递增；即使同批其他项或后批失败，已确认 accepted 的清零不回滚。未发送、无效或结果不明不能算作连续成功/拒收；同 ID 多个 occurrence 的结果不能唯一关联实体时不猜测。
- synthetic commit/snapshot 仍参与原 ACK 校验和批次屏障，但不构造文件拒收计数；只有 synthetic 且 outbox 不存在时不凭空要求目录身份。新生命周期从零开始，不能只凭未扫到或字符串变化认定新对象。
- 三次连续已确认拒收后，只有能保证最终动作作用于同一原条目且不覆盖 `dead/` 的其他实体时才能隔离；失败保留门槛状态并返回错误，随后有效 accepted 仍应清零。cursor 已持久化后的删除失败不能倒回 cursor，重试也不得删除同名新对象。

**未决前提**：`c.mu` 只约束该 collector 实例，不排除外部写者。必须证明读取至 ACK 的内容不可变或受等效排他保护、投影归属稳定、同名重建能识别、最终 rename/remove 作用于原对象且不覆盖他人；`EvalSymlinks`、`stat`、`SameFile`、打开句柄或再检查单独都不能关闭最终操作前替换。无法证明则保留对象并 STOP，不通过逐类 hash 补丁冒充保障。

本轮 balanced 限定静态复核 `01a1a9ff-1668-7374-9f4d-477692472145`（请求 `OpenAIPersonal/gpt-6.1-terra:xhigh`，actual unknown）再次确认现有证据不足以安全实现计数修复。另需核准来源归因：`applyAckRejections` 按 `commit:`/`snapshot:` 字符串前缀跳过计数；源码扫描未禁止允许冒号的平台出现 `commit:*.json` 名称，仅靠前缀不能证明其为 synthetic。是否存在这类真实生产文件尚未核实，不把理论路径当作事故。发送失败的本批没有可信 ACK，但下一 tick 会再次尝试；这不解决未知结果与迟到请求的合同。此复核只读四个指定文件、未运行测试或资源探针，也不扩大 HOLD 范围。

## 本轮采纳方向与仍需配对的合同

用户对上一轮整体最小方案回复“采纳你的建议，实施”。其中已采纳：拒收计数是进程内运维派生状态，重启后可从零重新累计；业务预算、stop 和消费事实不得因此清零。该取舍可能延后隔离，不保证跨重启恰好第三次；若现行合同要求更强结果，须先完成适用 B4 配对修订，不能把方向采纳写成原合同已改变。

另一个采纳方向是区分业务幂等身份与投递生命周期：同一次投递的重试应复用其已绑定身份；真正的新投递不得重用旧投递路径；ACK 只处置其对应的原投递。现有 `emitDriftAudit` 确定性文件名和已发射后可能重建的路径需与该方向逐项核对。随机文件名本身不能证明身份已持久化、旧 writer 不会重用、两个消费者最终只作用于原对象，亦不能替代源内容及 ACK 对应；未知或无法证明归属时保留现场。另核 `server/internal/governance/crsync.go#ingest` 与 `audit.go#ingestAudit`：audit 绕过 `cr_sync_event`、直接 INSERT `activity_log`；在 ACK 丢失后重投同一 audit 可能新增重复记录。不能用 checkpoint 的唯一键推断 audit 已幂等，此处仅为源码级条件推论，未运行 DB 或证明事故。

仍须配对核定同一物理 outbox 经不同 workspace 路径进入时的归属与计数、超时/崩溃请求迟到结果的排除或对账、“连续”与可信 ACK 的对应，以及旧文件和混版切换。用户采纳的是方向和实施授权，不等于已批准冲突合同、具体依赖、真实资源或 Gate。若要证明路径替换安全或完整无 Git 的 collector 测试，需要额外设计及适用授权；`ADJ-AIFI45-007` 仍未解决，真实 daemon/DB、投影、异常恢复和 Gate3 仍未验证。
