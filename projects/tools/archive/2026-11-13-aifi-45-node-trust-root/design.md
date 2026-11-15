# 授权节点内 crctl 可定位 daemon 信任根 - 技术设计

## Context

变更：`2026-11-13-aifi-45-node-trust-root`，与 multica 的 `2026-11-13-aifi-45-real-execution-closure` 成对。

`authorized-execution/v1` 的 grant、公钥和来源材料由 multica daemon 安装在其自有信任根 `store.Root`。crctl 当前只能通过 `--trust-root` 选择该目录；节点 skill 中的 `crctl advance` 不传此 flag，因而回退到 `<安装根>/.crctl/{grants,keys}`，通常以 `EXECUTION_CONSUMPTION_REQUIRED` 拒绝。

当前代码边界：

- `crctl.mjs` 的 `parseArgs` 是通用 flag 构造点，使用 `Object.create(null)`；它不区分命令，也不拒绝未知 flag。`git` 使用独立的 `parseGitArgs`。
- `kb`、`workspace`、`planning-entry`／`competitive-report`、`writeback-apply` 另有命令级 flag 白名单，不能向这些命令无条件注入 `flags['trust-root']`。
- `installDirectory(workspace, trustRoot)` 已集中实现绝对路径、realpath 可访问、目录类型以及不得位于或包含安装根的检查，错误码为 `EXECUTION_TRUST_ROOT_INVALID`。
- grant、binding 信封均按 `key_id` 从所选安装根的 `keys/` 读取公钥；receipt 写在所选根的 `execution-consumptions/`，业务写入仍发生在工作区。
- crctl 不清洗环境变量，子进程默认继承环境。本变更所称“只读变量”仅指 crctl 不修改它，不表示 agent 不能修改它。

逐一核对 `flags['trust-root']` 的实际消费者后，命令清单为：

`advance`、`authorization-bind`、`authorization-scope`、`sensitive-action`、`repair-admit`、`repair-resume`、`register`、`archive`。

对输入事实的一处修正：`crctl.mjs:2594` 位于 `sensitive-action`，不是独立的 `read-execution-grant` 命令；当前 dispatch 中不存在 `read-execution-grant` 子命令。`repair-assess`、`repair-outcome` 调用 `readRepairGrantPayload` 时没有传 trustRoot，故不在生效清单内。

本变更增加三处 crctl 侧接缝：①信任根定位通道；②（2026-11-14 并入，见决策 7）`workspace inspect --detail` 的 authority 事实键；③（2026-11-14 并入，见决策 8）crctl 自己 spawn 的 git 不经 agent 的 git shim。除此之外不改 grant、签名、binding、receipt、verdict 合同，不改状态机、`gates.json`、SKILL.md，不新增 flag，也不处理工作树中未提交的 M008／`merge-effects.mjs` 等改动。

## Decisions

### 1. 使用唯一变量，并在 main 的 flag 解析边界按命令合并

**方案**：

变量名定为 **`CRCTL_EXECUTION_TRUST_ROOT`**，不设置别名。

在 `crctl.mjs` 增加内部函数 `resolveTrustRoot(cmd, flags, env)`，于 `parseArgs` 之后、`bindTaskWorkspace` 和 `requireExplicitWorkspace` 之前调用。`git` 不调用该函数。函数只处理上述八个实际消费 trustRoot 的命令，并把环境变量值并入现有 `flags['trust-root']`，下游命令不再各自读取环境变量。

```text
if cmd 不在 trustRoot 消费者清单:
    return
raw = env.CRCTL_EXECUTION_TRUST_ROOT
if raw === undefined:
    return
if flags['trust-root'] 已存在:
    两者原字符串相同 → 保留 flag，通过
    否则 → EXECUTION_TRUST_ROOT_INVALID
else:
    flags['trust-root'] = raw
```

该清单是“环境变量生效命令清单”，不是新的通用 flag 白名单。其他命令即使变量为空、相对路径或与显式 flag 不同，也不增加任何环境变量相关行为；其原有显式 flag 处理保持不变。

**为什么**：

- 单一合并点保证 env 与同值 flag 走完全相同的下游路径。
- 在命令白名单检查之前按命令过滤，避免 `kb` 等命令因多出一个 flag 而新增 `BAD_ARGS`。
- 变量由 crctl 命名，multica 只复用同一个跨仓接口字面量。
- 不需要新增库、配置层或逐命令 env 读取。

**备选方案及排除原因**：

- 在 `parseArgs` 内无条件注入：会使有 flag 白名单的命令行为改变，排除。
- 每个命令分别读取环境变量：容易产生冲突规则和回退语义漂移，排除。
- 修改全部 SKILL.md 传 `--trust-root`：改动面大且容易漏改，已被 Q1 排除。
- 使用 `MULTICA_` 前缀或同时支持多个变量名：接口归属不清且增加兼容面，排除。

### 2. 冲突按原字符串判定；路径校验复用现有消费点，不提前改变分支语义

**方案**：

| 情况 | 行为 |
|---|---|
| 变量未设置 | 完全保持现状 |
| 生效命令仅设置变量 | 等同于传入同值 `--trust-root` |
| 变量与 flag 原字符串完全相同 | 通过，继续使用该值 |
| 变量与 flag 原字符串不同 | 在 workspace 读取前以 `EXECUTION_TRUST_ROOT_INVALID` 拒绝 |
| 非生效命令设置变量 | 忽略变量，不注入、不校验 |

“相同”指原字符串逐字相等；不做 trim、`path.resolve`、realpath 或尾分隔符归一。比如 `/a/trust` 与 `/a/trust/` 虽可能指向同一目录，仍按不同输入拒绝，以避免在参数边界引入另一套路径等价规则。

路径本身不在 resolver 中校验，继续由实际消费 trustRoot 时的 `installDirectory` 统一处理：

- 空串、纯空白、非绝对路径；
- 不存在或不可访问；
- 不是目录；
- realpath 后位于安装根内，或包含安装根；
- 经符号链接／junction 解析后落入上述禁止范围。

这些情况在被实际选择为信任根时均拒绝，且不得回退到 `.crctl`。冲突检查与路径检查不新增其他错误码；复用 `EXECUTION_TRUST_ROOT_INVALID` 是因为它们都属于“无法形成唯一、合法的执行信任根”，新码只会分裂现有调用方的错误处理。

**不消费 trustRoot 的分支不做提前文件系统校验**。例如：

- legacy CR 的 `advance` 在合同选择后返回，不读取 trustRoot；
- 参数不完整的 `repair-resume` 走原有模糊恢复路径；
- `repair-assess`、`repair-outcome` 本就不消费 trustRoot。

这些分支即使变量值不存在或非法，也与当前显式传同值 `--trust-root` 一样被忽略。若同时存在变量和不同值 flag，仍先按 Q2 的冲突规则拒绝。其他参数校验与路径校验的先后顺序也与同值 flag 保持一致，不承诺环境变量错误优先于所有既有错误。

**为什么**：

- 这是“语义等同于 flag”且不改变 legacy／显式 flag 现有行为的唯一一致实现。
- 避免在解析阶段访问文件系统，也避免 legacy CR 因 daemon 注入了变量而新增信任根要求。
- 不在多个位置复制路径校验。

**备选方案及排除原因**：

- 新增冲突专用错误码：没有新的调用方处理需求，排除。
- realpath 后再比较 env 与 flag：需要提前访问文件系统，并引入路径别名和不存在路径的额外语义，排除。
- 对所有生效命令提前执行 `installDirectory`：会改变 legacy 分支及既有 flag 的错误优先级，排除。
- 变量非法时回退 `.crctl`：会掩盖 daemon 配置错误，明确排除。

### 3. 八个现有消费者统一生效，不缩小为仅 advance

**方案**：

采用 Q3 的统一方案。`register`、`archive` 在变量存在时会像显式传入 `--trust-root` 一样进入 control admission；这可能使授权节点内原本按 legacy 方式能运行的调用失败，但本设计接受这一失败关闭行为，不为它们增加环境变量专用豁免。

具体而言：

- `register` 首次非重放写入将要求平台预分配 `--cr-id`、`--project-id`、grant 和有效 binding；缺少预分配 CR 时可出现 `REGISTER_PREALLOCATED_CR_REQUIRED`，缺 project 时可出现 `CONTROL_ADMISSION_PROJECT_REQUIRED`。
- `archive` 首次非控制重放写入将要求 `--project-id`、grant 和有效 binding；缺 project 时可出现 `CONTROL_ADMISSION_PROJECT_REQUIRED`。
- 两者均不依据 CR 是否有 `execution-contract` 来决定是否进入 control admission；这是当前显式 flag 的既有语义。
- 已完成或已有控制事实的重放继续走现有 replay 判据，不重复制造 admission。

这一影响通过部署边界控制：multica 只能把变量注入需要该信任根的授权 agent 进程，不能写入 daemon 全局环境、用户 shell 或所有任务。

**为什么**：

- 给 `register`／`archive` 增加 env 专用 legacy 回退，会使 env 与 flag 形成不同的安全语义。
- 统一方案技术上可行，不需要改状态机或事务合同。
- 失败是可观察的，不会把缺少平台准入静默解释为成功。

**备选方案及排除原因**：

- 只对 `advance` 生效：会让 binding、repair、register、archive 在同类授权节点中仍无法定位 daemon 根，并违背已确认的 Q3，排除。
- 按 CR 合同过滤：register 尚未形成可读取的 CR 合同，archive 当前也不以合同判断 control；另造过滤条件会改变现有事务语义，排除。
- 对 register／archive 静默忽略变量：形成 env 专用旁路，排除。

### 4. 威胁模型只声明“定位一致”，不声明隔离或平台授权

**方案**：

必须在 SPEC、测试说明和成对设计中保持以下口径：

1. **本变更不新增 agent 能力。** agent 今天已经可以传 `--trust-root <任意绝对目录>`；环境变量只是把同一值的输入通道从 argv 换成 env。
2. **本变更不提供隔离。** 不证明 trustRoot 由 daemon 拥有、agent 不可写，也不证明进程环境来自 daemon。env 比 argv 更不易审计，这是审计可见性的折衷。
3. **本地准入只证明所选根内文件和 binding 自洽。** 自备目录、自生成 Ed25519 密钥、自签 grant 和本地假 binding endpoint 在当前代码下可以完成本地准入并写 receipt；使用 env 不会比 flag 更严格。
4. **本地成功不等于平台授权。** daemon 的预消费事实、当前 head、撤销状态、daemon 签发的 challenge 及平台对 run receipt 的核验才是权威。假 endpoint 或自造 receipt 不得被平台接受为真实执行证据。
5. **不声称防止业务副作用。** 本地伪造链即使最终被平台判定无效，也可能已经造成工作区写入；本变更不是这一既有威胁的修复。
6. 本变更不新增签名、公钥固定、新信任根、环境变量认证、OS 身份隔离或本地静态验签回退；这些属于其他 change。

multica 成对 change 负责：从实际 `store.Root` 注入变量、授权节点启动前预消费，以及以平台事实验证执行结果。tools 侧只定义变量名和与同值 flag 一致的 crctl 行为。

**为什么**：

proposal 中“自备目录中的伪造 grant 或公钥不能使 advance 成功准入”与当前代码及现有 `trust-anchor-chain` fixture 不符。若保留该验收条件，将迫使本 change 意外扩大为信任锚重设计。

**备选方案及排除原因**：

- 把“daemon 注入 env”当作可信来源证明：env 可被 agent 改写，排除。
- 在本 change 中固定平台公钥或新增签名：超出定位需求且改变现有合同，排除。
- 以本地 receipt 的存在证明真实平台执行：与平台权威边界冲突，排除。

### 5. 版本错位由部署前置条件和平台收尾核验关闭，不在 crctl 增加兼容层

**方案**：

| 错位 | crctl 可观察行为 | 系统必须保证 |
|---|---|---|
| 新 daemon 注入变量，旧 crctl | 旧 crctl 忽略变量，按 legacy `.crctl` 读取。典型干净节点中，`advance` 因无可用授权而以 `EXECUTION_CONSUMPTION_REQUIRED` 等既有错误失败 | 发布顺序为先 tools、后 daemon 注入；multica 不依赖 crctl 的退出码判断成功，而以平台权威回执判断 |
| 新 crctl，旧 daemon 未注入变量 | 与当前无 flag 调用完全相同。daemon-only 材料不在 `.crctl` 时，通常以 `EXECUTION_CONSUMPTION_REQUIRED` 拒绝，且不写业务状态或 receipt | multica 对授权节点必须无条件注入；缺失注入不得被当作可选配置 |

crctl 单侧无法区分“旧 crctl 忽略变量”与“用户故意选择 legacy”，也无法保证存在旧 `.crctl` 材料时一定拒绝。因此，**不得声称所有版本错位都必然在 crctl 内硬失败**。

系统层“不静默降级为通过”的关闭条件是：

- daemon 不把 crctl exit 0 或本地 receipt 单独当作平台成功；必须核对与 daemon 签发 challenge、预消费和当前平台事实匹配的执行回执。
- 缺少预期 run receipt、回执不匹配或节点提前失败时，run 不得报告授权执行成功（multica 既有的 fail-closed：没有回执的节点完成会被拦住，不新增能力探测）。

**为什么**：

旧二进制不可能通过本次代码修改获得识别新变量的能力。可靠的边界只有发布顺序和 multica 的平台权威核验；不为此新增 crctl 能力探测。

**备选方案及排除原因**：

- 在 crctl 增加版本握手 flag／兼容协议，或让 daemon 启动前探测 tools 能力：超出最小需求且本 change 禁止新增 flag，排除。
- 宣称旧 crctl 必然报固定错误：存在 legacy 材料时不成立，排除。
- 新 crctl 无变量时一律拒绝 legacy：会破坏正常 legacy 调用，排除。

### 6. 实现与验证保持最小完整范围

**方案**：

生产代码预计只改 `skills/shared/crctl/scripts/crctl.mjs`：

1. 增加变量名常量和八命令消费者集合；
2. 增加 `resolveTrustRoot`；
3. 在 main 的解析边界调用一次。

`lib/execution-authorization.mjs`、`lib/execution-binding.mjs`、`lib/control-admission.mjs` 和事务库均不改。

测试复用现有 fixture，不新增需要真实模型、数据库或 daemon 的测试：

- 新增测试文件 `skills/shared/crctl/scripts/test/node-trust-root.test.mjs`，复用 `tac-control-fixture.mjs` 导出的 fixture；子进程 env 先清除 `CRCTL_*` 再按用例注入变量，不改 `trust-anchor-chain.test.mjs` 等既有测试文件。
- `tac-control-fixture.mjs` 的 `invokeControl` 总是追加 `--trust-root`；若新测试需要省略它，只增加默认关闭的 opt-in 选项，既有调用点不变。
- 用 `authorization-bind --check` 做同 fixture、同输入的 flag/env **stdout、stderr 原始字节及退出码对照**；该路径无动态 challenge 或 receipt。
- 用独立 fixture 验证 advance、binding、register、archive、repair 和 sensitive-action 的稳定行为，不对动态 challenge、时间戳或进程字段做不现实的逐字节比较。
- 非法值、伪造根均做 flag/env 对照；伪造根的断言是“通道间不更宽松也不更严格”，不是“必然拒绝”。
- 未设置变量时运行现有测试和全量 suite，确认 legacy 与显式 flag 用法不变。

**备选方案及排除原因**：

- 新建通用 env 解析库：当前只有一个变量和一个调用点，没有复用需求，排除。
- 新增独立测试夹具体系：会重复现有签名、binding 和工作区构造，排除。
- 以真实 daemon／数据库作为本 change 测试依赖：属于 multica 成对验证范围，排除。

### 7. `workspace inspect --detail` 补两个 authority 事实键（2026-11-14 并入，Q5）

**事实**：multica daemon 对每个 pipeline 节点任务在启动前执行 `crctl workspace inspect <CR> --workspace <root> --detail`，要求 JSON 含 `targetSpecId`（或 `target-spec-id`）与有效的 `targetVersion`（`inspectPipelineAuthority`，multica `server/internal/daemon/pipeline_task.go`）。tools HEAD 的 inspect 输出键只有 `op,cr,mode,txId,resources,changed,operationalWorkspace,operationalWorkspaceError,freshness`（`crctl.mjs` 的 `workspace` 命令 inspect 分支，`ok({ op: 'workspace-inspect', ... })`）；这两个键只出现在 `register` 的输出里。`git log -S` 证明历史上没有提交输出过它们，daemon 单测的 inspect 是手写 JSON。

**方案**：在 inspect 分支已算出 `operationalWorkspace`（`resolveOperationalWorkspace(ctx, cr).path`）之后、既有 `return ok({...})` 之前**插入**以下逻辑，不改既有行：

```text
targetSpecId = null; targetVersion = null
if operationalWorkspace != null:
    try:   m = resolveTargetSpecMode({}, cr, { authority: { path: operationalWorkspace } })
           targetSpecId = (m.mode === 'new') ? m.targetSpecId : null
    catch TxError: targetSpecId = null          # drift/缺失/非法：给 null，不新增错误码
    v = readCrMdTargetVersion(operationalWorkspace, cr)
    targetVersion = v.ok ? v.raw : null         # 原值逐字透传，包括 unassigned
Object.assign(result, { targetSpecId, targetVersion })
```

`result` 是 `ensureWorkspace` 每次调用新建的对象，既有 `return ok({ ...result, ... })` 的展开自然带上两个新键，既有行一个字符都不改。这样 `scripts/aifi45-real-run/crctl-stage.mjs`（multica 真实运行驱动的固定来源 crctl 副本）要求的「覆盖版只许对 HEAD 增行」继续成立；若 BUILD 时发现 `result` 并非本次调用独占（例如被缓存或共享），必须暂停并回到设计，不得为凑插入而绕过该检查。

**为什么这样**：

- `resolveTargetSpecMode` 与 `readCrMdTargetVersion` 已是 writeback、register 等命令使用的既有读取器，且都以 authority 路径为根（`crctl.mjs` 约 5146、5156、5177、5183 行）；inspect 本就算出该路径，复用它，不另造读取逻辑。
- 失败给 null 而不抛错：inspect 既有的 `operationalWorkspace` 也是「读不到给 null 加错误信息」的先例；daemon 对 null 以其既有错误码失败关闭（`TARGET_SPEC_AUTHORITY_DRIFT`、`WRITEBACK_VERSION_UNASSIGNED/INVALID`），所以不需要在 inspect 增错误码或错误字段。这也意味着 drift 与 legacy 对调用方都表现为 `targetSpecId` 为 null，且都被拒绝，不会放行。
- `unassigned`、`0.42` 等原值逐字透传，不在 inspect 里判有效性：有效性是调用方的合同（daemon 要求三段式），crctl 的 `normalizeTargetVersion` 对两段式版本也算有效，两边口径不同，不由本变更统一。
- 默认（summary）面不变：`projectWorkspaceInspect` 只挑选既有键，新键不在其挑选列表内；因此 detail 面多两个键、summary 面不变，`crctl-summary.test.mjs` 的真子集检查保持成立。

**金样本**：`test/golden/crctl-detail/workspace-inspect.json` 的 `fieldPaths` 由测试夹具的真实输出路径集合产生，且不计 null。夹具 CR-2026-901 带 `target-version: 0.42`，故 `targetVersion` 路径必增；`targetSpecId` 取决于夹具是否带 `target-spec-id`（BUILD 以真实输出为准，不凭印象）。该文件工作树内容已核实与 HEAD 一致（`git diff HEAD --quiet` 返回 0，`git ls-files --eol` 为 `i/lf w/lf`），可由本 change 编辑；每次编辑前重新核实，若与 HEAD 不一致则停止报告，不吞并他人改动。

**测试**：新增 `workspace-inspect-authority.test.mjs`（TC-NTR-010，六种工作区情形，独立 subtest；复用现有的 CR 工作区夹具写法，不起 daemon）；SC-NTR-010 由既有 `crctl-summary.test.mjs` 在金样本同步后承担（TC-NTR-011）。新测试文件须在 `gate-registry.json` 登记（files + cases）；注释与字符串里不得出现 `crctl <子命令> ...` 字面量（`caller-contract.test.mjs` 会扫描，见 EXP-2026-0001）。

**备选方案及排除原因**：

- 直接改既有 `return ok({...})` 一行加两个键：语义最直接，但违反「只许对 HEAD 增行」的覆盖版检查；要改就须先修订该检查并重审，成本高于一次 `Object.assign`，排除。
- 在 daemon 侧改为读 cr.md/_backlog：削弱 authority 检查，且改的是 multica 已审合同，已被用户 B2 裁定排除。
- 在 inspect 里同时输出 authority 的错误码或有效性判断：扩大合同，且两边的版本口径不同，排除。
- 另开 change：用户裁定并入（Q5），见 proposal。

### 8. crctl 自己 spawn 的 git 不经 agent 的 git shim（2026-11-14 并入，Q6）

**事实**（读码核实；三组对照为 multica A0 无模型替身运行实测，见 multica `design-adjustments.md` 的 ADJ-A0-3、ADJ-A0-4）：

- daemon 在 agent 的 PATH 前置 `{envRoot}/bin`，其中 `git`（Windows 另有 `git.cmd`）是 `multica gitguard-exec <真实 git> <调用者> "$@"` 的包装；后端读环境变量 `MULTICA_CONTROLLED_SHELL_RULES`，读不到则对每次 git 以 `SHELL_UNAVAILABLE` 失败关闭。agent 环境里没有该变量：multica 的 agent 环境构造丢弃全部继承来的 `MULTICA_*`，daemon 也不重新发布。
- crctl 的 git 调用共 10 处（`crctl.mjs` 2、`lib/change-scope.mjs` 4、`lib/workspace-transactions.mjs` 4），全是经 PATH 解析的 `spawnSync('git', …)`，在 agent 环境里同样命中该 shim。`deriveInstallRoot` 在 git 失败时回落到传入路径，所以此前没暴露。crctl 另外会 spawn `multica`（`crctl.mjs:360`）、`process.execPath`（`lib/workspace-transactions.mjs` 2 处）与测试方案声明的命令（`runTestPlan`，继承 `process.env`）；shim 目录里只有 `git`、`git.cmd` 与 daemon 写入的 `crctl` 启动器，不含这些程序。
- 三组对照（真实 podman 整栈、替身 writer、零模型费用；不是任何 TC 的证据）：① 现状：crctl 的 git 被 shim 拒绝，两个候选 `--workspace` 都在 `next` 或 `inspect` 失败，`advance` 一次也没能执行；② 仅让 shim 看到规则变量：拒绝变为白名单拒绝（`FORBIDDEN_SUBCOMMAND`），`rev-parse --git-common-dir`（`deriveInstallRoot` 的输入）与 advance 内的 `show HEAD:<CR>/execution-contract.yml` 被拒，安装根被回落成 CR worktree，第一次 `advance` 以 `EXECUTION_BINDING_INVALID` 失败，没走到平台；③ 仅让 crctl 子进程的 PATH 去掉 shim 目录、不发布规则变量：`next`、`inspect`、两次 `advance` 全部成功，没有任何白名单拒绝，`basis.grant_head` 等于授权 head，平台侧 consumption=1、effects=1/1/1，信任根读到的是该任务 generation 的目录；agent 自己直接调用的 git 仍失败关闭。

**方案**：`lib/git-shim-path.mjs` 新增纯函数 `stripGitShimDirs(pathValue, delimiter = path.delimiter)`；`crctl.mjs` 在 `main()` 的第一条语句处调用一次，仅当结果与原值不同时写回 `process.env.PATH`，其后 crctl 的全部 `spawnSync` 继承过滤后的 PATH：

```text
for each entry in pathValue.split(delimiter):        # 空条目逐字保留
    isShim(entry) = any name in ['git', 'git.cmd']:
                        f = join(entry, name)
                        f 是普通文件 且 size < 4096 且 内容含 'gitguard-exec'
                    # 任何文件系统错误按「不是 shim」处理，保留该条目
keep entries where !isShim，相对顺序不变，用 delimiter 重新拼接
没有任何条目被移除 → 返回原字符串（逐字相同）
```

**为什么这样**：

- crctl 对 git 另有自己的受控层：`controlledGit` 先过 `rules.json` 白名单（按调用者名）再 spawn，其余内部 git 的参数由 crctl 实现固定、不由 agent 决定。agent shim 管的是 agent 直接执行的 git；shim 自己的拒绝文案就是「Use `crctl git` for whitelisted operations」——crctl 的 git 若也过 agent shim，这条指引就走不通。
- 不新增 agent 能力：agent 直接调用的 git 仍走 shim、保持失败关闭；crctl 的 `controlledGit` 白名单、调用者名与命令面不变；shim 本来就不是隔离（agent 用绝对路径的真实 git 或改 PATH 就能绕过，与本 change 无关）。
- 一处入口、一个纯函数，不逐处改 10 个调用点（那要同时动 `change-scope.mjs` 与 `workspace-transactions.mjs`，也没有办法保证以后新增的 spawn 点不漏）。
- 识别用文件内容里的字面量 `gitguard-exec`——它是 daemon 隐藏子命令名，自 CR-2026-002 起就是 shim 的内容，不需要新的环境变量或 daemon 通知通道；小于 4096 字节的限制让真实的 `git` 二进制不会被读取。

**影响面（明示）**：PATH 过滤作用于 crctl 的全部子进程，包括按测试方案声明执行的命令（`runTestPlan`）；这些命令里的 git 同样不再经 agent shim，而此前 shim 因规则不可见是全拒的。声明命令由 crctl 代表授权流程执行，不是 agent 直接调用；把影响缩到 git 调用点需要逐处改 10 个点，不选。含 `crctl` 启动器的 shim 目录也一并移除，crctl 的子进程若按名字再调用 `crctl` 将找不到——crctl 自己不这样做。

**不做（明示，需用户在 Gate 审阅时确认）**：

- **daemon 不发布 `MULTICA_CONTROLLED_SHELL_RULES`**。用户 2026-11-14 选择 P 时包含该半边；对照 ② 证明它不充分（crctl 的 git 仍被白名单拒绝），对照 ③ 证明它非必要；并且它会把 agent 直接调用的 git 从「全拒」放宽成「按白名单放行」，是对所有 agent 的全局行为变化，不属于本目标。AI 把 P 收窄为只做 crctl 的一半。
- 不放宽 `rules.json` 白名单（给 `rev-parse --git-common-dir`、`show` 加许可同样会放宽 agent 直接调用的 git）。
- 不在 daemon 的 `crctl` 启动器里剥 PATH：它不覆盖直接 `node crctl.mjs`（daemon 代码注释把二者当作等价入口）。
- 不新增 shim 形态探测、环境变量、flag 或错误码。

**失败方向**：shim 改变形态（不再含该字面量）→ 剥离失效 → 回到 B4 的失败（失败关闭，不放宽）；由测试固定该标记，multica 的 A0 与真实运行端到端兜底。

**固定来源副本**：multica 的真实运行驱动使用 tools HEAD 整树加一个评审 overlay（目前只有 `crctl.mjs`，要求纯插入）。新文件 `lib/git-shim-path.mjs` 在 HEAD 不存在，该覆盖清单须同步包含它（仅允许 HEAD 中不存在的新文件）；这是 multica 侧 `scripts/aifi45-real-run/` 的实现事项，记在 multica 的调整记录与任务里，不在本 change 的受审保证内。

**测试**：TC-NTR-012，四个独立 subtest：识别并剥离（`git` 与 `git.cmd` 两种形态）、保留（无标记的 git、不小于 4096 字节的 git、无 git、不存在的目录）、无 shim 时逐字不变、真实进程接线（shim 脚本被执行即写标记并失败，其后是记录器目录；断言标记文件不存在且记录器非空，防止空通过）。真实进程子用例需要执行 POSIX 脚本，win32 skip（带原因），纯函数子用例所有平台执行；本机 Windows 的取证因此不证明接线，接线由 multica 的 A0 与真实运行在真实栈上观察。新测试文件须在 `gate-registry.json` 登记，注释与字符串里不得出现 `crctl <子命令> ...` 字面量。

## Architecture

### 调用链

```text
multica store.Root
    │  （成对 change：仅向授权 agent 进程注入）
    ▼
CRCTL_EXECUTION_TRUST_ROOT + argv
    │
    ▼
main
  ├─ git → parseGitArgs → 不解析该变量
  └─ 其他命令 → parseArgs
                  │
                  ▼
          resolveTrustRoot(cmd, flags, env)
            ├─ 非八命令：不注入
            ├─ 未设置：保持原 flags
            ├─ env-only：写入 flags['trust-root']
            ├─ 同值：通过
            └─ 异值：EXECUTION_TRUST_ROOT_INVALID
                  │
                  ▼
       bindTaskWorkspace / workspace 校验 / 命令分发
                  │
                  ▼
       现有 readExecutionGrant / repair / control admission
                  │
                  ▼
          installDirectory（唯一路径校验）
                  │
          ┌───────┴────────┐
          ▼                ▼
   <trustRoot>/grants   <trustRoot>/keys
          │
          ▼
   现有签名、来源、binding、head/root CAS
          │
          ▼
   <trustRoot>/execution-consumptions（receipt）
   
业务 CR、Git、journal 等工作区写入路径不变；信任根通道不新增输出字段或 receipt 字段（`workspace inspect --detail` 的两个新键属于决策 7，与本调用链无关）。
```

### 逐命令影响表

“变量未设”列均为当前行为；“变量已设”均指通过上述合并规则后，与同值 flag 一致。

| 命令 | 变量已设时的行为 | 关键边界 |
|---|---|---|
| `advance` | 新合同 CR 从所选根选择并读取 grant/key，经现有 control admission 后在所选根写 consumption receipt | 新合同仍无条件要求 admission/consume；legacy CR 不读取 trustRoot，行为不变 |
| `authorization-bind` | `--check` 从所选根验 grant/source；非 check 可进入现有 binding + admission + consume 路径 | 变量本身不提供 binding transport；无有效 stdio/endpoint 仍失败 |
| `authorization-scope` | 从所选根读取 grant/key 后做现有范围核对 | 只读，不进入 control admission，不写 receipt |
| `sensitive-action` | 从所选根读取 grant/source，再走现有平台配额请求 | 不新增本地配额裁决；平台传输仍必需 |
| `repair-admit` | 从所选根读取 repair grant；首次非重放写入要求 project 和现有 control admission | replay 仍沿既有回执路径；锁内重验不变 |
| `repair-resume` | 完整签名恢复请求从所选根读取并进入现有 control/replay 路径 | 参数不完整的旧恢复分支不消费 trustRoot |
| `repair-assess`、`repair-outcome` | 不生效 | 与当前显式 `--trust-root` 被忽略的行为一致 |
| `register` | 首次非重放写入进入 control admission | 可能要求额外 `--cr-id`、`--project-id`、grant；replay 判据不变 |
| `archive` | 首次非控制重放写入进入 control admission | 可能要求额外 `--project-id`、grant；既有控制 replay 不重复 admission |
| `kb`、`workspace`、`planning-entry`、`competitive-report`、`writeback-apply`、`git` 及其他命令 | 变量完全无效 | 不向 flags 注入，故白名单和 git 透传行为不变 |

失败语义：

- 冲突在 workspace 读取前拒绝。
- 路径非法在实际消费 trustRoot 时拒绝，不回退 `.crctl`，且不产生业务写入。
- 未设置变量时不新增任何分支、文件访问或输出。
- env 与 flag 的来源通道不写入输出或 receipt，保证只读结果可以逐字节一致。

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| env 可被 agent 修改，且比 argv 更难审计 | 明确不新增能力、不提供隔离；multica 以平台事实而非 env 来源作为授权依据 |
| 自造信任根可在本地形成自洽准入 | 测试 flag/env 等价性，不宣称伪造根必被拒；平台核验 daemon challenge、head、撤销和 receipt |
| `register`／`archive` 在注入环境中新增 control 要求，旧调用可能失败 | 影响表和负例固定行为；变量只注入授权 agent 进程；不为它们提供 env 专用 legacy 旁路 |
| legacy／不消费 trustRoot 的分支会忽略非法变量 | 与同值 flag 完全一致；场景和测试明确该边界，避免误解为全局 eager validation |
| 旧 crctl 忽略变量，或新 crctl 未获注入，可能走 legacy | tools 先发布；multica 对授权节点无条件注入；run 收尾核对平台权威回执（无回执即不推进） |
| 消费者清单与未来新增命令漂移 | 清单只覆盖当前实际消费者；新增 trustRoot 消费代码时必须同步评审该清单及影响表 |
| 测试 fixture 使用自签密钥和本地 endpoint，可能被误读为平台证据 | 测试注释明确只验证本地组件等价性；真实 daemon、DB、OS 隔离由成对 change 或独立隔离验证负责 |
| 工作树存在未提交 M008 改动 | 实现和测试不得读取、依赖、格式化或提交这些文件（golden `workspace-inspect.json` 经核实与 HEAD 一致，是唯一例外，编辑前重新核实）；Gate 不授权提交、推送或部署 |
| inspect 新增键被严格消费者拒绝，或被误读为 authority 有效证明 | 只增键，金样本与 summary 真子集检查兜底；字段只透传读取器结果，有效性仍由调用方判断；BUILD 时 grep 消费者，C1 复核 |
| `Object.assign(result, ...)` 依赖 `result` 是新建对象 | BUILD 时核对 `ensureWorkspace` 三处返回均为字面量；若不成立则停下回设计，不修改覆盖版检查 |
| shim 识别依赖字面量 `gitguard-exec`；shim 形态变化后剥离静默失效 | 失效方向是失败关闭（回到 B4 失败），不放宽；字面量写入接口锚定，TC-NTR-012 固定它，multica 的 A0 与真实运行端到端兜底 |
| PATH 过滤作用于 crctl 全部子进程（含 `runTestPlan` 的声明命令），或误剥其他目录 | 只移除含标记的目录，其余目录与顺序不变，由 TC-NTR-012 固定；声明命令由 crctl 代执行、非 agent 直接调用；影响面已在决策 8 明示，并在 Gate 审阅时交用户确认 |
| 剥离被误读为放宽 agent 的 git 限制 | 只改 crctl 自己进程的 PATH；agent 直接调用的 git、shim、rules.json 与 `controlledGit` 白名单不变，A0 对照 ③ 已观察 agent 直接 git 仍失败关闭；daemon 不发布规则变量 |

## 模型分层记录

- design 阶段（thorough）：由 strong 档 planner 生成初稿。`stdd config models --format json`：`model_tiers.design=strong`，`models.strong = GB-JP/kimi-k3.1-pro`（effort max）。configured = strong；requested = `GB-JP/kimi-k3.1-pro:max`；actual = unknown（会话未提供可核实的运行元数据）。
- 主会话不属于任何档位，只做抽查与修订：核对了 `flags['trust-root']` 的消费点与命令归属（crctl.mjs 1474-1511、1940-2095、2556、2594、2627-2677、6187-6225、7189-7247），与初稿一致；将第 4 节“本地伪造”事实列为 proposal 修订项（见下节）。
- 2026-11-14 并入决策 7 的修订由主会话撰写（范围小、事实已逐行核对，未再调用 planner）；并入与另开的流程成本由 balanced 子代理 `GB-JP/deepseek-flash:max` 只读调查（actual = unknown），结论由主会话据 `gate.py`、`evidence.py`、`revision-rules.md` 抽查。
- 事实调查（只读）使用 balanced 子代理 `GB-JP/deepseek-flash:max`（actual = unknown）；其结论中关于“agent 今天已能传任意 `--trust-root`”和“自造信任根可本地准入”已由主会话对照现有测试 `trust-anchor-chain.test.mjs:234-262、420-435` 的构造确认，未真实运行。
- 2026-11-14 并入决策 8 由主会话撰写。事实来自 A0 栈上 balanced 子代理 `GB-JP/deepseek-flash:max`（actual = unknown）的三组对照运行（零模型费用，仅替身 pi）；运行输出与各 git 调用清单由主会话逐条核对，spawn 点清单由主会话重新 grep 复核（含 `multica`、`process.execPath`、`runTestPlan` 声明命令三类非 git spawn）。

## 接口锚定

proposal 的 anchoring 为 L1、非 critical，不要求 L2 接口锚定；跨仓接口只有一个字面量与一条语义，在此固定：

- 变量名：`CRCTL_EXECUTION_TRUST_ROOT`（multica 成对 change 使用同一字面量）。
- 语义：等同于同值的 `--trust-root <绝对目录>`，仅对八个命令生效；值为 daemon 信任根（`store.Root`）。
- crctl 不向输出、receipt 写入通道来源。
- （2026-11-14 并入）`workspace inspect <CR> --workspace <root> --detail` 成功输出含 `targetSpecId`（字符串或 null）与 `targetVersion`（字符串或 null，原值透传）；daemon 沿用其既有读法与错误码。
- （2026-11-14 并入）shim 识别标记：字面量 `gitguard-exec`（multica `cmd/multica/cmd_gitguard.go` 的隐藏子命令名，亦是 `daemon/execenv/crguard_config.go` 所生成 `git`/`git.cmd` shim 的内容）。识别规则见决策 8；multica 改变 shim 形态前须同步本 change。

## 用户裁定与对 proposal 的修订（2026-11-13）

- Gate 1 时用户对 Q1–Q4 回复“确认”，视为接受 proposal 中的建议。
- 设计调查发现 proposal 原成功标准“自备目录中的伪造 grant 或公钥不能使 advance 成功准入”与现有代码和 fixture 不符，且本 change 的边界排除新增信任锚机制。已把该条改为“环境变量通道与 flag 通道等价、本地准入不构成平台授权证明”，并同步 what_changes、风险、非目标、Q1–Q4 结论。proposal 字节已变化，Gate 1 过期，需要与 Gate 2 一并重新确认。

## 2026-11-14 并入 B2 的用户裁定与修订

- multica 无模型替身运行（A0）发现 inspect 缺 authority 字段；用户先选「B2 选 A（tools 补字段）」，经只读成本核对后裁定**并入本 change**（Q5），不另开。
- proposal 字节变化（范围描述、约束、成功标准、非目标、风险），Gate 1 过期；design、canonical spec、test-plan 同步变化，Gate 2 过期；Gate 3 的输入含 Gate 2 输入，随之过期，且证据 run `e9c97c8d-…` 冻结的 `skills/shared/crctl/scripts` 输入会因 `crctl.mjs` 与金样本变化而失配。三道 Gate 均须由用户亲自重签（`--reapprove`，旧批准保留为 superseded 回执）；实现后须在最终代码上取新 run，旧 9 项检查与 B2 的 2 项在同一个 run 内。
- 既有 5 项调整（ADJ-1..5）仍只记录在 `design-adjustments.md`，未落入受审文档，沿用原处置。

## 2026-11-14 并入 B4 的用户裁定与修订

- multica A0 发现 agent 环境里 git shim 缺规则变量、对每次 git 失败关闭，crctl 的 git 也在其中；用户在「P / Q / R」中选 **P，并入本 change**（不另开）。
- AI 随后用 A0 栈做了两组对照（见 multica ADJ-A0-4），把 P 收窄为 crctl 的一半（决策 8）：daemon 发布规则变量的一半既不充分也非必要，且会全局放宽 agent 直接 git，故不做。**该收窄点由用户在 Gate 1/2 重审时确认或推翻**；若推翻，daemon 一半须回到 multica 受审文档另行修订。
- proposal 字节变化（Why、范围描述、约束、成功标准、非目标、风险、Q6），Gate 1 过期；design、canonical spec、test-plan 同步变化，Gate 2 过期；Gate 3 的输入含 Gate 2 输入，随之过期。旧证据 run `e9c97c8d-…` 冻结的输入已因并入 B2 失配，实现后须在最终代码上取新 run：原 9 项、B2 的 2 项与本次 1 项在同一个 run 内。三道 Gate 均须由用户亲自重签（`--reapprove`）。
- 实现在 Gate 1/2 重审通过前不开始。
