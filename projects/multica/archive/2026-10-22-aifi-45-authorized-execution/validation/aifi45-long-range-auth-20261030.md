# AIFI-45 全自动长程：限定授权清单（待确认）

**状态：DRAFT，不是授权回执。** 用户本轮提出“启用全自动长程模式”，这是模式意向，尚不是对本清单的确认；此前对全自动的选择针对新的 verdict change，不能冒称原 AIFI-45 已选长程。原 AIFI-45 的 M/T 两侧当前均为 BUILD、`long_range.mode: normal`。STDD 3.0.7 在 Gate2 后要求先按具体产物展示一次性清单、取得确认，再记录预授权；本文件本身不改变模式或权限。

**本次申请范围：** 仅对应 `projects/{multica,tools}/changes/2026-10-22-aifi-45-authorized-execution` 两侧剩余 BUILD；两侧分别记录同一真实用户确认与实际生效状态。`2026-10-29-trusted-verdict-outcome-binding` 两侧仍在 SPEC，此清单不覆盖其 BUILD；待其自身 Gate2 后按届时设计和测试方案重新展示清单。排除其他所有 change，包括仍在 UNDERSTAND 的 `2026-10-30-aifi-45-ci-disposable-db-supervisor`、`2026-10-30-aifi-45-evidence-delivery-integrity` 和 `2026-10-29-legacy-execution-migration`；不能提前实施。

**中途切换限制：** 原 AIFI-45 原先选择普通模式，现已进入 BUILD。STDD 3.0.7 `spec.md` 描述进入 BUILD 前的 Step 8a，`build.md` 描述 BUILD 中途退出，但未明确普通 BUILD 中途启用的原生流程。本清单只是拟参照 Step 8a 的限定授权方案；待用户确认后，仍须核实中途切换、可追溯状态写入及宿主权限的合规方式，不能保证 CLI 提供原生命令或先把 YAML 改成 `full_auto`。实际状态、有效限制与证据必须分别报告。

## A. 流程决策

- **A1 设计偏离：** 在已批准的实现范围内，小偏离自动记录并验证；重大行为/合同/安全偏离先记录影响，须审批的路径停止，不能篡改旧批准文本或把草案当授权。无依赖且安全的工作可继续。
- **A2 技术阻塞：** 普通阻塞先尝试已批准范围内的安全替代；不可安全解决则跳过该切片并标待处理，可继续无依赖切片。安全、HOLD、审批或真实数据边界受影响时降级并暂停该路径，不能以“绕过阻塞”破坏边界。
- **A3 迭代上限：** 每项最多 10 轮；到上限仍未解决时暂停并报告，不把失败伪装成完成后进入 Gate3。同一问题连续修复 3 次失败、测试通过率低于 95%、安全问题、零 TC 覆盖或连续三切片无新增测试，均暂停受影响路径；零 TC 覆盖处规范的 warning/degrade 文案不一致，本清单采用更严格的暂停，不静默继续。
- **已有 major：** 当前两侧 `pending-adjustments.yaml` 中 M 的 M001–M005 和 T 的 001–003 为 unresolved major；改变模式不自动关闭或豁免这些项，不减少原验收及 Gate3 条件。

## B. 操作授权与限制（对应 STDD 模板 B1–B7）

| 项目 | 拟授权 | 明确限制 |
|---|---|---|
| B1 目录操作 | 创建本轮项目内必要目录 | 不删除/覆盖未知归属文件；只清理本轮可证明归属且已授权资源 |
| B2 文件写入 | 在已批准范围修改源码、测试、任务和证据，按项目规范登记 `CUSTOM.md` | 保护未提交改动；新 change 或旧合同变更须先过各自门禁，不代用户审批 |
| B3 命令执行 | 仅执行下方具体清单中的只读诊断、静态检查和本地测试 | 测试前核身份、隔离、精确选择及副作用；不得触及历史事故资源或真实 CR |
| B4 脚本执行 | 仅执行下方具体清单中经复核的入库脚本 | YAML 账本必须用版本化脚本，但当前清单未包含账本更新脚本，须另行列明并获确认；禁止运行/改向旧 AIFI-45 runner |
| B5 网络及依赖 | 不默认授权真实外部 API、下载、安装新依赖或发布 | 如确需超出现有批准的网络、依赖或权限，暂停并另行请示 |
| B6 文件读取 | 读取适用规范、模板、源码和非敏感证据 | 不读取或输出密钥、凭据、既有容器环境，也不读取历史事故库 |
| B7 Git 只读 | 自动执行 status、diff、log 等只读操作 | 不 commit、push、merge、部署、修改真实 CR 或执行人类审批 |

### B3/B4 的具体执行清单

- 允许在相关项目目录只读运行 `git status --short`、`git diff --check`、`git diff` 与必要的 `git log`；以及原 AIFI-45 change 的 `stdd status`、`stdd validate`、`stdd canon verify 2026-10-22-aifi-45-authorized-execution --dry-run` 和 `stdd config models --format json`，输出避开敏感内容。`canon verify` 不加 `--dry-run` 可能重新生成文件，不是只读命令。
- `node --check <本 change 经审核的单个源码文件>` 仅做语法解析。以下 T 侧 `test-plan.md` 中**已点名**的命令，需先审查其当前源码/导入、目标、临时文件创建与精确清理，确认证据和隔离条件成立，才在 `../tools` 自动运行；不通过安全复核即 BLOCK：
  - `node pipeline-templates/emit-registry.mjs`；`node --test pipeline-templates/emit-registry.test.mjs`；
  - `node skills/shared/crctl/scripts/check-agents-contract.mjs`、`node skills/shared/crctl/scripts/check-skill-matrix.mjs`、`node skills/shared/crctl/scripts/check-pipeline-contracts.mjs`、`node skills/shared/crctl/scripts/lint-prompts.mjs`。
- M 侧 `test-plan.md` 中的 `pnpm -C packages/core test realtime/use-realtime-sync-inbox.test.tsx -t NTF-005` 及 `-t NTF-007`，须先核该脚本、依赖、初始化与无外部副作用，且不得自动安装依赖；当前测试文件未见这两个筛选标签，尚不能按该筛选选中目标用例，保持 BLOCK，不能以零选中或 skip 当通过。只有实现所需标签并确保精确选中后才运行。M 的 DB 相关 `go test` 包/用例和 generator 待下述隔离与命令计划通过后另行明确，不在本清单现时可运行范围内。
- 其他 Node/Go 测试、构建和脚本须先追加具体路径、参数、目标与安全复核结论并获用户确认，不能由 agent 单方面扩充本授权；不因此授权整包 `go test ./...`、真实网络测试或任意命令。暂时无法证明安全的测试保持 BLOCK，不以假绿替代。

**隔离数据库：** 历史事故库、容器与卷继续 HOLD。用户此前已授权新建独立本地可丢弃 PG 并清理本轮可证明归属的资源；这份清单不撤销该授权，也不授权访问或清理历史资源。新 PG 基线、替代入口须经用户明确批准、方式已核实的设计修订与记录，隔离/身份/权限/清理方案也须经验证；当前都未完成，不能执行。创建容器的具体命令、仅用可核对来源与摘要的本地镜像、所需权限、仅查看本轮实例非敏感最小元数据及精确清理，须先列入经用户确认的计划；镜像缺失不能自动下载，不得输出任何容器环境或完整 inspect。

原 M 测试计划的 DB 入口 `multica/scripts/aifi45-db/run.mjs` 当前固定指向 HOLD 实例，即 B4 禁止的旧 runner：不得运行，也不得仅通过换 URL 绕过。governance 父包测试初始化安全尚未证明，不能直接运行；不安全 fake-I/O 不能冒充验收。**在上述条件和正式替代入口获批前，DB 相关 TC 无法自动完成，因此本授权本身不能让 Gate3 达到 GO。**

## C. Gate、宿主与确认

- 原 AIFI-45 两侧已有 Gate2，但存在安全及 major 阻塞，Gate3 当前 NO-GO，最终须人确认；`crctl approve` 与真实 CR 流程同样不能代人操作。
- 可信 verdict 草案仍待其自身 Gate2；SC-MG-015/016 若修改须按原合同变更流程评审。用户接受方案方向不等于批准这些 Gate。
- 本会话宿主是 **pi**：不擅写 Claude Code 专属 `.claude/settings.local.json`；真实工具权限由 pi 宿主管理。若必要权限不能落实或条件不能表达，停止并如实报告，不宣称实现了模板全部自动化。
- STDD CLI 当前 `status` 只显示 `long_range.mode`，不会显示本文的细粒度约束；即便未来登记 `full_auto`，对外也必须说“**受限 full_auto**”并引用本清单，不能据 CLI 单字段输出推断各项预授权、权限或测试已落实。
- 确认后保留用户原话和最终清单版本，分别核对两侧状态；是否存在版本化的模式切换入口、BUILD 中途切换和保存位置须先查明。未经验证不得手改状态冒称原生启用。两个 change 的 `long-range-auth.md` 应有可追溯授权记录或指针，但确认前不得生成虚假回执。

## 审阅请求

用户可回复**“确认以上限定授权”**，或按 A/B 编号提出修改。该确认仅是上列两侧原 AIFI-45 的拟议限定授权，不批准新 change 的 Gate2、原 Gate3、生产部署、真实 CR 或历史事故资源操作；实际能否原生启用仍须通过以上检查。
