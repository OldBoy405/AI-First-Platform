# 8 项异常对照最新 main 的核实与落地方案

## 1. 核实基线与方法

本次不是沿用旧 checkout 或 CR 中途提交，而是重新取得两个仓库的最新默认分支 main，并在检查结束时独立核对远端 main SHA：

| 仓库 | 本次核实提交 | 提交说明 |
|---|---|---|
| AI-First-tools | `c69336475d01c4de5a42efc0dc087a5e605b5c82` | merge CR-2026-076: tools |
| AI-First-multica | `c47381ae72d4a274cf55208ea45bc105bb0bfc77` | merge CR-2026-076: multica |

两仓 `HEAD == origin/main == GitHub main`。检查期间未修改两仓源码，最终 `git status --short` 和 `git diff --check` 均无输出。只在仓库之外的当前工作目录建立临时核实脚本和结果日志。

方法：代码调用链检查、复用已有 fixture 对实际 crctl CLI 做输出复现、已有绑定／快照／模板／夹具测试，以及现有只读平台发布生效检查。不启动真实 Agent、不重启 daemon、不修改平台 Skill 来源、项目资源、CR 状态或预算。

## 2. 八项结论总表

| 原项 | 最新代码结论 | 是否需要继续修代码 |
|---|---|---|
| 1 Git 容量／静默截断／错误丢失 | **仍存在，实际 CLI 已复现** | 是，tools；最高优先级 |
| 2 payload 与 JSON 信封混流 | **仍存在，实际 CLI 已复现** | 是，与第 1 项同一聚焦修订 |
| 3 CR Task 绑定遗漏／能力误判 | **核心能力已经实现，52 个测试／子测试通过** | 不新建绑定机制；复用现有解析和正式关联 |
| 4 投影仍读默认分支旧 authority | **源码仍有该缺口** | 是，multica；数据库端到端验证尚未完成 |
| 5 Task completed／缺交付／永久等待 | **已修主要缺交付路径，残余边界未收口** | 仅补现有 Runner 边界，不再重写整套判定 |
| 6 消费者版本／来源不一致 | **已有生效检查，平台 13 项正文与 main 全匹配；来源收尾仍未完成** | 优先做既有部署／writeback 收尾，而非新功能开发 |
| 7 重复 reviewer／日志 dirty／交接 | **主要合同和隔离能力已具备，模板回归通过** | 不重复开发；补实际运行交接验收 |
| 8 跨仓 HEAD 夹具不确定性 | **已修复，目标回归通过** | 不再为此立修复任务 |

因此：不是 8 项全部重新开发。确定保留 1、2、4 的修订；第 5 项做小范围边界补齐；3、7、8 使用已有结果；6 做实际来源／执行器收尾验收。

## 3. 逐项证据与建议

### 1）Git 容量、静默截断和底层诊断：仍存在

**最新位置：** tools `skills/shared/crctl/scripts/crctl.mjs:565-595`，核心在 591-592。

代码仍为默认 `spawnSync`，随后对 stdout/stderr 无条件 `.slice(0, 20000)`；没有消费 `r.error` 或 `r.signal`。

使用仓库现有 `merge-fixture.mjs` 创建隔离 Git 仓，调用的是这份最新 main 的真实 `crctl git diff`，不是只模拟旧代码：

| 输入 | 原生 Git | 最新 crctl |
|---|---|---|
| 约 30 KB diff | exit 0，30,175 字符，完整末尾标记在位 | exit 0，输出加信封 20,030 字符，末尾标记丢失，仍返回 `{ok:true,exit:0}` |
| 约 2 MiB diff | exit 0，2,097,327 字符 | exit 1，输出加信封 20,034 字符，末尾标记丢失，返回 `{ok:false,exit:null}` |

本机 stderr 有 Git 的 LF/CRLF 提示；该提示不是底层容量失败诊断。不能把它当作 crctl 已提供真实执行错误。

**最小落地：**

1. 修共同执行原语 `controlledGit()`，不要给各 reviewer 单独打补丁。
2. 证据返回与日志摘要分开；成功的证据不得静默切片。
3. 小输出完整返回；大 diff 增加现有 git 子命令的文件承载方式，使用 Node 原生文件描述符，不建设流服务。输出文件限定在现有可信工作区／审计临时区域并沿用审计；通过现有 Read 分段消费。
4. 缓冲模式有明确上限时，超限必须明确失败并保留 `error.code`、signal、exit；提供大输出入口，而不是无限调大缓冲。
5. 对失败摘要截断必须有标记，不能再将摘要当作完整评审证据。

**验收：** 同一份 diff 的受控输出和原生输出逐字或 hash 一致，末尾标记在位；超限不能返回成功；原生错误可定位。复用现有 crctl 测试与 fixture，不新增框架。

### 2）回执混流：仍存在

**最新位置：** tools `skills/shared/crctl/scripts/crctl.mjs:4185-4211`、`parseGitArgs`（5146 起）；文档合同在 `skills/shared/controlled-shell/SKILL.md:127`。

CLI 仍先 `process.stdout.write(r.stdout)`，再输出 `{ok,exit}` JSON。文档仍要求字段分离的 `{ok,stdout,stderr,code}`。本次真实 `merge-base` 回执：首行是合法 SHA，整个 stdout 不是 JSON；将整个 stdout 作为 range，受控入口仍返回 `FORBIDDEN_SUBCOMMAND`。

**最小落地：** 与第 1 项同一 PR 处理。让机器调用方取现有 `controlledGit()` 对象的字段，不再从混流文本猜协议。在现有 `crctl git` CLI 增加一个明确的 JSON 消费模式并由自有参数解析器处理，不把该参数透传给 Git；返回完整 stdout 或文件回执、stderr、exit、code／signal。现有已部署消费者确实依赖旧形态，因此这一个显式模式是实际迁移需求，不建立通用兼容层。评审与相关文档同步使用该模式；SHA 参数仍须校验为单行合法对象 ID。

**不做：** 扩白名单、各 Skill 各写解析器、另建协议网关。检视现有调用方后再决定旧形态何时删除，不在本次顺手大迁移。

### 3）CR 绑定：已实现，不要再造入口

**最新位置：** multica `server/internal/daemon/pipeline_task.go:279-374`、`daemon.go` 的 `resolveTaskWorkspaceBinding` 调用处。

已有三类来源：Pipeline 绑定、触发评论的 `execution_context`、Task／来源 Issue 的正式 CR 关联。声明会匹配正式关联、仅使用任务自己的 local_directory、调用 `findPipelineCRRoot`、inspect 预检，再比对真实路径。多义关联和错误声明失败关闭。

**实测：** 已有绑定、环境注入和预检测试 **52 个测试／子测试通过**。当前聊天中的带声明重派也有实际成功回执。

**落地建议：** 不改根解析算法，不实现完整 coding Runner，不改共享项目目录。继续使用正式关联或已有唯一声明。若生产中某条委派未形成正式关联，先查现有上下文组装／委派说明，修真实漏点；不能将漏声明归结为平台完全没能力。独立 reviewer 每次启动均自行核验。沿用 AIFI-60 的现有工作，不另开平行绑定项目。

### 4）投影 authority 读源：仍存在

**最新位置：** multica `server/internal/daemon/crevents.go:329` 起；`server/internal/governance/reconcile_github.go:78-126`；`reconcile.go:240-289`。

- daemon snapshot 仍先读取配置 root 的 HEAD，再在该提交读取 backlog 和各 CR 文档。
- GitHub snapshot 仍明确读取 `default_branch` HEAD，所有 CR 文档都来自同一个默认分支 SHA。
- ApplySnapshot 的活动守卫只覆盖 running／waiting_approval 的 requirement／architecture run；不活动的 CR 仍按快照覆盖状态。它没有使错误的读源变成正确的读源。

故“在途 CR 分支已推进，默认分支还旧”的输入形态仍未被正确支持。已有快照完整性测试通过，只证明在所选提交内没有 torn read，不证明所选分支就是该 CR 的 authority。

**最小落地：**

1. 复用已有 CR 注册／分支／worktree authority 解析，在途 CR 读取其正式分支；发布／终态继续使用既定默认分支 authority。
2. daemon 与 GitHub reconcile 使用同一选择规则。声明的在途 authority 不可读时失败，不静默退到旧 trunk。
3. 不能只换读文件路径：现有快照是全局 `HeadSHA`，须让既有快照／投影中的来源 SHA 对应实际逐 CR 读源。使用现有 projected_commit 和快照合同扩展，不新建表、注册服务或补偿队列；保持 API 兼容。
4. 在 ApplySnapshot 处保留来源／freshness 校验，活动 run 守卫不能成为唯一防回退机制。

**验收：** 默认分支 drafting、CR 分支 approved 时，run 结束后投影不回退；缺失声明分支拒绝；事件与快照冲突最终按同一 authority 收口；终态仍恢复到发布态。复用 `crevents_test.go`、`reconcile_github_test.go` 和 reconcile 集成测试。

**限制：** 本次 daemon 快照／settlement 回归 12 个通过；governance 的数据库测试因本机测试 DB 不可用未实际执行，不能声称已经端到端复现和验证这项修复。

### 5）完成判定：主体已修，剩余边界要小修

**最新位置：** multica `server/internal/governance/runner.go:699-710,772-844`，architecture walk 的 410-431，以及对应 requirement walk。

已存在：

- `conclusiveReviewEvidence` 校验 attempt、subject SHA、reviewed-at 和 blocker 形状；
- `reviewDeliveryGap` 在投影已 settled 且无裁决时，以 `RUNNER_REVIEW_DELIVERY_MISSING` 进入现有失败终态；
- daemon task 收尾的 CR event settlement 已有回归通过。

所以不能再按“Task completed 后任何缺证据都会无限等待”的旧描述全盘重做。

**残余代码分支：**

1. `reviewRoundUndelivered` 只要 verdict 字符串为 pass/block 就提前认为不是缺交付，没有复用完整判据。
2. walk 遇到 pass/block 但 `conclusiveReviewEvidence=false` 时仍直接 `waitEvidence`。对于 Task 已结束、投影 settled 且字段无法再补齐的裁决，这个分支没有可见失败出口。
3. `projectionIsBehind` 仅看 needs_reconcile；持续为 true／CR 行持续不存在时，当前等待分支看不到有限退出保护。此点应以集成测试确认，不将正常异步同步延迟直接判失败。

**最小落地：** 继续在已有 AIFI-60 实现中修改。所有“有／无可执行裁决”判断复用 `conclusiveReviewEvidence`；缺失和格式不完整走同一既有交付-gap 判定，settled 后转现有失败终态。同步确实失败或长期未 settled 时使用现有节点／任务时间戳加明确有限策略，复用 failRun，不新建计时服务、轮询器或 provider 中止协议。

**验收：** completed＋缺裁决、completed＋字段残缺 pass/block、错 attempt、缺 subject SHA；正常同步延迟可等待，settled 后不无限等；永久未同步有可见技术失败。数据库环境准备好后在现有 runner 集成测试验证。本次对应 DB 测试未实际运行。

### 6）版本／来源：已有能力，实际部署收尾还没结束

**源码：** tools `skills/shared/crctl/scripts/test/publish-effectiveness.test.mjs` 已有线上 origin 路径与 13 项 Skill 正文比较；crctl 的人类触发来源事实消费代码也已合并。

**本次只读实测：**

- publication 3 个检查通过，**13 项线上 Skill 正文都与最新 main 相同**。
- 当前 CLI 为 `multica 0.6.1-432-gc47381ae7`，commit 与本次 main 匹配。
- 但 `review-code` 的 origin.ref 仍是 **`requirement/CR-2026-076`**，而不是 main。正文相同并不能证明来源收尾完成。
- 该测试对三份 Agent instructions 只记录 hash，不做正文相等断言；也不能证明 daemon 与 PATH 中的 crctl 文件都已生效。本次没有修改或读取越权的安装配置来补造这些证据。

**落地：** 不建安装平台或版本表。按原批准的 writeback 收尾，由已有授权操作者将 review-code 的 ref 与 source_url 一并回 main，refresh，独立 get-with-content 对照合并后的文件。核验完成前保留仍被引用的分支。运行回执继续分别记录 CLI、daemon、实际 crctl 文件／hash及行为；不能只看版本号或环境变量存在。

如果要修一点验收说明，就在既有 writeback 检查中明确“内容匹配”和“目标来源已恢复”是两项；不得把 main 约束硬套到所有在途阶段，不新增通用发布注册器。

### 7）重复链与 dirty：主要已修，复用现有结果

**最新证据：**

- `agents/quality-reviewer-agent.md:26-28` 已明确平台独立 reviewer 收到节点直接评审，不再 spawn 第二个 reviewer。
- `pipeline-templates/code-implementation.pipeline.json` 的 review-code prompt 也有同样约束，并保留作者自评禁止、正式测试和业务 reviewLoop。
- 现有 pipeline 合同测试 **36 个通过**。
- tools `crctl.mjs:425-430` 的 audit.log 放在 `.crctl`，默认建立忽略规则；正式 test-report／traceability／test-evidence 仍需通过既有 checkpoint 收尾。
- README 明确 checkpoint 可随时调用，阶段完成条件另行要求 PASS checkpoint；不需再加“测试 BLOCK 不能提交”的限制。

**落地：** 不重写调度器或另建通用提交器。验收现有独立 run 是否一次派发、实际取用 instructions 是否同源、普通日志是否不污染业务 diff、正式 BLOCK 产物是否能受控落盘。若存在特定漏落点，只改那个实际落点；不能全局放宽 clean 或删除审计。仓库 agents 目录并没有 `cr-coordinator-agent.md`，不能凭名称臆造待修改文件；已部署协调者 instructions 走其现有权威管理入口。

### 8）夹具 flake：已修，不再重复修复

**最新位置：** tools `skills/shared/crctl/scripts/test/merge-fixture.mjs:120-129`。

共用 fixture 已显式给三仓 init 设置相差一秒的 author／committer 时间。不是 sleep 等时钟跳秒，而是确定性指定提交元数据，因此两个空提交不再因恰好同秒而相同。`workspace-freshness.test.mjs:639-655` 的原断言没有被放松。

**实测：** 目标回归 **2 个通过**，没有修改生产 freshness 判据。

**落地：** 保留已有修复和测试，不再立项，不改成随机 SHA 或重试到绿。以后新加“不同版本”的用例可以直接构造同仓两个不同提交，但不为这个已经确定性修好的 fixture 做额外重构。

## 4. 最小实施顺序

### 第一批：tools 一个聚焦 PR，解决 1＋2

范围是共同 `controlledGit`、既有 `cmdGit`／参数消费、controlled-shell 合同和实际机器消费者，外加现有 fixture 的少量回归。交付完整输出、真实错误和结构化消费，不混入根绑定重构、安装平台或全部 Skill 迁移。

### 第二批：multica 一个 authority 修订，解决 4

在现有 snapshot／reconcile／authority 选择和来源 commit 归因处收口；两种采集方式同规则，保持现有 API 兼容，不建设新 CR 注册表。先用同仓 branch fixture 锁住“trunk 旧、CR 新、run 已结束”的失败输入。

### 第三批：AIFI-60 的既有 Runner 边界补齐，解决 5

先补 malformed／长期未同步的集成测试，然后复用完整裁决判据、delivery-gap 和失败终态。修几处分支，不再从头实现正式交付判定。

### 不需要新代码项目

- 3：已有绑定机制和 52 个通过的回归。
- 6：按现有授权完成实际来源和执行器验收；当前 review-code 的 ref 还需收尾。
- 7：现有独立 reviewer 合同和 36 个模板回归，做运行交接验收。
- 8：已修且目标回归通过。

## 5. 实际检查清单及限制

| 检查 | 结果 |
|---|---|
| 实际 crctl CLI 的 merge-base／污染 range／约 30 KB／约 2 MiB diff | 复现 1、2 的残留问题 |
| daemon 绑定／注入／预检回归 | 52 测试／子测试通过 |
| daemon 快照／事件 settlement 回归 | 12 通过 |
| tools pipeline contract | 36 通过 |
| freshness B-03 目标回归 | 2 通过 |
| publish-effectiveness 只读平台检查 | 3 通过；13 Skill 正文全匹配 |
| governance Runner 集成检查 | 测试 DB 不可用，没有实际测试通过记录 |
| governance reconcile 检查 | 同上；不能把包 exit 0 当作测试通过 |
| 两仓 source status／diff-check | 干净、无源码修改 |

本次没有通过复制主 checkout 的数据库配置或手工创建数据库来绕过测试环境；governance DB 检查应在仓库既定的 managed 测试环境内补跑。没有运行真实 Agent smoke、完整正式 test plan 或真实 CR reset／审批／合并流程。以上代码判断与已跑检查有明确区分。
