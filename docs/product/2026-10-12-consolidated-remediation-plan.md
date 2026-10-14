# AIFI-62 关联遗留问题与最新 main 整改方案（核查修订版）

> 本文件整合并替代以下三份方案：
> - `2026-10-12-aifi-62-minimal-remediation.md`（D1：T1–T5、M2）
> - `2026-10-12-latest-code-optimization-plan.md`（D2：A1、A2、B1、B2、C1、C2）
> - `latest-main-eight-items-verification.md`（D3：第 1–8 项）
>
> **交付决策：A–H 全部采用无 CR 的受控维护方式，不注册新 CR，也不回退原 CR-2026-076。**“无 CR”不等于绕过绑定、安全检查、评审、审计或提交身份约束。
>
> 本轮授权仅为核查和完善方案，**不是代码实施、提交、部署或线上操作授权**。AIFI-62 的解除阻塞由用户在全部整改完成后另行操作，**不作为整改验收或 PASS 指标**。

## 0. 已确认的边界

| 决策 | 本方案口径 |
|---|---|
| 范围 | A–H 全部必做；T5 提示去重也纳入。明确延期项不因“全部整改”自动扩入 |
| 交付方式 | 不走 CR；逐包提交、逐包评审、受控发布，保留实际用户提交身份 |
| 安全底线 | 不放松跨根校验、可信绑定、clean、审批签名、CAS、审计、脱敏；不提供绕过开关 |
| 复杂度 | 不新增表、服务、依赖、状态或通用框架；确需突破结构边界须重新确认 |
| 必要接口扩展 | 包 C 的显式 `--json`；包 E 的可选 `output_encoding`；包 F 的逐 CR 来源 SHA。均为窄接口，不扩为通用协议 |
| 发布与验收 | 必要验证缺失时允许合并、发布，但必须明示未验证；**允许发布不等于整改 PASS** |
| 完成标准 | 全部实现、必需验证、实际消费者生效核验完成后，才能判整体 PASS；未运行、skip、未部署均不能计入 PASS |
| AIFI-62 | 恢复不参与任何包或整体整改的 PASS；之后由用户独立操作 |
| 在途旧版本 | 新 run 用新版本；旧 run 保留原 digest／节点身份，迁移须显式交接，不直接改库 |

## 1. 核验基线与证据分层

### 1.1 本轮静态核验基线

| 仓库 | 本地 HEAD |
|---|---|
| AI-First-tools | `c69336475d01c4de5a42efc0dc087a5e605b5c82` |
| AI-First-multica | `c47381ae72d4a274cf55208ea45bc105bb0bfc77` |

本轮核查读取了现行约束、相关源码与调用方，以及 CR-2026-076 本地权威 worktree／事务记录。**没有执行仓库回归测试、DB 测试、生成器、网络 fetch 或线上操作。**本地 HEAD 不构成远端实时状态或实际部署版本的证明。

原方案曾记录两个生成器 `--check` 均 exit 1；这是此前核验记录，**不是本轮重新执行的结果**。实施时须在固定基线重新执行并提交原始回执。

### 1.2 已核实的主要修订点

1. SUP FR 不被当前 traceability 生成器接受；原推荐正则又缺少编号结束边界，会接受 `FR-1junk`。
2. checkpoint recovery 与 merge recovery 根不一致；status divergence 仍固定指向 requirement worktree。
3. finalize 声明存在，但平台生成表缺失；gate 生成器直接重跑会把 dev-start 与 code 指向同一节点。
4. 受控 Git 仍截断输出、丢失启动错误；机器调用不止 merge-base／diff。外部重定向不能绕过内部缓冲上限。
5. 完成正文已由标准 JSON 解码，三处再反转义会损坏路径。没有证据证明“单行”或某个 provider 版本必然表示转义正文。
6. 平台快照仍采用单一来源；任意本地 HEAD 不能当成已发布 trunk。分支内容与来源 SHA 必须绑定读取。
7. 现有 `--check` 忽略生成物的来源注释，只证明内容一致，不证明 tools SHA 一致。

### 1.3 未核实的运行事实

- 当前服务端／daemon／crctl 实际版本、路径、hash、运行配置和 DB 环境。
- AIFI-62 线上正式 CR 关联是否唯一、当前 Task 预检是否通过。
- review-code 线上 `origin.ref`／正文是否仍是 D3 记录的旧来源。
- 当前远端 refs、PAT 权限、浅历史／缺对象情况及真实交接结果。

以上均列入实施期核验，不能从本地源码推导为已完成。

## 2. 整改映射与不重复开发的事项

| 包 | 原编号 | 已核实的问题与处理 |
|---|---|---|
| A | D1-T1 | SUP FR 被拒绝；收紧编号边界后支持 SUP，schema 不变 |
| B | D2-A1／A2、CI 防漂移 | 修 gate 生成器、pending stage，重新生成 transitions／gates，更新 CI 固定来源 |
| C | D3-1／2 | 完整 Git 输出、显式 JSON 信封、全部机器消费点迁移 |
| D | D1-T2／T3／T4／T5 | recovery 同根、成功换根交接、权威根诊断与有限提示去重 |
| E1 | D1-M2 | 完成正文按明确编码解释，不再凭换行猜测；保持脱敏 |
| E2 | D3-5 | settled 后残缺 pass／block 进入 delivery-gap 失败分支 |
| F | D3-4 | 快照按已发布阶段选源、固定 SHA、逐 CR 来源及活动 run 保护 |
| G | D2-B1／B2／C1／C2 | 可信上下文优先、删除架构冗余报告要求、收敛规则与 README |
| H | D3-6、消费者核验 | 核实并纠正 Skill 来源；逐包记录实际运行版本与生效证据 |

D3-3 的正式 CR 关联绑定已有实现，本次复用，不新建绑定系统。D3-7 已有禁止二次 spawn reviewer 的合同和 `.crctl` 审计日志隔离源码；D3-8 的 `merge-fixture.mjs` 已错开三仓提交时间，`workspace-freshness.test.mjs` 保留 `TX_INPUT_CONFLICT` 负例。**这些是源码证据，不是本轮测试 PASS。**不重复立项；专门的派发／dirty 验证及夹具回归留到实施期，若发现回归再据证据确认范围。

## 3. 两条权威规则：本地操作与平台快照

### 3.1 本地操作根：复用事务解析器

本地权威规则以 `resolveOperationalWorkspace()` 为准，不重写一份：

- merge 交接完成前，使用 CR requirement 分支／worktree。
- journal `phase=complete`、operational workspace 及状态自洽后，使用 txws。
- `POST_FINALIZE_STATUSES` 包含 `merging`／`writing-back`／`archived`，但**状态属于该集合本身，不等于事务已完成或已发布**。
- archive 清理完成后，不再假定 txws／requirement worktree 仍存在；终态按既有历史账本规则读取。

包 D 的 status／next 诊断只复用解析结果；不得自动换根执行、改环境或写回状态。

### 3.2 平台快照：只表达已发布来源

包 F 的新采集路径不展示 txws 的未发布进度，允许暂时落后本地操作：

1. 明确知识库仓及其 trunk；以工作区声明为依据，对照 GitHub default branch。冲突先报告配置问题，不硬编码 `main`，也不把传入 root 的 HEAD 当 trunk。
2. 固定已发布 trunk SHA，从该 SHA 读取注册索引／history 和 trunk 上的 CR 文档。
3. trunk 文档为 `POST_FINALIZE` 时使用 trunk；否则优先读取已发布的 `requirement/{CR-ID}` 分支。
4. **确认远端分支不存在**时，允许使用 trunk 注册事实，这是正常的首次发布窗口；仅本地 tracking ref 缺失不算确认。
5. 分支存在时先固定其 commit SHA，再从该 SHA 读取正文。缺文档、缺对象、网络／权限／解析错误均使整轮失败，不静默降级或发送不完整快照。
6. history 终态仍按既有规则构造，但同样经过活动 run 守卫，不能以 archived 绕过保护。

本地操作根与平台快照采用相同的阶段方向，**不具有相同的时间点或发布证明**。事务发布窗口内允许出现 txws 已前进、平台尚未前进；不能据此重跑 merge 或改回本地状态。

## 4. 无 CR 受控维护的执行纪律

- 实施前另行确认维护清单、目标仓／分支、发布窗口、操作者和回退版本。本文件不自动授予实施权限。
- 使用普通源码／文档编辑和已有 `crctl git --workspace <KB> --cwd <repo>` 入口完成允许的暂存、提交与发布。该入口不要求 CR-ID，但仍加载规则并留审计；它不是新的 maintenance 事务框架。
- 已有可信 Task 绑定时继续遵守完整绑定与同真实根校验，不能清环境、换根或用裸 Git 绕过。需 ordinary Task 时，不挂到已有正式 CR 关联的 Issue 后再假称无 CR。
- Git 命令形态、提交信息格式按实际白名单执行；不扩大白名单，不伪造 CR 编号／审批记录，不篡改用户提交身份。
- 每包独立提交与代码评审，附变更范围、测试回执、未验证项和发布证据。包 F 独立提交和专项验收，不再硬性要求单独 CR／PR。
- multica 代码注释使用英文，定制变更按 `CUSTOM.md` 当时结构登记维护包、实际 Task／提交和问题来源，同步模块索引及相关追溯。CR-2026-076 等可作为真实问题出处，须注明不是本次交付 CR；不编造新的 CR／TASK 号，也不把本次变更冒充原 CR 已审批内容。
- 不直接修改 `specs/`、`delivery/`、traceability、CR status 或审批账本。隔离测试夹具不等于线上修复；状态操作仍只能走既有受控入口。
- 包 C 生效前，旧 Git 混合输出只能按旧合同识别，不得假设已经支持 `--json`。评审必须确认取证完整，不能将截断 diff 当正式证据。

## 5. 实施顺序与依赖

| 顺序 | 包 | 优先级／依赖 |
|---|---|---|
| 1 | C | P1，但建议先交付，给后续机器评审建立完整取证合同 |
| 2 | A、B | P0；可并行开发。B 先修生成器再生成，A 不再触发 AIFI-62 恢复 |
| 3 | D、E | P1；D 与 C 同文件，后合并方同步基线再评审；E1／E2 分清变更和证据 |
| 4 | F | P1；独立提交，需真实隔离 DB 验证及已发布来源测试 |
| 5 | G | P2；B 的生成器修复先落地，tools 模板先合并，再更新 multica 生成物及 CI 来源 |
| 全程／最后 | H | 每包发布后核验实际消费者，最后汇总全部证据 |

包 C 前置是取证顺序，不取消 A／B 的问题优先级。任何缺环境的包都可以按已确认政策发布，但必须标记未验证，不能据此判包或整体 PASS。

## 6. 各包修改与验收

### 包 A：SUP FR 兼容与编号边界（tools）

**修改**：`skills/writeback/scripts/writeback-traceability.mjs` 的 `buildNewMilestone()` 三处编号识别及排序；共用一个常量，声明在首次调用之前，避免 TDZ。

```js
const FR_ID = /^FR-(?:SUP-)?\d+(?=\s|$)/;
```

- 首格仍是“编号 + 空白 + 标题”，也允许编号单独占格；保留前导零及原编号。
- 只接受普通 FR 与 SUP；拒绝 `FR-1junk`、`FR-SUP-2junk`、`FR-SUP-X` 和其他命名空间。
- 普通 FR 在前、SUP 在后，各自按数字顺序排序；沿用原方案的 numeric `localeCompare` 即可，不新增排序框架。
- 五列表结构、TASK 与证据交叉检查不放松，输出 schema 不变。下游能承载 SUP，但不替生成器校验命名合法性。

**测试**：复用 `makeTraceWs()`／`traceOut()`：14 条普通 FR + 9 条 SUP、17 个 done TASK、15 个 cmd 的固定夹具生成 23 条链；核对顺序、标签、标题、证据。非法编号、非五列、未知 TASK、缺证据均失败且零 candidate。保留 legacy／幂等与下游 validator／archive 隔离回归。

```text
node --test skills/writeback/scripts/test/writeback.test.mjs
node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs skills/shared/crctl/scripts/test/archive-tx.test.mjs
```

**验收**：混合编号正确、非法输入 fail-closed，下游隔离回归通过。23／17／15 只是测试样本，**不写死生产数量，不依赖实际归档 CR-2026-076**。

### 包 B：平台状态机、门禁与 CI（multica）

1. `generate-gate-nodes.mjs`：删除 dev-start 的 `STAGES` 行和“第一个 human_approval”分支；其余默认 stage 缺失仍硬失败。
2. `project_gates.go`：`pendingApprovalStage("task-breakdown")` 仅在 `ApprovalGateNodes["dev-start"]` 存在时返回它，否则返回空串。
3. **先修生成器**，再从固定 tools commit 生成 transitions／gates。不可直接重跑旧生成器，也不可手改生成物。
4. 核对新增 `write-dev-tasks:finalize`；code 为 `…0010/seq10`，review-code 为 `…0009/seq9`；默认映射无 dev-start，code stage 唯一。
5. requirement／architecture registry digest 在仅包 B 修改时应不变，异常变化先停下核查。
6. CI 固定到同一个 tools commit，同时执行两个 `--check`。另核对生成物来源 SHA 与 CI 固定 SHA 一致；现有 `--check` 忽略来源注释，不能代替这项证明。

```text
node server/internal/governance/gen/generate-transitions.mjs --tools <fixed-tools-checkout>
node server/internal/governance/gen/generate-gate-nodes.mjs --tools <fixed-tools-checkout>
node server/internal/governance/gen/generate-transitions.mjs --tools <fixed-tools-checkout> --check
node server/internal/governance/gen/generate-gate-nodes.mjs --tools <fixed-tools-checkout> --check
# multica server/
go test ./internal/governance -count=1
```

**测试／验收**：finalize 正例、legacy 正例、unknown trigger 反例；默认无 dev-start 审批卡；code stage 唯一；两个内容检查和来源核对通过；governance DB 测试真正执行。

**不做**：特殊放行 crsync、恢复旧默认节点、删除 dev-start 兼容 API／tools gates／历史记录、历史回填。`gate_projection.go` 已有映射缺失保护，非必要不改。

### 包 C：受控 Git 完整输出与单 JSON 合同（tools）

**修改**：`crctl.mjs` 的 `controlledGit()`、`cmdGit()` 及参数解析。

- 删除 stdout／stderr 的 20000 字符 slice；`spawnSync` 设置 64 MiB `maxBuffer`。
- 保留原生 exit、error code、signal。超限明确失败，部分输出不能用于评审；**stdout 重定向不能绕过内部缓冲上限**。
- `--json` 由 crctl 消费，不透传 Git。可解析的该模式调用，前置拒绝和执行失败也输出单个 stdout JSON，不混入原文或诊断。
- 信封为 `{ok, exit, code, signal, stdout, stderr, error?, outbox?}`：未执行 Git 时 `exit=null`；`code`／`signal` 无值时为 null；前置失败保留既有 `error.code`／`error.message`，不新增业务错误码。
- JSON 模式 CLI 成功退出 0，失败退出非零；原生 Git 退出码另存 `exit`。未能启动 crctl、外部强杀等不承诺回执，调用方仍检查进程退出和 JSON 解析。
- 不传 `--json` 保持旧格式与旧合同。审计仍不记录完整 diff 正文，不用审计日志替代输出证据。

**全部机器调用方一起改**：controlled-shell 文档、review-code 的 diff／log／merge-base，以及 requirement／tech-design／dev-plan 评审中的 SHA 对账。先检查 `ok` 和退出情况，再读信封 `stdout`；SHA 必须是单行合法对象 ID，不能把信封本身当 SHA。`ok:false` 的任何部分输出都不可作为完整证据。

**测试／验收**：30 KB 与约 2 MiB diff 的输出 hash 和原生 Git 一致；末尾标记在；超限报 ENOBUFS；白名单拒绝／启动失败／Git 非零退出均可解析；参数没有透传；旧格式回归不变。缓冲负例使用可控夹具，不引入新测试框架。

```text
node --test skills/shared/crctl/scripts/test/crctl.test.mjs
```

**不做**：文件输出模式、流式协议网关、扩大白名单、全局错误框架、每个 Skill 自创解析器。实际超限需求出现后再决定扩展。

### 包 D：操作根、成功交接与诊断（tools）

| 子项 | 修改 | 必须验证 |
|---|---|---|
| T2 | publication-lag checkpoint recovery 的 args／cwd 从 `ctx.installRoot` 改为 `mergeWorkspace` | 完整绑定下 source 缺失／滞后，按原始 recovery 执行后 merge 可续；无绑定兼容；跨根仍拒绝 |
| T3 | delivery-agent、merge Skill、writeback node1 改为“当前 Task 已绑定操作根” | merge 完成且换根是成功交接；旧 Task 输出 txId／merge 证据后结束，新 Task 从 node2 接续，不重跑 merge／不改 env |
| T4 | `detectStatusDivergence()` 复用 `resolveOperationalWorkspace()`，status／next 共用 warning | merge 前指向 worktree；交接完成后指向 txws；在权威根无误报；解析失败不写入、不额外制造告警 |
| T5 | 仅针对缺 spec-id 的固定原因，在 status 摘要层去重 | checks 保持全部；不同文件缺失即使文案相同也保留两条失败 |

node4 的 `milestone_file` 改为“仅 legacy 模式传”，new 模式不得传。节点数仍为 5，不新建 coordinator／Runner Skill／根注册中心。

优先用正式 CR 关联自动 inspect／绑定；仅关联缺失或多义时使用既有显式声明。AIFI-62 线上关联未核实，不能把本地机制存在写成该 Issue 预检已通过。

```text
node --test skills/shared/crctl/scripts/test/merge-tx.test.mjs skills/shared/crctl/scripts/test/crctl.test.mjs skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
node --test pipeline-templates/emit-registry.test.mjs
# multica server/，须实际命中用例，0 个用例不算通过
go test ./internal/daemon -run 'Binding|ExecutionContext' -count=1 -v
```

真实交接验收使用授权的独立测试场景，不恢复 AIFI-62，也不为了造证据注册真实 CR。若既有编排不能表达上述交接，报告具体缺口再确认，不用提示词宣称已经完成。

### 包 E：完成正文编码与 Runner 证据分支（multica）

#### E1：最小显式编码合同

当前完成请求链是正文字符串直传，传输 JSON 已正常解码。**取消基于真实换行／provider 名称／版本的猜测**，也不保留无标志自动解码的旧行为。

- `TaskCompleteRequest` 和 Go `protocol.TaskCompletedPayload` 增加可选 `output_encoding`，保证 handler decode→重新 marshal→持久化 result 不丢字段。
- 缺省／`raw`：原样保留正文。
- `backslash-v1`：仅通过现有 helper 解释 `\n`、`\r`、`\t`、`\\`，不是完整 JSON-string 编码。
- 未知值在完成请求输入边界拒绝，使用既有请求错误合同，不猜测、不静默回退。
- 在 `task.go` 的 Issue 评论回退、聊天完成和 quick-create failure detail 三处，共用一个按编码解释正文的小函数。**不在 handler 对整个 output 统一反转义**。
- 结构化成熟度报告保持既有 raw JSON 文档合同，不把文本 helper 插入该路径；本包不为其扩展转义报告格式。
- 不把字段加到没有正文的 TS `task:completed` 生命周期事件；不扩展真正 FailTask 的 `error` 合同。
- 保持脱敏、正文裁剪、quick-actions 及空正文判定的安全要求；相关变化补回归。

**迁移**：先部署服务端。当前已核实的直传生产者继续缺省 raw，无须改 daemon 队列／发送协议。只有以后查到真实主动转义的生产者，才在该动作处标识并核验队列持久化／重放；不能凭旧版本打标。新字段对旧服务端被忽略不代表语义兼容，旧服务端仍可能二次解码。

**测试**：无标志／raw 的多行代码、单行 Windows 路径、UNC、正则和字面转义原样保留；显式 `backslash-v1` 才解码。原 quick-create “无标志字面 `\n` 自动解码”测试改为带标志，并补 raw 负向回归。未知值拒绝且不完成任务；字段往返不丢；三处消费、脱敏／裁剪／footer、结构化报告及原文复制均覆盖。

`UnescapeBackslashEscapes()` 与 CLI inline 文本测试保留原合同，不改通用 helper 来适配正文。tools 的 Windows 示例规则使用已确认根变量和 `Join-Path`，不将 `[REDACTED PATH]` 当目录。

#### E2：settled 后证据残缺明确失败

- `reviewRoundUndelivered()` 以 `conclusiveReviewEvidence(evidence, attempt)` 判断，不只看 verdict 字符串。
- requirement／architecture walk 中，残缺 pass／block 走 `reviewDeliveryGap(...)`，与 default 分支一致。
- settled 时进入现有 `RUNNER_REVIEW_DELIVERY_MISSING` 失败终态；`needs_reconcile=true` 等未 settled 情况继续等待。

测试 completed + 残缺 pass／block、attempt 错误、缺 subject SHA，以及未 settled 时仍等待。**本包不承诺消除全部无界等待，不新增超时／补偿协议。**

```text
# multica server/
go test ./internal/util ./pkg/redact ./internal/service ./internal/handler ./internal/governance -count=1
# multica 根目录
pnpm --filter @multica/views test chat/lib/copy-text.test.ts editor/utils/clipboard.test.ts
```

### 包 F：阶段选源与固定来源 SHA（multica）

本包仅完成 §3.2 的阶段读源修复，**不扩成全局投影／事件水位协议**。

- governance 中一个窄的阶段选择函数供 daemon／GitHub 共用；各适配器负责获取已发布 ref、固定 SHA、读取该 SHA 的文档。审批来源、evidence digest、签名及人类归因不改写。
- daemon 复用已允许的 `ls-remote --heads origin <精确 ref>`、fetch、完整 SHA show 等原语，不增加通用 Git 能力，不仅凭 tracking ref 判断存在性。冻结的对象不可取得则整轮失败。
- GitHub 先取 trunk／CR branch commit，再按 commit 读取内容；**分支查询的 404** 才能表示分支不存在。分支已存在但文档 404 是读取失败，不能混为“未发布”。
- snapshot payload／`AuthoritySnapshot` 增加可选逐 CR 来源 SHA；应用该 CR 时用实际读取其状态的 SHA，旧格式保留 HeadSHA 兼容回退，不伪造 branch SHA。相同状态的来源更新、history 来源和旧格式退化均须明确测试。
- 活动 run 守卫补齐 requirement／architecture／coding／feature-writeback 的 `running`／`waiting_approval`；跳过的 CR 不计 healed，不清 needs_reconcile，也不更新来源。history 终态没有绕过守卫的特权。
- 新版验收核实实际采集路径与来源；旧消费者的 HeadSHA 回退只是格式兼容，**不能据此宣称旧路径已满足 published 合同**。H 必须核验消费者更新与实际来源。

**必需回归场景**：

1. trunk 为 drafting、已发布 CR branch 为 approved：run 结束后投影读分支，不退回注册快照。
2. trunk 为 writing-back、branch 为 code-approved：读 trunk，不回退审批源。
3. 分支确认不存在：读固定 trunk 的注册事实；本地缺 tracking ref 不足以触发该回退。
4. 分支／内容读取错误：整轮不发送；只使用已冻结 SHA，正文与来源一致。
5. coding／writeback 活动 run 及 history 终态输入：按守卫跳过，结束后再对账。
6. 逐 CR projected_commit、同状态来源更新、旧字段兼容和结构化来源记录正确；不改审批 SHA。

复用 `crevents_test.go`、`reconcile_github_test.go`、`reconcile_test.go` 及隔离 DB 集成测试：

```text
# multica server/
go test ./internal/daemon -run 'Snapshot|CRWorkspace' -count=1 -v
go test ./internal/governance -count=1
```

测试筛选须实际命中用例；新增场景名称与命令同步，不能以 0 tests 或 DB skip 过关。

**明确未解决的限制**：

- 固定 SHA 是单个来源的绑定证明，不是跨所有 refs 的同一时刻事务快照。
- 普通 status 事件可先于发布到达；embedded 占位事件可能改状态而未更新真实 projected_commit。
- 当前 ApplySnapshot 的跨实例原子性、全局旧消息／分叉拒绝及来源水位一致性，不能仅靠阶段选择证明已解决。
- 本包不新增采样令牌、统一来源祖先协议或改造所有事件写入路径；不承诺消除全部投影回退。若限制导致六组必需回归不通过，包 F 不能判 PASS；落在明确延期边界的情况单列风险，保留证据，不扩写成已解决，也不自行扩项。

### 包 G：模板与说明收敛（tools → multica）

- 需求模板 5 处“读取 node-1 的 execution_context”改为“优先平台注入的 Verified execution_context；未注入时才回退 node-1”。包含 human approval 提示，注册 node-1 继续生成。
- 架构模板删除节点 1／2／4 的 node-N 摘要输出要求；节点数、UUID、顺序不变，历史文件不删。**保留 node1 的结构化 `execution_context` 输出及原样传递合同**，仅移除编号报告文件要求；不能为删摘要一并删掉可信上下文。
- 在既有通用行为约束加一句：不按编号惯例生成未声明报告；运行摘要留在运行输出，正式产物按既有 checkpoint 合同收尾。
- README 写清默认 requirement／tech-design／code 三处审批；dev-start 为显式兼容路径；coding 为 11 节点。原审批规则继续约束真实 CR，不因本次维护免 CR 而废除。
- tools 先合并，再从固定 commit 重新生成 multica registry／gates，同步 CI 来源并执行两个 `--check` 及来源核对。在途旧 run 按既有显式交接处理，不改库、不伪造 digest。

```text
# tools/
node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs pipeline-templates/emit-registry.test.mjs
# multica/
node server/internal/governance/gen/generate-transitions.mjs --tools <fixed-tools-checkout> --check
node server/internal/governance/gen/generate-gate-nodes.mjs --tools <fixed-tools-checkout> --check
```

`emit-registry.mjs` 导出需求／架构 registry，prompt 与 approvalPrompt 进入 digest；G 会改变这些摘要。gate 生成器另编译 coding 节点，对 feature-writeback 仅使用固定 pipeline ID，因此 D 的该模板措辞不改变当前编译内容，但重新生成仍可能更新 tools SHA 来源注释。不要把“一个模板不触发 digest”泛化成所有 prompt 都可不重新生成。

### 包 H：运维与消费者生效证据

- 授权操作者先核实 review-code 的实际 `origin.ref`／`source_url`；若仍是 D3 记录的旧分支，恢复到目标 main 来源并 refresh，再独立用 get-with-content 对照正文。
- 仍被引用的分支不提前删除。refresh 成功不等于正文已更新；必须取回正文核对包 C 等新合同。
- 每包分别记录：tools commit、实际 crctl 路径及 hash、multica 构建版本、相关 daemon／Skill／registry 的实际来源，以及操作者与核验回执。
- E1 核实服务端先更新；F 核实真实 collector root／trunk／已发布 ref 及新字段消费；B／G 核实生成来源与 CI 固定来源一致。
- 不只看 PR 合并、版本号或仓库 HEAD。验证失败／未能执行明确保留，不写“已生效”。

## 7. 验收、发布与回退

### 7.1 逐包证据

| 包 | 判 PASS 必需证据 |
|---|---|
| A | 混合编号与排序正确，非法边界 fail-closed；legacy／幂等／下游隔离回归通过 |
| B | 两个内容检查及来源一致；finalize 合法；默认无 dev-start 卡；stage 唯一；DB 真正执行 |
| C | 完整输出 hash／末尾标记；超限与前置失败单 JSON；机器消费正确；旧合同不变 |
| D | recovery 原样续接；权威根诊断正确；成功交接不重跑 merge／不换 env；T5 不误去重 |
| E | raw 与显式编码正确、未知编码拒绝、字段不丢、脱敏不退；残缺证据 settled 后失败 |
| F | 六组具体读源／守卫／来源场景通过，DB 真正执行；不扩写成全局防回退保证 |
| G | 模板与可信上下文一致；无新冗余报告；registry／CI 来源同步；旧 run 不被暗改 |
| H | Skill 正文与实际消费者版本／路径／hash／来源可核对，部署生效已确认 |

允许缺验证时发布，但回执必须分别列明：**已修改、已评审、已运行、未运行（含 skip）、已发布、未发布、已生效、未确认**。任何必需证据缺失，包／整体保持未验收完成，不能用“部署了”替代 PASS。

### 7.2 回退

使用经评审的 revert／旧版本发布路径，不使用 force、reset 或直接改状态。B／G 的生成物与 CI 固定来源一起回退；E 的回退说明旧消费者可能重新损坏输出，不能把新字段被忽略称为语义兼容。

已完成的业务合并／回写资产不随程序版本回退而撤销。程序回退造成原 CR 再次阻塞时，保持阻塞并报告，不删除节点证据或篡改治理文件。

## 8. AIFI-62：整改后的独立用户操作参考

本节不属于整改验收，也不授权实施者恢复 Issue。用户在全部整改完成后，如决定解除阻塞，应重新读取现场，而非照历史快照直接执行。

本轮本地记录支持 CR-2026-076 的 txws 状态为 writing-back、requirement worktree 仍为 code-approved；merge 及 baseline／tasks 发布 journal 已 complete，17 个任务交付记录存在。**这些是本地记录，不是线上当前状态或恢复成功证明。**

后续操作参考：

1. 重读 Issue、CR 权威状态、`workspace inspect`、节点产物和发布证据；正式字段决定 spec-id／target-version，不硬编码历史值。
2. 若 node1 merge 和 node2／3 证据仍有效，只续 node4／5；不重跑已完成 merge，不在旧 Task 中换根。
3. 新 Task 优先依靠唯一正式关联自动绑定；缺失／多义才走既有显式声明。不要拿脱敏路径当实际目录。
4. node4 经既有 writeback-apply，随后 archive；检查链路、任务、manifest／应用／发布原始回执。数量按当时输入确定，不能只用 23／17 判断合法。
5. 新结构错误返回原始回执并停止，不盲目重试、伪造完成或直接推进 Issue。

**AIFI-62 恢复与否不改变本方案的整改 PASS；用户无需恢复它来提供验收证据。**

## 9. 明确不做

- 不注册整改 CR，不回退 CR-2026-076，不伪造审批／身份／digest／generatorSha。
- 不新增表、服务、依赖、状态、业务错误码、通用 FR 命名框架、绑定中心、handoff 或水位协议。
- 不新增超大 Git 文件输出模式；不按正文换行／provider 版本猜编码；不无依据扩展 daemon 队列。
- 不自动改在途 run／Task env，不删除仍被引用的来源分支，不批量修复历史损坏消息。
- 不重复开发 D3-3／7／8；M1 排队问题仍排除。
- 不停止生成需求 node-1；未 settled 的永久等待、全局投影乱序等明确延期，不写成已解决。
- 不将任何线上 AIFI-62 恢复动作、真实 CR 归档或 Issue 状态变更作为整改验收条件。
