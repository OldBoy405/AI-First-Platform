# AIFI-45 四阶段 Registry 合同、提示词与测试执行修订 — 技术设计（草案）

> STDD Phase 2；Gate 1 已确认（含测试诊断/修复），Gate 2 待确认。本文不是实现/部署证据。
> 需求：`../../../../docs/AIFI-45-CR流程减负方案.md`（相对 change）；权威提案：`canonical/proposals/2026-10-19-aifi-45-runner-contracts.yaml`。
> 下文 T 为 sibling tools 仓根，M 为 multica/server；本机绝对路径不进入业务包。

## Context

- 基线 T=`a5ecb57`、multica=`b0b60a15b`。T 是 Node ESM 与 Markdown/YAML/JSON 包，无 package.json；本次不使用其 CR 流程来实施维护，采用 Issue + PR + STDD。
- `T/pipeline-templates/emit-registry.mjs` 当前仅支持 requirement/architecture；节点权限项仅 `{ref,owner,pipelineOwnerCanCall}`，缺 nodeId/executor。模板既有节点数为 6/4/11/5，不新增业务节点。
- coding 有重复的 `write-dev-tasks`/`workspace-freshness` ref、`code_generation` 节点和三个 loop；writeback 无 loop。平台现有固定四/六节点 parser、按 ref 唯一与 pipeline 单 loop 假设必须同时演进，不能只开放四个 ID。
- 生成器位于 `M/internal/governance/gen/generate-gate-nodes.mjs`；现有编译常量只含需求/设计。四个 PipelineIDs 不等于已接通四阶段执行。
- emitter 的 canonical body 当前只覆盖 pipeline/pipelineOwner/nodePermissions，inputs key 列表在 digest 外。扩展后的输入与执行绑定也必须被 digest 保护。
- 核查修正：四个 approve Skill 已无 start/resume 尾命令，保留当前正确行为并做负向回归；需要删除的接力在 Agent 与模板正文，不能虚构无用改动。
- 测试范围实测发现为 crctl 31 文件、output-guard 3、registry 1，共 35 文件；不是 35 个 case。原 15s/200s 限时不足以证明 12 文件挂死，亦不能证明它们是既有代码缺陷。根因诊断见本节后续修订，未经实测不写结论。
- STDD `extract-proposal` 的结构化输出未识别渲染视图中的 capabilities。已核对 canonical YAML，Phase 2 以该权威源的六个 capability 为准，不扩大范围去改 STDD 产品。

## Decisions

### 1. 在既有 emitter 内扩展按 node ID 的单一派发合同（L2 锚定）

**方案**：保留现有 schema 名称；补 code/writeback 对应 schema，在同一个 emitter 导出四个模板。规范字段：

```json
{
  "schema": "ai-first.pipeline-registry/code-core-v1",
  "pipeline": {
    "id": "code-implementation",
    "name": "existing template name",
    "inputs": [{"key":"cr_id","type":"text","required":true}],
    "nodes": [{"id":"stable-template-node-id","kind":"skill","ref":"write-dev-plan","prompt":"existing prompt","onFail":"existing policy","timeoutMinutes":30}]
  },
  "pipelineOwner": "dev-agent",
  "nodePermissions": [{"nodeId":"stable-template-node-id","ref":"write-dev-plan","owner":"dev-agent","executor":"dev-agent","pipelineOwnerCanCall":true}],
  "digest": "sha256:canonical-body-digest"
}
```

这是结构约定示例，不是新增模板/节点或运行时快照。需求/设计保留 `requirement-core-v1`/`architecture-core-v1`；新增 `code-core-v1`、`writeback-core-v1`。`nodeId` 和 `executor` 为拟新增导出字段；`pipeline.inputs` 为模板已有声明的补导出。现有顶层 inputs key 列表可暂为同源派生兼容视图，不能再作为第二份输入权威。

- digest body 覆盖 `pipeline`（含 inputs 的类型/required 及节点真实执行字段）、`pipelineOwner`、`nodePermissions`。JSON 字段生成顺序固定；读入先规范 CRLF。变化应使 digest 改变，不掩盖漂移。
- 每个非 human 节点恰有一条 permission，以 nodeId 唯一，不按 ref 去重。human gate 保留在节点序列，但不创建可执行 system Agent。
- 普通节点 executor 默认 pipelineOwner；独立 review 节点若需要显式声明，字段 `executor` 放在原模板节点上。执行绑定校验 active Skill、唯一 owns、所选 executor 为真实 kind=agent、owns/can-call、forbidden，作者与 reviewer 必须不同。review 绑定现有 quality-reviewer-agent，不让作者凭 can-call 代审。
- 逻辑 system owner 的 checkpoint/freshness 仍由已获授权的阶段 Agent 执行；owner 记录维护归属，不充当执行者。
- 平台只消费绑定并用同 workspace 的 `agentByName` 解析真实 Agent UUID，缺少/停用/无 runtime/能力不符即沿既有错误处理；不临时回退到调用者或其他空闲 Agent。

**为什么**：已有 matrix 与模板足以确定执行者；一个 emitter 承担确定性校验，运行时无需重建授权规则。

**备选排除**：另建路由表会产生第二事实源；按 ref 索引会覆盖 coding 重复节点；给 system 建 Agent 会伪造身份；把所有 Skill 授予调用者破坏独立评审。

### 2. 原样保存执行语义，不把多 loop/no loop 降成固定 walker

**方案**：导出原节点 `kind/ref/prompt/approvalPrompt/onFail/timeoutMinutes/reviewLoop`，包括 reviewLoop 内 `passCondition/replayNodes/replayPolicy/attemptInput/maxAttempts` 的完整声明。新增 coding/writeback 支持时，平台改为按 nodeId 消费多 loop；无 loop 的交付不要求 reviewLoop。

**为什么**：业务回修与技术 retry 不同；固定单 loop 会重置或错用计划/测试/代码的业务轮次。

**备选排除**：把所有节点翻译为四节点或统一一次评审，会丢失 freshness/finalize、业务结果与既有审批语义。不得添加新业务节点或新解释器。

### 3. 对齐原有 authority、机器结果与模板输入

**方案**：

- 注册仍允许 unassigned，需求评审前由负责人确认真实版本，Agent 用现有 version-set；不猜 tbd、不拖到代码审批后。
- coding/writeback 从 crctl authority 和现有输出继承 spec/version。new 模式不要求 milestone，legacy 按既有合同保留；不强迫用户重复填相同字段，不增加查询命令。
- merge 现有输出 `operationalWorkspace`（camelCase）与模板消费对齐；需要 spec/version 时最小扩展同一输出或 carrier，不建立同义字段副本。
- `phase=release-drift` 即使 exit0 也是回开发分支，不能当合并完成或技术 retry；`testCr.status=block` 即使 exit0 也不得当测试通过；`archive.status=cleanup-pending` 是既有归档业务成功。
- `recovery` 沿用 `executable/args/cwd/requiresTTY/promptFor`，保留机器 code，不让模型从错误文字猜恢复授权。merge 后新 task 绑定 operational root，archive 从安装根执行，工作目录由 daemon/crctl 决定，不让 server 猜本机路径。

**为什么**：深原语已具备 authority 与恢复语义，模板应消费实际字段而不是另行推导。

**备选排除**：文本解析 Issue 标题、静默占位版本、单看退出码、改运行中 task env 都会制造假完成或越权。

### 4. 删除重复编排，但不删除人工业务确认

**方案**：更新五个 Agent（requirement-writer/dev-agent/quality-reviewer-agent/delivery-agent/cr-coordinator-agent）及相关模板/Skill，只承接当前已派发节点。Runner 负责正常跨阶段派发、BLOCK/replay 与合法回修。保留 `crctl status/next` 为只读事实查询，不把“按 next 继续”写成 Agent 自行跨阶段启动。

- 协调者只负责入口、异常和必要人类输入；移除评论 mention 派 reviewer/启动阶段/审批接续。
- 四个 approve Skill 当前已正确，保留 grant/TTY、幂等与人工驳回的业务回退；仅为确实矛盾的文字修改，不为凑范围制造源码 diff。
- 仅必要索引/权限变化才修改 `_index.yml`、matrix，保持 56 active Skills 的合法归属，不新增 Skill/Agent。
- 合同测试替换旧接力正向断言，增加不得跨阶段自启的负向断言；不新增 lint 命令或第二份状态表。

**为什么**：去掉自动推进的人肉中转，不等于去掉审批/版本确认或允许 Runner 代签。

**备选排除**：保留 Leader fallback 或同时让模型与 Runner 接力，会重复派发；以删除审批“减负”违背需求。

### 5. 测试超时：先诊断再最小根因修复，完整测试仍是验收范围

**方案**：先记录 Node/Git/宿主环境、实际文件与 case 数、命令、monotonic 耗时及真实退出码。在临时隔离夹具中用 name-pattern 选择最小 case，对比能完成的同类调用，检查共同子进程/环境/钩子/输出缓冲。依据证据选择：

1. 若是正常慢文件：按实测确定预算和可见进度，不虚构业务缺陷；保留所有断言。
2. 若是环境或共享 harness 缺陷：RED 复现应在真实 caller seam，修共享根因，不逐文件打补丁。
3. 若是进程泄漏/死等：先写捕捉本次阻塞的回归，再限制/清理归属明确的子进程；不杀整个机器的 Node/Git。

最终命令保留全部 35 个当前文件及新增回归。不得 skip/exclude、全局关闭安全 Hook、只延长 timeout 或用 tail 退出码制造绿灯；不新增测试平台或产品命令。完整日志在临时路径，PR/Issue 只留经脱敏的证据摘要。

**备选排除**：本次之前直接排除 12 文件没有根因依据，已撤回；“文件没在15s结束”等于“一个case挂死”的推断也已撤回。

## Architecture

```text
tools: existing pipeline JSON + matrix + active indexes
  → emit-registry (4 schemas, nodeId/executor, full input and loop contract, digest)
  → multica existing generator (fixed tools revision)
  → compiled registry + existing parser/carrier + Runner (current node only)
  → task Agent calls current Skill → crctl authoritative business result
  → result carrier → Runner next node/handoff/recovery

existing approval/grant/TTY remains the business confirmation path
STDD Gate 1/2/3 governs this maintenance only, never approves live business CRs
```

### 改动与测试缝

| 改动 | 既有文件（T 根） | 回归重点 |
|---|---|---|
| 四阶段导出与绑定 | pipeline-templates/emit-registry.mjs、四模板 | emit-registry.test.mjs：重复 ref、未授权/system executor、多/no loop、digest |
| 模板输入和业务结果 | code-implementation/feature-writeback.pipeline.json、现有 deep primitive 输出必要扩展 | pipeline-structure/merge-tx/writeback-tx/archive-tx/test-cr/version-set.test.mjs |
| 提示词 | agents/五文件、相关 Skill、README | contract-scan/skill-scope/check-agents-contract/check-skill-matrix/lint-prompts.test.mjs |
| 测试基线 | 已有测试与共享 harness（仅证实根因涉及处） | test-execution-reliability 规格；全部35文件+新增回归 |

### 执行顺序（Gate 2 后才实施）

0. 诊断全量测试基线，证实缺陷才 RED→GREEN；不先更改业务代码。其后每个切片仍要真实 RED。
1. emitter 与模板合同的 RED→GREEN；固定 tools commit，暂不启用平台自动调度。
2. multica 侧生成器/parser/claim/carrier 同步；使用既有 `--tools`/`--check` 验证，不手改生成文件。
3. 开发/回修/交付、Tx handoff、heartbeat/key/grant、retry/tick 的对应回归接通后，去掉旧 ack/评论接力。
4. 同源提示词/模板更新及完整验证，非生产演练；两个变更通过 Gate 3 仍不代表获准 commit/push/部署。

## Risks / Trade-offs

| 风险 | 缓解 |
|---|---|
| 改 digest 会让旧 run 失配 | 受控接管复用既有入口和确认参数；不改旧digest、不跳校验；上线动作另需授权 |
| 模板先去接力、平台后启用出现无人推进 | 协同发布但不半套启用；实施期分支可分提交，正常模式切换必须整体就绪 |
| 作者借 can-call 执行 review | 显式 reviewer 绑定、禁止作者同人，运行时复用同 workspace 和节点能力约束 |
| 误把exit0的block/drift当成功 | 对真实机器结果做断言，回归 exit0-block/drift 与cleanup-pending分支 |
| 测试误判 | 实际退出码+文件/case/skip计数+计时；超时是未完成不是缺陷或通过的证据 |
| governance测试空跑 | multica TestMain 不连测试库会exit0；其单独验收必须证明真实case执行，不由tools绿灯替代 |
| STDD草稿多但无产品实现 | 本目录仅过程记录，全部测试状态标待验证；Gate2前不改业务实现，不发上线成功声明 |

### 诊断结论与已锁定的最小修复（Phase 2 实测补充）

| 实测范围 | 结果 | 结论 |
|---|---|---|
| checkpoint两个指定case，15s预算 | 15.15s，监督器124 | 超时仅代表预算不足，不是自然测试失败 |
| 同两个case，45s预算 | 18.12s，自然exit0，2 pass | 直接证伪“15s没结束就是挂死” |
| crctl单个TTY测试、内部24组合 | 26.53s，自然exit0，1 pass | 一个test内部可能有大量子进程，不能以文件数估case耗时 |
| crctl.test.mjs整文件 | 358.14s，自然exit1，294 case：288 pass/6 fail/0 skip/cancelled | 套件会自然结束；200s不足，但有6个真实失败须修 |

整文件在约5–355s仅输出TAP头；200s时已有5551次子进程调用完成，说明静默不等于无进度。Git trace确认环境有Git LFS hooks；仅诊断性的进程级hooks对照显示开销差异（11.64s→7.16s），不是正式验证方式，不能把禁用hook当修复。所有诊断所属进程已清理为0 PID。

**首批修复点**：

1. 五个失败返回`PAYLOAD_NOT_FOUND`，测试夹具把payload放在主checkout，但`cmdReviewRecord`先调用`authorityWorkspace`，随后按CR权威工作副本读取临时payload（`crctl.mjs`约3045、3086）。在`crctl.test.mjs`约2588、3146、6058、6436、8259按真实authority与测试目标修正夹具/绝对--from入口，不放宽生产authority、不伪造PAYLOAD_NOT_FOUND为原预期错误。先保留原安全断言（forged、drift等）形成RED，再修fixture。
2. `cmdTaskDone`的authority解析抛出已知`TxError(CR_WORKTREE_STATUS_MISSING)`，逃到总catch后变成`INTERNAL_ERROR`（约5495）。追查全部`authorityWorkspace`调用点后确认：它还供`readDataRoot`、advance/preflight、approve、attempt、review-reset、review-record、task相关入口等复用；个别调用者已有格式化而其他调用者遗漏。修复落在共享authority解析出口，且在现有容忍分支判定之后仅格式化已知TxError，保留错误详情、显式override、无绑定兼容与零业务写入；未知异常继续抛给总catch。不能为task done单独打补丁，不任意透传`e.code`或改总catch的可信边界。既有R1测试约8814为首个RED，补同源caller、合法容忍和未知异常边界的最小回归。

已证实的最小RED命令（tools根，原文件未修改）：

```text
node --test --test-reporter=tap --test-name-pattern="^TASK-06 ①: payload 伪造 release-subjects -> RELEASE_SUBJECTS_FORGED，annotation 零写入（AC-1）$" skills/shared/crctl/scripts/test/crctl.test.mjs
node --test --test-reporter=tap --test-name-pattern="^AIFI-69 B1/R1：显式 --operational-workspace 仍按传入值；authority 解析失败时零业务写入$" skills/shared/crctl/scripts/test/crctl.test.mjs
```

单例实测分别约1.03s/1.11s、exit1；预期分别`RELEASE_SUBJECTS_FORGED`与`CR_WORKTREE_STATUS_MISSING`，实际分别`PAYLOAD_NOT_FOUND`与`INTERNAL_ERROR`。完整证据在系统临时诊断目录`aifi45-node-diag-uubvw97i/crctl-file-native/{command.json,result.json,stdout.log,stderr.log}`，不复制敏感环境值进仓库。

**剩余待分类**：其余此前超时文件未逐一完成，不宣称全部只有同一根因或全部通过。Phase3基线切片按实测预算（单文件crctl已需约6分钟，全量应更长）运行完整35文件，逐个分类真实失败；若出现超出本scope的安全/环境阻塞，记录并请求调整，不删除测试。当前证据仅Windows/Node24，不伪称Node20或Linux已验证。
