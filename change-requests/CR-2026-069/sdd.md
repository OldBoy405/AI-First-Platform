---
id: CR-2026-069-sdd
type: SDD
cr-ref: CR-2026-069
title: CR 流程降本提效首期：FR-8 成本基线 + FR-1 OutputGuard + FR-2 crctl 输出瘦身 技术设计
target-version: 0.42
status: draft
created: 2026-09-17T15:45:00+08:00
updated: 2026-09-17T15:45:00+08:00
---

# 1. 架构概览

## 1.1 设计目标与不变量

本 CR 的技术设计只做一件事：**在「工具结果进入下一轮模型上下文之前」与「crctl 成功输出投影层」两个面上做减法，并用一份离线度量把「省了多少、有没有变差」变成可证伪的事实**。设计输入是需求合同（`dep-1`：FR-8 / FR-1 / FR-2、AC-1～AC-21）与需求来源（`dep-2` §5～§10）；设计边界由 `dep-1` §1.3.1 / §1.3.2 / §7 与 `dep-2` §2 / §3.1 / §11 钉定：**零新增治理结构**。

落成九条设计不变量（供 `review-tech-design`、plan/TASK 与 `implement-code` 逐条核对）：

| # | 设计不变量 | 判据落点 |
|---|---|---|
| I1 | **Core 无状态且确定性**：Core 是纯函数；同一决策指纹（`policyVersion` + 命中规则标识 + 规范化参数 + 规范化原始正文）在同一 policy 版本下必须产生逐字相同的模型可见结果与 trailer；跨调用零状态（不建授权文件、nonce、永久开关、"下一次调用"状态） | FR-1 第 1/6 项、§4.2、§4.4、AC-3 / AC-6 |
| I2 | **三份 JSON 各自唯一事实源**：`policy.json`＝阈值与命令族、`capabilities.json`＝Runtime 能力、`conformance.json`＝跨 Adapter 合同；代码、Prompt、Skill、README 一律不复刻其内容，只引用 | FR-1 第 1 项、NFR-2、§2.3 / §3.5、AC-3 / AC-13 |
| I3 | **seam 唯一**：裁剪只发生在「Runtime 原生工具调用 → Adapter → Core → 模型可见结果」这一条链上；下游 transcript / preview / daemon 展示层零改动 | FR-1 定位段、§1.3、AC-12 |
| I4 | **完整性与覆盖度诚实**：被裁剪结果必须标 `complete=false`；不可安全保持字段/结构则不裁剪并标 `coverage=unavailable`；`complete=false` 不得作为充分门禁证据；降级必须显式，不得静默假装生效 | FR-1 第 5/8 项、NFR-6、§4.2 / §4.5、AC-8 / AC-15 / AC-16 |
| I5 | **FR-2 只动呈现层**：唯一改动面是成功输出的投影层；退出码、错误码与错误体、字段语义、状态、门禁、审批、CAS、事务与 Git 行为逐一不变 | FR-2 第 3～5 项、§4.6、AC-10 / AC-11 |
| I6 | **度量只读且非权威**：FR-8 不推进 CR、不参与门禁、不写状态与账本；机器结果只有一份 JSON；口径与观测时刻随输出；样本数不硬编码 | FR-8 第 1/3/6 项、§4.7、AC-17 / AC-18 |
| I7 | **治理面零新增**：无新状态、门禁、审批、Pipeline 节点、账本、数据库、仪表盘、sidecar 日志、WAL、CAS 层、远程开关；跨仓写入一律复用既有事务与 checkpoint | NFR-1、§4.9、AC-1 / AC-2 |
| I8 | **同一 Release 原子发布 + 单点回滚**：Core + 三份 JSON + 五个 Adapter 属同一 Tools Release；单 Runtime 误伤只禁用该 Adapter（新会话生效） | FR-1 第 10/12 项、§3.4、AC-19 / AC-14 |
| I9 | **行尾与硬失败纪律**：任何对仓库文件或 session 文件做哈希、跨行正则、逐行解析的代码，读入先 `\r\n → \n`，解析用 `split(/\r?\n/)`，匹配失败硬失败报错（禁止"匹配不到 → 空集 → 静默通过"） | NFR-8、`dep-3` §5 不变量 4、§7.1 |

**本 CR 的核心架构判断**（三条，全部由 `dep-1` / `dep-2` 钉定，SDD 只做落点选择）：

1. **成本杠杆在"治理点位置"，不在"提示词自律"**：seam 必须在模型可见结果之前（I3）；因此 Adapter 必须挂在 Runtime 的**工具结果回填 hook**上，而不是在 daemon 的 transcript/preview 上做二次加工。
2. **裁剪必须是"确定性、非语义"的**：不调用 LLM、不做语义压缩，只做"唯一文件列表 / 连续行窗口 + 原始行号 / 头尾保留"三类机械变换（§4.3）；任何需要理解语义的收窄交回给模型（通过 trailer 提示下一次 `offset/limit` 或缩小范围写法）。
3. **降级必须是"显式 fail-open"且与 fail-closed 安全层正交**：OutputGuard 失效时原调用继续、结果不改（安全层不受影响）；crctl / Git / 账本 / 审批的 fail-closed 行为不因 OutputGuard 而改变（§7.2）。

## 1.2 变更面鸟瞰

本 CR 交付 diff = 三个仓的**新增为主 + 既有文件最小改动**，无删除文件、无新状态、无新节点、无新账本。计数单位：新增文件按"文件"计，既有文件按"落点"计。

```text
../tools（方法论包；本 CR 代码实施面主体）
  新增：
    output-guard/core.mjs                                     ← FR-1 纯函数 Core（无依赖，node 内建）
    output-guard/policy.json                                  ← FR-1 阈值/命令族唯一事实源（数值由 TASK-01 产出）
    output-guard/capabilities.json                            ← FR-1 Runtime 能力唯一事实源
    output-guard/conformance.json                             ← FR-1 跨 Adapter 共享测试向量
    output-guard/README.md                                    ← 模块总览 + 权威入口链接（不复制政策内容，AC-13）
    output-guard/adapters/pi/index.ts                         ← TASK-03（pi extension：tool_call + tool_result）
    output-guard/adapters/pi/README.md
    output-guard/adapters/claude/{pretooluse-guard.mjs,posttooluse-guard.mjs,settings.template.json,README.md}   ← TASK-04
    output-guard/adapters/codebuddy/{pretooluse-guard.mjs,posttooluse-guard.mjs,settings.template.json,README.md} ← TASK-05
    output-guard/adapters/qoder/{pretooluse-guard.mjs,posttooluse-guard.mjs,settings.template.json,README.md}     ← TASK-06
    output-guard/adapters/codex/{pretooluse-guard.mjs,posttooluse-guard.mjs,hooks.json.template,README.md}        ← TASK-07
    output-guard/scripts/check-install.mjs                    ← 启动检查：只报告缺失/损坏 + 明确修复命令（AC-19③）
    output-guard/test/{core.test.mjs,conformance.test.mjs,adapters-contract.test.mjs}   ← FR-1 回归面
    skills/shared/metrics/scripts/cr-cost.mjs                 ← FR-8 度量脚本（TASK-01 / TASK-10）
    skills/shared/metrics/scripts/lib/{sessions.mjs,aggregate.mjs,select.mjs,render.mjs}  ← FR-8 纯函数分层
    skills/shared/metrics/test/cr-cost.test.mjs               ← FR-8 回归面
    skills/shared/crctl/scripts/lib/summary-projectors.mjs    ← FR-2 独立 summary projector（TASK-08）
    skills/shared/crctl/scripts/test/crctl-summary.test.mjs   ← FR-2 summary/detail 合同测试（TASK-08）
    skills/shared/crctl/scripts/test/caller-contract.test.mjs ← FR-2 调用方扫描断言（AC-21①）
    skills/shared/crctl/scripts/test/golden/crctl-detail/*.json ← 改造前完整输出金样本（字段路径 + 稳定值）
  既有文件改动（落点逐个列明）：
    skills/shared/crctl/scripts/crctl.mjs                     ← 3 处：ok() 投影入口 / parseArgs 的 --detail 布尔化 / HELP 一行
    skills/shared/crctl/scripts/test/gate-registry.json       ← manifest.files + manifest.cases 同步（AC-21②）
    skills/shared/crctl/SKILL.md                              ← `--detail` 采纳（§8）
    skills/develop/review-{tech-design,code,dev-plan}/SKILL.md ← 取证完整性规则采纳（AC-16，§8）
    README.md                                                 ← §8「权威事实源链接」增一行 + §4 一行导航（AC-13）
    ARCHITECTURE.md                                           ← §3 代码地图增 output-guard / metrics 两条（只增不改 §4/§5/§6）
    .github/workflows/crctl-ci.yml                            ← paths 增 output-guard/** + metrics/**；steps 增两条测试步骤
  明确零 diff（见 §9 zero_diff）：
    skills/shared/crctl/scripts/lib/durable-tx.mjs、lib/workspace-transactions.mjs、lib/outbox-contract.mjs、
    lib/yaml-subset.mjs、gates.json、dir-graph.yaml、pipeline-templates/*.pipeline.json、
    agent-skill-matrix.yml、skills/shared/controlled-shell/rules.json

../multica（平台底座；只做 Runtime 启动挂载，挂载先例与挂载点见 `dep-4`）
  新增：server/internal/daemon/execenv/outputguard_config.go   ← TASK-09 挂载解析/拼接（不复制 policy）
  既有文件改动：server/internal/daemon/execenv/crguard_config.go ← 单写入点内合成 OutputGuard hooks（新增可空入参）
              server/internal/daemon/execenv/*_test.go（同包回归测试）
              CUSTOM.md                                        ← 按其现状登记本次定制（AGENTS.md 纪律 10）
  明确零 diff：server/internal/daemon/tool_output_preview.go、server/internal/governance/runner.go、
              server/pkg/agent/pi.go（不新增/不放开任何 argv 面）、Provider 事件归一化实现

ai-first-platform-docs（KB：只承载本 CR 过程产物）
  变更：change-requests/CR-2026-069/{sdd.md（本文档）、evidence/fr8-baseline.json（TASK-01 机器结果副本）}
  零 diff：specs/、delivery/、docs/、四账本（cr.md 除 crctl 状态行外、_backlog.yml、traceability.yml、
          tasks/_index.yml）、prd.md（已随审批按 evidence-digest 钉住，本阶段不得改写）
```

**改动量上界**：`crctl.mjs` ≤ 6 行（不含新增导入）；`crguard_config.go` ≤ 40 行（新增入参 + hooks 合成，原行为在入参为 nil 时逐字不变）；其余既有文件均为"增行/加一段"，无既有语义改写。

## 1.3 依赖方向与分层与多仓口径（不变）

```text
Agent → Pipeline → Skill → crctl                         （治理链，本 CR 不动；AC-1）
Runtime 原生工具调用 → Runtime Adapter → OutputGuard Core → policy.json
                                                          （本 CR 新增的唯一裁剪链，FR-1）
离线度量脚本 → 既有 session / provider usage（只读）       （本 CR 新增的唯一读链，FR-8）
```

三条硬约束逐字取自 `dep-3`（§4 分层与依赖方向、§5 硬不变量、§6 刻意不做）：

- 依赖只朝下；Skill 不得绕过 crctl 直接改写账本（本 CR 不新增第二条账本通道；度量脚本零账本写入）。
- 「另一套独立 WAL/事务框架」是既有禁区（`dep-5` 是跨文件与跨仓写入的唯一实现）；本 CR 的新增代码不引入锁、journal、write-set、CAS 或提交框架。
- 「零第三方依赖」是 `dep-6` 所在层的既有不变量；`output-guard/` 与 `skills/shared/metrics/` 沿用同一口径（只用 `node:*` 内建模块，无 `package.json`、无构建步骤）。

**多仓路径 authority**（`dep-1` §1.3.2 的目标仓表 + `write-tech-design` Step 1）：本 SDD 的全部仓内路径只以 `crctl workspace inspect CR-2026-069` 返回的 `resources[].worktreePath` 为根，禁止按 `.rayai-worktrees/{repo}/requirement/{cr}` 目录命名拼接。三仓 worktree 事实（本轮 `workspace inspect` 实读，classification 均 `healthy`、`dirty=false`）：`ai-first-platform-docs`、`multica`、`tools`。

## 1.4 关键流程

### 1.4.1 一次工具调用的完整决策链（FR-1）

```text
① Runtime 自身权限与既有安全控制（`dep-7` 白名单 / protected paths / 审批 / 账本写入控制）
      ↓ 先于 OutputGuard，且 OutputGuard 既不评估也不放宽
② Adapter Pre 侧（Pi: tool_call；Claude/CodeBuddy/Qoder/Codex: PreToolUse）
      → 取"原始命令首行"判定一次性逃生阀标记
      → 解析失败/畸形 → 视为"不存在该标记"（§4.1，不拒绝调用、不新增 action 取值）
      → 逃生阀合法 → action=passthrough，跳过全部封顶，仍受 ①
      → 命中命令族且可判定 → action=block（拒绝 + 可执行替代写法）
                             或 action=rewrite（对参数施加上限后执行）
      → 不确定（管道/重定向/脚本嵌套）→ 允许执行，进入 ③ 的统一封顶
③ 工具执行
④ Adapter Post 侧（Pi: tool_result；Claude/CodeBuddy/Qoder: PostToolUse.updatedToolOutput；Codex: PostToolUse feedback 路径）
      → 先做"可保持性检查"：Runtime 结果结构能否承载 toolName/toolCallId/isError/exitCode(若该 Runtime 有)
      → 不可保持 → action=unavailable，结果逐字不改，标 coverage=unavailable（§4.2）
      → 可保持 → Core 纯函数裁剪 → action=truncate，追加一行 trailer，标 complete=false
      → 未命中任何规则 → 不追加任何文本（§6.7 的"正常未触发调用不增加文本"）
⑤ 裁剪后的结果进入下一轮模型上下文 / session / transcript
```

终态取值集合固定为 `{block, rewrite, truncate, passthrough, unavailable}`，不新增第六个取值（`dep-1` FR-1 第 7 项）。

### 1.4.2 降级与覆盖度派生（FR-1 → FR-8）

```text
安装期：output-guard/scripts/check-install.mjs  → 每个 Runtime 一行 output-guard runtime=… coverage=… policy=v1
        （只读检查：Adapter 是否被 Runtime 的配置面引用、policy/capabilities/conformance 是否可解析）
运行期：Adapter 加载失败/被禁用/bundle 损坏/policy 解析失败 → OUTPUT_GUARD_UNAVAILABLE runtime=… reason=<四值枚举>
        → 原调用继续、结果不改（fail-open）→ 该会话 coverage=unavailable，排除出完整覆盖样本
离线期：cr-cost.mjs 读取既有 session + 启动检查记录 + trailer，派生 coverage{runtime→full|partial|unavailable}
```

三级 scope（`dep-1` FR-1 第 10 项 / AC-19④）的落点与"谁来做安装"：

| scope | 配置面（各 Runtime 既有面） | 本 CR 的动作 | Adapter 是否由本 CR 自动写入 |
|---|---|---|---|
| Project | 目标 workspace 内的 `.claude/settings.json` / `.lingma/settings.json` / `.codebuddy/settings.json` / `.pi/settings.json` | 提供模板 + 安装说明 + 检查命令 | 否（人工安装一次） |
| User | `~/.claude/settings.json` / `~/.lingma/settings.json` / `~/.codebuddy/settings.json` / `~/.pi/agent/settings.json#extensions` | 同上 | 否（人工安装一次） |
| Managed | Multica 每任务 env 内由 daemon 写入的 Runtime 配置（claude / codebuddy / qoder） + 宿主级 `~/.pi/agent/settings.json`（Pi） | daemon 挂载（TASK-09）+ 安装说明 | 是（仅 Managed：Multica 任务环境） |

### 1.4.3 FR-2 成功输出投影（一次命令的呈现层）

```text
main() 取 cmd 与 flags
   → resolveProjection(cmd, flags)：
        flags.detail === true            → null（走原路径，逐字段完整输出）
        cmd 不在 SUMMARY_PROJECTORS 中    → null（未投影命令等价于现状）
        否则                              → 该命令的纯投影函数
   → 分发到 cmdXxx()
        → 成功出口 ok(obj)  ← 唯一投影点，未注册投影时空转
        → 失败出口 fail(code,msg,extra) ← 零改动（247 个出口全部不进投影）
```

### 1.4.4 FR-8 两次执行与扩项判定

```text
改造前（TASK-01）：cr-cost.mjs baseline --out <path>
   → 读既有 session（只读）→ 样本筛选（目录/类型/时间窗/CR-ID 归属）→ 归一化指标 + crctl 命令聚合
   → 对历史 session 离线回放 OutputGuard policy（纯函数重算，不执行任何命令）
   → 输出唯一机器 JSON（字段集 ≡ PRD FR-8 第 3 项 / 来源 §5.4）+ stdout 人读摘要（同一对象渲染）
   → 选出"覆盖 ≥80% crctl 输出 token 的最小命令集合" → 交 TASK-08 落进 projector 注册表
部署后（TASK-10）：cr-cost.mjs after --window 14d
   → 只统计 coverage=full 且带 CR-ID 的完整 Pi CR
   → 目标桶 tokens/CR ≥20% 下降 ∧ 三项质量护栏全不恶化 → 才允许重新立项评估 FR-3～FR-9
   → 样本不足 → 输出 insufficient-sample，不产出成本结论、不延长本 CR
```

### 1.4.5 本 CR 自身的交付顺序（十个 TASK 的依赖，不新增节点）

```text
TASK-01（FR-8 基线 + 命令聚合 + 历史回放）
   ├─→ TASK-02（Core / policy / capabilities / conformance）
   │        ├─→ TASK-03 Pi ─┐
   │        ├─→ TASK-04 Claude ─┤
   │        ├─→ TASK-05 CodeBuddy ─┼─→ TASK-09 Multica 挂载（claude/codebuddy/qoder）→ TASK-10 部署后复测
   │        ├─→ TASK-06 Qoder ─┤
   │        └─→ TASK-07 Codex ─┘
   └─→ TASK-08（FR-2 summary/detail + 调用方同步 + 棘轮登记）
```

启用顺序（部署顺序，不新增 CR 状态或 Pipeline 节点）：`Pi → Claude → CodeBuddy → Qoder → Codex(partial)`；每个 Runtime 以「conformance 通过 + 真实冒烟通过 + 降级验证通过」为下一项的前置（AC-20）。

### 1.4.6 术语预检（Step 2.5 结论）

只对进入数据模型/接口契约且存在歧义风险的术语硬化，结论如下（不新增术语表文件，本节即载体）：

| 术语 | 歧义风险 | 本 SDD 的裁决（全文唯一口径） |
|---|---|---|
| `coverage` | `dep-1` 在两处使用：FR-1 的"路径/会话覆盖度标记"与 FR-8 输出的 `coverage{runtime→full\|partial\|unavailable}` | **三级正交定义**：`level`（Runtime 治理能力，声明于 `capabilities.json`，取值 full/partial/unavailable）/ `pathCoverage`（某条 Runtime 路径是否被治理，声明于 `capabilities.json.paths[]`）/ FR-8 输出的 `coverage[rt]`（**派生投影**：由 `level` + 窗口内是否观测到该 Runtime 的 `OUTPUT_GUARD_UNAVAILABLE` 与启动检查记录共同决定）。FR-8 的 `coverage` 永不作为声明源，只作派生值 |
| `complete` | trailer 的 `complete=false` 与 Runtime 自身的截断字段（如 Pi 的 `details.truncation`）可能被读成同一件事 | `complete` 只表示"**模型可见结果正文是否等于工具原始结果正文**"；Runtime 自身的截断字段语义不变、不被本 CR 改写（`V-3`）。两者同时出现时，`complete=false` 由 OutputGuard 产生，Runtime 字段保持原样 |
| `action` | `unavailable` 在 `dep-1` FR-1 第 7 项与第 5 项中来源不同 | `action` 是**单次调用的终态裁决**，取值闭包五值；`unavailable` 有两个合法来源：其一为第 8 项的 bundle/policy 降级面（连带 `OUTPUT_GUARD_UNAVAILABLE` 码），其二为第 5 项的"字段/结构不可安全保持"路径面（不产生错误码，只产生 trailer + `pathCoverage=unavailable`）。二者不合并、不新增取值（同时关闭 `dep-1` §1.5 第 5 条与需求评审 S-2） |
| `escape hatch` / 逃生阀 | 与"绕过安全控制"混读 | 逃生阀**只影响 OutputGuard 自身的封顶**（`action=passthrough`），对 `dep-7` 的 git 白名单 / protected paths / 审批 / 账本写入控制**零影响**（AC-6 四条负向测试） |
| `--detail` | 与"新增输出模式"混读 | `--detail` 是**布尔型呈现层开关**，只决定"成功输出是否被投影"；不参与状态判定、门禁、审批、CAS；未投影命令收到它是**布尔真但无投影函数 → 与现状等价**（同时关闭需求评审 S-1） |
| `policyVersion` | 被读成"多版本兼容/迁移" | 只表示**格式版本**；不建多版本兼容、不建迁移框架、不支持同时加载两版 policy（FR-1 第 10 项） |
| `k` | 被读成"真实账单节省" | `k = 计费金额来源值 ÷ 同区间工具结果 token`；**必须同时输出金额来源标识与分母 estimator 标识**；金额来源不可得时 `k=null` 且禁止任何金额宣称（FR-8 第 4 项、AC-18；需求评审 S-4 的计数口径类风险由 §3.6 的 `observedAt` + `rule` 义务关闭） |

**语义冲突结论**：以上裁决全部是对 `dep-1` 内部两处用词的对齐（`dep-2` 未与 `dep-1` 冲突），**不构成需要需求负责人澄清的语义冲突**，因此不阻塞首次状态推进（`crctl advance --to tech-designing` 已在草案落盘前执行）。

## 1.5 与 PRD §1.5 九条口径的承接

`dep-1` §1.5 的九条中：五条为需求侧钉定或更正（第 1、2、3、4、8 条）、三条标为"需人工一并确认"（第 5、6、7 条）、一条明确交 SDD 决定（第 9 条）。第 5/6/7 条由本 SDD 按 `dep-1` 的钉定实现，并在架构审批时随本 SDD 一并人工过目（本 SDD 未改写这三条的任何取值）。逐条承接如下（关闭项编号见 §6.5）：

| `dep-1` §1.5 | 本 SDD 的承接 |
|---|---|
| 第 1 条（Issue 标题 FR-0 不存在） | 只做 FR-8 / FR-1 / FR-2 三块；§9 `scope_out` 逐条排除 FR-3～FR-7、FR-9 |
| 第 2 条（FR 编号空洞刻意） | 全文不出现"缺 FR-N"式补全；TASK 编号与 FR 编号解耦（一个 TASK 可承载多 FR，见 §6.1） |
| 第 3 条（样本数不写成硬事实） | §3.6：样本数由脚本输出；代码/门禁中零硬编码样本常量；任何计数断言必须带口径与观测时刻（SDD-CLOSE-08） |
| 第 4 条（能力矩阵不由 PRD/SDD 复述为事实） | §2.4 `capabilities.json` 为声明载体；§6.3 的 `V-1`～`V-7` 列为待核实依赖；降级唯一合法动作与 AC-4 的联动见 §4.5 + SDD-CLOSE-05（同时关闭需求评审 S-3） |
| 第 5 条（逃生阀标记不合法 → 视为不存在） | §4.1 算法 A1：不合法标记 → `absent`，不拒绝调用、不新增 action 取值；若随后被裁剪仍输出 `action=truncate` trailer（SDD-CLOSE-04） |
| 第 6 条（`--detail` 与旧完整输出的等价定义） | §3.1 契约 + §4.6 合同测试：**字段集合等价**（逐字段路径）＋稳定值等价＋易变字段形态等价；禁止字节比对（SDD-CLOSE-02） |
| 第 7 条（棘轮登记同步义务） | §6.4：新增 `*.test.mjs` 即触发 `SUITE_MANIFEST_FILE_DRIFT`，因此 `manifest.files` + `manifest.cases` 必须同批更新；`exceptions` 保持空数组（SDD-CLOSE-03） |
| 第 8 条（Adapter 与既有 crctl 适配器的关系） | §3.4 + §6.5 SDD-CLOSE-01：两套职责分目录、各自模板、各自安装入口；`policy.json` 不进入 `skills/shared/crctl/adapters/`；唯一联合点是 Managed scope 下单写入点合成（§4.9） |
| 第 9 条（Plugin 打包形态交 SDD） | §5 决策 D-3：**不引入 plugin 打包形态**，沿用既有"模板 + 安装时物化绝对路径"先例；理由与替代方案见 D-3（SDD-CLOSE-06） |

---

# 2. 数据模型

## 2.1 零新增实体、字段与账本（NFR-1 落点）

本 CR **不新增任何数据库表、迁移、账本字段或状态**：三仓交付面全部是"新增目录/文件"与"既有文件增行"；KB 侧只写 `change-requests_{cr}/` 下的过程产物（与既有 CR 目录同构）。数据库/schema 变更与写路径鉴权完整性一节因此在 §2.6 显式记 `N/A`。

## 2.2 本 CR 新增的四个数据形状

四个形状全部是**纯 JSON 文件或纯函数返回值**，无运行时存储、无索引、无缓存持久化。

### 2.2.1 `policy.json`（FR-1 阈值与规则唯一事实源）

```jsonc
{
  "policyVersion": "v1",                  // 只表示格式版本（见 §1.4.6）
  "families": [                            // 首期命令族（dep-1 FR-1 第 2 项钉定的五族）
    { "id": "grep",   "kind": "search", "match": ["grep", "rg"] },
    { "id": "find",   "kind": "list",   "match": ["find", "Get-ChildItem"] },
    { "id": "read",   "kind": "read",   "match": ["cat", "Get-Content"] }
  ],
  "thresholds": {                          // ← 唯一数值面；全部由 TASK-01 基线产出，代码内零常量
    "resultTokensCap": 0, "lineWindow": 0, "maxHits": 0, "headLines": 0, "tailLines": 0
  },
  "truncation": { "search": {…}, "list": {…}, "read": {…}, "generic": {…} },
  "hints": { "narrow": "…", "nextOffset": "…", "omitted": "…" },   // 文案模板，唯一事实源
  "escapeHatch": { "marker": "# output-guard: full", "reasonMaxLength": 0, "singleLine": true }
}
```

规则：`thresholds` 的任一字段在 `core.mjs` 中**不得出现字面量**（AC-3 的判据：代码 diff 内无阈值常量、无第二份阈值副本）；`policy.json` 缺失或不可解析 → `POLICY_INVALID` 降级（§4.5）。

### 2.2.2 `capabilities.json`（Runtime 能力唯一事实源）

```jsonc
{
  "schema": "output-guard/capabilities/v1",
  "enableOrder": ["pi", "claude", "codebuddy", "qoder", "codex"],   // 部署顺序，不新增 CR 状态
  "runtimes": {
    "pi": {
      "level": "full",                       // full | partial | unavailable（声明，由 conformance 验证）
      "preHook": "tool_call", "postHook": "tool_result",
      "preserve": { "toolName": "present", "toolCallId": "present", "isError": "present",
                    "exitCode": "absent-by-runtime" },   // 见 §4.2：absent-by-runtime 必须在 V-1/V-3 核实后落笔
      "startRecord": "extension-load",       // 会话启动记录的产生面
      "paths": [ { "id": "bash", "coverage": "full" }, { "id": "read", "coverage": "full" } ]
    },
    "claude":    { "level": "…", "paths": [ … ] },
    "codebuddy": { "level": "…", "paths": [ … ] },
    "qoder":     { "level": "…", "startRecord": "none", "paths": [ … ] },
    "codex":     { "level": "partial", "startRecord": "session-start",
                   "paths": [ { "id": "…", "coverage": "partial" },
                              { "id": "hosted-websearch", "coverage": "unavailable", "uncovered": true } ] }
  }
}
```

`preserve` 的取值闭包为 `{present, absent-by-runtime}`：`present` 表示该 Runtime 的结果结构确实承载该字段、Adapter 必须原样保留（丢失即不得裁剪，§4.2）；`absent-by-runtime` 表示该 Runtime **不存在**该字段（不是被丢弃），必须附证据链接（`V-1`/`V-3`），且该路径的 `coverage` 不得因此降级——否则 Pi/Claude 等路径会被形式上判死（需求评审 S-2 的延伸风险，本 SDD 显式裁决，见 §9 `follow_up`）。

### 2.2.3 `conformance.json`（跨 Adapter 共享测试向量）

```jsonc
{
  "schema": "output-guard/conformance/v1",
  "vectors": [
    { "id": "esc-01", "kind": "escape-hatch", "input": { … }, "expect": { "action": "passthrough" } },
    { "id": "dec-01", "kind": "decision",     "input": { … }, "expect": { "action": "truncate", "complete": false } },
    { "id": "deg-01", "kind": "degradation",  "input": { … }, "expect": { "code": "OUTPUT_GUARD_UNAVAILABLE" } },
    { "id": "idem-01","kind": "idempotence",  "input": { … }, "expect": { "secondRunEqualsFirst": true } }
  ],
  "declaredVectorCount": 0        // 自棘轮：由 conformance.test.mjs 断言"实际执行向量数 == 声明值"
}
```

`declaredVectorCount` 是本 CR 内**唯一**用于新增测试面的计数棘轮（不新增账本、不写 `gate-registry.json` 之外的登记面）。四个 `kind` 与 AC-4 / AC-6 / AC-8 / AC-3 一一对应。

### 2.2.4 trailer 与启动记录（唯一可观测面）

```text
裁剪：  [output-guard action=truncate complete=false original≈12k kept≈4k reason=output-cap]
不可保持：[output-guard action=unavailable complete=true coverage=unavailable path=<runtime>/<tool>]
启动：  output-guard runtime=pi coverage=full policy=v1
```

trailer 是**结果正文的追加行**（不新增文件、不新增 JSONL/sidecar/DB）；启动记录写到各 Runtime 既有的启动/stderr 面，由安装期检查或会话启动 hook 产生。字段闭包固定为 `action` / `complete` / `original≈` / `kept≈` / `reason=` / `coverage=` / `path=`，不新增字段名。

## 2.3 术语与既有结构的只读引用

- 状态机、门禁、审批、账本 schema 的术语与结构一律**只读沿用** `dep-3` / `dep-8` / `dep-1` 的既有表述，本 SDD 不复刻其内容（避免第二份事实源）。
- 本 CR 新引入的术语只有 §1.4.6 表中七个，全部给出唯一裁决。

## 2.4 声明 vs 核实：`capabilities.json` 的填写纪律

`capabilities.json` 的每个 `level` 都是**声明**，其真实性由 `conformance.json` 的 full 向量逐 Adapter 验证（AC-4）。因此：

1. **落笔前核实**（AGENTS.md 纪律 4）：TASK-04～TASK-07 在填 `level` 前必须先按 `V-4`～`V-7` 的核实命令读一次目标 Runtime 的真实 hook 文档；文档不支持结果回填的，直接填 `partial`/`unavailable`，不得先填 `full` 再"实现期再说"。
2. **降级即 AC-4 未达成**：任一 Runtime 由 full 降为 partial/unavailable，即视为 AC-4 未达成，必须回到人工确认（scope amendment）后重定 AC-4；**不得**把降级静默吸收为通过（关闭需求评审 S-3，SDD-CLOSE-05）。
3. 非 full 路径必须在 `paths[]` 里逐条列出 `uncovered: true`，且 FR-8 报告里该 Runtime 只报覆盖度与裁剪量、不参与 Pi 的成本外推（FR-8 第 4 项）。

## 2.5 状态与门禁（零变化）

`dep-8` 的 `tech-design-review-pending` 门禁判据（`fileExists change-requests/{cr}/sdd.md`）与 `approvalStages.tech-design` 的 passCondition 引用均不改动；本 CR 的 diff 不触及 `dep-9`（pipeline 节点数保持 5/4/12）与 `dep-8`。

## 2.6 数据库 schema / 写路径鉴权完整性：N/A

理由：本 CR 不新增/修改任何数据库表、迁移、DDL 或写路径鉴权（三仓交付面无 DB 面；`../multica` 的改动只写每任务 env 内的 Runtime 配置文件，不写数据库、不新增鉴权面）。因此 `write-tech-design` Step 2 的"数据/schema 变更与写路径鉴权完整性"条件未触发，本节记 `N/A`。

---

# 3. 接口契约

契约分四类：crctl CLI 面（3.1）、OutputGuard 模块与 hook 面（3.2～3.4）、只读与「不复刻」边界（3.5）、FR-8 脚本 CLI 面（3.6）。**HTTP / REST / IPC / 事件契约在本 CR 全部不适用**（3.7）。

## 3.1 `crctl <命令> [--detail]`（FR-2）

| 项 | 契约 |
|---|---|
| 形态 | `--detail` 是**布尔型**开关：出现即为真，**不消费后随 token**（`parseArgs` 对它走专用分支，避免 `crctl status --detail CR-2026-069` 被解析成 `flags.detail='CR-2026-069'` 并吃掉位置参数） |
| 默认面 | 命令在 `SUMMARY_PROJECTORS` 注册表内 → 成功出口输出 compact summary JSON；不在表内 → 与改造前逐字相同 |
| `--detail` 面 | 无论命令是否被投影，均输出改造前的完整字段集（等价性合同见 §4.6） |
| 未投影命令 + `--detail` | 语法接受、无投影函数 → 等价于现状（裁决见 §1.4.6；关闭需求评审 S-1） |
| 退出码 | 不变：成功 0；错误非 0（`fail()` 路径完全未改） |
| 错误面 | 不变：`dep-6` 的 247 个 `fail()` 出口零改动，不进投影 |
| 权限分支 | **无**：`--detail` 不参与任何状态判定、门禁、审批或 CAS 判定 |
| 幂等 | 同一命令在同一仓库状态下重复调用，`--detail` 输出恒等（纯呈现层，无时钟/随机源注入） |
| 平行开关 | 禁止新增：不新增 `--output json` / `--verbose` / `--pretty`（`dep-6` 对这四个 flag 全仓零命中） |

## 3.2 OutputGuard Core 模块接口（`output-guard/core.mjs`，ESM，零第三方依赖）

```ts
// 纯函数面（无 fs / 无时钟 / 无随机 / 无环境读取；Node 内建只在 Adapter 侧使用）
export function parsePolicy(text): Policy          // 解析失败抛 PolicyParseError，调用方转 POLICY_INVALID
export function normalizeText(s): string           // \r\n → \n（唯一规范化入口，I9）
export function parseCall(input: CallInput, policy): CallDecision
   // → { action:'block'|'rewrite'|'passthrough', ruleId, rewrittenInput?, hint?, reason? }
export function classifyFamily(cmdline, policy): FamilyDecision
   // → { family, determinate, limits }；不做 shell 解析：管道/重定向/脚本嵌套 → determinate=false
export function parseEscapeHatch(firstLine, policy): EscapeDecision
   // → { state:'valid', reason } | { state:'absent' }；不合法一律 absent（§4.1）
export function evaluateResult(input: ResultInput, policy): ResultDecision
   // → { action:'truncate'|'passthrough'|'unavailable', body, trailer, keptTokens, droppedTokens, ruleId }
export function fingerprint(input): string         // sha256 hex（§4.4）
export function renderTrailer(decision): string    // 字段闭包见 §2.2.4
```

**类型（结构化契约；实施时以 JSDoc 承载，不引入 TS 构建）**：

```ts
type CallInput   = { runtime, toolName, toolInput }
type ResultInput = { runtime, toolName, toolCallId, isError, exitCode?, body,
                     structure: 'text' | 'content-parts' }
type Policy      = { policyVersion, families[], thresholds{}, truncation{}, hints{}, escapeHatch{} }
```

三条实现约束（AC-3 的机械判据）：

1. `core.mjs` 内**不得出现任何阈值字面量**（数值只能来自入参 `policy`）；
2. 同一 `(policyVersion, ruleId, toolName, normalizedInput, normalizedBody)` 必须产生同一 `body` 与同一 `trailer`（合同测试逐字断言）；
3. Core 不读文件、不读环境变量、不调用子进程——policy 的读取是 Adapter 的职责。

## 3.3 Runtime hook 契约（五个 Adapter 的输入/输出映射）

统一形态：Adapter 从 stdin（Pi 为扩展事件回调）取 Runtime payload → 映射为 Core 输入 → 输出 Runtime 约定的 hook 结果；**Adapter 内不含阈值判断与裁剪算法**（I2）。五个 Adapter 都只通过**相对说明符** import 同一 Release 的 `core.mjs` 与读取同一 Release 的 `policy.json`（Pi 的 `.ts` 入口同理，不引入任何构建步骤或依赖）。

| Runtime | Pre 面 | Post 面 | 结果回填形态 | Adapter 文件 |
|---|---|---|---|---|
| Pi | `tool_call`（可阻断；`event.input` 可原地改写） | `tool_result`（可修改，返回 patch） | 返回 `{ content, details?, isError? }` 局部 patch（省略字段保持原值） | `output-guard/adapters/pi/index.ts` |
| Claude Code | `PreToolUse` | `PostToolUse` | `hookSpecificOutput.updatedToolOutput` | `adapters/claude/{pre,post}tooluse-guard.mjs` |
| CodeBuddy | `PreToolUse` | `PostToolUse` | `hookSpecificOutput.updatedToolOutput` | `adapters/codebuddy/…` |
| Qoder | `PreToolUse` | `PostToolUse` | 同 Claude（同一 hook 协议族，复用同一映射实现） | `adapters/qoder/…` |
| Codex | `PreToolUse`（managed） | `PostToolUse` block/feedback 路径 | 非透明替换；uncovered 路径逐条声明 | `adapters/codex/…` |

**Adapter 的 fail-open 契约（§4.5 的具体化）**：任一 Adapter 在「payload 不可解析 / policy 不可读或不可解析 / 结果结构不可安全保持 / 内部异常」四种情况下，**必须输出"无决策"**（不写任何替换字段、不禁用调用），并以非零退出码之外的方式在 stderr 打一行 `OUTPUT_GUARD_UNAVAILABLE runtime=<r> reason=<枚举>`；**不得**输出会误伤调用的 deny/block 决策。五种 Runtime 的 payload 字段名与输出协议以各自模板与 README 为落点，SDD 不复刻（I2）。

## 3.4 安装 / 挂载契约（目录归属与唯一写入点）

`dep-1` §1.5 第 8 条留给 SDD 的两项裁决（SDD-CLOSE-01）：

1. **目录归属**：OutputGuard 的 Adapter 一律落在 `output-guard/adapters/**`，**不进入** `skills/shared/crctl/adapters/**`；`policy.json` 不被复制到任何其它目录；两套适配器的配置文件不得合并成一份事实源。
2. **安装入口是否共用**：**不共用**。`dep-10`（Claude）/ `dep-11`（Qoder）/ `dep-12`（Codex）的既有模板治理"裸 git / 受控路径写入 / SessionStart 注入"，其安装动作是"把 hooks 段合并进目标 Runtime 的 settings"；OutputGuard 沿用**同一安装形态**（模板 + 安装时物化 `{TOOLS_ROOT}` 绝对路径），但模板文件各自独立，互不嵌套引用。
3. **唯一联合点**：Managed scope（Multica 每任务 env）下，daemon 把两套 hooks 写进**同一个** Runtime 配置对象（§4.9），写入点唯一，避免两个写者对同一文件互相 clobber。

## 3.5 只读契约与「不复刻」边界

- 度量脚本对三仓与 session 目录**只读**；唯一写面是调用方显式指定的 `--out` 路径（`cr-cost.mjs` 的 `--out`，以及 TASK-01 把同一 JSON 复制进 KB CR evidence 目录的一次人工动作）。
- README / SKILL / 模板不得复刻 `policy.json` 的阈值、`capabilities.json` 的能力矩阵或 hook 细节，只能引用路径（AC-13）。**判据**：任一文档中出现 `thresholds` 的数值字面量或完整 `runtimes` 能力表 → fail。

## 3.6 FR-8 脚本 CLI 契约（`skills/shared/metrics/scripts/cr-cost.mjs`）

| 子命令 | 契约 |
|---|---|
| `baseline --out <path> [--sessions-root <dir>]... [--window <from>..<to>]` | 改造前唯一一次执行：产出唯一机器 JSON（字段集 ≡ `dep-1` FR-8 第 3 项 / `dep-2` §5.4）+ 对历史 session 离线回放 policy（纯函数重算）；stdout 打印同一对象渲染的人读摘要 |
| `after --out <path> --window 14d` | 部署后唯一一次执行：只统计 `coverage=full` 且带 CR-ID 的完整 Pi CR；样本不足 → `insufficient-sample`（不产出成本结论、不延长本 CR） |
| `replay --policy <path>` | 单独的历史回放（供抽检误伤使用），输出回放统计，不产出成本结论 |
| `verify-selection --baseline <path>` | AC-10 的机械核对入口：从 baseline 的 crctl 命令聚合重算最小集合，与 `SUMMARY_PROJECTORS` 注册表逐项比对，不一致即非零退出 |

**输出纪律（AC-17 / AC-18）**：① 机器结果只有一份 JSON，字段集固定，人读摘要由同一对象渲染（不写第二份产物文件）；② 每个计数字段必须携带 `observedAt`（ISO 时间）与 `rule`（可复现的筛选命令/口径），不合规即视为实现缺陷（同时关闭需求评审 S-4 的计数口径类风险）；③ 代码与门禁中不出现样本常量的硬编码（含 672 等值）；④ `k` 必须同时给出 `costSource`（取值闭包 `pi-session-usage` / `external-invoice` / `unavailable`）与 `tokenEstimator`（分母的估算口径标识）；`costSource=unavailable` 时 `k=null` 且输出中不出现任何金额宣称。

## 3.7 HTTP / REST / IPC / 事件契约：N/A

理由：本 CR 不新增或修改任何 HTTP endpoint、请求/响应结构、IPC 协议或事件总线契约（`dep-1` §1.3.3 的适用面判定）。OutputGuard 的 hook 面是 Runtime 进程内的本地调用（stdin/stdout 或扩展回调），不是网络契约；`crctl --detail` 是 CLI 呈现层，不是 endpoint。

## 3.8 错误语义：唯一新增降级码

```text
OUTPUT_GUARD_UNAVAILABLE runtime=<runtime> reason=<ADAPTER_MISSING|DISABLED|BUNDLE_INVALID|POLICY_INVALID>
```

- `reason` 为**四值闭包**，不新增第五值；
- 该码不进入 crctl 的错误码面（不影响 `dep-6` 的 `fail()` 出口语义）；
- 该码的唯一可见面是 Adapter stderr 一行 + 安装期检查输出；不写文件、不写账本、不写 JSONL/sidecar（错误路径零文件写入、零状态变更、无补偿事务）；
- `dep-7` 与 crctl 的 fail-closed 行为不受影响（§7.2）。

---

# 4. 关键算法与流程

九个算法块，逐块给出输入、步骤、终态与判据锚点。全部实现为纯函数或纯映射，不含时钟/随机/网络。

## 4.1 A1 — 逃生阀解析（FR-1 第 7 项②，SDD-CLOSE-04）

```text
输入：命令文本 commandText（含换行）
步骤：
  1. cmd ← normalizeText(commandText)                       // I9，先归一
  2. firstLine ← cmd.split('\n')[0]
  3. 若不是 shell 命令族（如 Pi 的 read 工具）→ absent       // 逃生阀只存在于 shell 首行
  4. m ← /^#\s*output-guard:\s*full\s+reason=(?<r>.*)$/.exec(firstLine)
     - 未命中 → absent
     - 命中但 r 为空 / 含换行 / r.length > policy.escapeHatch.reasonMaxLength
       → absent（**不合法一律视为不存在**，见下）
     - 否则 → valid(reason)
终态：{valid|absent}；无第三态、无错误码、不新增 action 取值
```

**不合法标记的处置**（`dep-1` §1.5 第 5 条）：视为不存在 → 该调用按普通路径参与判定；**不拒绝工具调用本身**；若随后被裁剪，仍按 §4.3 输出 `action=truncate` 的 trailer（模型因此可见"本次未获得完整结果"）。不新增第二套错误码、不引入授权文件（保持无状态）。

**逃生阀的边界**：`valid` 只让该次调用跳过 OutputGuard 的封顶（`action=passthrough`），**不参与** `dep-7` 的 git 白名单 / protected paths / 审批 / 账本写入控制的判定，也无法影响它们（四类各一条负向测试，AC-6）。

## 4.2 A2 — 决策顺序与终态裁决（FR-1 第 7 项）

固定顺序，每一步 **命中即终态**，无并列、无回溯：

```text
① Runtime 权限与既有安全控制   → 由 Runtime 自己裁决，OutputGuard 不评估、不放宽（在 Core 之外）
② parseEscapeHatch(firstLine)  → valid ⇒ action=passthrough（跳过封顶；仍受 ①）
③ classifyFamily(cmdline)      → determinate ∧ 命中规则 ⇒ action=block | action=rewrite(限流)
                                   !determinate ⇒ 放行，但对结果施加统一封顶
④ evaluateResult(body, policy) → 可保持 ∧ 超阈值 ⇒ action=truncate（complete=false + trailer）
                                  不可保持 ⇒ action=unavailable（不改结果 + coverage 标记）
⑤ 以上均未命中 ⇒ 不追加任何文本
```

**可保持性检查（步骤④的门）**——这是 I4 的机械落点，也是 AC-15 的唯一判据：

```text
输入：Runtime 的原始结果对象 R + capabilities[runtime].preserve
检查（全部通过才允许裁剪）：
  a. R 的 toolName / toolCallId / isError 三字段在 Runtime 结果结构中存在且可原样回填
  b. capabilities[runtime].preserve.exitCode
       == "present"           → R 中必须存在该字段且可原样回填
       == "absent-by-runtime" → 不做要求（该 Runtime 无此字段，缺失不是丢失）
  c. 结果结构可承载替换：R 的正文形态 ∈ {text, content-parts} 且替换后结构键集不变
不通过 ⇒ action=unavailable（结果逐字不改；标 pathCoverage=unavailable；trailer 一行）
```

**`exitCode` 的口径**（本 SDD 的显式裁决，`dep-1` FR-1 第 5 项的逐字对照见 §9 `follow_up`）：`dep-1` 要求"必须保留 … `exitCode` 与 Runtime 要求的结果结构"，其可执行含义是**"Runtime 结果结构中存在的字段不得丢失"**；对**结构上不存在**该字段的 Runtime（Pi 的 bash/read 工具结果只提供 `isError` 与状态文本，`V-1`/`V-3` 核实），`exitCode` 记 `absent-by-runtime`，**不因此降级该路径、也不触发 `unavailable`**。理由：若按"字段必须存在"的字面读法，Pi 与 Qoder 的首期主力路径会被形式上判死，与 FR-1 第 11 项"Pi 首个启用"直接冲突；两种读法不可同时成立，SDD 取值前者，并在 §9 `follow_up` 留下"若评审要求字面读法，需回到需求侧收窄该条"的显式出口。

**幂等与"跨调用零状态"**：决策不写入任何跨调用状态（无授权文件、无 nonce、无永久开关、无"下一次调用"记忆）；`action=passthrough` 不在会话中留下可被后续调用读取的痕迹。

## 4.3 A3 — 三类确定性裁剪（FR-1 第 4 项）

| 结果类型 | 算法 | 不变量 |
|---|---|---|
| 搜索（`grep`/`rg`） | 保留唯一文件列表 + 总命中数 + 可执行的缩小范围写法；同文件多命中折叠为一行的退出提示 | 命中数必须来自原始正文的机械统计，不得估算 |
| 列举（`find`/`Get-ChildItem`） | 保留唯一路径列表（去重、稳定排序）+ 总条目数 + 缩小范围写法 | 排序键固定（字典序），保证逐字可复现 |
| 读取（`cat`/`Get-Content` 与 Pi 的 read 工具） | 保留**连续行窗口** + 原始行号 + 下一次 `offset/limit` 的具体值 | 行号必须是原始文件行号（不得重编号）；窗口必须连续（不得拼接不相邻片段） |
| 普通 shell | 保留头部 N 行 + 尾部 M 行 + 中间省略量 | `N`/`M` 来自 `policy.json`，代码内零常量 |

所有文本处理先 `normalizeText`（I9：`\r\n → \n` 后再切行，`split('\n')`）；正文按 UTF-8 字节/字符边界切断时必须回退到整行边界（不得切断多字节字符）。裁剪结果**只保留正文**：被丢弃部分立即丢弃，不进 `details`、不写盘、不进任何日志（AC-7）。

## 4.4 A4 — 决策指纹与幂等证明（FR-1 第 6 项）

```text
fingerprint = sha256(
  policyVersion ‖ '\u0000' ‖ ruleId ‖ '\u0000' ‖ runtime ‖ '\u0000' ‖ toolName ‖ '\u0000'
  ‖ canonicalJson(normalizedInput)   // 键升序、EOL 归一、去除易变字段（时间戳/绝对路径前缀）
  ‖ '\u0000' ‖ normalizeText(body)
)
```

证明义务（合同测试）：同一 fingerprint 连续求值两次，`body` 与 `trailer` **逐字相等**（`conformance.json` 的 `idem-01` 向量）；跨 policyVersion 不做兼容承诺（`policyVersion` 只是格式版本）。

## 4.5 A5 — 降级与错误闭包（FR-1 第 8 项）

四种命中条件与唯一的降级码：

| 条件 | 触发面 | 结果 |
|---|---|---|
| Adapter 未被 Runtime 加载 / 无 Adapter | 安装期检查 + 运行期缺失 | fail-open，`reason=ADAPTER_MISSING` |
| Adapter 被显式禁用（安装配置移除即禁用；无远程开关） | 安装期检查 | fail-open，`reason=DISABLED` |
| bundle 损坏（文件缺失/哈希不符/接口版本不符） | Adapter 加载 | fail-open，`reason=BUNDLE_INVALID` |
| `policy.json` 不可读 / 不可解析 / `policyVersion` 不支持 | Adapter 加载 | fail-open，`reason=POLICY_INVALID` |

任一时：**原工具调用继续、结果不修改**；FR-8 侧该会话标 `coverage=unavailable` 并排除出完整覆盖样本；不静默假装生效；不让 Agent 退化为 Prompt 自觉；不影响 crctl / Git / 账本 / 审批的 fail-closed；错误路径零文件写入、零状态变更、无补偿事务。

## 4.6 A6 — FR-2 投影与等价性合同（SDD-CLOSE-02）

**投影入口（唯一改造点）**：

```text
main()：
  ACTIVE_PROJECTION ← resolveProjection(cmd, flags)     // 见 §1.4.3 三分支
  switch (cmd) → cmdXxx()
ok(obj)：
  const out = ACTIVE_PROJECTION ? ACTIVE_PROJECTION(obj) : obj
  process.stdout.write(JSON.stringify(out, null, 2) + '\n')
```

- **不在全局 `ok()` 删字段**：`ok()` 只是"若该命令注册了投影函数则调用它"，未注册命令逐字走原路径（`dep-1` FR-2 第 1 项末句）。
- **投影函数是每命令独立的纯函数**：输入成功出口的对象，输出 compact summary 对象；不得读取全局状态、不得访问文件系统。
- **输出格式化不新增模式**：summary 仍为 2 空格缩进 JSON——FR-2 的杠杆是**字段投影**而非空白压缩；不引入 `--pretty`/minified 第二形态（决策 D-2）。

**等价性合同（`dep-1` §1.5 第 6 条的落地）**：合同测试按三层比对，禁止字节比对：

| 层 | 判据 | 失败即 |
|---|---|---|
| ① 字段集合 | `fieldPaths(--detail 输出)` ≡ 改造前金样本的 `fieldPaths` | blocker 级实现缺陷 |
| ② 稳定值 | 金样本中标记为 `stable` 的字段路径，其值逐字相等 | 同上 |
| ③ 易变字段形态 | 金样本中标记为 `volatile`（时间戳 / 提交 SHA / 绝对路径）的字段路径，其值类型与形态（ISO 8601 / 40 hex / 绝对路径）匹配 | 同上 |

金样本（`skills/shared/crctl/scripts/test/golden/crctl-detail/*.json`）**必须在实现投影前**由未改造的 CLI 在既有 fixture 工作区上采集（TASK-08 第 1 步），随 CR 提交；采集脚本与 fixture 复用既有测试夹具（消费式引用 `dep-13`/`dep-14` 已在仓的夹具构造方式，不改其语义）。

**命令集合的选择（AC-10）**：见 A8。**调用方同步（AC-21①）**：见 A10。

## 4.7 A7 — FR-8 聚合与 `k`（FR-8 第 2～5 项）

```text
样本筛选（可复现，随输出）：
  roots  = [<multica pi-sessions 根>, <pi agent sessions 根>]（可 --sessions-root 覆盖）
  type   = *.jsonl；window = [from, to)
  crId   = 会话内出现 CR-<YYYY>-<NNN> 形式的标识（正则固定，随输出）
每会话聚合（只读）：
  toolResults = 每条 role=toolResult 的正文 token 估计（tokenEstimator 标识 + 原始字节/字符数）
  usage       = assistant 消息 usage 的 input / cachedInput(=cacheRead) / cacheWrite / output 四维
  buckets     = 按工具族归类（搜索 / 列举 / 打印 / crctl 命令输出 / 其它）
派生指标：tokensPerCR / sessionsPerCR / searchTokenRatio / fullReadRatio / bootstrapTokensPerSession
护栏指标：firstPassGateRate / reviewLoopsPerCR / reviewDefectsPerCR
k：分子 = costSource 对应的计费金额；分母 = 同区间工具结果 token（同 estimator）；不可得 ⇒ k=null
```

**关键口径与诚实性规则**：

1. `tokenEstimator` 必须显式写出（零第三方依赖的约束下不引入 BPE tokenizer；比值型结论不依赖 estimator 的绝对精度，但**金额型结论必须同时标注 estimator 与 costSource**）。
2. `cachedInput` 映射为既有 usage 的 `cacheRead`（`dep-1` FR-8 第 2 项用 `cachedInput|cacheRead` 双名，SDD 取 `dep-1` 的写法并在输出里保留原始键名）。
3. 护栏三项来自既有 Pipeline 与评审数据（门禁一次通过、`review-loop` 轮次、评审发现缺陷数），全部只读复用，不新增采集面。
4. `insufficient-sample` 是**终态之一**：样本不足即输出该状态并停止，不输出部分成本结论、不延长本 CR。

## 4.8 A8 — summary 命令集的选择算法（AC-10 的可机械核对面）

```text
输入：baseline JSON 的 crctlCommands[] = [{ command, tokens, calls }]
1. 按 tokens 降序；tokens 相等按 command 字典序（确定性 tie-break）
2. 贪心取前缀，直到累计份额 ≥ 80%
3. 输出 = 该前缀的命令集合（份额全为正 ⇒ 该前缀即"达到阈值的**最小基数**集合"；交换论证：任何更小的集合必然漏掉某个更大份额项，累计份额更低）
```

三条硬约束：

1. `SUMMARY_PROJECTORS` 的键集合必须**等于**该算法输出（`verify-selection` 子命令逐项比对，不一致即非零退出）；
2. 该命令集合与算法均**不写入 PRD/Prompt/Skill/门禁**，只活在 `summary-projectors.mjs` 与 baseline evidence 中；
3. 基线之前不得预设集合（TASK-08 的输入是 TASK-01 的输出，顺序不可颠倒）。

## 4.9 A9 — Managed 挂载的合成算法（TASK-09，`../multica`）

```text
输入：envRoot、workDir、provider、既有 dep-4 的 per-task 环境锻造流程
1. 读本地安装配置（一个显式环境变量指向 Tools Release 根；未配置 ⇒ 本次挂载整体跳过，既有行为逐字不变）
2. 解析 output-guard/adapters/<provider>/ 下的 hook 入口绝对路径与 policy 读取面
   （**只写路径引用，不复制 policy、不复制 Adapter 正文**）
3. 与该 provider 既有的 crctl 守卫 hooks **在同一个配置对象内合成**：
   - 同一 JSON 写入一次（单一写者）；hooks 数组按"既有段在前、OutputGuard 段在后"追加
   - 已存在的用户配置文件 **不 clobber**（沿用既有"存在即跳过并告警"的行为）
4. provider 无 hook 支撑（Pi / Codex）⇒ 不写文件、不猜路径，只在报告里给出该 Runtime 的安装指引
```

**边界（`dep-1` §1.3.2 的 multica 行 + AC-12）**：只做挂载与写出配置；不碰 `dep-15` 的责任边界以外的语义、不放开 `dep-16` 的 argv 白名单面、不改 `dep-17`（preview/transcript 层）、不新增远程开关、不新增安装框架、不在 CR 过程中安装任何东西（安装是部署动作）。Pi 的挂载不走 argv 注入，改由宿主级配置面安装一次（§1.4.2 的 Managed 行）。

## 4.10 A10 — 调用方同步扫描（AC-21① 的可机械核对面）

```text
扫描面：skills/**/SKILL.md、pipeline-templates/*.pipeline.json、agents/*.md、skills/**/*.mjs、README.md
提取：`crctl <子命令> [<子子命令>] [args]` 字面量（含 `node …/crctl.mjs …` 形态）
判定（逐条，写入测试内的显式表）：
  a. 子命令 ∉ 投影集合            → 无需动作（输出未变）
  b. 子命令 ∈ 投影集合 ∧ 该处消费的字段 ⊆ summary 字段集 → 无需动作
  c. 子命令 ∈ 投影集合 ∧ 该处需要 summary 之外的字段        → **必须显式补 `--detail`**
检查：caller-contract.test.mjs 断言扫描面内每一处 (b) 类调用与显式表一致、(c) 类调用都带 `--detail`；
     新增/改动调用点若与表不符即红（表是人工审过的白名单，断言是机械的）
```

`summary` 的字段集**按"调用方充分性"设计**：先在 A10 的表里枚举每个被投影命令的既有消费字段，再据此定义 summary 必须保留的字段；只有确实无法进入 summary 的字段才用 `--detail` 兜住。这样 `--detail` 是"显式例外"，而不是"大面积补丁"。

---

# 5. 技术选型与替代方案

只记录同时满足三判据（难以逆转 + 无上下文会疑惑 + 有真实权衡替代）的决策；不伪造替代方案，不新增 ADR 文件或审批节点。

## D-1 seam 位置：Runtime 工具结果回填 hook（选定） vs daemon preview 层

- **Context**：`dep-1` §1.1 的第 1 条根因结论（治理点位置错）与 S11 的 seam 定义。
- **选定**：Adapter 挂在 Runtime 的 Pre/Post hook 上，在结果进入下一轮模型上下文之前裁剪。
- **替代**：在 `dep-17`（daemon 的 preview/transcript 层）做截断。
- **否决理由**：该层在模型上下文之后，降不了 token；且该文件被 `dep-1` 钉为**零 diff**（AC-12）。
- **不可逆性**：Adapter 的位置决定 policy 的读取面与安装模型，改位置等于重做发布/安装契约。

## D-2 summary 的输出形态：保持 2 空格缩进 JSON（选定） vs 单行/minified

- **Context**：FR-2 的默认面从"全量缩进 JSON"变成"compact summary JSON"；`dep-6` 的成功输出面只有一个 `ok()`。
- **选定**：summary 仍是 2 空格缩进的合法 JSON，只是字段被投影。
- **替代**：单行 minified JSON（更省 token）。
- **理由**：FR-2 的杠杆是字段投影而非空白；Skill/Agent 阅读 compact summary 的可读性直接决定后续动作质量；新增第二种格式化形态会与"不新增 `--pretty`/平行开关"的边界冲突，并让日志与 diff 排查退化。
- **不可逆性**：默认面是调用方契约，改形态等于二次破坏性变更。

## D-3 分发形态：模板 + 安装时物化绝对路径（选定） vs plugin 打包（SDD-CLOSE-06）

- **Context**：`dep-1` §1.5 第 9 条（tools 仓当前无 plugin 载体，是否引入交 SDD）。
- **选定**：沿用 `dep-10`～`dep-12` 的既有形态——提供各 Runtime 的配置模板 + 安装说明 + 启动检查，`{TOOLS_ROOT}` 在安装时物化为绝对路径。
- **替代**：引入 `.claude-plugin/plugin.json` 等 plugin 清单元数据 + 安装/升级框架。
- **否决理由**：仓内无既有载体；引入即需要新的安装入口、版本同步与信任语义，触碰"不新建安装框架 / 不建远程开关"的硬边界；且 `dep-1` 只钉"显式安装一次、三级 scope、启动只检查不修复、不得复制 policy"四项合同。
- **残留**：`dep-2` §6.10 的"Tools Plugin 携带 Skills 与 hooks"一句话在本 CR 不落地；本 SDD 不改写该句，只在 §9 `follow_up` 记录差异。

## D-4 逃生阀的识别面：shell 命令族首行注释（选定） vs 任意文本扫描

- **Context**：`dep-1` FR-1 第 2/7 项（不实现完整 parser）与 `dep-2` §6.6 的统一首行注释形态。
- **选定**：只在"命令族被识别为 shell 调用"时解析首行，且只解析首行。
- **替代**：在整段命令文本里搜索标记（含管道/重定向/脚本内部）。
- **否决理由**：会触发"必须解析任意嵌套"的不可判定面，与"不实现完整 Bash/PowerShell parser"直接冲突；且会把"注释"与"可执行语句"混淆。

## D-5 `unavailable` 也输出一行 trailer（选定） vs 完全静默

- **Context**：`dep-2` §6.7 字面只规定"发生拒绝或裁剪时"追加 trailer；而 FR-1 第 5/7 项的路径级 `unavailable` 与 NFR-6 的"降级显式"都要求该事实可见。
- **选定**：`action=unavailable` 追加一行 `[output-guard action=unavailable complete=true coverage=unavailable path=…]`。
- **替代**：不追加任何文本，只靠安装期检查记录。
- **理由**：`action=unavailable` 不是"未命中任何规则"（`dep-2` §6.7 的"正常未触发调用不增加文本"针对后者）；若完全静默，则"护栏在跑但拒绝裁剪"与"护栏根本没跑"在会话里不可区分，NFR-6 的"不静默假装生效"不能成立，FR-8 也无法把该会话排除出完整覆盖样本。
- **边界**：这是对 §6.7 的一次**紧读边界裁决**，随本 SDD 一并进入人工审批过目（§9 `follow_up` 保留了改为静默的退路）。

## D-6 `exitCode` 的语义：Runtime 结构存在才要求保留（选定） vs 字面要求必存在

见 §4.2 末段。选定前者；替代（字面读法）会让 Pi 判死，与 FR-1 第 11 项"Pi 首个启用"冲突。此裁决同样进入人工审批过目。

## D-7 Managed scope 的挂载方式：daemon 单写入点合成（选定） vs 纯手工安装

- **Context**：Multica 平台在每任务 env 内**已经**为 claude 写项目级 Runtime 配置（`dep-4`）；纯手工安装会与该写入点竞争同一文件。
- **选定**：在该写入点内合成（单写者、单次写），并把 OutputGuard 段落置于既有 hooks 之后。
- **替代**：要求运维在用户级/项目级各装一次，daemon 不参与。
- **否决理由**：AC-14 要求在真实 Multica 任务里冒烟，而项目级写入点会覆盖/竞争用户级配置，纯手工安装下"是否真的生效"不可判定（等于把降级风险藏进部署过程）。
- **代价**：`../multica` 产生一处小改动（`dep-4` 文件 + 新文件），需按其 `dep-18` 登记定制。

## D-8 FR-8 的 token 估计：带标识的自研 estimator（选定） vs 引入 BPE tokenizer

- **Context**：`dep-2` §4 的口径用 o200k 编码；而 tools 包无依赖机制（`dep-3` §5 不变量 3 的零依赖口径）。
- **选定**：不引入第三方 tokenizer；输出显式 `tokenEstimator` 标识 + 原始字节/字符数（保证任何口径都能重算）；比值型结论（≥20% 下降）不依赖绝对精度；金额型结论必须同时标注 estimator 与 costSource。
- **替代**：引入 `o200k` BPE 依赖或自带词表 → 否决：破坏零依赖口径、引入随版本漂移的第三方资产。

## D-9 FR-2 投影入口：`main()` 内设定模块级 `ACTIVE_PROJECTION`（选定） vs 改 45 个 `ok()` 调用点

- **Context**：`dep-6` 的成功出口是单一 `ok(obj)`，共 45 个调用点，其中含 async 链（approve 系列）。
- **选定**：在 `main()` 里按 `(cmd, flags)` 一次性解析出投影函数挂到模块级变量，`ok()` 消费它；未注册即 null。
- **替代**：`ok(obj, cmd)` 显式传参（45 处改动）。
- **理由**：投影与命令名的绑定只有一个权威点（dispatch 入口），传参会把同一映射散布到 45 处、易漏且易漂移；`ACTIVE_PROJECTION` 的作用域严格限于一次进程内的单次命令执行（CLI 一次性进程），无并发写者。
- **代价**：模块级可变状态需要一条测试断言"未注册命令 + 未传 `--detail` 时输出与改造前逐字相同"（见 §6.4 的回归面）。

---

# 6. FR 到技术实现映射

## 6.1 FR 逐条映射

| FR | 技术方案落点 | 承载 TASK | 判据锚点 |
|---|---|---|---|
| FR-8 第 1 项（位置与执行次数） | `skills/shared/metrics/scripts/cr-cost.mjs` 的 `baseline` / `after` 两个子命令；不进 Pipeline/Skill/定时任务；机器 JSON 落 `--out` 与 KB `change-requests/CR-2026-069/evidence/` | TASK-01 / TASK-10 | §3.6、AC-17①④ |
| FR-8 第 2 项（输入只读复用） | `lib/sessions.mjs` 只读遍历（`V-2` 的 JSONL 形状）+ 既有 review/门禁数据只读读取 | TASK-01 | §4.7、AC-17② |
| FR-8 第 3 项（输出字段集） | `lib/aggregate.mjs` 产出固定字段集；`lib/render.mjs` 从同一对象渲染人读摘要（stdout，不写第二份文件） | TASK-01 | §2.2.1～§3.6、AC-17② |
| FR-8 第 4 项（`k` 与金额口径） | `lib/aggregate.mjs` 的 `k` 计算 + `costSource` / `tokenEstimator` 标注；非 Pi Runtime 只报覆盖度与裁剪量 | TASK-01 | §4.7、AC-18 |
| FR-8 第 5 项（窗口与扩项门槛） | `after --window 14d`；`insufficient-sample` 作为可测终态；三项护栏与 ≥20% 判定为脚本内纯函数 | TASK-10 | §4.7、AC-17⑤ |
| FR-8 第 6 项（可复现） | 筛选规则随输出（`rule` + `observedAt`）；比较只用归一化指标 | TASK-01 / TASK-10 | §3.6、AC-17②③ |
| FR-1 第 1 项（职责切分） | `core.mjs` 纯函数 + `policy.json` / `capabilities.json` / `conformance.json` 三份唯一源 + 五个 Adapter 只做映射 | TASK-02～TASK-07 | §3.2～§3.4、AC-3 |
| FR-1 第 2 项（首期命令族） | `policy.json#families` 三族五命令；`classifyFamily` 的不确定分支=放行但统一封顶 | TASK-02 | §4.2、§4.3、AC-5 |
| FR-1 第 3 项（阈值来源） | 阈值只在 `policy.json#thresholds`；由 TASK-01 产出后写入；代码/Prompt/Skill 零阈值 | TASK-01 → TASK-02 | §2.2.1、AC-3 |
| FR-1 第 4 项（裁剪策略） | `evaluateResult` 四类分支（搜索/列举/读取/普通 shell） | TASK-02 | §4.3、AC-5 |
| FR-1 第 5 项（门禁证据不变量） | 可保持性检查 + `complete=false` + trailer + 丢弃正文立即释放 | TASK-02 + 各 Adapter | §4.2、§4.3、AC-7 / AC-15 |
| FR-1 第 6 项（幂等） | `fingerprint` + 跨调用零状态 | TASK-02 | §4.4、AC-3 / AC-6 |
| FR-1 第 7 项（权限与顺序） | 五步固定顺序、五值终态闭包、逃生阀不影响安全层 | TASK-02 + 各 Adapter | §4.1、§4.2、AC-6 |
| FR-1 第 8 项（错误闭包） | `OUTPUT_GUARD_UNAVAILABLE` 四值 reason + fail-open 四场景 | TASK-02 + 各 Adapter | §3.8、§4.5、AC-8 |
| FR-1 第 9 项（副作用面） | 唯一可见副作用=正文 + 一行 trailer + 启动一行；无 JSONL/sidecar/DB | 全体 | §2.2.4、AC-7 |
| FR-1 第 10 项（发布与安装） | 同一 Release 相对路径读取；`check-install.mjs` 只报告不修复；三级 scope | TASK-02～TASK-09 | §1.4.2、§3.4、AC-19 |
| FR-1 第 11 项（启用顺序） | `capabilities.json#enableOrder` + 三前置证据链；不新增状态/节点 | TASK-03～TASK-09 | §1.4.5、AC-20 |
| FR-1 第 12 项（回滚粒度） | 单 Adapter=安装配置移除即禁用；Core/Policy=整体回退 Release；无远程开关 | TASK-03～TASK-09 | §7.3、AC-14 |
| FR-2 第 1 项（选择规则与 projector） | `summary-projectors.mjs` 独立投影器 + A8 选择算法；不在全局 `ok()` 删字段 | TASK-08 | §4.6、§4.8、AC-10 |
| FR-2 第 2 项（开关面收敛） | 只新增 `--detail`；不新增平行开关；调用方按 A10 补 `--detail` | TASK-08 | §3.1、§4.10、AC-21 |
| FR-2 第 3 项（幂等与无权限分支） | `--detail` 纯呈现层，无状态/门禁/审批/CAS 参与 | TASK-08 | §3.1、AC-11 |
| FR-2 第 4 项（错误闭包） | `fail()` 与错误体零改动 | TASK-08 | §3.1、§3.8、AC-11 |
| FR-2 第 5 项（不变量） | §4.6 三层等价性合同 + 既有测试全绿 + 新增合同测试 | TASK-08 | §4.6、AC-10 / AC-11 |
| FR-2 第 6 项（棘轮同步义务） | `manifest.files` + `manifest.cases` 同批更新；`exceptions` 保持空 | TASK-08 | §6.4、AC-21②③ |
| FR-2 第 7 项（不做） | 不优化运行时小文件读取、不建字段/错误码事实页（FR-9 候选） | — | §9 `scope_out` |

## 6.2 AC 逐项设计与验收映射

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-1 | §9 `zero_diff` 清单 + §6.4 零改动核对清单 | `crctl git diff --name-only <baseRef>..HEAD` 对清单内路径逐条为空；状态机/门禁/审批/账本/事务行为类文件零变化 | 本 CR 的改动面（`output-guard/**`、`skills/shared/metrics/**`、`crctl.mjs` 投影层、CI/README/ARCHITECTURE、multica `execenv` 两文件）与清单无交集，断言可机械执行 |
| AC-2 | §4.9/§6.4 + 新增代码的依赖纪律 | `dep-5` 的 lib 四文件零 diff；全 diff 无锁/journal/write-set/CAS/提交框架；无手写账本；passCondition/状态映射/reviewLoop 算法零复制 | 新增代码不写任何账本、不引入文件锁（度量脚本只写 `--out`，Adapter 只读 policy）；复制类漂移由既有 prompt 合同扫描 + 人工复核兜住 |
| AC-3 | §3.2 三条实现约束 + `policy.json` | 幂等向量逐字相等；`core.mjs` 内阈值字面量零命中；阈值第二副本零命中 | policy 由 Adapter 读入并以参数进 Core；thresholds 唯一出现在 `policy.json` |
| AC-4 | `capabilities.json` + `conformance.json` + 每 Adapter 的向量执行 | 测试输出能区分 full / partial / unavailable；Pi/Claude/CodeBuddy/Qoder 的 full 向量逐 Adapter 出结果；Codex 的 uncovered 路径逐条列示 | 若实测某 Runtime 不具备 full，按 §2.4 降级并触发 scope amendment（不静默吸收） |
| AC-5 | §4.3 + `policy.json#hints` | 每个命令族的替换结果含可执行替代写法：搜索/列举→唯一文件列表+命中数+缩小范围写法；读取→下一次 `offset/limit` 具体值 | 替代写法由 Core 从原始正文机械生成（不依赖模型、不依赖网络） |
| AC-6 | §4.1 + §3.3 | 逃生阀 valid/absent 两态向量；连续两次调用无跨调用状态；四条负向测试证明逃生阀不影响 git 白名单/受控路径/审批/账本写入 | OutputGuard 运行在 Runtime 权限与既有安全控制之后（① → ②），负向测试在 hook 层并列验证 |
| AC-7 | §4.3 末段 + `evaluateResult` 的正文替换 | sentinel 端到端用例：sentinel 不在模型可见 `tool_result`、不在 session 文件、不在 transcript、不在新增日志；无 sidecar/JSONL/DB 新增 | 裁剪只替换正文；`details` 不被写入丢弃正文；测试夹具把 payload 控制在 Runtime 自身截断阈值之下以隔离 `V-3` |
| AC-8 | §4.5 四场景 | 四场景各出 `OUTPUT_GUARD_UNAVAILABLE` 且 reason ∈ 四值；原调用继续、结果不改；无静默安装/修复（负向断言：不写任何文件） | 四场景可用可注入路径/损坏 bundle 在测试中复现（`BUNDLE_INVALID`/`POLICY_INVALID` 为纯函数可造） |
| AC-9 | §4.7 `replay` | `baseline.json` 含可复现筛选规则与实际样本数；离线回放完成；合法调用抽检清单与判定入证据 | 回放是纯函数重算，不执行命令、不依赖网络 |
| AC-10 | §4.6 + §4.8 | 默认输出=compact summary；`verify-selection` 断言注册表 ≡ 基线最小集合；`--detail` 与金样本三层等价 | TASK-01 先于 TASK-08；baseline evidence 随 CR 提交，核对命令可复跑 |
| AC-11 | §3.1 + §6.4 | 逐命令退出码不变；错误码与错误体不变（`fail()` 出口零 diff）；既有测试全绿（CI 双平台）；状态/门禁/审批/CAS/事务/Git 代码零改动 | `fail()` 与各 `cmdXxx` 的非成功分支完全未改；投影只在 `ok()` 内生效 |
| AC-12 | §9 `zero_diff` | `crctl git diff --name-only` 对 `dep-17` 路径为空 | multica 改动只落在 `dep-4`/新增 `outputguard_config.go`/`dep-18` |
| AC-13 | §3.5 判据 | README 仅增导航与权威入口链接；`thresholds` 数值与完整能力矩阵在 README/Skill 中零命中 | 检查脚本以"数值字面量 + 能力表关键词"为模式，纳入 CI |
| AC-14 | §1.4.2 + TASK-03～TASK-07 / TASK-09 | 每个已启用 Runtime 至少一次真实冒烟，覆盖拒绝/裁剪/逃生/损坏降级四类行为；记录作为交付证据 | 冒烟在 Multica 启动的真实任务环境执行；失败按 §2.4 记降级并触发 scope amendment |
| AC-15 | §4.2 可保持性检查 | sentinel 不在模型可见结果；`toolName`/`toolCallId`/`isError` 保留、`exitCode` 按其 Runtime 事实保留（`present` 必须保留 / `absent-by-runtime` 不作要求）；结果结构键集不变；任一 `present` 字段丢失即该路径不得裁剪并标 `unavailable` | 检查是 Core 的前置门，不通过的路径直接进入 `unavailable` 分支（不可能"裁了才发现"） |
| AC-16 | §2.2.4 trailer 指令 + §8 的 reviewer Skill 采纳 | 至少一条端到端用例：以 `complete=false` 结果提交门禁/审批判断时被要求继续切片取证或走逃生阀；trailer 指令文本为固定契约 | 无新门禁/新状态可用，拦截由"trailer 固定指令 + reviewer Skill 合同条款 + 端到端用例"三者共同承载；残余风险见 §7.4 |
| AC-17 | §3.6 + §4.7 | ① 执行次数恰为两次（evidence 目录两个 JSON）；② 字段集 ≡ `dep-1` FR-8 第 3 项（来源 §5.4）；③ 样本数由脚本输出、代码与门禁零硬编码常量；④ 报告以 KB evidence + Issue 附件存在、四账本零变化；⑤ 14 天窗口与 `insufficient-sample` 为可测函数 | 脚本 CLI 显式提供 `baseline`/`after --window 14d`/`--out`；evidence 目录随 CR 提交 |
| AC-18 | §4.7 `k` 段落 | 输出含 `costSource` + `tokenEstimator` + 分母 + 原始 usage 四维；`costSource=unavailable` ⇒ `k=null` 且无金额宣称；非 Pi 只报覆盖度与裁剪量 | 四维键名来自 `V-2` 的实读结构；Pi-only 由 `capabilities.level`/`coverage` 派生控制 |
| AC-19 | §1.4.2 + §3.4 + `check-install.mjs` | Adapter 以自身位置推导同一 Release 的相对 policy 路径（无复制目录）；无单独升级命令；启动检查只打印缺失/损坏与修复命令且不写任何文件；三级 scope 可区分 | 检查脚本只读 + 打印；scope 由参数与配置面路径显式区分 |
| AC-20 | §1.4.5 + `capabilities.enableOrder` | 启用顺序记录可核对：每个 Runtime 以"conformance 通过 + 真实冒烟通过 + 降级验证通过"为前置；CR 状态与 Pipeline 节点零新增；无长期 shadow mode | 顺序是部署顺序，落在 `capabilities.json` 与交付证据里，不进入状态机 |
| AC-21 | §4.10 + §6.4 | 扫描面内每处投影命令调用与显式表一致、需完整字段者带 `--detail`；`manifest.files`/`cases` 与实际一致；`exceptions` 保持空数组；`suite-gate --run` 同步前后均绿 | 新测试文件落在 `dep-13` 的磁盘集合内，未登记即 `SUITE_MANIFEST_FILE_DRIFT`（机械暴露，不靠自觉） |

## 6.3 既有实现依赖与事实

下表按**正文首次出现顺序**编号（`dep-1` 起，只增不改；新增条目只追加编号，删除条目留空洞不复用）。每项以稳定标识开头，固定五要素。正文只用 `dep-N` 引用承载实现事实，不重复陈述"当前代码已经如何工作"。

```text
dep-1
  repo: ai-first-platform-docs
  relative path: change-requests/CR-2026-069/prd.md
  stable symbol/对象: PRD 全文（§1.3.1 范围原文前缀、§1.4 十六项落笔前核实事实、§1.5 九条口径、§3 三条 FR、§4 九条 NFR、§5 二十一条 AC）
  commit SHA: 926ef5399f9b3a29177484995fabd516417633fa
  依赖结论: 本 CR 的需求合同；blob 56626 B，在 926ef539 与当前 HEAD 之间逐字未变（已随人工审批按 evidence-digest 钉住）。本 SDD 只读引用，任何修订必须回到需求侧，不得由本阶段改写

dep-2
  repo: ai-first-platform-docs
  relative path: change-requests/CR-2026-069/sources/CR需求来源_CR流程降本提效_收敛版.md
  stable symbol/对象: 收敛版需求来源（§1 首期三项、§2 硬边界、§3.1/§3.2 既有基础设施、§5 FR-8、§6 FR-1、§7 FR-2、§8 十 TASK、§9.1 十六条硬验收、§10 回滚、§11 非目标、§12 候选 Backlog）
  commit SHA: a4e33ff50a6868608599b37119ba3011e0a155d8
  依赖结论: 本 CR 的范围权威；blob 26406 B，自引入提交起逐字未变。首期范围 = FR-8 + FR-1 + FR-2；FR-3～FR-7 与 FR-9 只是编号占位

dep-3
  repo: tools
  relative path: ARCHITECTURE.md
  stable symbol/对象: §3 代码地图、§4 分层与依赖方向、§5 硬不变量 1～8、§6 刻意不做（含"另一套独立 WAL/事务框架"与"独立账本操作脚本库"两条否决记录）、§8 维护规则
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 本设计的架构约束来源：依赖只朝下、账本单一写入通道、零第三方依赖、行尾与硬失败纪律、状态机口径唯一、Skill 通用约束归仓。本 CR 不新增也不修改这些不变量

dep-4
  repo: multica
  relative path: server/internal/daemon/execenv/crguard_config.go
  stable symbol/对象: prepareCRGuard / CRGuardResult（每任务 env 锻造：PATH shim + provider=claude 时写 {workDir}/.claude/settings.json；hook 脚本路径从 rules.json 位置派生；已存在则跳过并告警）
  commit SHA: 947386318d52ecdb026a017f76220cde2ef7b94e
  依赖结论: 本 CR 的挂载先例与挂载点：Runtime 启动接线在既有每任务 env 锻造流程内完成、且"派生路径而不是二次配置"是既有做法。本 CR 在同一写入点内合成 OutputGuard hooks；挂载入参为空时该函数行为逐字不变

dep-5
  repo: tools
  relative path: skills/shared/crctl/scripts/lib/durable-tx.mjs、lib/workspace-transactions.mjs、lib/outbox-contract.mjs、lib/yaml-subset.mjs
  stable symbol/对象: durable-tx 的锁/journal envelope/recoverable write-set/CAS/nowIso/FAULT_POINTS；workspace-transactions 的仓库与 worktree 解析、候选 manifest 校验、受控 Git、原子提交、checkpointCr、release-subjects；outbox-contract 的事件可比字段；yaml-subset 的行级解析器
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 跨文件与跨仓写入的唯一既有实现（四个文件构成 lib 面）。本 CR 零 diff，只允许消费式 import；新增代码不得引入第二套锁/journal/CAS/提交框架

dep-6
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: ok(obj)（全量缩进打印、45 个调用点）、fail(code,message,extra)（247 个出口，写 stderr 并非零退出）、parseArgs（`--flag` 通用取值且对未知 flag 零校验）、main() 的 switch dispatch
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: FR-2 的事实基线：成功输出是单一漏斗、错误面与成功面完全分离、flag 解析无白名单。因此 `--detail` 既不会被既有实现拒绝，也不会因"未注册"而报错，但需要专用布尔分支以免吞掉后随 token

dep-7
  repo: tools
  relative path: skills/shared/controlled-shell/rules.json
  stable symbol/对象: git 白名单（sub/shapes）、forbiddenFlags、protectedPaths.deny（`cr.md` / `_backlog.yml` / `approval.yml` / `review-loop.yml` / `review-annotations/*.yml`）与 ask（`specs/`、`delivery/`、`test-report.md`）
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 先于 OutputGuard 的既有安全控制面。逃生阀只影响 OutputGuard 的封顶，不得影响该面（AC-6 四条负向测试的对象）。本 CR 零 diff

dep-8
  repo: tools
  relative path: skills/shared/crctl/gates.json
  stable symbol/对象: statusGates（含 `tech-design-review-pending` = fileExists `change-requests/{cr}/sdd.md`）、approvalStages（含 `tech-design` 的 to/trigger/expect/approvalSection/passCondition）
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 技术设计阶段的证据路径与审批声明唯一源；本 CR 零 diff

dep-9
  repo: tools
  relative path: pipeline-templates/*.pipeline.json、pipeline-templates/_index.yml、skills/_index.yml
  stable symbol/对象: `architecture-design` 的 4 节点与其 reviewLoop（repairNodeId/repairRef/replayNodes/maxAttempts=3/passCondition：verdict=pass ∧ blockers 为空）、`code-implementation` 的 12 节点；两个 `_index.yml` 的 active 条目集
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 节点数（5/4/12）与 reviewLoop 是既有合同；且 pipeline 的 skill 引用必须落在 `skills/_index.yml` 的 active 集内 —— 因此新增目录不得被注册为 skill

dep-10
  repo: tools
  relative path: skills/shared/crctl/adapters/claude-code/{settings.template.json,hooks/pretooluse-guard.mjs,README.md}
  stable symbol/对象: hooks 段模板（PreToolUse / SessionStart / UserPromptSubmit）+ `{TOOLS_ROOT}` 安装时物化为绝对路径的约定 + 三步安装说明
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: OutputGuard 的 Claude 安装形态与 README 结构沿用该先例；两套适配器各自持有模板文件、不共用一个事实源（§3.4）

dep-11
  repo: tools
  relative path: skills/shared/crctl/adapters/qoder/{settings.template.json,README.md}
  stable symbol/对象: `.lingma/settings.json` 三级配置面（用户级/项目级/项目本地）、格式与 Claude 一致、**无 SessionStart**（注入挂 UserPromptSubmit）、改配置需重启
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: Qoder 的安装面与 hook 协议族事实；OutputGuard 的 Qoder 适配器沿用同一映射，`capabilities.qoder.startRecord` 只能记 `none`

dep-12
  repo: tools
  relative path: skills/shared/crctl/adapters/codex/{hooks.json.template,README.md}
  stable symbol/对象: `.codex/hooks.json`（用户级/项目级）与 config.toml `[[hooks]]` 等效、matcher 为正则、非托管 command hook 有 `/hooks` 审查-信任（按哈希，脚本变更需重新信任）
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: Codex 的安装面与"信任"前置；OutputGuard 的 Codex 适配器按 partial 处理，README 必须写明信任步骤

dep-13
  repo: tools
  relative path: skills/shared/crctl/scripts/test/{suite-gate.mjs,gate-registry.json,assertion-sources.mjs}
  stable symbol/对象: `readTestFileSet(toolsRoot)`（只收 `*.test.mjs`）；磁盘文件集合 ≡ `manifest.files`（`SUITE_MANIFEST_FILE_DRIFT`）；每文件顶层用例数 ≥ `manifest.cases` 基线（`SUITE_MANIFEST_CASE_DROP`）；`manifest.files` 当前 21 项、`exceptions` 为空数组
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 在被扫描目录内新增 `*.test.mjs` 会**立即**触发文件集合漂移红，因此登记同步是硬约束（AC-21②）；同时该目录外的测试文件不受此棘轮保护，必须有独立 CI 步骤

dep-14
  repo: tools
  relative path: skills/shared/crctl/scripts/test/{merge-fixture.mjs,fault-harness.test.mjs,assertion-sources.mjs}
  stable symbol/对象: 三 bare remote 的事务夹具构造、故障注入与恢复断言、状态机/索引断言工具
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 采集 `--detail` 金样本与构造 FR-8 测试样本时复用这些既有夹具构造方式（消费式引用），不得另造并行夹具体系

dep-15
  repo: multica
  relative path: server/internal/daemon/execenv/runtime_config.go
  stable symbol/对象: 每任务运行时配置与记忆文件的写入责任面（per-provider 的 `CLAUDE.md` / `CODEBUDDY.md` / `AGENTS.md` 与各 Runtime 的原生 skills 发现路径，含 Pi 的 `.pi/skills/`）
  commit SHA: 947386318d52ecdb026a017f76220cde2ef7b94e
  依赖结论: 每任务运行时资源写入的既有责任边界；OutputGuard 挂载只新增"Runtime hooks 配置"这一类文件，不改动 Prompt/记忆文件的既有语义

dep-16
  repo: multica
  relative path: server/pkg/agent/pi.go
  stable symbol/对象: buildPiArgs（`-p` / `--mode json` / `--session` / `--model` / `--thinking`）与 piBlockedArgs（`--extension`/`-e`/`--no-extensions`/`--session-dir` 等被阻断项）
  commit SHA: 947386318d52ecdb026a017f76220cde2ef7b94e
  依赖结论: Pi 的 argv 面不放开：用户 custom_args 不能注入扩展；因此 Pi 的 OutputGuard 挂载只能走宿主级配置面（`~/.pi/agent/settings.json#extensions` 或 `~/.pi/agent/extensions/`），不能靠 argv 注入

dep-17
  repo: multica
  relative path: server/internal/daemon/tool_output_preview.go
  stable symbol/对象: `toolOutputPreviewBudget = 8192` 与包注释 "It does not limit the full output consumed by the agent."
  commit SHA: 947386318d52ecdb026a017f76220cde2ef7b94e
  依赖结论: 该文件只限制展示/预览预算，不限制模型消费的完整输出，因此不是本 CR 的 seam。本 CR 零 diff（AC-12）

dep-18
  repo: multica
  relative path: CUSTOM.md
  stable symbol/对象: 「按 CR 里程碑归类」的二开台账（行号稳定 ID、合并注意列、核对口径 grep 命令）
  commit SHA: 947386318d52ecdb026a017f76220cde2ef7b94e
  依赖结论: 凡在 multica 仓落代码必须按其现状登记；TASK-09 的改动（`dep-4` 新增入参 + 新增 `outputguard_config.go`）必须新增台账条目

dep-19
  repo: tools
  relative path: .github/workflows/crctl-ci.yml
  stable symbol/对象: `on.push` / `on.pull_request` 的 `paths` 列表；`jobs.contracts.steps`（lint-prompts --mode enforce、check-skill-matrix、check-agents-contract、pipeline 结构断言、suite-gate --run、writeback 单测）
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 现有触发路径不含 `output-guard/**` 与 `skills/shared/metrics/**`；不扩展触发面则新目录的测试永不进入 CI（NFR-7 的回归保护失效）

dep-20
  repo: tools
  relative path: skills/shared/crctl/scripts/lint-prompts.mjs
  stable symbol/对象: R7（advance --to/--trigger、backlog-set 字段白名单、--template subject 编号）、R8（inbox-emit 接口）、R9（下一步提示收敛 crctl next）、R10～R13（废弃接口/退役 Skill/状态机副本/backlog 状态推断）
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 规则集内**没有**"未知 flag"校验，因此在 Skill 文本中新增 `--detail` 不会触发 lint 漂移；同时该工具抓不到"crctl 新增能力但 Skill 未采纳"，该面只能由 §8 清单 + `caller-contract.test.mjs` 兜住

dep-21
  repo: tools
  relative path: skills/develop/review-tech-design/SKILL.md、skills/develop/review-code/SKILL.md、skills/develop/review-dev-plan/SKILL.md、skills/requirement/review-requirement/SKILL.md
  stable symbol/对象: 四个 reviewer Skill 的 crctl 调用面（status/next/gate/attempt/review-record）及其引用的输出字段（gateBlockers/reviewLoops/warnings/legalNext）
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: AC-21① 的真实调用方主体；投影命令集确定后必须逐条核对是否需要 `--detail`，并在其中新增 `complete=false` 取证完整性规则
```

### 待核实依赖（`V-1`～`V-7`）

以下引用的外部事实**无法绑定** `repo` + 40 位 `commit SHA` 五要素（npm 全局安装的包、外部厂商文档），因此单列于此，正文只以 `V-N` 引用；每条给出可复跑的核实命令与"核实失败时的唯一合法动作"。**编号按语义分组（V-1～V-3 = Pi、V-4～V-7 = 各 Runtime 文档）而非首现顺序——顺序规则只适用于 `dep-N`。**

```text
V-1  Pi 扩展 API（@earendil-works/pi-coding-agent 0.85.1，本机全局安装）
  声明: `tool_call` 可阻断（返回 {block:true, reason?, terminate?}；event.input 可原地改写且不重新校验）；`tool_result` 可修改（返回 {content, details?, isError?, usage?} 局部 patch，省略字段保持原值；handlers 按加载顺序链式）；扩展发现面 = `~/.pi/agent/extensions/*.ts`、`.pi/extensions/*.ts`（及 */index.ts），额外路径可经 `settings.json#extensions[]` 声明；`PI_CODING_AGENT_DIR` 可覆盖配置目录（默认 `~/.pi/agent`）
  证据: docs/extensions.md（事件流 L304-306、tool_call L778-796、tool_result L842-855、扩展位置表 L113-135）、docs/environment-variables.md L81、dist/core/extensions/loader.js L572-573
  核实命令: PI_PKG="$(npm root -g)/@earendil-works/pi-coding-agent"; node -e "console.log(require(process.argv[1]+'/package.json').version)" "$PI_PKG"; sed -n '842,856p' "$PI_PKG/docs/extensions.md"; sed -n '110,136p' "$PI_PKG/docs/extensions.md"
  失败动作: 若结果回填不受支持 → `capabilities.pi.level` 降级为 partial/unavailable，按 SDD-CLOSE-05 走 scope amendment

V-2  Pi session JSONL 形状与规模
  声明: 每行一条 JSON 记录，`type` ∈ {session, model_change, thinking_level_change, message}；message 记录形如 {type:'message', id, parentId, timestamp, message}，`message.role` ∈ {user, assistant, toolResult}；assistant 的 `content[]` 含 {type:'toolCall', id, name, arguments}，`message.usage` 含 input/output/cacheRead/cacheWrite/reasoning/totalTokens 与 `cost.{input,output,cacheRead,cacheWrite,total}`；toolResult 含 {toolCallId, toolName, content[], isError, timestamp} 与可选 details
  口径与观测时刻: 本机 `~/.multica/pi-sessions` 直属 `*.jsonl` 共 585 个（观测 2026-09-17 15:35 CST；口径 = 该目录直属 *.jsonl、非递归）；抽样文件 20260825T102935.566100800.jsonl（1,707,218 B）内 role 计数 user=1 / assistant=47 / toolResult=109，toolName 直方图 {bash:945, read:349, write:45, edit:27}（样本 = 该目录前 30 个文件）
  核实命令: node -e "const fs=require('fs'),p=process.argv[1];const l=fs.readFileSync(p,'utf8').replaceAll(String.fromCharCode(13,10),String.fromCharCode(10)).split(String.fromCharCode(10)).filter(Boolean);const s={};for(const x of l){const o=JSON.parse(x);const k=o.type+(o.message?'/'+o.message.role:'');s[k]=(s[k]||0)+1}console.log(s)" "$HOME/.multica/pi-sessions/20260818T043049.725742100.jsonl"
  失败动作: 键名不同 → 只改 `lib/sessions.mjs` 的读取口径；`dep-1` FR-8 第 3 项的输出字段集是需求面，不改

V-3  Pi 内置工具截断行为
  声明: bash 工具的 toolResult.details 会带 `truncation`（含被丢弃正文片段）与 `fullOutputPath`（完整输出落盘路径）；read 工具的 details 带 `truncation`
  证据: `V-2` 同一抽样命令下实读到的 details 形状 + dist/core/tools/bash.js 的截断/退出码分支
  影响: AC-7 / AC-15 的 sentinel 用例必须把 payload 控制在 Pi 自身阈值以下，才能把"谁的丢弃"隔离干净（§7.4 R-4）
  失败动作: 若该行为已变 → 调整 sentinel 用例的 payload 控制策略；本 CR 不治理该既有行为（F-5）

V-4  Claude Code hooks 文档   来源 https://code.claude.com/docs/en/hooks
V-5  CodeBuddy Code hooks 文档   来源 https://www.codebuddy.ai/docs/cli/hooks
     本轮已实读的部分（2026-09-17，用于 §3.3/§3.4 的落点选择）: 配置面 `~/.codebuddy/settings.json`（用户）/ `<project-root>/.codebuddy/settings.json`（项目）/ `.codebuddy/settings.local.json`；多 scope 的 hooks 为**合并**而非覆盖；`PostToolUse` 支持 `hookSpecificOutput.updatedToolOutput` 替换工具结果（文档明示该能力用于压缩冗长输出）与 `additionalContext` 追加；`PreToolUse` 支持 `permissionDecision` / `modifiedInput`；Windows 下 hook command 强制 Git Bash；配置在会话启动时快照、改配置需重启；`/hooks` 面板审查
V-6  Qoder hooks 文档   来源 https://docs.qoder.com/en/cli/hooks
V-7  Codex hooks 文档   来源 https://developers.openai.com/codex/hooks
  声明（V-4～V-7 共用）: 各 Runtime 的 Pre/Post hook 事件名、结果回填能力（updatedToolOutput 或 block/feedback）、配置面路径、信任/审查前置、Windows shell 约束
  失败动作: 逐 Runtime 落 `capabilities.level`；任一 Runtime 由 full 降级即 AC-4 未达成（§2.4 + SDD-CLOSE-05），不得静默吸收
```

**依赖引用规则自查**：① 正文出现的每个 `dep-N` 均在本节有定义；② 本节编号按正文首现顺序分配（自查实测：dep-1@16、dep-2@16、dep-3@30、dep-4@78、dep-5@106、dep-6@107、dep-7@116、dep-8@317、dep-9@330、dep-10@408、dep-11@408、dep-12@408、dep-13@560、dep-14@560、dep-15@615、dep-16@615、dep-17@615、dep-18@687、dep-19@773、dep-20@846、dep-21@853，单调且无空洞）；③ 无法绑定五要素的外部引用全部在"待核实依赖"单列，正文只以 `V-N` 引用；④ 本 CR 确有既有实现依赖，故本节不写 `N/A`。

## 6.4 既有测试面改动清单与零改动核对清单

**改动清单（全部为"增项"，不改既有断言语义）**：

| 面 | 动作 | 触发原因 |
|---|---|---|
| `dep-13` 的 `gate-registry.json` | `manifest.files` 增 `crctl-summary.test.mjs`、`caller-contract.test.mjs`；`manifest.cases` 增两条对应基线 | 磁盘测试文件集合 ≡ `manifest.files`（`SUITE_MANIFEST_FILE_DRIFT`），新增文件不登记即红 |
| `dep-13` 的 `gate-registry.json#exceptions` | **保持空数组**，不新增例外 | AC-21③ |
| `output-guard/test/*.test.mjs` | 新增，由 CI 新增步骤执行 | 不在 `dep-13` 的扫描目录内，因此**必须**有独立 CI 步骤，否则新合同无回归保护 |
| `skills/shared/metrics/test/cr-cost.test.mjs` | 新增，由 CI 新增步骤执行 | 同上 |
| `dep-19` 的 `.github/workflows/crctl-ci.yml` | `paths` 增 `output-guard/**`、`skills/shared/metrics/**`；`steps` 增 `output-guard` 与 `metrics` 两条测试步骤 | 现有触发路径**不含**新目录 → 不增则新目录的测试永不运行（部署面裸奔） |

**零改动核对清单（提交前逐条 `git diff --name-only` 核对）**：`dep-5` 的 lib 四文件、`dep-7`、`dep-8`、`dir-graph.yaml`、`dep-9` 的全部 pipeline JSON、`agent-skill-matrix.yml`、`dep-18`；以及 multica 侧除 `dep-16`/`dep-17` 之外的运行时语义文件、`prd.md`、四账本（`cr.md` 的 status 行由 crctl 写入，不计入）、`specs/`、`delivery/`、`docs/`。

## 6.5 SDD-CLOSE 关闭义务（CR-2026-060 AC-06）

`dep-1` 显式延后到 SDD 的设计项逐项关闭如下。每项覆盖该事项实际涉及的数据生产、存储/传输、消费与兼容降级层。

| 编号 | 待关闭项（来源） | 关闭结论 | 覆盖层 |
|---|---|---|---|
| SDD-CLOSE-01 | Adapter 目录归属与安装入口是否与既有 crctl 适配器共用（`dep-1` §1.5 第 8 条） | **分目录、分模板、分安装入口；唯一联合点是 Managed scope 下的单写入点合成**（§3.4、§4.9） | 生产（模板）／传输（安装物化）／消费（Runtime 配置）／降级（任一模板缺失只影响该 Runtime） |
| SDD-CLOSE-02 | `--detail` 与旧完整输出的"等价"定义（§1.5 第 6 条） | **三层等价性合同：字段集合 ≡ / 稳定值逐字 ≡ / 易变字段形态 ≡；禁止字节比对**（§4.6） | 生产（投影函数）／传输（stdout）／消费（调用方字段集合，§4.10）／降级（未投影命令等价现状） |
| SDD-CLOSE-03 | 新增合同测试的棘轮登记同步义务（§1.5 第 7 条） | **`manifest.files` + `manifest.cases` 同批更新；`exceptions` 保持空；新增目录另加独立 CI 步骤**（§6.4） | 生产（测试文件）／存储（登记面）／消费（suite-gate）／降级（不登记即红，不静默） |
| SDD-CLOSE-04 | 逃生阀标记不合法时的行为（§1.5 第 5 条） | **视为不存在（`absent`）**：不拒绝调用、不新增 action 取值；若随后被裁剪仍出 `action=truncate` trailer（§4.1） | 生产（解析）／传输（Pre hook 决策）／消费（执行与结果面）／降级（无第二套错误码） |
| SDD-CLOSE-05 | Runtime 能力不足时的降级路径与 AC-4 联动（§1.5 第 4 条 + 需求评审 S-3） | **降级唯一合法动作=改 `capabilities.json`；由 full 降级即视为 AC-4 未达成，须回人工确认（scope amendment）后重定 AC-4**（§2.4） | 生产（声明）／存储（capabilities.json）／消费（conformance 与 FR-8 覆盖度）／降级（partial/unavailable 显式） |
| SDD-CLOSE-06 | 是否引入 plugin 打包形态（§1.5 第 9 条） | **不引入**；沿用模板 + 安装时物化绝对路径（D-3、§3.4） | 生产（模板）／传输（安装动作）／消费（Runtime 配置加载）／降级（未安装＝未启用，检查脚本报告） |
| SDD-CLOSE-07 | FR-8 机器结果的落点与"不新增账本"的边界（`dep-1` FR-8 第 1/3 项与 AC-17④） | **机器 JSON：脚本 `--out` + KB `change-requests/CR-2026-069/evidence/` 副本 + Issue 附件；人读摘要只走 stdout（不写第二份产物文件）；四账本零变化**（§3.6） | 生产（聚合）／存储（evidence）／消费（TASK-08 选择 + TASK-10 复测）／降级（`insufficient-sample`） |
| SDD-CLOSE-08 | 计数类断言的"口径 + 观测时刻"义务（§1.5 第 3 条 + 需求评审 S-4） | **每个计数字段携带 `observedAt` 与 `rule`；脚本与门禁中零硬编码样本常量**（§3.6） | 生产（脚本输出）／存储（JSON 字段）／消费（评审与复算）／降级（口径缺失即实现缺陷） |
| SDD-CLOSE-09 | Managed scope 的挂载责任面（`dep-1` §1.3.2 multica 行） | **claude/codebuddy/qoder 由 daemon 单写入点合成挂载；Pi 走宿主级配置安装一次；Codex 走宿主级 + uncovered 声明**（§1.4.2、§4.9） | 生产（挂载解析）／传输（每任务配置文件）／消费（Runtime 加载）／降级（未配置即整体跳过，行为零变化） |
| SDD-CLOSE-10 | `exitCode` 等"字段必须保留"的可执行化（`dep-1` FR-1 第 5 项） | **按 Runtime 结果结构的真实字段集判定：`present` 必保留，`absent-by-runtime` 不作要求且不因此降级**（§4.2、D-6） | 生产（可保持性检查）／传输（结果回填）／消费（门禁证据判定）／降级（不可保持 → `unavailable`） |

---

# 7. 安全与性能考量

## 7.1 行尾纪律与硬失败（I9）

任何读入仓库文件或 session 文件的代码（Adapter 读 policy、度量脚本读 JSONL、测试读金样本）**必须先 `\r\n → \n`**，逐行解析用 `split(/\r?\n/)`；跨行正则匹配失败必须硬失败报错，禁止"匹配不到 → 空集 → 静默通过"。落地判据：新增的解析函数全部经由 `core.mjs#normalizeText` 或同名等价入口，且失败路径抛错/非零退出。三处高风险面单独列出：

1. **金样本比对**（§4.6）：Layer ③ 的易变字段形态判定在 EOL 归一后执行，防止 Windows 检出差异造成假失败。
2. **session 遍历**（§4.7）：JSONL 逐行 `JSON.parse`，单行解析失败计入 `malformedLines` 并保留观测计数，**不得**整体静默跳过文件；文件级读失败必须计入 `unreadableFiles` 并在输出中可见。
3. **multica 挂载合成**（§4.9）：读取既有配置文件失败时按"存在即不 clobber"处理并告警，**不**写半成品文件。

## 7.2 安全边界（fail-open 与 fail-closed 正交）

| 面 | 失效行为 | 依据 |
|---|---|---|
| OutputGuard（Adapter / policy / Core） | **fail-open**：原调用继续、结果不改、显式标 `coverage=unavailable` | FR-1 第 8 项 |
| crctl / Git 白名单 / 受控路径 / 审批 / 账本写入 | **fail-closed 不变**：本 CR 不改其任何判定逻辑 | `dep-7`、NFR-6 |

四条不可跨越的边界（AC-6 与 AC-19 的负向面）：

1. 逃生阀只影响 OutputGuard 的封顶，**不影响** git 白名单 / protected paths / 审批 / 账本写入控制；
2. OutputGuard 不新增任何授权面（无授权文件、无 nonce、无"下一次调用"状态、无远程开关）；
3. 启动检查只读：**不**自动安装、**不**改写用户配置、**不**修复 Runtime；
4. 被丢弃正文不落盘、不进 transcript、不进任何日志；度量只记 token 数与计数，不存正文（隐私面）。

## 7.3 性能与可观测

| 面 | 目标 | 手段 |
|---|---|---|
| hook 延迟（每次工具调用） | 同数量级于"读一个小 JSON"；不引入外部进程、不做网络调用 | policy 读取后在同一次 hook 调用内复用；Core 为 O(n) 单遍扫描；无正则回溯风险模式（限长匹配） |
| 内存 | 被丢弃正文立即释放（不缓存、不堆积） | 只保留 kept 片段与计数；不保留 original |
| FR-2 收益 | 默认面 token 数下降（不设硬指标；由 FR-8 复测观察） | 字段投影 + 保持既有格式化（D-2） |
| FR-8 运行成本 | 离线、可重复、单次全量遍历；不进入 CR 门禁与 Pipeline | 只读遍历 + 纯函数聚合；不执行任何命令 |
| 可观测 | 只有两个可见面：一行 trailer、一行启动记录 | 不新增 JSONL/sidecar/DB/仪表盘（NFR-5） |

**回滚路径（FR-1 第 12 项）**：单 Runtime 误伤 → 移除该 Runtime 的安装配置（新会话生效，其它 Runtime 不受影响）；Core/Policy 共性错误 → 整体回退 Tools Release；阈值过严 → 改 `policy.json` 后随完整 Release 发布。三者都不需要补偿流程、不需要远程开关。

## 7.4 残余风险（需要在实施期被看见，而不是被假设掉）

| # | 风险 | 缓解与判据 |
|---|---|---|
| R-1 | AC-16 的"不得作为充分门禁证据"在"不新增门禁/状态"的约束下无法做成机器硬拦截 | 由"trailer 固定指令 + reviewer Skill 合同条款 + 至少一条端到端用例"三件套承载；残余风险如实登记（`follow_up` F-4） |
| R-2 | D-5（`unavailable` 也出 trailer）与 D-6（`exitCode` 按结构存在性）是对 `dep-2` §6.7 / `dep-1` FR-1 第 5 项的紧读边界裁决 | 两条裁决在 §9 `follow_up` 留了显式替代出口，并随本 SDD 进入人工审批过目；改动任一条会连带影响 AC-15 与启用顺序，必须在设计阶段决定 |
| R-3 | 某 Runtime 实测不具备 full 能力（`V-4`～`V-7` 待核实） | 按 §2.4 降级 + scope amendment；不得静默吸收（SDD-CLOSE-05） |
| R-4 | Runtime 自身的截断行为（`V-3`：Pi 把被丢弃正文放进 `details` 并写 `fullOutputPath`）会造成"谁的丢弃"混淆 | 测试夹具控制 payload 尺寸以隔离；该行为本 CR 不治理（F-5） |
| R-5 | Pi 的扩展加载面（`V-1`）与 Multica 的 argv 白名单（`dep-16`）共同决定 Pi 只能走宿主级安装 | 已在 §1.4.2 / D-7 落成显式设计；AC-14 冒烟必须在 Multica 启动的真实任务环境完成 |

---

# 8. Prompt 采纳影响

**触发判定**：本 CR 的 diff 触及 `dep-6`（`crctl.mjs`）的 dispatch 与成功输出投影层 → 本节必填。另需说明：「新增能力未被采纳」这类漂移是 `dep-20`（`lint-prompts` 的 R7～R13）**抓不到的**——它只校验参数形态、废弃接口与状态机副本一致性，不校验未知 flag，因此新增 `--detail` 本身不会触发 prompt 漂移，采纳与否只能由本节 + `caller-contract.test.mjs` 兜住。

**与典型情形的差别（关键）**：本 CR **不新增 crctl 子命令**，只新增一个布尔型呈现层开关 `--detail` 并改变被投影命令的**默认输出字段集**。因此本节的采纳义务不是"改用新子命令"，而是三件事：① 把 `--detail` 写进权威 Skill 文档；② 对"需要 summary 之外字段"的真实调用点显式补 `--detail`（A10 的机械扫描面）；③ reviewer 类 Skill 采纳 `complete=false` 的取证完整性规则（AC-16）。

| Skill / 文件 | 现状 | 应改为 |
|---|---|---|
| `skills/shared/crctl/SKILL.md` | 只描述子命令与参数形态，未提及任何输出投影开关；示例隐含"输出为完整 JSON" | 增一节（或并入既有"调用方式"段）：默认输出为 compact summary；需要完整字段时显式加 `--detail`；明确"未投影命令加 `--detail` 等价于现状"；不复刻任何字段清单（只指向 `summary-projectors.mjs`） |
| `dep-21`：`skills/develop/review-tech-design/SKILL.md`、`skills/develop/review-code/SKILL.md`、`skills/develop/review-dev-plan/SKILL.md`、`skills/requirement/review-requirement/SKILL.md` | 四份均已以 `crctl status` / `next` / `gate` / `attempt` / `review-record` 原样调用，并逐字引用 `gateBlockers` / `reviewLoops` / `warnings` / `legalNext` 等字段 | 按 A10 表：若涉及字段不在该命令 summary 内 → 调用改为带 `--detail`；同时增一条"以 `complete=false` 结果不得作最终判断，须继续切片取证或走逃生阀（AC-16）"的规则条款 |
| `skills/develop/approve-tech-design/SKILL.md`、`skills/develop/approve-dev-start/SKILL.md`、`skills/develop/approve-code/SKILL.md`、`skills/requirement/approve-requirement/SKILL.md` | 同样消费 `crctl status/gate` 的完整字段（证据摘要、`gateBlockers`） | 同上（按 A10 表定点补 `--detail`） |
| `skills/sync/**`（`push-progress` / `pull-progress` / `workspace-freshness` / `handover-cr` / `resume-from-remote`） | 消费 `crctl status` / `workspace inspect` / `workspace freshness` 的完整字段 | 同上（按 A10 表定点补 `--detail`） |
| `pipeline-templates/*.pipeline.json` 的 prompt 文本 | 含 `crctl <命令>` 示例调用 | 若示例所在步骤需要完整字段 → 补 `--detail`；不新增节点、不改 reviewLoop |
| `agents/*.md` 与 `README.md` | 含 `crctl` 调用叙述 | 仅当叙述要求完整字段时补 `--detail`；README 只增导航与权威入口（AC-13） |
| `output-guard/**` 文档（新增） | — | README/模板只允许写"路径 + 安装命令 + 检查命令"，禁止复制 `policy.json` 阈值与 `capabilities.json` 能力矩阵 |

**冻结机制**：A10 的显式表落成 `skills/shared/crctl/scripts/test/caller-contract.test.mjs` 的数据段。该表是**人工审过的白名单**，断言是机械的——任何调用点与表不符（缺 `--detail` 或声明与实际字段消费不一致）即红。因此 `dep-20` 抓不到的那一类漂移，在本 CR 里由该测试 + `review-dev-plan`/`review-code` 的 Prompt 采纳维度共同兜住。

---

# 9. 批准范围

## scope_in（当前 CR 必须交付的 FR/AC）

1. **FR-8 全量**：`skills/shared/metrics/scripts/cr-cost.mjs` + `scripts/lib/{sessions,aggregate,select,render}.mjs` + `test/cr-cost.test.mjs`；`baseline`/`after`/`replay`/`verify-selection` 四个子命令；TASK-01 的机器 JSON 副本落 `change-requests/CR-2026-069/evidence/`（AC-17 / AC-18 / AC-9）。
2. **FR-1 全量**：`output-guard/{core.mjs,policy.json,capabilities.json,conformance.json}` + 五个 Adapter 目录 + `scripts/check-install.mjs` + `test/*` + 各 Adapter README（AC-3～AC-8、AC-13～AC-16、AC-19、AC-20）。
3. **FR-2 全量**：`skills/shared/crctl/scripts/lib/summary-projectors.mjs`；`crctl.mjs` 的**三处改动**（`ok()` 投影入口、`parseArgs` 的 `--detail` 布尔分支、HELP 一行）；`test/crctl-summary.test.mjs`；`test/caller-contract.test.mjs`；`test/golden/crctl-detail/*.json`；`test/gate-registry.json` 的 `manifest.files` / `manifest.cases` 同步（AC-10、AC-11、AC-21）。
4. **Prompt 采纳面**（§8）：`skills/shared/crctl/SKILL.md`、四个 review Skill、四个 approve Skill、`skills/sync/**` 中 A10 表命中项的定点补 `--detail` 与 AC-16 规则条款。
5. **治理登记与 CI 面**：`dep-18`（`../multica/CUSTOM.md` 按其现状登记本次定制）；`dep-19`（`.github/workflows/crctl-ci.yml` 的 `paths` 增 `output-guard/**`、`skills/shared/metrics/**`，`steps` 增两条测试步骤）；`README.md` 增导航与权威入口；`ARCHITECTURE.md` 增 `output-guard/` 与 `skills/shared/metrics/` 两条代码地图条目。
6. **TASK-09 挂载（Managed scope）**：`../multica` 新增 `server/internal/daemon/execenv/outputguard_config.go` + `crguard_config.go` 的单写入点合成入参 + 同包回归测试（AC-14、AC-19、AC-20）。
7. **交付证据**：TASK-01/TASK-10 的机器 JSON、各 Runtime 的真实冒烟记录、conformance 结果、调用方扫描表、AC-10 的 `verify-selection` 输出。

## scope_out（明确排除的路径和能力）

- **FR-3 / FR-4 / FR-5 / FR-6 / FR-7 / FR-9**：候选 Backlog，编号保留、本 CR 不实施、不得借本 CR 顺手做（`dep-1` §7）。
- **`dep-17`（`tool_output_preview.go`）及其上游 daemon 展示/transcript 语义**：零 diff（AC-12）。
- **`dep-15` 的固定 `architecture-design` 切片语义与 Provider 事件归一化行为**：零 diff。
- **KB 的 `specs/` / `delivery/` / `docs/`**（含只读的历史分析文档）：零写入。
- **治理结构**：不新增状态、门禁、审批、CR 生命周期节点、Pipeline 节点、账本字段、数据库表、仪表盘、sidecar 日志、WAL、CAS 层、事务框架、远程动态开关、shadow mode。
- **实现手段**：不实现完整 Bash/PowerShell parser（管道/重定向/脚本嵌套不做解析）、不调用 LLM 做输出摘要、不做语义压缩、不优化 crctl 运行时小文件读取、不建 crctl 字段/错误码事实页、不引入 plugin 打包形态、不引入第三方 tokenizer 依赖。
- **运行环境**：不自动安装 Provider、不修复 Runtime、不重试失败工具调用、不改写任何用户配置文件。
- **历史数据**：不治理历史上从未读取的大文件；不通过合并相邻会话解决 bootstrap。

## zero_diff（明确不得改动的调用点 / 签名）

| 对象 | 约束 |
|---|---|
| `dep-6` 的 `crctl.mjs` 中除 `scope_in` 第 3 项列明的三处落点以外的全部代码（含 247 个 `fail()` 出口与全部状态/门禁/审批/CAS/事务/Git 分支） | 零修改（与 AC-1 的同一 carve-out） |
| `dep-5` 的 lib 四文件（`durable-tx.mjs` / `workspace-transactions.mjs` / `outbox-contract.mjs` / `yaml-subset.mjs`） | 零 diff 或仅消费式 `import`；不新增实现、不拆分、不重构 |
| `dep-8` 的 `gates.json` | 零 diff |
| `dir-graph.yaml`（含 `#change-request-track.state_machine`） | 零 diff（状态数与转移集不变） |
| `dep-9` 的全部 pipeline JSON | 零 diff（节点数保持 5/4/12，reviewLoop / replayNodes / maxAttempts 不变） |
| `agent-skill-matrix.yml` | 零 diff（不新增 Skill、不新增 actor/权限项） |
| `dep-7` 的 `controlled-shell/rules.json` | 零 diff（`protectedPaths.deny` 与 git 白名单面不变） |
| 既有测试文件的既有断言 | 语义零变化；只允许新增文件与新增用例，以及 `dep-13` 中 `manifest.files`/`manifest.cases` 的**增项** |
| `../multica` 的 `server/internal/governance/runner.go`（固定 `architecture-design` 切片）与 Provider 事件归一化实现 | 零 diff |
| `dep-16` 的 argv 白名单面（`piBlockedArgs` 等既有清单） | 零 diff（不新增、不放开任何被阻断的 argv） |
| `dep-17`（`tool_output_preview.go`） | 零 diff（AC-12） |
| KB：`prd.md`（审批 evidence-digest 钉住）、`specs/`、`delivery/`、`docs/`、四账本手工编辑 | 零写入 |

（四字段自洽判据逐条自查：① 无对象同时出现在 `scope_in` 与 `zero_diff`——`dep-6` 按**落点**切分（三处投影落点在 `scope_in`、其余代码在 `zero_diff`），与 AC-1 的同一 carve-out 逐字一致；② 三处"外部规则强制修改"的对象——`dep-18` 的定制登记、`dep-13` 的棘轮登记同步、`dep-19` 的 CI 触发面——**全部已纳入 `scope_in`**，未留在 `zero_diff`；③ `scope_out` 未隐藏任何当前交付必须发生的治理修改；④ `follow_up` 各项均非当前 AC 的必要条件。）

## follow_up（发现但留给后续 CR 的缺口）

| 编号 | 缺口 | 为什么不在本 CR |
|---|---|---|
| F-1 | `dep-2` §6.10 的"Claude 由 Tools Plugin 携带 Skills 与 hooks"未落地（本 CR 按 D-3 走模板 + 安装时物化） | 引入 plugin 形态需要新的安装/版本/信任语义，属"不新建安装框架"边界外；需要独立 CR 决策 |
| F-2 | Qoder 无 SessionStart → 无会话启动记录（`startRecord: none`） | 属 Runtime 能力事实；厂商补齐后可把声明改为 `session-start` 以提升 FR-8 覆盖度派生精度，不影响当前 AC |
| F-3 | D-5 / D-6 两条紧读边界裁决的替代出口（若评审要求字面读法） | 本 SDD 已给出裁决；若人工审批改判，需连带重定 AC-15 与启用顺序（属 scope amendment，不在本 CR 内部消化） |
| F-4 | AC-16 无法在"不新增门禁/状态"的约束下做成机器硬拦截 | 升级为机器拦截需要扩展 `review-record` payload 或新增门禁维度，两者都被本 CR 的 `scope_out` 排除 |
| F-5 | Pi 内置截断把被丢弃正文写入 `details` 与 `fullOutputPath`（`V-3`） | 既有行为，不属于 OutputGuard 的副作用面；若 F-8 复测显示其仍是 token 大头，作为候选 FR 重新立项 |
| F-6 | Codex 的托管 hook 与 hosted `WebSearch` 等 uncovered 路径 | 首期只做声明与逐条标记，不追求全覆盖（`dep-2` §6.3 的限制明确如此） |
| F-7 | 后续新增 Runtime 的"字段存在性"口径 | 沿用 D-6：已有 `absent-by-runtime` 声明的 Runtime 不得被反向要求提供该字段；新 Runtime 必须按 `V-*` 核实后落笔 |

---

# 修订记录

- **初稿（2026-09-17）**：以 `dep-1`（已审批 PRD，冻结）与 `dep-2`（收敛版需求来源）为输入；按 `write-tech-design` 的九节骨架起草，条件触发的第 8 节（Prompt 采纳影响）因本 CR 触及 `crctl.mjs` dispatch 与成功输出投影层而必填。§6.3 的既有实现依赖表按正文首次出现顺序编号（`dep-1` 起），待核实依赖（`V-1` 起）单列于同节。关闭 `dep-1` 显式延后到 SDD 的 10 项（SDD-CLOSE-01～10）；对需求评审的 4 条非阻塞 suggestion 的处理：S-1 由 §1.4.6 与 §3.1 裁决（未投影命令 + `--detail` 等价现状）、S-2 由 §1.4.6 的 `action`/`coverage` 三级定义对齐、S-3 由 §2.4 + SDD-CLOSE-05 的 scope amendment 出口关闭、S-4 由 §3.6 的 `observedAt` + `rule` 义务关闭；**均未改写 `prd.md`**（该文件已随审批按 `evidence-digest` 钉住）。
