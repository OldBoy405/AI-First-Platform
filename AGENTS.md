# AGENTS.md — AI First Platform 工作区行为约束

本仓库是 AI First 平台的设计文档与知识库工作区。仓库和路径以 `dir-graph.yaml` 为准；`../tools/` 是 sibling 方法论包，不是本仓库的 `tools/` 子目录。

## 流程选择与读取

- 只读分析不创建变更；读取与问题相关的资料，不自动注册 STDD change 或 CR。
- 已有变更沿用原流程。若请求与原流程冲突，先停止冲突操作并确认迁移方案；不映射状态、不双写任务、不伪造完成。
- 新开发变更默认使用 STDD。先明确目标业务仓，核实其 `.stdd/binding.yaml`、资源根与记录根，再从业务仓优先加载当前阶段的已安装 STDD Skill；若对应入口未安装，从已核实资源根的 `.stdd/skills/` 读取该阶段 Skill，不假称命令已注册；资源不可用时停止。仅知识库 cwd 无绑定不是失败：目标仓及其绑定明确时先核实三根，从业务仓执行。
- 用户显式选择 tools CR 时，按 `../tools/AGENTS.md`、`../tools/README.md` 和当前阶段的 Pipeline／Skill 执行；注册以 `requirement-register` 和 `crctl register` 的现行契约为准。按任务和阶段加载资料，不无条件读取完整 CR 手册。
- 无论选哪个流程，变更身份、目标仓、绑定或归属不明、或彼此冲突时，先停止并询问，不执行受控写入；不猜目录、不自动初始化、不回退旧模式、不同时写两个流程。
- STDD Gate 不替代 CR 审批，CR 审批也不自动确认 STDD；评审、人工审批和合法授权按各自流程执行，Agent 不得代签。记录不等于批准或执行；STDD Gate 与 CR 审批都不自动授权 Git 提交、推送或部署，这些操作按所属流程另行取得授权。

## 事实源与目录

- 本工作区目录及仓库声明：`dir-graph.yaml`。STDD 资源在 `../stdd/`；目标项目的 binding 决定记录根及项目 ID，现有记录按项目放在 `projects/`。
- CR 的 Tools Root 由 `dir-graph.yaml#workspace.tools_package_path` 确定；状态机与门禁以该包的 `dir-graph.yaml#change-request-track.state_machine` 和 `skills/shared/crctl/gates.json` 为准，本仓库不复刻。CR 下一步、参数和恢复以现行 `crctl` 与相关 Skill 为准。
- CR 操作根以 crctl 返回为准；接手在途 CR 使用 `crctl status`／`next`，不凭主 checkout 的陈旧快照判断状态，不自行拼 worktree 或事务工作区路径。
- `specs/` 和 `delivery/` 承载 CR 回写的基线及交付物；基线是累积文档，不得覆盖历史。`docs/product/`、`docs/analysis/` 的跨 CR 资产不强行迁入 `specs/`。

## 工程纪律

- 对仓库文件做哈希、跨行正则或逐行解析的代码，读入后先将 `\r\n` 规范化为 `\n`；逐行解析使用 `split(/\r?\n/)`。解析失败必须硬失败，不得静默降级为空数据。
- 事实断言先核实；实施中发现 PRD／SDD 的依据不符，按 revision 修订并说明结论是否受影响。
- 修改目标仓前先读取其约束；multica 代码注释用英文，本仓库和 tools 文档用中文。修改 multica 代码须按其当时 `CUSTOM.md` 的结构登记定制，追溯真实流程的变更和任务标识；格式不接受该标识时停止并确认，不编造 CR 身份。
- **STDD change 记账**：遵循当前 STDD Skill、模板及命令规定。Skill 指定 CLI 或版本化脚本入口的操作，必须使用该入口；Skill 明确要求更新 `.stdd.yaml` 等流程记录、但未指定专用入口时，允许用 Edit 按要求精准更新相应字段，不因缺少专用 CLI 而停止。此授权不允许替代 Gate 确认、跳过验证、伪造结果或绕过 STDD 的阶段推进规则。
- **CR 记账**：遵循 Tools Root 的现行工具及相关 Skill。CR 状态、审批、任务、额度、索引和权威投影等执行账本，只经其规定的合法入口处理；禁止手工或会话内现写脚本改写。脚本已入库、可测试，不代表可以绕过所属流程的权限、唯一入口、CAS、审计、review／approve 或门禁。任务完成后按实现 Skill 即时登记，不积压到回写期。关联 STDD change 不改变 CR 账本的归属和规则。
- **记录完整性**：修改前确认记录所属 change／CR；按所属流程的模板维护，保留原记录及扩展字段，写后核对 YAML 可解析性与修改差异。设计偏离记录须依据原话或可靠来源，区分事实、具体决定、执行授权和未决事项；记录不等于批准或执行，`resolved` 须如实反映处理状态。
- **其他账本**：继续遵循其所属工具和流程的合法入口规则；归属不明或规则不明确时停止确认，不自行套用 STDD 的直接编辑授权。