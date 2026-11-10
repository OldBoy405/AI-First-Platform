# BUILD 验证报告（未闭合）

> Change：`2026-11-06-stdd-default-cr-opt-in`；documentation / standard / 普通模式。
> 历史 Gate 2 已确认方案 A；2026-11-10 修订版 Gate 2 重新确认待完成。当前仍为 BUILD，Gate 3 pending；本报告不是批准、交付证明、实际模型路由验证或原生 TC 执行证据。

## 结论与阻塞

此前已按批准范围修改知识库四个入口、tools `AGENTS.md` 和用户级 `APPEND_SYSTEM.md` 第 2 行，并完成部分静态、语义和差异检查。2026-11-10 仅在本 change 内原位修订记录，未修改上述业务／全局文件。**BUILD 尚未完成；已确认工具缺口，停止推进，不提交 Gate 3**：

1. 原生 TC 当前执行覆盖实际检查仍为 **0/10**；缺少有效的独立 run 和受控原生执行证据。STDD 并非只允许运行时测试：证据计划支持 command/manual，人工确认可绑定 run／冻结输入。但其项目级 CP 读取、共享报告写入和 project/data 两根输入限制，使本 change 的跨根文档验收无法在“仅修改本 change”范围内闭合。这是 STDD 工具缺口，详见 design D7／test-plan；方案 A 与本次修订授权均不豁免该检查。
2. STDD 确定性检查仍报告缺少必需 `coverage.json`。源码已有带理由的 `coverage: {applicability: not_applicable, reason: ...}` 合法机制，但必须先通过读取项目级 CP 的完整计划校验，不能单独填豁免字段绕开限制。本轮不创建不可执行计划、不制造覆盖文件、不改全局配置。
3. tools 全量质量测试 **未运行**：发现 `execution-control-isolation.test.mjs` 需要真实受限身份，可通过 WSL root 操作宿主 `/var/lib/aifi45/` 并启动 detached 子进程；仅复制目录、限制 Git 协议不足以保证隔离。未证实安全边界，普通模式下停止该项。
4. 未发现 `phases.build.slices_completed` 的合法写入口；没有原生切片完成记录。不手改 `.stdd.yaml`，不以任务勾选冒充切片证据。
5. `ADJ-001` 已按用户 2026-11-10 决定完成设计层调整：D5／CP-PG-003／TC-PG-003／spec 仅保留批准新句，取消并行替代预期。修订版 Gate 2 重新确认未完成，故 resolved 仍 false；`ADJ-002` 的完整重写偏离与并发窗口风险仍未处理。gate status 实查原 Gate 2 为 historical/unfingerprinted，不自动变 stale；不能以旧批准推定修订版已确认。

## 条款与场景

| 项 | 已执行的检查 | 结果与边界 |
|---|---|---|
| 修改前静态基线 | 逐项运行 10 个原始 CP 的只读文本 action | WFR-001–006、PG-001–003 失败；PG-004 通过。不是人为破坏文件，也不是原生 TC 结果。 |
| 修订前静态 action（历史） | 先前从 tools 根执行 10 个 action 并核对规格／输入前后 LF 哈希 | 当时 WFR-001–006、PG-001/002/004 共 9 条退出 0，PG-003 退出 1；旧句断言失败的历史保留在 ADJ-001，不是当前并行预期。 |
| 当前 CP-PG-003 | 2026-11-10 从 tools 根执行修订后的唯一 action，使用声明的 venv Python，以直接 argv 加 `-I -B -X utf8` 执行并核对声明断言与三个输入的前后 LF 哈希 | exit 0，`CP-PG-003 STATIC PASS`，哈希前后一致；只证明新句及该 action 覆盖条款，本轮未重跑其余 9 个 CP，不产生原生 TC 证据。首次 shell=True 包装执行 exit 1，并出现 UTF-8 解码错误，未计通过；改以直接 argv 执行同一断言，未改 action 或增加替代预期。 |
| 人工文案场景（历史） | 先前独立评审 10 个场景的路由、写入、授权和停止条件；本轮未重新执行完整语义评审 | 文案可复述主要规则；未执行真实 STDD／CR，不能证明运行时行为。PG-001 的 Claude 入口残留和 ADJ-002 并发风险仍在；修订授权不是当前 run 人工签认，不将 10 项记为验收通过。 |
| 规格数量与兼容视图 | 9 Requirement、10 Scenario、10 CP、10 TC；两份 spec.md 保留 | 定义数不是执行覆盖；BUILD A1 的无 YAML 回退及 DELIVER Step 2 的合并步骤仍需 spec.md，故不删除。它们不作为需同步维护的第二来源，评审直接引用 Canonical CP，canon verify 不覆盖它们。 |

## quality 与结构

下表业务 quality 为 2026-11-06 的历史执行记录，本轮未重跑；四项 STDD 检查于 2026-11-10 从 tools 业务根重新运行：

| 检查 | 实际结果 | 范围 |
|---|---|---|
| `lint-prompts.mjs` | exit 0，report 模式 **0 findings** | tools 内对应规则；不扫描本次全部根／全局文件。 |
| `lint-prompts.mjs --mode enforce` | exit 0，**0 findings** | 同上，不替代跨入口语义检查。 |
| `check-agents-contract.mjs` | exit 0 | Agent 合同；不证明运行时 guard 已执行。 |
| `check-skill-matrix.mjs` | exit 0 | Skill 矩阵一致性。 |
| quality 的 Node 全量测试 | **未运行**；原工作树发现 82 + 3 + 1 = 86 个测试文件 | 进程级与宿主隔离尚未确认；tests/pass/fail/skipped、退出码和耗时均不可用。没有创建测试副本或临时 fixture。 |
| `stdd validate <ID>` | exit 0 | change 结构，不代表 BUILD 验收。 |
| `stdd proposal validate <ID>` | exit 0 | proposal YAML。 |
| `stdd canon verify <ID>` | exit 0，2/2 | proposal 的哈希／正文；**不覆盖**两个 Agent CP 或人工评审副本。 |
| `stdd ci check-failures <ID>` | 2026-11-10 exit 1：6 PASS、1 WARN、1 SKIP、2 FAIL | CLI 确定性子集：缺 coverage.json、TC 执行覆盖 0/10、缺调用方独立选定的有效 run；无切片记录 SKIP。范围蔓延告警涉及 10 个可能越界文件，非本次修订归因。完整 14 类含语义检查尚未全量执行。 |

上表前四项的历史复验时间为 2026-11-06 13:48（+0800），当时 lint report、lint enforce、Agent 合同及 Skill 矩阵均 exit 0，两种 lint 均为 0 findings。2026-11-10 另运行 `gate status <ID>` exit 0（Gate 1／2 historical/unfingerprinted，Gate 3 pending），以及 pending-adjustments 的只读 YAML 校验 exit 0（先 CRLF→LF，核对归属、类型、必需字段、两条 ID 唯一及无冲突标记）。本轮没有运行 Node 全量测试、完整 10 CP 或生成原生 TC／覆盖率证据；工具缺口未消失。

CI 范围告警列出 tools 工作树其他既有 dirty 文件，不能将它们归因于本 change。`code-structure-delta.md` 也扫描了整个 dirty 工作树，不是本次交付文件清单。

## 差异、安全与评审

- knowledge base 的 `dir-graph.yaml` 语义比较：除允许修改的 repository description 外，解析对象相等；顶部 Tools Root 注释已单独核对。
- 根 `AGENTS.md`：LF 字符数 **6,287 → 2,139**；由 HEAD、当前账本条目正文和其原编号重建的写前内容与记录的写前 LF SHA-256 一致。账本保护正文逐字保留，列表编号改为项目符号；哈希不是并发锁，ADJ-002 记录了完整重写与核查／写入间并发窗口风险。
- `README.md`、`CONTEXT.md` 的变动局限于入口说明；tools `AGENTS.md` 的变动局限于阅读顺序、章节作用域和编排事实源表述。最新复核将其平台包边界第 7 条中的“在途变更”明确限定为“在途 CR”，并注明其他流程按自身规则管理；保留 CR 的原有规范模型。针对新开发、显式 CR、已有变更、只读、状态／任务隔离、审批隔离及 CR 记录范围的 8 项文本检查通过，tools lint enforce exit 0。这些是静态检查，不证明实际路由。相关 Git `diff --check` 退出 0；没有暂存、提交、重置或清理其他 dirty。
- 用户级文件此前仅第 2 行按 ADJ-001 变动，其余 LF 内容当时依据写前哈希核对；本轮未写该文件。`pending-adjustments.yaml` 的历史与扩展字段保留，ADJ-001 新增 decision，说明设计层已处理、修订版 Gate 2 确认仍 pending；两条 resolved 均为 false，不把记录当批准。
- 已有三路独立只读评审结果（安全／正确性、测试／配置、文档／Skill），并针对身份与目标冲突、解析硬失败、资源 Skill 回退、陈旧状态说明及列表格式补充修正。配置的 strong / balanced / economy 模型分别为 `OpenAIPersonal/gpt-6.1-sol` / `OpenAIPersonal/gpt-6.1-terra` / `Gobao/deepseek-flash`；后续评审按配置请求，实际后端模型缺少可核验元数据，记为 **unknown**。静态语义评审不等于运行时验证。

## 已知范围外风险与未完成项

- `../tools/CLAUDE.md` 仍要求 Claude 无条件读取完整 README，与按需加载目标冲突；不在已批准修改范围，**不能宣称 Claude 场景已闭合**。
- `../tools/AGENTS.md` 的部分既有 CR 驳回描述与当前 `../tools/dir-graph.yaml` 存在漂移；`CONTEXT.md` 存在历史 `cr-init` 术语。真实 CR 以现行合同为准，本次未擅自改动 CR 合同或领域正文。
- 完整 14 类失败模式、经验库命中更新及受控 `design-adjustments.yaml` 汇总尚未完成；不将部分检查写成完成，也不把未知归属 YAML 当成可随意编辑的执行账本。
- 未运行或模拟实际注册／审批／迁移／部署；未调用会写项目共享报告的 `agent verify`，未修改现有 quality 配置。未测量 token 消耗或提供部署成功结论。

## 后续处理方向（未经执行）

停止 BUILD 推进，等待另行授权解决跨根、change-local 文档验收的 STDD 工具缺口及切片状态入口；不在本次修改 STDD 或其他目录。修订版 Gate 2 仍需按 Skill 重新展示确认；原批准无指纹，CLI 不会自动判 stale，现有 reapprove 对历史批准幂等返回，不能手改状态冒充重新冻结。隔离测试环境、ADJ-002 与范围外入口风险仍未闭合。只有真实满足适用强制检查并形成报告后，才可请求 Gate 3；提交、推送和部署仍需独立授权。
