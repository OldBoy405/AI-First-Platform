---
id: CR-2026-076-plan
type: PLAN
cr-ref: CR-2026-076
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
status: draft
created: 2026-10-10T16:15:00+08:00
updated: 2026-10-10T18:10:00+08:00
---

# CR-2026-076 开发计划

> 修订 r2（2026-10-10，TASK-01 载体裁定同步；裁定原文 = Issue AIFI-62 评论 `01a1253d-ccdf-7112-947b-33f17dc212da`）：SDD r4 已按 §4.1 的 2a／2b 关联事实来源（既有认领载荷附加投影，`dep-35`）同步；本计划只同步 §5.5 的 cmd-01 观测面与静态前提（仍为 DB-free），TASK 集、依赖图、里程碑与验收口径不变。

承接已审批 `sdd.md`（`review-annotations/sdd.yml` attempt 3/3 PASS、`traceability.yml#reviews.tech-design` 3 次尝试末次 pass、`approval.yml#tech-design` 由 `crctl approve` 于 `2026-10-10T16:00:11+08:00` 以 `evidence-digest=aa94a012da350d702cd90ae41a7d0942d20f2809dac30e01e8acde859ac4af15` 落盘）。本计划的范围 = SDD §9 `scope_in` 的 **FR-01～FR-14、FR-SUP-01～FR-SUP-05、FR-SUP-06（错误根防线部分）、FR-SUP-07（写入边界安全校验与诊断口径部分）、FR-SUP-08、FR-SUP-09（本 CR 部分）** 与 **AC-01～AC-24、AC-SUP-01～AC-SUP-10（本 CR 侧）**；`scope_out`、`zero_diff`、`follow_up` 一律不做（尤其：不建影子账本、不新增 crctl 子命令、不改签名算法与 `rules.json` 白名单、不做平台 CR 投影 reconcile 根治、不把 AIFI-60 承接项做成本 CR 交付）。

交付仓分工（SDD §1.3、§1.5）：`tools` 承载 crctl 判定面、门禁／状态机／Pipeline 模板、受控写入入口、文档链校验与合同文本；`multica` 承载 daemon 绑定解析与任务 Git trust（+ 其包内测试）；`ai-first-platform-docs`（knowledge-base）只承载本 CR 文档与 `test-evidence/`，**无代码变更**。三仓代码事实与路径一律取 `crctl workspace inspect CR-2026-076 --workspace <workspace> --detail` 的 `resources[].worktreePath` 与 `operationalWorkspace` 原样值（本轮实测三仓 `classification=healthy`、`dirty=false`、`changed=false`、`operationalWorkspaceError=null`、分支 `requirement/CR-2026-076`），不按 `.rayai-worktrees/{repo}/requirement/{cr}` 命名拼接、不回退主工作区（SDD-CLOSE-04）。TASK 编号即 canonical 完整 id（`CR-2026-076-TASK-NN`），与 `tasks/_index.yml` 的 id 集一致。

本计划不含步骤粒度表述；步骤切分在 `write-dev-tasks` / `implement-code` 按 `coding-discipline` §2 执行。所有代码注释遵循目标仓约定（multica 仓注释为英文，tools 仓沿用其既有中文注释口径）。

## 1. 交付里程碑

| 里程碑 | 内容 | TASK | 预估（人天当量） |
|---|---|---|---|
| M1 multica 平台侧：可信绑定与 Git 身份 | 绑定解析新增「task／来源 Issue 唯一正式 CR 关联」段与错误项目根／阶段根写前拒绝；Git trust 由「替换全局配置」改为原生 `include` 叠加；核实 `repocache` 是否存在第二处 Git 配置写入点并同批收口 | TASK-01、TASK-02 | 3.5 |
| M2 绑定诊断与评审落盘闭环 | tools 侧绑定归一与只读诊断口径（`workspace inspect`／`status`／`next`）＋ crctl 合同文本同步；`review-record` 隔离提交、幂等与中断恢复；`next` 判定优先级与普通 BLOCK 回修 | TASK-03、TASK-04、TASK-05 | 5.0 |
| M3 门禁减负与流程 | 合法本地信任贯通（`warnings[]` 不参与通过判定，硬条件仍阻断）；默认 coding 去 dev-start（状态机 +1 声明、门禁组合、Pipeline 模板、Skill／矩阵同步）；认证人类「继续」一次一 cycle 与幂等 | TASK-06、TASK-07、TASK-08 | 5.5 |
| M4 tree 等价与最小重验 | `compareTree` 单一比较缝、合入等价推进、发布 source 固定与恢复分支、freshness 三段路由 | TASK-09、TASK-10 | 4.0 |
| M5 CI 收敛与文档链 | `suite-gate` 数量下降降为 warning 与四个 summary 宿主例外根因收敛（转绿后撤销登记）；Windows 文档链文件名提取与 `docCount` 断言 | TASK-11、TASK-12 | 3.0 |
| M6 owner／source 与交接核对 | owner `user_id` 值域校验与契约同步；`source` 自动绑定与注册前／使用前双防线；历史事实只读扫描与 `validate` 维度；PRD 交接完整性核对 | TASK-13、TASK-14、TASK-15、TASK-16 | 5.5 |
| M7 实际发布生效 | 平台消费者实际取用版本核对、已安装入口与真实 run 行为证据、人类动作与窗口落盘 | TASK-17 | 2.0 |

合计 28.5 人天当量（228h = 各 TASK 卡 `estimate` 之和，与 `tasks/_index.yml` 的 `taskCount=17`／`totalEstimateHours=228` 一致；含人类 owner 在 M7 执行的两次平台侧动作；TASK 粒度按 1～3 天切分，见各 TASK 卡）。

## 2. 任务依赖图

```text
M1  TASK-01（multica 绑定可信关联 + 错误根拒绝）
      └─> TASK-02（multica Git trust 叠加 + 身份保留）
      └─> TASK-03（tools 绑定归一 + 只读诊断口径 + crctl 合同同步）
             └─> TASK-04（review-record 隔离提交/幂等/恢复）
                    ├─> TASK-05（next 优先级 + 普通 BLOCK 回修）
                    └─> TASK-08（人类继续一次一 cycle）
             └─> TASK-06（合法本地信任贯通 + warning 分流）
                    ├─> TASK-07（默认 coding 去 dev-start）
                    └─> TASK-09（tree 比较缝 + 合入等价 + 发布 source 固定）
                           └─> TASK-10（freshness 最小重验）
             └─> TASK-11（suite-gate 数量门禁 + 宿主红例收敛）
M5  TASK-12（Windows 文档链真实扫描）—— 独立
M6  TASK-13（owner user_id 校验 + 契约同步）
      └─> TASK-14（source 自动绑定 + 双防线校验）
             └─> TASK-15（历史事实只读扫描 + validate 维度）
    TASK-16（PRD 交接完整性核对，KB 产物）—— 独立
M7  TASK-17（平台消费者取用版本 + 已安装入口 + 真实 run 证据）
            <── TASK-01～TASK-16 全部生产者（按仓顺序：tools 合同文本先于平台切消费者）
```

依赖说明：TASK-03 依赖 TASK-01 是**语义**依赖（诊断口径以已发布的绑定三元组语义为准），不是文件依赖；TASK-11 依赖 TASK-03 是因为四个 summary 宿主例外的根因是「夹具用系统临时目录 + 显式异根 `--workspace`」，其转绿判据由绑定归一的拒绝语义决定。其余依赖均为「产出 → 消费」的同一产物的前后关系。

## 3. 资源与分工

| TASK | 主责仓 | 依赖 | 主要产出 | 预估 |
|---|---|---|---|---|
| CR-2026-076-TASK-01 | multica | — | `server/internal/daemon/pipeline_task.go`（`resolveTaskWorkspaceBinding` 新增唯一正式 CR 关联段 + 写前拒绝）与其包内测试 | 2.0 |
| CR-2026-076-TASK-02 | multica | TASK-01 | `configureTaskGitEnvironment` 叠加式 `include` 配置；`repocache` 第二写入点核实结论与必要收口；英文注释与包内测试 | 1.5 |
| CR-2026-076-TASK-03 | tools | TASK-01 | `crctl` 诊断面（只读核对与失败关闭）用例补齐；`skills/shared/crctl/SKILL.md` 合同文本同步 | 1.5 |
| CR-2026-076-TASK-04 | tools | TASK-03 | `cmdReviewRecord` 的 write-set／隔离提交／恢复／幂等（复用 `durable-tx` 与 `ledgerTxKey`；不新增幂等账本） | 2.0 |
| CR-2026-076-TASK-05 | tools | TASK-04 | `cmdNext` 判定优先级与「对象已变／未变」分支；`skills/cr/cr-review-record/SKILL.md`、`skills/develop/*` 相关合同文本 | 1.5 |
| CR-2026-076-TASK-06 | tools | TASK-03 | `runGateChecks`／`cmdApprove`／`cmdValidate`／`cmdMerge` 同判与 `warnings[]` 扩展形式；`review-code`／`review-dev-plan`／`write-test-report` 的 Skill 文本 | 1.5 |
| CR-2026-076-TASK-07 | tools | TASK-05、TASK-06 | `dir-graph.yaml#change-request-track.state_machine`（+1 声明）、`gates.json`、`pipeline-templates/code-implementation.pipeline.json`、`skills/develop/write-dev-tasks/SKILL.md` 收尾职责、`skills/develop/approve-dev-start/SKILL.md` 兼容说明、`skills/cr/inbox-emit/SKILL.md` 映射来源、`agent-skill-matrix.yml`＋`AGENT-SKILL-MATRIX.md`＋`agents/_index.yml`＋三份 agent 文本 | 2.5 |
| CR-2026-076-TASK-08 | tools | TASK-04 | `review-loop reset --continue-reason` 的认证来源判定与幂等；`skills/sync/handover-cr` 相关契约说明 | 1.5 |
| CR-2026-076-TASK-09 | tools | TASK-06 | `lib/workspace-transactions.mjs` 单一 `compareTree` 缝；`cmdMerge` 等价推进；发布 source 固定与恢复分支（`cmdCheckpoint`） | 2.5 |
| CR-2026-076-TASK-10 | tools | TASK-09 | freshness 三段路由输出与 `skills/sync/workspace-freshness/SKILL.md`、`skills/sync/push-progress/SKILL.md` 文本 | 1.5 |
| CR-2026-076-TASK-11 | tools | TASK-03 | `suite-gate.mjs` 数量下降 warning；`gate-registry.json` 四个宿主例外根因收敛与撤销；夹具同安装根化 | 2.0 |
| CR-2026-076-TASK-12 | tools | — | `skills/shared/engineering-docs/scripts/src/validators/chain.ts`（`node:path.basename` + `docCount` 断言）与其 vitest 用例 | 1.0 |
| CR-2026-076-TASK-13 | tools | — | `cmdRegister`／`cmdOwnerSet` 共用 owner 值域校验缝；`skills/requirement/requirement-register/SKILL.md` 与 Pipeline owner 输入示例同步 | 1.5 |
| CR-2026-076-TASK-14 | tools | TASK-13 | `source` 自动绑定与注册前 containment／可读性校验；使用前防线保留；`skills/sync/handover-cr/SKILL.md` 错误语义 | 1.5 |
| CR-2026-076-TASK-15 | tools | TASK-13、TASK-14 | 版本化只读扫描（owner 身份异常 + `source` 路径异常）与 `validate` 只读维度 `owner-source-anomalies`；单文件测试 | 1.5 |
| CR-2026-076-TASK-16 | ai-first-platform-docs | — | PRD 交接完整性核对记录（`prd-path` 指向分支内实际文件、FR-SUP／AC-SUP 编号保留、checkpoint 据实报告） | 1.0 |
| CR-2026-076-TASK-17 | multica + tools + 人类 owner | TASK-01～TASK-16 | 平台侧同步清单、已安装入口版本与真实 run 行为证据、`test-evidence/effective-version.md`、三个 summary 例外外的发布生效核对 | 2.0 |

## 4. 风险与回滚策略

| 风险 | 触发面 | 应对 | 回滚单位 |
|---|---|---|---|
| Git trust 改叠加式后身份丢失（或反向：全局配置被写） | TASK-02（`configureTaskGitEnvironment`） | 用 `include.path` 叠加而非替换；`GIT_CONFIG_GLOBAL` 仍指向任务内配置且**只含 safe.directory 与 include 两段**；身份缺失在新账本写入前失败关闭；`repocache` 第二写入点实施期先核实（SDD §10「待核实依赖」），存在则同批收口 | revert TASK-02（含其包内测试），随后按逆拓扑 revert TASK-01 |
| 绑定新解析段误把非唯一关联当唯一目标 | TASK-01 | 0／多命中一律拒绝（沿用 `findPipelineCRRoot` 基数语义），普通无 CR 信号任务保持原行为；失败关闭零业务写入 | revert TASK-01（TASK-03 的诊断口径只读，无下游代码依赖） |
| `warnings[]` 减负被误用成「放宽通过判定」 | TASK-06、TASK-07 | warning 不参与 `evaluatePassCondition`（`dep-18`）；AC-10～AC-13 的正反两面都在同一 cmd 内断言（合法变化仅 warning，必需产物缺失／结构非法／blockers 非空／真实测试失败仍硬阻断） | revert TASK-06 → TASK-07 → TASK-05 → TASK-04 → TASK-03 |
| 状态机 +1 声明与门禁／模板／Skill／矩阵任一处不同步 | TASK-07 | 由 `gate-registry.json#stateMachine` 独立登记 + `crctl.test.mjs` 的「推导 ≡ 登记」断言（仓库不变量）与 pipeline／contract 组用例双面钉住；`approve-dev-start` 保留为兼容路径，不是默认必经 | revert TASK-07（文本与模板；`approve-dev-start` 转换未删除，回退不破历史 CR） |
| tree 等价比较被当成「跳过复评」 | TASK-09、TASK-10 | 比较缝只产出「对象是否等价」事实，不替代真实测试与远端发布检查；等价判定必须带 SHA 追溯；dirty／diverged／unknown 仍按原技术失败合同处理 | revert TASK-10 → TASK-09（先回滚消费面） |
| `suite-gate` 四个宿主例外撤销后暴露真实红例 | TASK-11 | 先复现根因（夹具系统临时目录 + 显式异根 `--workspace`），把夹具改为同安装根内临时根并复用既有 `baseEnv`；转绿后撤销例外条目，不静默续期；到期即清 | revert TASK-11（登记面与夹具同批回退，例外条目随回复原） |
| `owner-source-scan` 只读扫描被误做成自动修复 | TASK-15 | 扫描只报告（CR-ID、字段／角色、原值、异常原因），不写受控账本、不阻塞无关 CR、不建定时巡检；修复只经既有受控入口由人工裁决 | revert TASK-15 → TASK-14 → TASK-13 |
| 实际发布生效核对变成「源码已改即算完成」 | TASK-17 | 判据固定为「安装后新 run 的目标行为证据 + 实际取用版本记录」（SDD-CLOSE-08）；启动自述不构成证据；`cmd-15` 断言启动回执载明现场入口版本、`cmd-14` 断言平台 Skill 取用内容与仓库目标逐字一致 | revert TASK-17（证据与清单；平台侧消费者切换由人类 owner 按同一清单以仓库目标文本回退） |
| 环境前提不可得（无 Node／Go、依赖未安装、安装环境不可用） | 全部 TASK | 按 §5.2 的 readiness 证据即时验证；前提无法建立且修复超出权限时以 `ENVIRONMENT_MISMATCH` 技术中止（该标签的唯一详细事实源是 `implement-code`，本计划只引用不复述） | 不适用（技术中止，不推进状态） |

**回滚逆拓扑顺序（与交付覆盖表「回滚」列一致）**：`TASK-17 → TASK-16 → TASK-15 → TASK-14 → TASK-13 → TASK-12 → TASK-11 → TASK-10 → TASK-09 → TASK-08 → TASK-07 → TASK-06 → TASK-05 → TASK-04 → TASK-03 → TASK-02 → TASK-01`。任何单点 revert 都必须先确认其下游消费者已回退：共享改动只有 `TASK-03`（诊断与合同文本，被 TASK-04／TASK-06／TASK-11 消费）与 `TASK-09`（比较缝，被 TASK-10 消费）两处，故这两处不得声明为单点回滚。远端发布事实由 `crctl checkpoint` 收口，本地 revert 不等于远端回退（`dep-21`）。

## 5. 验收与发布策略

### 5.1 发布前 checklist

1. 三仓 CR worktree `classification=healthy`、`dirty=false`，且本次验收运行前 `crctl workspace inspect CR-2026-076 --workspace <workspace> --detail` 原样值已记入 `test-evidence/`。
2. 每条 `cmd-NN` 真实执行、退出码与 `test-evidence/cmd-NN.log` 原样落盘；`test-evidence/` 内不出现未执行却声称通过的行。
3. `review-dev-plan` PASS 且 blockers 为空；TASK 全部在 `tasks/_index.yml` 登记（`done` 于实现期逐个即时标记，不积压到回写期）。
4. SDD §9 `zero_diff` 面零触碰（签名算法、状态集合、`rules.json` 受控路径与白名单 shape、crctl 子命令集合、`specs/`／`delivery/` 权威路径、用户全局 Git 配置本体、生产已注入的绑定变量）。
5. TASK 完成边界全部落在 `developing` 内（`crctl task done` 可登记），不以 `merge`／`writeback`／`archive`／`code-approved` 为完成前置。
6. FR-14 的人类动作清单（§5.4）已执行，`test-evidence/fr14-launch-receipt.md` 与 `test-evidence/fr14-run-behavior.md` 原样在位。

### 5.2 环境静态前提（owner、建立方式、可获得性；只确认静态事实，不要求审批时服务在线）

| 环境 | owner | 建立方式 | 可获得性 | readiness 证据（复用既有 `cmd-NN`） |
|---|---|---|---|---|
| 本地 Node 运行时（`node --test` 单文件形态） | dev-agent（既有开发机运行时） | 无需新建；沿用既有安装 | 本 CR 全部 tools 证据命令的运行前提 | cmd-04 |
| Go 工具链 + multica `server` 模块 | dev-agent | 无需新建；`go test` 直读模块，不依赖 DB／消息队列／外部服务 | `go` 与模块缓存可用 | cmd-01 |
| engineering-docs 脚本依赖（vitest） | dev-agent | 在 tools CR worktree 的 `skills/shared/engineering-docs/scripts` 内按 `pnpm-lock.yaml` 做**目录内**依赖安装（一次性准备，不新增常驻服务） | 锁文件在位且包源可达 | cmd-12 |
| multica CLI／daemon 安装环境（安装根 + 桌面监督进程） | Ray（人类，平台管理员） | 由维护来源既有构建／安装流程安装 CR worktree 版本，并重启桌面监督一次（FR-14 授权的单次人工启动前置） | `multica --version`、`multica daemon status --output json` 可读；平台服务 `http://localhost:8080` 既有常驻 | cmd-15 |
| 平台元数据读取面（imported Skill／Agent 记录） | Ray | 既有平台服务，本 CR 只读消费 | `multica skill list`／`skill get`／`agent list` 可取 | cmd-14 |

**缺失时处置**：readiness 证据未通过（命令非零、产物缺失、依赖未安装）时，按既有 `ENVIRONMENT_MISMATCH` 标签中止并报告所需建立动作，不静默降级、不以「本地可跑」替代安装环境事实、不轮询等待。

### 5.3 发布策略与 feature 开关

本 CR 不引入 feature flag：所有改动都是既有判定面的定点修订，默认路径即时生效；唯一需要「先后顺序」的是消费者切换（§5.4 第 1、2、3 条按 tools 合同文本 → 平台 Skill 取用 → multica CLI／daemon 安装的顺序执行，生产者先兼容新合同再切消费者，SDD §4.13）。回退不使用开关，按 §4 的逆拓扑 revert。

### 5.4 人类动作、责任方、窗口与可达入口（FR-14 / SDD-CLOSE-06）

| # | 动作 | 责任方 | 窗口 | 可达入口 | 证据落点 |
|---|---|---|---|---|---|
| 1 | 按维护来源既有导入／发布流程，把本 CR §8 变更的 Skill 目标文本同步到平台（imported Skill 取用内容更新） | Ray（人类，平台管理员） | M7，TASK-17 执行窗口内，早于代码审批；不依赖 merge／writeback | 平台既有 Skill 导入／发布流程（本计划不写具体命令） | `cmd-14` 的逐项实际取用版本记录 + `test-evidence/effective-version.md` |
| 2 | 构建并安装 multica CLI／daemon 的 CR 版本到安装根 | Ray | 同上 | 维护来源既有构建／安装流程 | `cmd-15` 的 `multica --version`／`daemon status` 原样输出 |
| 3 | 重启桌面监督（daemon）一次使新版本生效 | Ray | 同上 | 桌面应用既有重启入口 | `multica daemon status --output json` 原样输出（进程 uptime／版本） |
| 4 | 以更新后的**已发布**入口启动一次真实 run（受控任务），不使用候选 CLI 作正式治理 | Ray | 同上 | 平台既有派发入口 | `test-evidence/fr14-launch-receipt.md`（执行者原样回执，含实际使用的入口与其版本输出） |
| 5 | 提供该次 run 在安装环境留下的目标行为证据原样结果 | 执行者（Ray）提供原样事实，dev-agent 原样落盘（不加工、不改写） | 同上 | 同上 | `test-evidence/fr14-run-behavior.md` |

说明：①「已人工启动」的自述**不构成证据**，只有可核验产物计入（SDD §4.13）；②平台侧写入动作全部由有权限的人类 owner 执行，agent 不写平台配置；③`tools/agents/*.md` 三份文本的平台取用版本按记录型观测（其平台部署副本通道 `multica/cr-prompts-revised/*.md` 不在 SDD §1.5 变更面内，本计划不据以声称指令同步完成，也不把该通道纳入本 CR 的仓库变更面）；④本 CR 不接受逐节点人肉代跑，只接受上表这一次有边界的人工启动前置。

### 5.5 证据范围与定向口径（每个 `cmd-NN` 的真实运行范围与观测面）

命令算法唯一事实源 = §6.2 证据命令表行。以下逐条写明真实运行范围与观测面，**均不声称全量**（唯一例外是 `cmd-11`，见其条目）：

- **cmd-01**：`multica/server` 包内 `./internal/daemon/` 单包的定向子集（`-run` 正则名集，命中 11 个测试函数），观测「绑定三元组解析与拒绝面、认领载荷 CR 关联投影的消费（task 正式关联／来源 Issue 唯一关联／多值拒绝／无信号不变）、绑定发布到任务环境、preflight 投影注入、CR 根基数与 workspace 健康预检」；不声称 multica 仓全量通过。**形态说明**：该行的 `args` 值内含正则交替符（同一字符也是 Markdown 表格分隔符），本表按 CR-2026-075 既有证据行形态原样写入，读取时须把 `args` 单元格内全部 `|` 视为 JSON 字符串内容；实现期新增用例必须落在该 `-run` 名集已命中的函数名下（或写成既有函数内的子测试），使本命令的观测面随实现同步扩大，不得另行新增未出现在本表的命令。
- **cmd-02**：同上单包的定向名集（4 个测试函数），观测「任务 Git 环境的叠加式配置、`GIT_CONFIG_GLOBAL` 指向与失败关闭」；形态说明同 cmd-01；不覆盖 `repocache` 包（由 cmd-03 承担）。
- **cmd-03**：`multica/server` 的 `./internal/daemon/repocache/` 单包全文件，观测「身份加载与共享缓存隔离、外键 worktree 拒绝、锁失败可重试」——用于 FR-02 的「第二处 Git 配置写入点」核实结论；不声称 `internal/daemon` 全包通过。
- **cmd-04**：tools 仓单文件 `skills/shared/crctl/scripts/test/crctl.test.mjs`（`node --test`，同目录；当前登记 237 顶层用例；凡改动该文件顶层用例数的 TASK 必须在其变更内据实更新 `gate-registry.json#manifest.cases` 的对应条目，本 CR 由 TASK-11 在其变更内对 `manifest.cases` 全部条目做一次据实收口——见本节末「登记面所有权」），观测 crctl CLI 层的绑定归一只读诊断与失败关闭（`WORKSPACE_CONTEXT_MISMATCH`／`WORKSPACE_REQUIRED`）、`next` 判定优先级、`approve`／`gate`／`validate` 的本地信任告警分流、`review-record` 的 CLI 出口、`review-loop reset`、owner／source 写入前校验缝、状态机 32 条声明的「推导 ≡ 登记」不变量；**不声称覆盖 crctl 全部子命令行为**，也不声称覆盖 `lib/` 模块内部语义（由 cmd-05～cmd-08 承担）。
- **cmd-05**：tools 仓三文件 `caller-contract.test.mjs` + `fault-harness.test.mjs` + `durable-tx.test.mjs`，观测 `review-record` 的调用方契约、故障注入下的恢复分支与共享事务原语（write-set／CAS／回滚／`ledgerTxKey` 幂等）；不声称覆盖 `workspace-transactions.mjs` 的其他命令面。
- **cmd-06**：tools 仓两文件 `register-tx.test.mjs` + `owner-source-scan.test.mjs`（后者由 TASK-15 新建的同目录单文件），观测注册事务的 owner／`source` 校验与零写入、`validate` 只读维度 `owner-source-anomalies` 与版本化只读扫描的只报告语义；不声称扫描覆盖全量历史之外的运行时状态。本 TASK 新建的 `owner-source-scan.test.mjs` 与 `gate-registry.json#manifest.files`／`manifest.cases` 的登记**由 TASK-15 在同一变更内落盘**（见本节末「登记面所有权」）。
- **cmd-07**：tools 仓三文件 `merge-tx.test.mjs` + `checkpoint-tx.test.mjs` + `workspace-resolver.test.mjs`，观测单一 `compareTree` 缝的等价／不等价判定、合入等价推进、发布 source 固定与恢复分支、参与仓解析；真正涉及 Git 的调用一律走 `rules.json` 已允许的受控入口（不新开裸面、不改 `rules.json`）。
- **cmd-08**：tools 仓单文件 `workspace-freshness.test.mjs`，观测 fresh／behind-clean／diverged／unknown 四态与三段路由（接续／最小复评／技术失败）；不声称覆盖 `workspace inspect` 的其他输出面。
- **cmd-09**：tools 仓六文件 `pipeline-structure.test.mjs` + `contract-scan.test.mjs` + `check-skill-matrix.test.mjs` + `check-agents-contract.test.mjs` + `lint-prompts.test.mjs` + `skill-scope.test.mjs`，观测 Pipeline 模板结构、Skill／Agent 合同文本与权限矩阵的一致性（FR-06 去 dev-start 同步、FR-SUP-02 owner 示例口径、FR-SUP-07 诊断与失败关闭口径）；不声称覆盖业务逻辑行为（由 cmd-04～cmd-08 承担）。
- **cmd-10**：tools 仓单文件 `crctl-summary.test.mjs`，观测四个 summary 宿主例外（`summary-03`～`summary-06`）根因修复后的转绿；这是撤销 `gate-registry.json#exceptions` 条目的直接判据，不声称覆盖其他文件。
- **cmd-11**：`node skills/shared/crctl/scripts/test/suite-gate.mjs --run`（**本 CR 唯一的全仓命令**）。依据：AC-23 明确要求「少跑、未登记／不一致文件集合、零有效执行、加载／TAP／真实失败、非法例外」仍被拒绝，并要求四个宿主例外逐项复现／根因回归后**转绿并撤销对应例外**——这三个判定面（文件集合一致性、零有效执行、例外登记面）只在登记表完整范围内可观测，属已批准 AC 明确要求的全量命令，满足 CR-2026-073 FR-6 的例外条件。不声称覆盖未登记在 `manifest.files` 的文件，也不把上游同步（`CUSTOM.md` 全量 + Windows 已知失败原文）口径混入本 CR 的绿色判据。该命令的登记面判据是**严格集合相等**（`suite-gate.mjs:441`／`:531` 比较、`:442`／`:532` 触发 `SUITE_MANIFEST_FILE_DRIFT`；磁盘集合事实源 `assertion-sources.mjs:88-97` 取登记目录内非递归全量 `*.test.mjs`），且 `:536` 只 spawn `declared` 列表——故本 CR 新建的两个测试文件必须登记，登记同批生效后即进入本命令的真实执行面（登记 owner 见本节末「登记面所有权」）。
- **cmd-12**：tools 仓 `skills/shared/engineering-docs/scripts` 目录内单文件 `src/__tests__/chain.test.ts`（vitest 单文件），观测 Windows 反斜杠与原生嵌套目录下 `docCount > 0` 的真实扫描；前置为该目录内依赖已按 `pnpm-lock.yaml` 安装（§5.2）。不声称 engineering-docs 全部测试通过（generators／validators 不在本 CR 声称面内）。
- **cmd-13**：knowledge-base CR worktree 根目录内的只读脚本（`repo=ai-first-platform-docs`、`cwd=.`，即 `operationalWorkspace` 自身），观测 `_backlog.yml#prd-path` 指向的文件在分支内实际存在、PRD 保留 FR-SUP-01…09 与 AC-SUP-01…10 编号（逐号存在并打印次数）、需求评审 `verdict=pass`；**不声称**以字符串计数证明实质覆盖——实质覆盖由独立需求评审（`review-annotations/requirement.yml`）判定，本命令只做交接完整性核对（不与 AC-SUP-10 的「不能只检查字符串数量」冲突：本命令不产生正确性结论，只记录机械事实）。
- **cmd-14**：tools 仓 CR worktree 内的只读单文件测试（`skills/shared/crctl/scripts/test/publish-effectiveness.test.mjs`，由 TASK-17 新建），观测平台 imported Skill 的**实际取用版本**：对 SDD §8 变更的 Skill 集合，逐项取 `multica skill get --with-content` 的线上内容与 tools CR worktree 目标文件逐字比较（`\r\n → \n` 归一、尾空行归一），并打印每项的 origin（repo／ref／path）与内容 sha256；对三份 CR Agent instructions 只**打印**线上版本 sha256（记录型观测，不做相等断言，理由见 §5.4 说明③）。不声称覆盖未在 §8 声明变更的 Skill。本 TASK 新建的 `publish-effectiveness.test.mjs` 与 `gate-registry.json#manifest.files`／`manifest.cases` 的登记**由 TASK-17 在同一变更内落盘**（见本节末「登记面所有权」）。
- **cmd-15**：knowledge-base CR worktree 根目录内的只读脚本，观测「已安装入口的实际版本」与「真实 run 证据」：spawn `multica --version` 与 `multica daemon status --output json` 打印现场版本并断言两者同版本；断言 `test-evidence/fr14-launch-receipt.md` 非空且载明现场入口版本；断言 `test-evidence/fr14-run-behavior.md` 非空。不声称覆盖被启动 run 的业务结果正确性（该事实由行为证据原样文本承载，由人工与评审消费）。

**登记面所有权（`gate-registry.json`：`manifest.files` 与 `manifest.cases`）**：`skills/shared/crctl/scripts/test/` 是本 CR 全部 `suite-gate` 判定的登记目录，其集结合同是**严格集合相等**，因此登记不是收尾动作而是产物本身：

1. **谁新建文件，谁同批登记**：新建／改名／删除该目录内 `*.test.mjs` 的 TASK，必须在**同一变更**内同步 `gate-registry.json#manifest.files`，并为新文件写入整数型 `manifest.cases` 基线（该文件真实顶层用例数）。缺项与非整数基线由 `SUITE_MANIFEST_CASE_DROP` 判定（`suite-gate.mjs:452`）；低于基线经 FR-12 后仅是 warning（`:453`）。本 CR 的登记 owner 恰两张卡：**TASK-15**（`owner-source-scan.test.mjs`，cmd-06 的第二个文件）与 **TASK-17**（`publish-effectiveness.test.mjs`，cmd-14）。
2. **登记面 owner = TASK-11**：它拥有 `gate-registry.json` 与 `suite-gate.mjs`，负责 (a) 保持「文件集合不一致」（`SUITE_MANIFEST_FILE_DRIFT`）与「零有效执行」仍为**硬失败**，不随 FR-12 的数量下降 warning 一并放宽；(b) 在其变更内对 `manifest.cases` 全部条目（含 `crctl.test.mjs`）据实收口一次并留证；(c) 回滚单位为「登记面与夹具同批」（§4 风险表）。
3. **基线是下界**：`manifest.cases` 的判据是「实际顶层用例数 `<` 基线」，故其后 TASK 追加用例不会使 M5 收口的基线失真（TASK-13／TASK-14 在 M6 追加 `crctl.test.mjs` 用例属此情形）；反之，任何**净减少**某文件顶层用例数的 TASK 必须在其同批内据实下调该基线并在结果中写明原因，不得让 warning 掩盖真实减少。

## 6. 两张稳定表（契约必填节）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-01 机器保证启动前可信绑定 | §4.1 判定顺序 2a、§6.1（`resolveTaskWorkspaceBinding` 新增 task／来源 Issue 唯一正式 CR 关联段，`dep-5`；crctl `bindTaskWorkspace` 保持失败关闭，`dep-1`／`dep-2`） | CR-2026-076-TASK-01（关联 TASK-03） | cmd-01 + cmd-04 | revert TASK-01；TASK-03 消费绑定对发布面，按逆拓扑先回退 TASK-03 |
| FR-02 任务 Git trust 保留用户身份 | §4.2 + D-01、§2.2 E6（`GIT_CONFIG_GLOBAL` 叠加式 `include`，`dep-6`；`repocache` 第二写入点核实） | CR-2026-076-TASK-02 | cmd-02 + cmd-03 | revert TASK-02；TASK-01 是其上游生产者，须最后回退 |
| FR-03 review-record 写入与隔离提交原子闭环 | §4.3 + SDD-CLOSE-01（write-set／隔离提交／恢复／幂等；复用 `dep-12`、`dep-13`、`dep-34`，不新增第二幂等账本） | CR-2026-076-TASK-04 | cmd-04 + cmd-05 | 逆拓扑：先 revert TASK-05、TASK-08（消费者），再 revert TASK-04 |
| FR-04 普通 BLOCK 回修与 next 收尾一致 | §4.4（`cmdNext` 判定优先级与对象变化分支；`dep-16`、`dep-17`） | CR-2026-076-TASK-05 | cmd-04 | revert TASK-05；TASK-07 消费其 `next` 判定，按逆拓扑先回退 TASK-07 |
| FR-05 G01/G02 合法本地信任贯通 | §4.5 + D-04 + SDD-CLOSE-05（`warnings[]` 扩展形式；`runGateChecks`／`cmdApprove`／`cmdValidate`／`cmdMerge` 同判；`dep-18`、`dep-19`、`dep-20`） | CR-2026-076-TASK-06 | cmd-04 + cmd-07 | revert TASK-06；TASK-09 消费 warning 分流，按逆拓扑先回退 TASK-09、TASK-10 |
| FR-06 G03 默认 coding 取消重复开发启动确认 | §4.6、§3.3、§8（状态机 +1 声明、`gates.json` `developing` 判定组合、Pipeline 模板去必经节点、Skill／矩阵／Agent 合同同步；`dep-24`～`dep-26`） | CR-2026-076-TASK-07 | cmd-09 + cmd-04 | revert TASK-07（模板与合同文本；`approve-dev-start` 兼容转换未删除，回退不破历史 CR） |
| FR-07 G04 人类继续一次一 cycle | §4.7 + D-03（认证触发事实为输入，不以 `--confirm`／TTY 作唯一通路；幂等与失败只恢复原操作；`dep-20`） | CR-2026-076-TASK-08 | cmd-04 | revert TASK-08；TASK-04 是其上游生产者，须最后回退 |
| FR-08 G05/G06 共用整个 Git tree 内容比较 | §4.8 + D-02（`compareTree` 单一缝落在 `workspace-transactions.mjs`，不在 crctl 内双实现；`dep-14`） | CR-2026-076-TASK-09 | cmd-07 | 逆拓扑：先 revert TASK-10（消费者），再 revert TASK-09 |
| FR-09 G05 合入对象与发布意图核验 | §4.8、§4.10（`cmdMerge` 等价推进与发布 source 固定；`dep-15`、`dep-21`） | CR-2026-076-TASK-09 | cmd-07 | 同 FR-08（先 revert TASK-10，再 revert TASK-09） |
| FR-10 G06 同步后的最小重验 | §4.9（freshness 三段路由输出；`dep-7`） | CR-2026-076-TASK-10 | cmd-08 | revert TASK-10（含其 Skill 文本）；TASK-09 是其上游生产者，须最后回退 |
| FR-11 代码源不可判时恢复或建立新证据 | §4.8 恢复分支（先复原对象、否则新建测试／评审事实；不以当前 HEAD 补历史） | CR-2026-076-TASK-09 | cmd-05 + cmd-07 | 同 FR-08（先 revert TASK-10，再 revert TASK-09） |
| FR-12 G07 数量下降告警与既有红例收敛 | §4.11（`suite-gate` 数量下降 warning 与仍拒绝面、四个 summary 例外根因收敛与撤销；`dep-22`） | CR-2026-076-TASK-11（登记面 owner；关联 TASK-15／TASK-17 各自新文件的同批登记） | cmd-10 + cmd-11 | revert TASK-11（登记面与夹具同批回退）；TASK-03 是其上游，须最后回退 |
| FR-13 Windows chainCheck 真实扫描 | §4.12 + D-05（`node:path.basename` + `docCount` 断言；`dep-23`） | CR-2026-076-TASK-12 | cmd-12 | revert TASK-12（单文件与用例，无下游代码消费者） |
| FR-14 实际发布生效与合法执行边界 | §4.13 + SDD-CLOSE-08（消费者实际取用版本核对、计划承载人类动作与窗口、判据不采源码合入／构建；`dep-8`、`dep-30`） | CR-2026-076-TASK-17 | cmd-14 + cmd-15 | revert TASK-17（证据与同步清单）；平台侧消费者切换由人类 owner 按同一清单以仓库目标文本回退 |
| FR-SUP-01 三角色 owner 使用成员 user_id 且写入前校验 | §4.14（`cmdRegister`／`cmdOwnerSet` 共用校验缝；`dep-31`、`dep-32`） | CR-2026-076-TASK-13 | cmd-06 + cmd-04 | 逆拓扑：先 revert TASK-15、TASK-14（消费者），再 revert TASK-13 |
| FR-SUP-02 owner 契约与示例同步 | §4.14、§8（register Skill + Pipeline 输入示例；`dep-29`、`dep-33`） | CR-2026-076-TASK-13 | cmd-09 + cmd-06 | 同 FR-SUP-01 |
| FR-SUP-03 source 自动绑定与空值语义 | §4.15（创建入口 + `register.source` 持久化语义；含「入库通道待核实」二选一分支） | CR-2026-076-TASK-14 | cmd-06 + cmd-04 | 逆拓扑：先 revert TASK-15（消费者），再 revert TASK-14 |
| FR-SUP-04 source 的注册前与使用前校验 | §4.15（containment + 可读性双防线，使用前防线不因入口已校验而删除） | CR-2026-076-TASK-14 | cmd-06 + cmd-04 | 同 FR-SUP-03 |
| FR-SUP-05 注册阶段与阶段根的可信交接 | §4.1、§4.14（注册节点绑定 KB 主 checkout，返回后经 `workspace inspect` 复核；`dep-7`、`dep-26`） | CR-2026-076-TASK-01 | cmd-01 | revert TASK-01；TASK-03 的诊断口径须先回退 |
| FR-SUP-06 错误根防线（本 CR 部分） | §4.1（启动前失败关闭与错误项目根／阶段根写前拒绝；`dep-5`、`dep-7`；reviewer 派发部分按 §1.2 移交 AIFI-60） | CR-2026-076-TASK-01 | cmd-01 | 同 FR-SUP-05 |
| FR-SUP-07 作者／评审者开工检查与诊断安全合同（本 CR 部分） | §4.1（`workspace inspect`／`status`／`next` 只读核对 + `WORKSPACE_CONTEXT_MISMATCH` 失败关闭；`dep-1`、`dep-2`） | CR-2026-076-TASK-03 | cmd-04 + cmd-09 | revert TASK-03；TASK-04／TASK-06／TASK-11 是其消费者，按逆拓扑先回退 |
| FR-SUP-08 历史事实的一次性检查与受控定点修复 | §4.16（版本化只读扫描 + `validate` 只读维度；只报告不修复、不建巡检；`dep-19`） | CR-2026-076-TASK-15 | cmd-06 + cmd-04 | revert TASK-15（扫描与维度用例，无下游代码消费者） |
| FR-SUP-09 PRD 交接完整性与节点完成判定（本 CR 部分） | §4.17（`prd-path` 与实际文件一致、checkpoint 据实报告；节点完成判定移交 AIFI-60） | CR-2026-076-TASK-16 | cmd-13 | revert TASK-16（核对记录，无下游代码消费者） |

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | multica | server | go | ["test","./internal/daemon/","-count=1","-v","-run","Test(ResolveTaskWorkspaceBinding|InjectTaskCRWorkspaceEnv|ParseExecutionContext|TaskWorkspaceBinding|PipelinePromptCarriesTheVerifiedExecutionContext|FindPipelineCRRootCardinality|PreparePipelineTaskHydratesMachineLocalPaths|PreparePipelineTaskDirtyGate|InspectPipelineWorkspaceDirtyInput|InspectPipelineWorkspaceDetailContract|DaemonEnvBuildHasNoConfigFirstRootFallback)"] | 900 |
| cmd-02 | multica | server | go | ["test","./internal/daemon/","-count=1","-v","-run","Test(ConfigurePipelineGitEnvironment|ConfigureTaskGitEnvironment|PreparePipelineTaskHydratesMachineLocalPaths|InjectTaskCRWorkspaceEnv)"] | 900 |
| cmd-03 | multica | server | go | ["test","./internal/daemon/repocache/","-count=1","-v"] | 900 |
| cmd-04 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/crctl.test.mjs"] | 900 |
| cmd-05 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/caller-contract.test.mjs","skills/shared/crctl/scripts/test/fault-harness.test.mjs","skills/shared/crctl/scripts/test/durable-tx.test.mjs"] | 900 |
| cmd-06 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/register-tx.test.mjs","skills/shared/crctl/scripts/test/owner-source-scan.test.mjs"] | 600 |
| cmd-07 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/merge-tx.test.mjs","skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs","skills/shared/crctl/scripts/test/workspace-resolver.test.mjs"] | 900 |
| cmd-08 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/workspace-freshness.test.mjs"] | 600 |
| cmd-09 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/pipeline-structure.test.mjs","skills/shared/crctl/scripts/test/contract-scan.test.mjs","skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs","skills/shared/crctl/scripts/test/check-agents-contract.test.mjs","skills/shared/crctl/scripts/test/lint-prompts.test.mjs","skills/shared/crctl/scripts/test/skill-scope.test.mjs"] | 600 |
| cmd-10 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/crctl-summary.test.mjs"] | 600 |
| cmd-11 | tools | . | node | ["skills/shared/crctl/scripts/test/suite-gate.mjs","--run"] | 3600 |
| cmd-12 | tools | skills/shared/engineering-docs/scripts | node | ["node_modules/vitest/vitest.mjs","run","src/__tests__/chain.test.ts"] | 600 |
| cmd-13 | ai-first-platform-docs | . | node | ["-e","const fs=require('fs'),cp=require('crypto');const NL=String.fromCharCode(10),CR=String.fromCharCode(13);const LD=p=>fs.readFileSync(p,'utf8').split(CR+NL).join(NL);const bad=[];const B=LD('change-requests/_backlog.yml').split(NL);let inCr=false,prdPath='';for(const l of B){if(l.indexOf('  - id: CR-2026-076')===0){inCr=true;}else if(inCr&&l.indexOf('  - id: ')===0){inCr=false;}if(inCr&&l.indexOf('prd-path:')>=0){prdPath=l.split('prd-path:')[1].split(String.fromCharCode(34)).join('').trim();}}const okFile=prdPath?fs.existsSync(prdPath):false;if(!okFile){bad.push('prd-path 未指向分支内实际文件: '+prdPath);}else{console.log('prd-path='+prdPath+' sha256='+cp.createHash('sha256').update(LD(prdPath)).digest('hex'));}const prd=okFile?LD(prdPath):'';const ids=[];for(let i=1;i<=9;i++){ids.push('FR-SUP-0'+i);}for(let i=1;i<=10;i++){ids.push('AC-SUP-'+(i<10?'0'+i:String(i)));}const cnt=[];for(const id of ids){const n=prd.split(id).length-1;cnt.push(id+'='+n);if(n<1){bad.push('PRD 未见编号: '+id);}}console.log('编号出现次数: '+cnt.join(' '));const ann='change-requests/CR-2026-076/review-annotations/requirement.yml';const at=fs.existsSync(ann)?LD(ann).split(NL):[];if(!at.some(l=>l.trim()==='verdict: pass')){bad.push('需求评审 verdict 非 pass: '+ann);}if(bad.length){console.error(bad.join(NL));process.exit(1);}console.log('cmd-13 ok: prd-path 指向分支内实际文件；FR-SUP-01…09 与 AC-SUP-01…10 逐号存在；需求评审 verdict=pass（实质覆盖由独立需求评审判定，本命令不作正确性结论）');"] | 300 |
| cmd-14 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/publish-effectiveness.test.mjs"] | 600 |
| cmd-15 | ai-first-platform-docs | . | node | ["-e","const fs=require('fs'),cp=require('child_process'),cr=require('crypto');const NL=String.fromCharCode(10),CR=String.fromCharCode(13);const LD=p=>fs.readFileSync(p,'utf8').split(CR+NL).join(NL);const RD=p=>fs.existsSync(p)?LD(p):'';const bad=[];const S=x=>x?String(x):'';const run=(c,a)=>{const r=cp.spawnSync(c,a,{encoding:'utf8'});return {code:r.status,out:S(r.stdout),err:S(r.stderr)};};const v=run('multica',['--version']);const vline=S(v.out.trim().split(NL)[0]);console.log('installed-entry: '+vline);if(v.code!==0){bad.push('multica --version 非零退出: '+v.err.trim());}const tok=S(vline.split(' ')[1]);const d=run('multica',['daemon','status','--output','json']);let cli='';try{cli=S(JSON.parse(d.out).cli_version);}catch(e){bad.push('daemon status 非 JSON: '+d.out.slice(0,200));}console.log('daemon-cli-version: '+cli);if(cli&&tok&&cli!==tok){bad.push('daemon 与已安装 CLI 版本不一致: '+cli+' vs '+tok);}const R='change-requests/CR-2026-076/test-evidence/';const rh=RD(R+'fr14-launch-receipt.md');const rb=RD(R+'fr14-run-behavior.md');if(!rh.trim()){bad.push('缺少启动回执原样证据: '+R+'fr14-launch-receipt.md');}else{console.log('launch-receipt sha256='+cr.createHash('sha256').update(rh).digest('hex'));if(tok&&rh.indexOf(tok)<0){bad.push('启动回执未载明现场入口版本: '+tok);}}if(!rb.trim()){bad.push('缺少 run 目标行为证据: '+R+'fr14-run-behavior.md');}else{console.log('run-behavior sha256='+cr.createHash('sha256').update(rb).digest('hex'));}if(bad.length){console.error(bad.join(NL));process.exit(1);}console.log('cmd-15 ok: 已安装 CLI／daemon 版本一致且与启动回执一致、run 目标行为证据原样在位');"] | 600 |

## 7. AC/业务闭环覆盖矩阵

关键 AC（影响主路径验收可达性，含用户可观察的成功／失败／隔离／幂等）必须唯一 TASK owner 且「验收证据」列为稳定 `cmd-NN`；非关键 AC 合并行但仍可追溯到至少一条 TASK。

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-01（关键）可信 task 已关联 CR、无手工根声明也能启动 | §4.1 判定顺序 2a、§6.2 AC-01 | CR-2026-076-TASK-01 | cmd-01 |
| AC-02（关键）仅来源 Issue 唯一正式关联时复用；多目标不猜测；无 CR 信号不退化 | §4.1 顺序 2a／2b、§6.2 AC-02 | CR-2026-076-TASK-01 | cmd-01 + cmd-04 |
| AC-03（关键）关联／声明／项目资源／真实根冲突：启动前拒绝、无业务写入 | §4.1 拒绝面、§6.2 AC-03 | CR-2026-076-TASK-01 | cmd-01 + cmd-04 |
| AC-04（关键）Git 姓名／邮箱来自原全局配置；全局配置未被修改 | §4.2、§6.2 AC-04 | CR-2026-076-TASK-02 | cmd-02 + cmd-03 |
| AC-05（关键）PASS／BLOCK × 有无 bump 的账本隔离提交与 SHA 事实 | §4.3、§6.2 AC-05 | CR-2026-076-TASK-04 | cmd-04 + cmd-05 |
| AC-06（关键）commit 失败或存在不相关暂存时：不夹带、回滚暂存影响、payload 保留 | §4.3、§6.2 AC-06 | CR-2026-076-TASK-04 | cmd-05 |
| AC-07（关键）commit 后崩溃或同操作重投：按已提交事实恢复、无重复 bump／提交 | §4.3、SDD-CLOSE-01、§6.2 AC-07 | CR-2026-076-TASK-04 | cmd-05 |
| AC-08（关键）恢复期间原对象变化：保持原对象与操作事实，不重标旧 verdict | §4.3、§6.2 AC-08 | CR-2026-076-TASK-04 | cmd-05 |
| AC-09（关键）旧 BLOCK 对象已变则建议独立复评；未变继续回修；upstream／耗尽优先 | §4.4、§6.2 AC-09 | CR-2026-076-TASK-05 | cmd-04 |
| AC-10（关键）合法本地正文／TASK 集合／证据定义变化仅 warning，批准保持有效 | §4.5 + D-04、§6.2 AC-10 | CR-2026-076-TASK-06 | cmd-04 + cmd-07 |
| AC-11（关键）合法存量文档缺 `subject-sha256`：提示继续、不补造历史摘要 | §4.5、§6.2 AC-11 | CR-2026-076-TASK-06 | cmd-04 |
| AC-12（关键）必需产物缺失／结构非法／blockers 非空／真实失败仍硬阻断 | §4.5、§4.6、§6.2 AC-12 | CR-2026-076-TASK-06 | cmd-04 |
| AC-13（关键）server-approve 签名／摘要／归属变化保持严格拒绝，不转本地批准 | §4.5、§6.2 AC-13 | CR-2026-076-TASK-06 | cmd-04 |
| AC-14（关键）默认新合同无需重复 dev-start 人工确认，经合法转换进入 developing，不伪造批准 | §4.6、§3.3、§6.2 AC-14 | CR-2026-076-TASK-07 | cmd-09 + cmd-04 |
| AC-15（关键）认证人类「继续」只开一个下一 cycle；目标不唯一则询问；自报不授权 | §4.7 + D-03、§6.2 AC-15 | CR-2026-076-TASK-08 | cmd-04 |
| AC-16（关键）重复继续指令不增 cycle；失败只恢复原操作；真实 blockers 不被清除 | §4.7、§6.2 AC-16 | CR-2026-076-TASK-08 | cmd-04 |
| AC-17（关键）HEAD 变但 tree 相同：合法本地路径可继续并保留 SHA 追溯与签名检查 | §4.8、§6.2 AC-17 | CR-2026-076-TASK-09 | cmd-07 |
| AC-18（关键）tree 真变化先更新测试／复评，不直接合入；只有真实失败才回实现 | §4.8、§4.9、§6.2 AC-18 | CR-2026-076-TASK-10 | cmd-08 + cmd-07 |
| AC-19（关键）同步后 tree 相同则接续、不同走最小重验；dirty／分叉／冲突仍技术失败 | §4.9、§6.2 AC-19 | CR-2026-076-TASK-10 | cmd-08 |
| AC-20（关键）原代码源不可取得先恢复；不可判则建立新证据，不以当前 HEAD 补历史 | §4.8 恢复分支、§6.2 AC-20 | CR-2026-076-TASK-09 | cmd-05 + cmd-07 |
| AC-21（关键）知识仓其他 CR 的变化不计为当前代码资源变化 | §4.5、§4.8、§6.2 AC-21 | CR-2026-076-TASK-09 | cmd-07 |
| AC-22（关键）部分 publish 后恢复仍使用原 journal 固定 source | §4.10、§6.2 AC-22 | CR-2026-076-TASK-09 | cmd-07 |
| AC-23（关键）数量下降仅提示；少跑／未登记／集合不一致／零执行／真实失败／非法例外仍拒绝；四例外复现转绿后撤销 | §4.11、§6.2 AC-23 | CR-2026-076-TASK-11（关联 TASK-15／TASK-17：其新文件须同批登记进 `manifest.files`，否则 `cmd-11` 在最终状态必红，见 §5.5「登记面所有权」） | cmd-10 + cmd-11 |
| AC-24（关键）Windows 文档链非零准确 `docCount`；实际部署后新 run 使用已验证版本并记录版本与行为证据 | §4.12、§4.13、SDD-CLOSE-08、§6.2 AC-24 | CR-2026-076-TASK-17（关联 TASK-12） | cmd-12 + cmd-14 + cmd-15 |
| AC-SUP-01（关键）owner 合法性：接受成员 `user_id`，拒绝显示名／membership ID／异 workspace UUID | §4.14、§6.2 AC-SUP-01 | CR-2026-076-TASK-13 | cmd-06 + cmd-04 |
| AC-SUP-02（关键）身份查询失败按技术失败停止，不报为成员不存在、不猜 ID | §4.14、§6.2 AC-SUP-02 | CR-2026-076-TASK-13 | cmd-06 |
| AC-SUP-03（关键）上传自动绑定：source 自动填入、writer 在 CR worktree 内可读 | §4.15、§6.2 AC-SUP-03 | CR-2026-076-TASK-14 | cmd-06 |
| AC-SUP-04（关键）无文档与失败分流：`source` 为 `""`；上传／读取／入库失败停止注册 | §4.15、§6.2 AC-SUP-04 | CR-2026-076-TASK-14 | cmd-06 |
| AC-SUP-05（关键）source 前置门禁：不存在／非文件／不可读／越界（相邻前缀与符号链接）均拒绝 | §4.15、§6.2 AC-SUP-05 | CR-2026-076-TASK-14 | cmd-06 |
| AC-SUP-06（关键；本 CR 只做集成验收）注册后阶段交接取得正确阶段根，独立评审与审批读取在同一权威工作区闭合 | §1.2、§4.1、§6.2 AC-SUP-06 | CR-2026-076-TASK-01 | cmd-01 |
| AC-SUP-07（关键）零写入与幂等恢复：校验失败不占 `registration_key`、不建账本与 worktree | §4.14、§4.15、§6.2 AC-SUP-07 | CR-2026-076-TASK-14（关联 TASK-13） | cmd-06 |
| AC-SUP-08（关键）合同与检查同步；一次性历史扫描只输出异常、不改受控状态 | §8、§4.16、§6.2 AC-SUP-08 | CR-2026-076-TASK-15 | cmd-09 + cmd-06 |
| AC-SUP-09（关键）新 CR 经注册节点在唯一 KB 主 checkout 注册，后续任务启动前绑定权威 CR 工作区 | §4.1、§4.14、§6.2 AC-SUP-09 | CR-2026-076-TASK-01 | cmd-01 + cmd-06 |
| AC-SUP-10（关键）需求节点交接完整：PRD 实质覆盖 AC-SUP-01～10、保留编号、`prd-path` 指向分支内实际文件 | §4.17、§6.2 AC-SUP-10 | CR-2026-076-TASK-16 | cmd-13 |

说明：AC-24 覆盖 FR-13 与 FR-14 两个 FR，故其 TASK owner 取 FR-14 的生产者 TASK-17，并把 FR-13 的 `cmd-12` 一并列入证据（AC 归属不改 FR 行的唯一主责 TASK）。AC-SUP-06 按 SDD §1.2 的承接边界只做本 CR 侧的集成验收，其平台实现部分（reviewer 单层派发与启动预检）由 AIFI-60 承接，不重复实现、不重复要求同一组证据。
