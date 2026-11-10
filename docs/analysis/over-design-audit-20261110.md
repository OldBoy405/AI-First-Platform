# 过度设计与过度防御排查（2026-11-10）

范围：`projects/` 下 STDD change，在途 4 个、归档 12 个、中止 1 个。tools CR 轨道（`change-requests/`，79 个）不在本次范围。
方式：三路只读审计（strong 档）并行，主会话抽查高影响结论。只做分类，**不执行任何收窄**；每项收窄须经所属 change 的 revision 或新 change 落地。

## 判定标尺

- **使用者**：一个内部团队，多数时候只有一个人；没有外部租户，没有合规要求。
- **唯一要防的对象**：干活的 AI agent 自报成功，以推进 CR（例如自填 `settlement.kind=effect`、自报 PASS）。不防团队成员，也不防外部攻击。
- **已核实的环境事实**：
  - 本机上 agent 与操作者是同一 OS 用户；rootless podman 和 WSL 都归该用户所有；仓库根 `.env` 带 `DATABASE_URL`。本机不存在 agent 与操作者之间的身份边界。
  - 真实部署中，server 与 DB 在服务器主机，agent 在 daemon 主机，机器边界天然存在。daemon 代码不读 `DATABASE_URL`。
  - 以上见 `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/pending-adjustments.yaml#ADJ-AIFI45-M005-TRUST`。
- **底线**：只要某项是 agent 与「自证 effect」之间唯一的阻隔，就不删。

## 路径缩写

| 缩写 | 路径（相对 `projects/`） |
|---|---|
| mA | multica/changes/2026-10-22-aifi-45-authorized-execution |
| mD | multica/changes/2026-10-30-aifi-45-ci-disposable-db-supervisor |
| mL | multica/changes/2026-10-29-legacy-execution-migration |
| mR | multica/archive/2026-10-19-aifi-45-four-phase-runner |
| mV | multica/archive/2026-10-27-trusted-verdict-channel |
| mO | multica/archive/2026-10-29-trusted-verdict-outcome-binding |
| tRC | tools/archive/2026-10-19-aifi-45-runner-contracts |
| tAE | tools/archive/2026-10-22-aifi-45-authorized-execution |
| tVC | tools/archive/2026-10-27-trusted-verdict-channel |
| tTA | tools/archive/2026-11-08-aifi45-trust-anchor-chain |
| tOB | tools/archive/2026-10-29-trusted-verdict-outcome-binding |
| tED | tools/archive/aborted/2026-10-30-aifi-45-evidence-delivery-integrity |
| tT | tools/changes/2026-11-06-stdd-default-cr-opt-in |
| mS1 / mS2 | multica/archive/2026-10-20-upstream-sync-4efd5062c9 / …-upstream-sync-gate1-v2（模板变更，不是第二次同步） |
| gS1 / gS2 | gbrain/archive/2026-10-26-upstream-sync-2568d32ac8 / 2026-11-10-upstream-sync-553b547334 |

## 分类结果

列含义：**验** 表示主会话已抽查源码或事实；空白表示审计子会话引用、未复核。

### C1 过度防御：防的是这个团队不存在的威胁

| change | 项 | 证据 | 建议 | 收窄后如何仍可验证 | 验 |
|---|---|---|---|---|---|
| mO | 把完整密钥生命周期（轮换、撤销、泄露处置）列为上线门禁 | mO/design.md:50,78；mO/test-plan.md:183–191,217–225 | **收窄**为一把 pinned key；未知 key 或错误 key 一律拒绝；需要更换时停止新准入、人工替换，历史字节保留 | 两项部署检查：以 agent 身份读不到私钥；可用 DB 登录对信任表无写权限 | ✓ 已写入 ADJ-AIFI45-M005-TRUST |
| 本会话早前建议 | 签 key 与批 manifest 的人员分离、双 key 轮换演练、按 CR 发 key | 本会话 | **删除**，已在 ADJ-AIFI45-M005-TRUST 中更正 | 同上 | ✓ |

C1 只有这两项，说明多数「重」不是防错了对象，而是下面几类问题。

### C2 过度设计：没有当前需求的控制面或抽象

| change | 项 | 证据 | 建议 | 收窄后如何仍可验证 | 验 |
|---|---|---|---|---|---|
| tTA / tVC / tAE | **把 T 做成信任锚**。crctl 由 agent 在流水线内执行；agent 运行的 CLI 无法靠自检变成独立验证者 | tTA/design.md:95；tAE/pending-adjustments.yaml:29–33 | **收窄**：server + DB 是唯一准入权威，T 默认是非可信客户端；签发者放在服务端 | 以真实 agent 权限伪造 PASS、替换本地材料后，仍推不动服务端状态 | ✓ 与 M005-TRUST 结论一致 |
| tVC | 本地 store、帧链、owner fence、checkpoint 组成第二套裁决存储与恢复引擎 | tVC/design.md:64–78；lib/execution-control-store.mjs:3–16 | **收窄**：业务事实、唯一键和 CAS 只放在受保护的 DB；本地 journal 只负责文件和 Git 操作的恢复 | 同一请求并发只产生一次消费；本地整链被替换也改不了服务端事实 | |
| mV / tVC | D7 部署控制面（激活、停新、legacy 排空与退役、readiness 观察签发）超出「版本一致、可停新」的需求 | mV/design.md:84–91；execution_deployment.go:111,208,262,330,377；tVC/design.md:87–93 | **收窄**：固定一个受支持的部署组合；在启用边界核对版本与信任根；保留「停止新准入」和在途任务的 generation fence | 在实际部署身份下做启用预检，缺任一项即拒绝启用 | ✓ 函数存在 |
| tT | 渲染器不支持文档型 spec，于是另建人工 spec 副本加逐项映射 | tT/design.md:94–100；tT/test-plan.md:186 | **删除**人工副本，只保留一份权威 spec | 评审直接引用源条目 | |

### C3 检查膨胀：同一保证多处重复验证，或用数量代替保证

| change | 项 | 证据 | 建议 | 收窄后如何仍可验证 | 验 |
|---|---|---|---|---|---|
| mV / tVC | 验收绑定 leaf 名称、数量下限、逐 leaf mutation | mV/proposal.md:32,40–43；tVC/test-plan.md:6,19–22 | **收窄**：取消「数量即完整」；mutation 只用于关键放行边界 | 每个信任边界一组表驱动正例与负例，并断言零副作用 | |
| mA | 覆盖率台账需要再对账、选口径、复核摘要，已出现重复计数 | mA/validation/tc-ledger-reconciliation-20261029.md:5–32 | **收窄**为一份当前「保证 → 测试证据」索引，历史报告只链接 | 每项保证只记当前状态：通过或未验证，附原始链接 | |
| mO / mA | TC-MG-017 与 TC-MG-016 内容重叠，是为补足 Scenario 数而登记 | mO/test-plan.md:260–278 | **合并**为同一参数化测试，多个 Scenario 引用它 | 一张恢复状态表，每行断言排他、不新发布、不编造结算 | ✓ 本会话登记，确有此动机 |
| tTA | 逐 TC 单独运行，再全量运行，还绑定精确 TAP 文案 | tTA/test-plan.md:20,78 | **收窄**为一次全量运行，产出结构化结果与覆盖集合 | 核对实际执行集合、断言结果和退出码 | |
| tTA | 来源语义提取做了两遍：平台签发前一遍，T 再按 json-pointer 映射一遍 | tTA/design.md:34,52 | **收窄**：只由认证平台解释来源；T 只做验签、完整性和适用性检查 | 授权字节或来源字节被改即拒绝 | |
| mA → mD | 事故期的旧库全表扫描、源码 pin、锁与 session 检查，被沿用为新环境的常规门槛 | mA/tasks.md:74–90 | **收窄**：新实例拿不到旧库凭据即可；只检查本次实例 ID 与清理结果 | 新实例连不到旧库；按 ID 清理成功 | ✓ run.mjs 已按实例 ID 校验 |
| mA | Inbox 在原设计中另设第二个去重唯一键，实施时已改为复用 notice 唯一键 | mA/design.md:80；execution_notice.go:295–348 | **删除**设计中的这条重复约束 | 并发同键只得到一个稳定的 Inbox ID | |
| mS1 / gS2 | 用 CUSTOM 标记数量相等来证明「挂钩零丢失」 | mS1/test-plan.md:10；gS2/test-report.md:17 | **删除**这条硬门槛，数量只作诊断提示 | 对受影响的挂钩，按符号、调用点和行为核对 | |
| gS1 → gS2 | 上一轮已确认 Windows 全量测试不提供信号，第二轮仍重新全量诊断 | gS1/test-report.md:47–61；gS2/test-report.md:25–35 | **收窄**：把平台适用边界固定下来 | 本地只跑构建、受影响行为、迁移和生成物检查；未跑的明确标注 | |
| tT | 同一 lint 既跑 report 又跑 enforce；改文案也要求跑完整运行时测试 | tT/test-plan.md:177–181 | **收窄**为一次 enforce，按改动面选择检查 | 文档差异评审，加相关合同检查 | |

### C4 逐异常补丁：按场景特判，而不是设一个共同边界

| change | 项 | 证据 | 建议 | 收窄后如何仍可验证 | 验 |
|---|---|---|---|---|---|
| mA | 通知正文用命令词表封堵，空格和 tab 各列一遍，另外单独处理 Unicode 行分隔符 | execution_notice.go:168–200 | **收窄**：生产者只提交结构化的处置类型，由固定模板渲染；正文不承载执行语义 | 只校验允许的通知类型、收件人和长度，加 canonical 链接 | ✓ |
| tAE / tED | 机械免审靠 shell 名与包装器名单（env、xargs、nohup…）判定「无语义变化」 | lib/evidence-mechanical.mjs:14–17,57 | **收窄**：取消按命令名分类的免审通道，统一走独立核验 | 固定的生成过程只比较受控输入与完整输出 | ✓ |
| gS2 | 已有「生成物统一重建」规则，仍因生成物未逐文件登记而 BLOCK | gS1/design.md:44–48；gS2/gate1-detail.md:14–37 | **收窄**：登记真源与生成命令，由统一规则覆盖 | 重建后核对差异与 freshness | |
| tT | 用户已批准新措辞，仍保留旧精确断言，另加替代检查，形成两套预期 | tT/pending-adjustments.yaml:14–24 | **收窄**：经设计调整更新唯一的当前预期 | 对照批准原话核对当前句子 | |

### C5 流程过重：审批、台账、确认超过保证所需

| change | 项 | 证据 | 建议 | 收窄后如何仍可验证 | 验 |
|---|---|---|---|---|---|
| mD / mA | 测试入口替换被绑到 Gate 2 调整；建库、连接、清理又各自拆出审批 | mD/proposal.md:14–26 | **收窄**为一次性批准一个可弃用资源信封（镜像、端口、凭据、清理边界） | 入口自动拒绝越界；只有触及旧库、生产或扩大范围才重新审批 | ✓ run.mjs 已有身份校验 |
| mL / mA | 本期明确不做迁移，却长期以 MISSING 挂在 Gate 3 偏差里 | mL/canonical/proposals/…:11–30；mA/pending-adjustments.yaml:36–40 | **收窄**：做一次正式范围裁定，把它移出本期分母，保留占位和启动条件。不能改记为 PASS | 本期只验证旧 CR 不迁移、新旧不串用 | |
| tAE / tOB | 同意原文、实施许可、配对生效、资源许可反复交织 | tAE/pending-adjustments.yaml:64 | **收窄**为一份当前决定记录，绑定范围与版本 | 能直接回答谁批准了哪个版本的什么范围 | |
| mS2 | 模板文档变更也完整走三次 Gate | mS2/proposal.md:4,27–38 | **收窄**为一次模板差异审阅 | 一份审阅记录 | |
| mS2 / gS2 | 状态日期、排版这类修正被升级为合并前置条件 | mS2/upstream-sync-gate1-v2.md:16–17,72 | **收窄**：只有归属、迁移水位等实质信息不明时才阻止 | 从冻结树核对受影响的 CUSTOM 条目 | |
| tT | 纯文档交付被原生执行证据、coverage、切片状态入口卡住 | tT/design.md:9,100–102 | **收窄**：通过任务契约声明「仅文档验收」 | 审实际文档差异与用户批准；明确不证明运行时行为 | |

### K 必须保留：看起来重，但是承重

| change | 项 | 唯一支撑的保证 |
|---|---|---|
| mO / tOB | 签名结果语义 + 冻结命令绑定；写入端验签与准入端语义检查职责不同，不算重复 | caller 自填 `effect` 不能成为可信许可 |
| mA / mV / tAE | 永久逻辑幂等、同事务结算、未知结果保持排他 | 崩溃、重放或换 run 时，不重复派发、不重复消费 |
| tOB / tVC | 外部效果未知时既不推断成功，也不盲目重做 | 不伪造本 attempt 的效果归属 |
| tVC / tAE | 当前候选写集 + 受保护的合同选择 | agent 不能用旧证据或删字段来推进候选 |
| mR / mA | canonical 业务事实 + 实际 diff 与可运行证据 | 作者自报 PASS、exit 0 不能直接交付；这里隔离的是证据来源，不是要求增加审批人 |
| mA / mV | 真实身份边界（生产使用机器边界） | agent 不能替换信任根或直接改权威状态；本机不成立，已如实记录 |
| gS1 / gS2 | 空库实际产物探针、CUSTOM 挂钩追到上游新调用链 | DDL 确实生效；fork 行为确实接入了新结构 |

## 跨 change 根因（4 条）

1. **权威边界先放错，再靠更多证明去补。** T 由 agent 执行，却被当作信任锚，于是长出帧链、readiness、第二套语义提取。修正的方向是把权威收回 server + DB，而不是给 T 继续加检查。C2 中的主要条目都源于此。
2. **验收格式反过来塑造需求。** leaf 下限、Scenario/TC 数量、标记计数、历史分母推动新增用例和常驻缺口，而不是从有限的保证推出最少的测试。C3 大多源于此。
3. **事故期的临时保护被固化成永久流程。** 旧库巡检、逐动作审批、日期排版前置都属于这一类。应改为：资源边界一次性批准，并由入口自动执行。
4. **流程模板本身也被流程化。** 模板变更走三次 Gate，纯文档交付被运行时证据卡住。应按任务实际能证明什么来选择证据，而不是把框架的槽位全部补齐。

## 修订方案（未执行）

落点规则：**在途且属本 change 范围 → 本 change 内 revision；归档项只有留下「仍在运行且有成本或风险」的产物才新开 change；纯历史仪式不动，也不改归档。**

2026-11-10 两项核实改变了落点：
- D7 部署函数（ActivatePolicyTx 等 6 个）生产调用方为 0；tools 的 execution-control-store、execution-control-readiness 非测试引用为 0。它们是休眠代码，运行时无成本，归属由 M005 的接线决定。
- 数量门槛不来自任何 STDD 规则（stdd/.stdd、tools/skills 中无出处），而是各 change 的 test-plan 自己写进去的。因此撤回「在 STDD 层面单独开 change」的建议。

| 批次 | 落点 | 条目 | 触发 |
|---|---|---|---|
| A 已修订 | mA design §1/§2/§6/风险表 | M005 信任模型：签发者在服务端、T 是非可信客户端（2026-11-10 用户批准） | design 变更待用户重新确认 Gate 2 |
| A 已修订 | mA pending-adjustments 文件头、test-plan | 覆盖台账合并为单一口径 42/48；逐项「保证 → 当前证据」需按当前源码重验，归 Gate 3 准备 | — |
| A 已修订 | mL proposal / mA M004 | 范围裁定：TC-EVD-008 记 OUT_OF_SCOPE（不是 PASS），由 legacy-migration 在启动条件发生时验收 | — |
| A 已修订 | mD canonical proposal | 可弃用数据库按资源信封一次批准；信封内替换入口只登记、不走 Gate 2；run.mjs 身份校验不动 | — |
| A 修订中 | tT | 仅文档验收、人工 spec 副本、单一措辞预期 | 见 tT 记录 |
| A 随 M009 评审 | mA M009 规格 §3 | 通知正文词表收窄为结构化处置类型；删除 design §5 的 Inbox 第二唯一键。后者即 M009 偏差（deviation_approved_pending_evidence），提前改 design 等于绕过其证据门槛 | M009 评审 |
| B 不开 | — | crctl 机械免审。核实：`evidence-mechanical(-admit)` 可调用，但没有任何 gate、review、approve、Skill 或 pipeline 读取其结果；写入 test-report 的证明标记只被自身幂等检查读取；记录仓无 CR 使用过。无法借此跳过评审，是休眠能力 | 并入 C |
| C 延后 | 清理 change（双载体） | 删除 M005 落地后仍未接线的 D7、tools store、readiness、第二套语义提取，以及机械免审命令 | AIFI-45 的 M005 关闭 |
| D 不动 | — | mS2 的三次 Gate、gS2 的 BLOCK、tTA 的逐 TC 运行、tAE/tOB 的同意记录、mV 的 leaf 计数、TC-MG-017 | 已发生，无运行时成本 |
| D 下次用时 | 下一次上游同步 change | 同步模板 v3：标记计数只作诊断；生成物按真源加命令登记；固定平台适用边界 | 下一次同步（模板只存在于归档 change 中，未安装） |

本方案自身只设两项检查：
1. 任何触及代码的修订完成后，K 类既有用例仍全绿：shared vectors、TestTC_RUN_003、governance DB 套件。
2. 任何删除动作执行前，当时重新核实生产调用方为 0。

风险：带「验」标记的条目已由主会话复核，其余为审计子会话引用，落地前须按证据行号复核；tools CR 轨道未覆盖。
