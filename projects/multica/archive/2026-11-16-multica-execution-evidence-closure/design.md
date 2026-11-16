# multica 执行恢复与证据闭环 - 技术设计

## Context

- Change：2026-11-16-multica-execution-evidence-closure。Gate 1 已确认；本轮起草 SPEC，不改业务代码，不批准 Gate 2。
- 业务基线：multica `294d793a91c8f1dce2f97a549b41cf468e562b1a`；目标 tools pin：已发布的 `7a0a2ab57f3f5e2c583c3523bc69d67e7be115c1`。不重做 sqlc、pg 导入和已归档 backend-tests-green。
- 当前模式为 standard，按原流程由主会话起草，不额外派 planner 或声称已升到配置的 strong 模型。
- `runner.go:729`、`runner_requirement.go:43`、`runner_code.go:44` 是全部三个生产 `withRunLock` 调用点。各自锁前选 A，回调内再按 workspace/CR/pipeline 查最新活动 run；`ORDER BY created_at DESC LIMIT 1` 可能选 B。共享锁原语本身不认识活动 run。
- `runner_code.go:312` 的 writeback 不调用该锁；本 change 不为其添加新锁。`runner_requirement_entry.go` 的 CR 级创建锁不改。
- `selection.mjs` 的字段名单只有六项；本机 `go doc cmd/test2json`（Go 1.27.1）列出八项，新增可选 OutputType 与 FailedBuild。CI 使用 Go 1.26.9 系列；旧六字段流与已核实 1.27.1 流均在有限兼容范围，不承诺未来未知协议。
- `governance-run-lock` 当前无 expected，仅 totals>0 不能证明两个锁测试均执行。`tools-pin.mjs:15` 的三个必需文件也不包含新消费方使用的 rules.json。
- 最新真实 CI run 43727687773 受账单/额度阻塞，未启动；最终业务提交 f8a23564a 的实际 run 43752944966 同样因账单 runner_id=0、六测试 skipped，未启动有效执行。2026-11-16 用户明确裁定本轮延期 TC-MEC-003（not_applicable，接受风险）；权威 CI 仍是目标合同，但本轮未验证，额度恢复后另行验证，不以本地/离线结果冒充。

## Decisions

### 1. 三个恢复入口核对锁后身份，不改锁原语

**方案**：保留锁前的 run A 快照；回调里的最新对象使用另一个局部变量。沿用既有活动 run 查询，在 digest 检查和任何节点/任务写入前比较最新 ID 与 A.ID。相同则执行最新快照；无活动 run 或 ID 不同则本次返回 nil，释放 A 锁，不在 A 锁下执行 B。非 ErrNoRows 查询错误及 digest 错误继续传播。

**为什么**：只需要三个局部身份核对，全部同类调用者一次覆盖。共享 `withRunLock` 继续只负责串行、释放和取消，不学习三种业务选择规则。查询和迁移文件、50ms 退避、锁键、池上限和创建入口均不改。

**备选方案及排除原因**：
- 回调内发现 B 后持 A 锁再取 B 锁：引入嵌套锁及死锁顺序。
- 新建无限目标重试/统一 Runner 框架：既有周期恢复已负责补漏，无需新机制。
- 改成按 CR 全局锁或新建按 ID 查询：扩大并发语义/查询面，三个比较已经满足本次有限保证。

**可接受代价**：换目标的这次唤醒不推进 B，由下一次既有唤醒在 B 锁下执行；不承诺同一次调用完成目标切换或立即推进。这不增加业务轮次，不失败关闭 B。

### 2. 用现有真实库设施制造目标切换

**方案**：在 `runner_run_lock_test.go` 加一个顶层 `TestReconcileRunIdentity`，内部普通表循环覆盖 architecture、requirement、code 三个入口及 unchanged/changed/no-active 三种情形，不增加生产 hook。

复用 `setupRunnerIntegration`、`setupRequirement`、`setupCodeWalker` 的合法上下文和假 enqueuer。每个情形用独占的 Runner 测试池（MaxConns=4），测试控制连接持有 A 的 advisory lock，恢复调用先选 A 再等锁；通过该池 AcquireCount 的新增获取确认活动 run 查询已完成且已进入取锁路径，而不是只确认 goroutine 启动：architecture 的锁前有 writeback 与 architecture 两次查询，故等待至少三次新增获取；requirement/code 锁前各一次查询，故等待至少两次。夹具查询走独立控制连接，不污染这个计数。

changed 情形在控制连接内把 A 设为终态并创建同 workspace/CR/pipeline 的合法 B；B 的 created_at 使用明确顺序，不依赖时钟粒度。控制连接继续持 B 锁，再释放 A：第一次恢复须返回，B 的节点、任务及状态不变。另一次恢复须等 B 锁，释放 B 后正常推进一次，再次唤醒不重复派发。unchanged 情形推进 A；no-active 情形无效果返回。回归保留两个既有直接锁测试和 TestMTick003。

**为什么**：必须观察生产恢复入口、目标身份与副作用，单测锁回调串行无法证明调用方没有换对象；持 B 锁的正向对照区分正确重取锁与无锁推进。

**备选方案及排除原因**：只 sleep 后读行数不能证明交错已发生；把生产查找函数改成可注入接口只为测试增加抽象；无限循环压测不能替代一个确定性交错。

资源释放放在测试清理中，等待有总 deadline；测试串行执行并限定本情形 CR，复用既有夹具的清理，不共享全库为空的断言。改变 fixture 不能绕过 admission、nonce 或 digest 判据。

### 3. 在原事件边界接纳已知元数据，保留完整选择判定

**方案**：扩展 `selection.mjs` 的既有 eventKeys 为 Time、Action、Package、Test、Elapsed、Output、OutputType、FailedBuild。其余未知键仍 EVENT_INVALID；不改 expected 的 package/test/leaf 三字段合同及事件状态机。

OutputType 可省略；存在时必须是字符串，只出现在 output 事件，值为官方已知的空串/frame/error/error-continue。它只描述日志，不替代 pass/fail 判定。FailedBuild 可省略；存在时须为非空合法字符串且只出现在 fail 事件，失败流仍不能 matched。原六字段合法流继续 matched。重复键、错误类型、错误时序、缺测试、额外测试、skip/fail、截断、非零退出及 signal 继续拒绝，报错不回显原始输出或异常消息。

**为什么**：这是有限协议边界更新，不是逐版本加 fallback；合法元数据和最终测试结论各负其责，不为兼容移除全量字段检查。

**备选方案及排除原因**：忽略所有未知字段扩大信任面；删 expected 回退 totals 失去完整选择保证；新增解析框架或独立版本协商没有必要。

在既有 `selection.test.mjs` 加一个表驱动 `TC-MEC-002 event matrix` 测试，串行复用 fixture 和真实 verifyGoTestSelection/decideSelection。覆盖新旧合法流、元数据非法形状、删一个完整测试的全部事件（其余 pass 和进程 exit0）、skip/fail/截断，以及完整结果下新名单确实 matched。既有拒绝测试原样保留，不为每个字段另建检查脚本。

### 4. 精确名单复用 governance-run-lock，不新增执行层

**方案**：将该 selection 的 run 改为四个顶层测试的完整锚定 alternation：TestWithRunLockSerialisesSameRun、TestWithRunLockCancelReleasesWaiter、TestReconcileRunIdentity、TestMTick003；expected 明确列这四个完整 import package/test/leaf=true。普通表循环不产生额外子测试事件，成功 totals 为 pass=4/fail=0/skip=0。

**为什么**：两项既有锁保证、一个身份交错回归、一个池 4 并发恢复在同一个一次性库命令内执行和对账。原 `governance-mtick003` 入口保留给既有归属引用；本 change 不再单独重复执行它。

**备选方案及排除原因**：只比 pass>0 或手抄 pass 数不能证明测试身份；另建 runner/selection 生成器或扩展所有 selection 的 expected 超出本次范围。

本地命令用已有 run-selection，Node 原生 spawnSync 设置 GOFLAGS=-race -count=1，不写 Windows 无法执行的 VAR=1 前缀。沿用 governance TestMain 固定池 4 和既有一次性库门禁。只继承已核实、对应当前 pin 的 AIFI45_TOOLS_ROOT/CRCTL_MJS；环境缺失即失败，不回落开发机目录，不运行真实 agent。

### 5. 权威规则放进既有 pin 完整性入口

**方案**：pin 更新为上述已发布 SHA；backend-tests job env 增加 `MULTICA_CONTROLLED_SHELL_RULES: ${{ github.workspace }}/.aifirst-tools/skills/shared/controlled-shell/rules.json`。不把 `$AIFI45_TOOLS_ROOT/...` 当作会在 YAML env 中自动展开的字符串。

在 `tools-pin.mjs` 的 REQUIRED_FILES 追加该规则路径，同步既有 required-list 精确断言；现有逐必需文件缺失的测试自然覆盖第四文件，缺失在检出后的共同入口失败。凭据诊断继续在 pinned checkout 前，两个消费者仍读取同一个 pin；两套生成器只跑 --check，不重生成或改 digest。若检查显示合同漂移，停止并报告，不扩大范围修到绿。

在 `scripts/ci-scope.test.mjs` 的现有 job 解析设施中补一项 `TC-MEC-002 CI wiring`，钉住 backend job 的规则路径、同一 pin checkout 和 pin-check 早于 Test，并保留已有 provisioning、受限 DATABASE_URL、admin 对账及 always teardown 断言。不要把源码字符串出现当成整个 CI 已成功。

**为什么**：既有消费方在配置了不可用规则时 Fatal；共同完整性检查一次拒绝缺文件，静态接线检查防止删除 env 后静默 fixture 回落，实际 CI 再证明实际加载。

**备选方案及排除原因**：在六个测试里分别补 env guard 或每次临时 overlay 是逐异常兜底；新 CI job、依赖安装和重复全量测试不能增加本次必要保证。

实际 CI 验收固定最终业务 SHA，核对 backend-tests 和其 Test/证据对账/admin 步实际执行成功；六个既有快照测试都有 pass，TestProposedSnapshotReadShapes 的真实规则加载日志出现。六个名称沿用 tools 归档 SC-004：TestM26B2TestFactsPayload、TestM26B2TestFactsPreserveFailures、TestM26B4CollectorKeepsBothReviewStages、TestM26B4ScanEmitsIndependentTestEvent、TestM26B4ScanTestOnlyAndReviewOnly、TestProposedSnapshotReadShapes。不为收集日志重跑一次全量；复用同一 CI 的原始事件流和元数据。本轮该权威验证因账单/额度阻塞经用户裁定延期（TC-MEC-003 not_applicable，接受风险），仍未完成；已交付并验证的是 pin/env/必需文件与离线接线测试这一静态防护，实际 runner 加载权威规则的事实待额度恢复后另行核对，不冒充通过。

### 6. 一次台账核对，不把计数当产品保证

**方案**：CUSTOM 按当时表结构登记本 change 和真实任务标识，上游挂钩与 fork 文件分清；模块索引/CR 索引/明细一致，当前状态不得写成已在 CI 通过。必要时追加当前事实说明，保留历史变更原记录。

前三数仅统计 git 跟踪的 server/packages 下 .go/.ts/.tsx/.sql/.mjs：①含 AIFIRST 或 CR-2026-[0-9]{3} 的文件数；②同样正则的匹配行数；③其中含 AIFIRST 的匹配行数。一行多次命中只计一次。基线记录实际 tree/HEAD 与时间，不把旧 596/1659/736 或未跟踪文件冒充当前测量；正常删除/重构导致下降须解释，不把单调递增当安全保证。第四数写明确未决/本次未测，不填旧 314 冒充新结果。

**为什么**：一次精确人工核对即可承担记账职责，无需台账校验框架；测量只能说明标记集合，不能证明全部定制或功能闭环。

**备选方案及排除原因**：猜第四数口径违反已确认范围；重写全部历史 CUSTOM TODO 或归档既无授权也会改变历史含义。

## Architecture

```text
三个恢复入口：选 A -> 既有 withRunLock(A) -> 重读最新活动 run
  同 ID -> 原 digest/admission/节点流程
  无对象或不同 ID -> 本次无效果返回 -> 既有下一次唤醒重新选择并取锁

GO test 事件 -> 原字段/状态/expected 完整性对账 -> 原 decideSelection -> PASS/FAIL

单一 pin -> 既有 checkout -> 扩展必需文件检查 -> 固定规则 env -> 既有 backend-tests
  同一次 CI 事件流/metadata -> 人工实际运行核对
```

## Risks / Trade-offs

| 风险 | 有限保证与检查 |
|---|---|
| 目标切换延迟一次唤醒 | 本次不错误推进；下一次在 B 锁下正常推进的正向对照，不承诺无延迟 |
| 跨三个入口漏一处 | 单个真实库身份矩阵明确覆盖三者，不靠静态 grep 代替运行 |
| 测试先看到错误状态而不是锁交错 | 独占池计数、A/B 持锁和明确 created_at 顺序；全部等待有 deadline |
| metadata 兼容变成放行未知流 | 有限字段及值域，不改已有缺失/失败/skip/重复/截断拒绝 |
| pin 改动触发生成合同漂移 | 两个 --check 失败即停止，不扩大到生成物或模板 |
| 账单/凭据/push 授权使真实 CI 不能执行 | 本轮经用户裁定延期 TC-MEC-003（not_applicable，接受风险）；真实 CI 仍未验证，不继承旧 N/A、不绕过平台、不冒充通过；额度恢复后另行验证 |
| caller 标注未强制、40hex 对象类型边界 | 已归档风险不变；本 change 不宣称只对 orchestrator 放行或只读 commit |
| 第四数未闭环 | 用户明确允许暂不收口；台账写未决，M4 不被夸大为全部完成 |

## 方案审查与锚定

- 提案四项变更对应三份 code spec：governance-runner-run-lock、selection-reconciliation、ci-backend-environment；台账作为交付追溯义务附在第三份，不新造 capability。
- 两组命令检查（真实库锁矩阵、离线事件与接线矩阵）加一次台账人工核对承担本轮已验证保证；真实 CI（TC-MEC-003）经用户裁定本轮延期为 not_applicable（接受风险），权威验证仍未完成。共四个 TC，其中三个本轮验证/确认、一个延期；不在 SPEC 执行任何产品验收。
- 经验库使用 EXP-2026-0002/0008 的 check-then-act 与确定性交错教训、EXP-2026-0010 的池 4 形状、EXP-2026-0004 的资源失败清理教训；不照搬每条经验的检查数量。
- proposal 的 L3 引用沿用两个已归档 change，锁语义与 selection 判定锚定既有实现；批准前仍由 STDD 的 (l) 唯一判定，不以本文自评代签。
