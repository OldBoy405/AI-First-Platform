---
id: CR-2026-040-prd
type: PRD
cr-ref: CR-2026-040
title: tools CR 生命周期最小优化 3/5 — 结构化测试闭环
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-14T19:45:43+08:00
updated: 2026-08-14T19:45:43+08:00
---

# 1. 概述

当前 Tools 包的正式测试证据由 `crctl test`、`write-test-report`、Pipeline 和代码评审共同维护，但入口仍接收 shell 命令字符串，执行与记录分散，且 `test-report.md`、`traceability.yml#tests` 和 review-loop 可能分别更新。这样会产生三类生命周期风险：

1. 测试命令的解析和执行边界依赖 `shell:true` 或字符串拼接，命令参数中的空格、Unicode 和 shell 元字符可能导致误执行或结果不一致。
2. 测试运行已完成但机器证据尚未完整发布时，进程中断、重复重试或单文件写入失败可能留下半套报告，后续代码评审和审批无法判断证据是否完整。
3. `test-report.md` 的机器结果与人工/模型分析混在同一生成路径中，重跑测试时可能覆盖人工分析；反过来，人工分析也可能误改由 `crctl` 生成的 status、commands 或测试账本。

本 CR 落实跨 CR 生命周期规格的实施切片 3，仅覆盖 FR-07、FR-08：将正式验证收敛为一份结构化 `cr-test-plan/v1`，由单一 `crctl test` 深接口以 `shell:false` 执行；在所有命令完成后，以既有 durable transaction 原子发布机器测试证据、`traceability.yml#tests` 和 review-loop attempt；再由 `write-test-report` 只维护 `<!-- crctl:analysis-below -->` 之后的人工分析区。测试失败是可记录的业务结果，测试计划、工作树、执行器或事务失败是技术错误，二者必须分流。

本 CR 不建设测试平台、日志服务、通用 `run/record` 协议、binary write-set、完整工作树 hash、配额系统或新的事务框架。实现必须遵循 ponytail 优先级：复用既有 `crctl`、durable transaction、review-record、controlled Git、Node 标准库和现有测试 fixture；只在现有深接口无法表达且存在真实故障时增加最小代码。

# 2. 用户故事

- **US-01 开发负责人**：希望正式验证只由一份明确的结构化计划驱动，参数按 argv 传递，不因 shell 字符串解析差异执行了错误命令。
- **US-02 测试负责人**：希望测试结果、原始日志、报告机器区、traceability 测试证据和 review-loop 轮次在一次成功发布中保持一致，失败后可按同一入口完整重试。
- **US-03 代码评审者**：希望只读取最终 `test-report.md`、真实日志和结构化 command digest，不需要重新执行 lint/test/build，也不会采信缺少 canonical 证据的报告。
- **US-04 需求/开发 Agent**：希望只负责路由、业务判断和选择 Pipeline/Skill，不保存测试命令表、不维护状态机、不直接写受控账本。
- **US-05 Tools 维护者**：希望在 Ubuntu 和 Windows 上复用 Node 标准库与既有事务设施，区分技术失败和测试失败，不引入第二套执行器、记录器或状态推进实现。
- **US-06 流程接续者**：希望测试重跑、review-loop 回修和 checkpoint 继续遵循现有 CR 状态、评审和审批门禁，任何不完整证据都不能进入代码评审或人工审批。

# 3. 功能需求

## FR-01 结构化测试单一深接口

1. 保留一个公共测试入口：

   ```text
   crctl test <CR-ID> --plan <temporary-plan.json> --workspace <knowledge-base-worktree>
   ```

2. 该入口内部可以有“执行计划”和“发布记录”两个顺序阶段，但不得对调用方公开或要求调用方组合 `test run`、`test record` 两个命令。
3. 调用方不得传入任意 shell 命令字符串、管道、重定向、命令拼接、candidate 路径、状态、review-loop 轮次或 traceability payload。
4. `crctl test` 负责结构化计划校验、测试命令执行、原始日志保存和机器证据原子发布；不负责测试发现、TASK 业务覆盖判断、测试质量评审或 CR 状态推进。
5. 入口必须校验当前 CR 处于合法开发状态，并校验 `cr.md` 中 `owners.test.id` 与 `owners.test.assigned-at` 存在。非法状态或缺少测试负责人时技术失败，canonical 测试证据不变。
6. 入口成功输出至少包含：`op`、`cr`、`attempt`、`status`、`commands`、`test-report`、`traceability`、`review-loop` 和可供 Pipeline 分流的结构化结果。
7. `crctl test` 不新增状态、状态转换、人工审批或独立 test-run ledger。状态推进继续由现有 `crctl advance`，人工审批继续由现有 `crctl approve`。

## FR-02 `cr-test-plan/v1` 输入合同

1. 测试计划 schema 固定为 `cr-test-plan/v1`，最小形态如下：

   ```json
   {
     "schema": "cr-test-plan/v1",
     "commands": [
       {
         "repo": "tools",
         "cwd": ".",
         "executable": "node",
         "args": ["--test", "test/example.test.mjs"],
         "timeoutSeconds": 600
       }
     ]
   }
   ```

2. `commands` 必须为非空数组。每条命令必须包含：
   - `repo`：目标 workspace `dir-graph.yaml#repositories` 中已声明且 active 的 repository id；
   - `cwd`：相对于该 CR worktree 仓根的相对路径，缺省为 `.`；
   - `executable`：非空可执行文件名或路径片段；
   - `args`：字符串数组，允许空数组；
   - `timeoutSeconds`：正整数，并受既有执行超时上限约束。
3. `repo` 必须解析到当前 CR 的对应 worktree。未声明仓库、缺失 worktree、分支不是 `requirement/{CR-ID}` 或解析失败时硬失败。
4. `cwd` 必须规范化后位于对应 CR worktree 内，不接受绝对路径、`..` 穿越、跨仓路径或通过符号链接逃逸 worktree 的路径。
5. 计划和字段解析必须先将 CRLF 规范化为 LF；同一语义的 CRLF/LF 计划必须得到相同 canonical digest。解析失败必须硬失败，禁止静默跳过坏命令或降级为空数组。
6. `crctl` 不从仓库自动发现测试命令。`write-test-report` 根据 TASK 验收条件、仓库原生 lint/test/build 配置和 `implement-code` 输出选择命令，并生成临时结构化 plan；Agent 不保存正式命令表，Pipeline 只传递 CR、worktree 和前序输出。
7. 计划文件是一次调用的临时输入，不作为新的 canonical 产物长期写入 CR；报告机器区记录规范化后的 command 对象和整体 digest，避免重复维护一份 `plan.json` authority。

## FR-03 安全执行与命令结果语义

1. 每条命令必须通过 Node 标准库 `child_process.spawnSync(executable, args, { shell: false, cwd, timeout })` 或等价的 `shell:false` 原生执行路径运行。
2. `executable`、`args`、`cwd` 和 timeout 必须分别传入执行器，不得拼成一条 shell 字符串。命令中的空格、Unicode、引号、`;`、`&&`、`|`、`>` 等字符只能作为参数数据处理，不得获得 shell 语义。
3. 运行阶段不创建 durable journal、不持有受控账本写锁、不修改 `cr.md`、`_backlog.yml`、`traceability.yml` 或 review-loop。运行阶段只收集每条命令的退出码、信号、timeout、stdout/stderr 和执行元数据。
4. 已成功启动的命令返回非零退出码或 timeout，属于**业务失败**：
   - 记录该命令的失败结果和日志；
   - 继续执行计划中的其余命令；
   - 所有命令结束后统一生成 `status: block` 的完整 canonical 证据；
   - 不因一条失败命令跳过其余命令，也不提供 `continueOnError` 等额外分支配置。
5. 计划 schema、repository、worktree/cwd containment、executable 启动或参数校验失败，属于**技术失败**：
   - 立即中止；
   - 不发布新的 canonical test report、traceability tests 或 review-loop attempt；
   - 以结构化错误返回失败原因、文件/字段和可重试动作。
6. 运行阶段发生外部中断或进程无法完成全量计划时，不能把部分结果发布为新的 canonical attempt，不能覆盖上一轮 canonical report；重试必须从完整 plan 重新执行。
7. `implement-code` 可以执行开发期临时检查，但其输出不能替代本 FR 定义的 canonical `crctl test` 记录。`review-code` 不得执行或重新执行 lint/test/build。

## FR-04 机器证据原子发布

1. 所有命令结束且结果已归类后，`crctl test` 必须使用既有 durable transaction 同批发布以下机器事实：
   - `change-requests/{CR-ID}/test-report.md` 的机器区；
   - `change-requests/{CR-ID}/test-evidence/` 下与每条命令对应的原始 stdout/stderr 日志；
   - `change-requests/{CR-ID}/traceability.yml#tests`；
   - `change-requests/{CR-ID}/review-loop.yml` 中 `write-test-report` 的 attempt，以及 traceability 中对应的 review-loop 投影。
2. 正常业务失败也必须完成上述一次性发布，只是 canonical 报告为 `status: block`，并由 Pipeline 回到 `implement-code`；业务失败不是事务错误，不得因为非零退出码回滚或丢弃测试证据。
3. 任一技术校验、文件写入、CAS、事务提交或发布失败时，canonical 测试报告、traceability tests 和 review-loop 必须保持上一轮完整状态；不得留下只更新其中一部分的半完成投影。
4. 原始 stdout/stderr 必须落到现有 `test-evidence/`，报告中的每个 command 只引用对应日志的 workspace-relative 路径，不复制完整日志内容到 traceability。
5. 机器区必须记录每条规范化 command 的完整对象、结果、退出码或 timeout、日志路径，以及整个规范化 command 集合的 LF canonical SHA-256 digest。digest 的输入必须同时包含相对路径和文件内容，避免不同命令集合因简单拼接产生碰撞。
6. 机器区的 `status` 只允许由实际命令结果确定：全部命令退出码为 0 时为 `pass`；任一已启动命令非零或 timeout 时为 `block`。模型、Agent、Pipeline 和 `write-test-report` 不得改写 `status` 或 command 列表。
7. 同一次完整 plan 的记录必须具有稳定的 command 语义；重复执行产生新的合法 attempt 时，必须以新一轮完整结果替换当前 canonical 机器区，而不是把上一轮和本轮命令数组拼接。

## FR-05 `test-report.md` 机器区与人工分析区分界

1. `test-report.md` 使用唯一 marker：

   ```text
   <!-- crctl:analysis-below -->
   ```

2. marker 之前是 `crctl` 独占的机器区，包含 frontmatter、规范化 commands、结果、digest、日志引用和生成来源。`write-test-report`、Agent、Pipeline 和人工不得直接改写该区域。
3. marker 及其之后是人工/模型分析区。`write-test-report` 只拥有该区域，负责根据最新机器结果更新：
   - 测试结果摘要；
   - TASK 验收覆盖矩阵；
   - 新增/修改测试文件；
   - 未覆盖风险与不适用说明；
   - 对失败结果的解释和下一步建议。
4. 重跑测试时，marker 后已有内容必须逐字保留，除非 `write-test-report` 在新的分析写入步骤中基于最新机器结果主动更新；保留机制不能被解释为旧分析自动仍然有效。
5. 报告不存在时，`crctl test` 创建合法机器区并写入唯一 marker，marker 后为空分析区，随后由 `write-test-report` 补充分析。
6. marker 缺失、重复或无法唯一确定机器区/分析区边界时硬失败，要求人工修复后重试；不得猜测第一处、最后一处或通过截断文本降级。
7. marker 与其前后的 CRLF/LF 变化不得改变分界结果。跨行匹配失败必须返回结构化错误，不得静默生成空分析区。
8. `traceability.yml#tests`、`review-loop.yml` 和报告机器区不属于人工分析区，`write-test-report` 不得在分析步骤中直接写入或修改它们。

## FR-06 Skill、Pipeline 与 Agent 采用

1. `write-test-report` Skill 的职责限定为：
   - 校验 CR、测试负责人和前置文档；
   - 根据 TASK 和 implement-code 输出进行业务判断，生成临时结构化 plan；
   - 调用一次 `crctl test`；
   - 读取 crctl 返回的机器结果；
   - 只更新 marker 后分析区；
   - 输出 `status`、blockers、repair-target、attempt 和下一步。
2. `write-test-report` 不得：
   - 手写 `test-report.md` 的 status、commands、generated-by 或机器 digest；
   - 直接写 `traceability.yml#tests` 或 review-loop；
   - 实现 `spawnSync`、shell 安全、事务、CAS、日志归档或账本原子写入算法；
   - 重新执行测试命令来代替 `crctl test`。
3. `code-implementation.pipeline.json` 的测试节点只描述输入传递、一次 Skill 调用、结果分流、`reviewLoop` 和失败中止。测试证据阻塞时按既有 `replayNodes=[implement-code, write-test-report]` 回修，最多 3 次；超过上限停止在当前闭环，不进入 checkpoint、代码评审或人工审批。
4. 代码评审回修的 `reviewLoop` 必须按既有顺序重放：

   ```text
   implement-code -> write-test-report -> push-progress -> review-code
   ```

   评审 PASS 后仍需先完成 checkpoint，checkpoint 未完成不得进入人工审批。
5. `review-code` 只读取真实 diff、TASK/SDD、最终 `test-report.md`、command digest 和原始日志，产出业务评审结论；不得调用 `crctl test`，不得自行补写测试报告或 traceability。
6. Agent 只负责根据职责和当前 `crctl next` 结果选择 coding Pipeline/Skill、传递输入和判断是否需要人工介入；Agent 不保存状态机副本、测试命令表、Git 算法或受控文件写入逻辑。
7. `crctl` 只负责状态、门禁、结构化计划执行、原始日志、机器证据、CAS/durable transaction、review-loop 与审计；不判断 TASK 是否覆盖充分、不判断测试是否“合理”、不生成 LLM 评审结论。
8. 版本化脚本只在本 CR 需要时执行确定性文档转换；本 CR 不增加测试脚本的状态推进、审批或 Git 发布能力。README 只保留人读流程总览和权威入口，不复制本 FR 的执行算法。

## FR-07 测试证据到评审和审批的门禁

1. `write-test-report` 返回 `status=block`、证据缺失、机器区漂移或分析区写入失败时，Pipeline 必须在当前节点中止或进入声明的 reviewLoop 修复，不得进入后续 `push-progress`、`review-code` 或 `human_approval`。
2. `review-code` 通过条件必须同时满足：
   - `review-annotations/code.yml#verdict=pass`；
   - `blockers=[]`；
   - `test-report.md` 的 canonical machine status 为 `pass`；
   - command digest、日志引用和报告机器区可复算且未漂移；
   - analysis 区已存在且对 TASK 覆盖与未覆盖风险作出明确说明。
3. `review-code` 不得因为测试报告缺失、status 非 pass、digest 不一致、日志缺失或分析不完整而降级为 suggestion；这些均必须形成 blocker 并回到 `implement-code -> write-test-report`。
4. 代码评审 PASS 后必须调用现有 `push-progress` 完成 checkpoint；checkpoint 返回的 `phase` 非 `complete` 时中止，不进入人工审批。
5. `approve-code` 继续使用现有 `crctl approve --stage code`，由 `crctl` 校验证据和人工审批，不新增测试审批接口、不把 Pipeline 的 PASS 文本当作审批结论。

## FR-08 幂等、重试和跨平台行为

1. 计划校验、命令执行和事务发布必须支持同一入口重试。事务已完成的重放应复用既有 journal/commit 事实，返回幂等成功，不重复执行已确认的账本发布或产生重复 review-loop attempt。
2. 技术失败必须零 canonical 变化；修正 plan、repository、cwd、executable、marker 或事务冲突后，使用同一 `crctl test` 入口重新执行完整 plan。
3. 业务失败必须生成一份完整的 `block` 证据；修复代码后重新执行完整 plan，不能只执行失败的单条命令、续用部分日志或合并多个 attempt 的结果。
4. 中断运行不得覆盖上一轮 canonical report，不得生成新的 canonical attempt，不得把残留临时日志当作成功证据；重试重新开始并在完整结束后一次性发布。
5. 所有跨行解析、报告 marker 定位、digest 输入和文件读取必须先做 CRLF 到 LF 规范化；输出的 canonical 机器区和 digest 在 Windows/Ubuntu 上一致。
6. 不新增 npm 依赖。优先复用 Node 标准库 `child_process`、`fs`、`path`、`crypto`，以及现有 `crctl` 的解析、hash、CAS、durable transaction、审计和测试 fixture。
7. 不允许 force write、手改 `_backlog.yml`/`cr.md`/`traceability.yml`/`review-loop.yml` 绕过失败，不允许通过增加 `--continueOnError`、`--allow-shell` 或类似开关削弱安全边界。

# 4. 非功能需求

- **安全性**：所有正式测试执行均为 argv + `shell:false`；不接受任意 shell 字符串，不接受绝对路径或跨 worktree cwd，不提供绕过开关。
- **原子性**：机器报告、测试日志引用、traceability tests 和 review-loop attempt 必须在同一既有 durable transaction 中发布；任一技术失败不产生半套 canonical 投影。
- **可恢复性**：测试运行失败与事务技术失败必须返回结构化、可区分的错误/业务结果；重试不需要手工改账本。
- **可审计性**：记录实际规范化 command、结果、digest、日志路径、CR、测试负责人和 attempt；不把完整 stdout/stderr 复制进 traceability。
- **跨平台性**：Windows/Ubuntu 的 CRLF/LF、路径分隔符、参数空格和 Unicode 行为一致；canonical 输出使用 LF。
- **可测试性**：至少覆盖计划 schema、argv 安全、worktree containment、启动失败、非零退出、timeout、中断、事务故障、重复重试、marker 保留/缺失/重复和 command digest 重算。
- **性能**：单 CR 的命令数为 `n` 时，计划校验与证据整理不引入超出命令输出规模的额外持久化模型；不缓存、不并行、不建立测试服务。
- **极简性**：不新增 test runner、test record API、日志平台、schema registry、通用事务层、插件 registry、错误码中心或工作树全量 hash。

# 5. 验收标准

- **AC-01（FR-01/02）**：合法的 `cr-test-plan/v1` 能被 `crctl test` 接受；空 commands、缺 schema、字段类型错误、未知 repo、缺失 worktree、非法 cwd、非正 timeout 和 executable 为空均在写入前失败，返回结构化错误且 canonical 文件零变化。
- **AC-02（FR-02/03）**：包含空格、Unicode、引号、`;`、`&&`、`|`、`>` 等参数的计划按原始 argv 执行，不能触发 shell 解释；测试能证明 `shell:false`，且命令参数没有被拼接为单字符串。
- **AC-03（FR-02/08）**：同一语义的 CRLF 与 LF plan 在 Windows/Ubuntu 上生成相同 command digest；非法跨行/marker 解析硬失败，不产生空 commands 或空分析区。
- **AC-04（FR-03）**：计划中第一条命令返回非零或 timeout 时，剩余命令仍执行；所有命令结束后报告为 `status: block`，每条命令均有退出结果/timeout 和对应原始日志。
- **AC-05（FR-03）**：repository、cwd containment、executable 启动、参数或计划 schema 技术失败时立即中止；上一轮 `test-report.md`、traceability tests 和 review-loop 不变，且不存在新的 canonical attempt。
- **AC-06（FR-04）**：一次成功测试发布同时更新机器报告区、所有命令原始日志引用、`traceability.yml#tests` 和 `review-loop.yml`；任一事务/CAS/fault point 注入失败时，不留下仅更新其中一部分的投影。
- **AC-07（FR-04）**：机器区包含规范化 command 对象、结果、日志路径和可复算的整体 SHA-256 digest；修改 executable、args、cwd、repo 或 command 集合后旧 digest 必然不匹配；不生成第二份 canonical `plan.json`。
- **AC-08（FR-05）**：报告 marker 后已有多行人工分析在测试重跑后逐字保留；marker 缺失或重复时硬失败，报告字节、traceability tests 和 review-loop 均不变化；新报告创建后包含唯一 marker 和空分析区。
- **AC-09（FR-05/06）**：`write-test-report` 只能修改 marker 后分析区；静态 contract 检查证明 Skill 不手写 status/commands/frontmatter、traceability tests、review-loop、spawnSync 或账本 CAS 算法。
- **AC-10（FR-06）**：Pipeline 的测试 evidence reviewLoop 在 block 时按 `[implement-code, write-test-report]` 重放；代码 reviewLoop 按 `[implement-code, write-test-report, push-progress, review-code]` 重放；达到 3 次仍 block 时停止，不进入 human approval。
- **AC-11（FR-06/07）**：`review-code` 不再重新执行 lint/test/build；缺失报告、status 非 pass、digest/日志漂移或分析区不完整均产生 blocker，并回到实现和测试报告节点。
- **AC-12（FR-07）**：测试报告 PASS 后，review-code PASS 仍必须先完成现有 checkpoint；checkpoint `phase != complete` 时不能进入人工审批；`approve-code` 仍只通过现有 `crctl approve --stage code` 推进状态。
- **AC-13（FR-08）**：同一完整 plan 的合法事务重放幂等成功，不重复执行已确认的账本发布，不重复 attempt；修改代码后重试完整 plan 会生成新完整结果，不复用部分日志或只重跑失败命令。
- **AC-14（FR-03/08）**：外部中断发生在命令执行或发布前后时，不覆盖上一轮 canonical report，不发布半套机器证据；恢复只能通过重新执行完整 plan。
- **AC-15（全范围）**：静态检查证明 Agent 不持有状态机/Git/账本算法，Pipeline 不复制 Skill/crctl 完整算法，Skill 不手写受控账本，crctl 不包含业务测试发现或 LLM 评审结论，README 不增加另一份可执行事实源。
- **AC-16（工程质量）**：现有 crctl、review-loop、traceability、checkpoint、code review 和 approval 回归测试保持通过；新增结构化 test、shell:false、原子发布、marker、CRLF、timeout、中断和 fault-injection 测试在 Ubuntu 与 Windows 均通过；不引入新的生产依赖。

# 6. 成功指标

- 正式验证命令全部由 `cr-test-plan/v1` 驱动，生产路径不再接受 shell 命令字符串或 `shell:true`。
- 测试机器证据的唯一发布路径为 `crctl test`；`test-report.md`、`traceability.yml#tests` 和 review-loop 不再存在分散写入造成的半完成状态。
- 测试重跑不会覆盖 marker 后人工分析；marker 异常不会被静默修复或猜测。
- `review-code` 不再重复执行测试命令；测试证据不足时能够通过既有 reviewLoop 回到实现和测试报告节点。
- 所有承诺的技术失败零变化、业务失败可记录、完整重试和事务故障恢复场景均有可执行测试。
- CR-2026-040 的实现不增加第二套测试平台、事务框架、run/record 协议、状态机或账本模型。

# 7. 依赖与风险

- **依赖**：Tools 当前 `crctl` 的 CR/worktree resolver、Node 文件与 hash helper、`spawnSync` 可用能力、durable transaction、CAS、audit、review-loop 和 traceability 投影；`write-test-report`、`review-code` 与 `code-implementation.pipeline.json` 的现有契约。
- **风险 R-01：旧调用契约残留**。当前 Skill/Pipeline 仍可能描述 `--cmd` 字符串或由评审重新执行测试；必须在同一 CR 内同步收敛调用方，并用静态 contract 测试阻止回归。
- **风险 R-02：机器区与分析区边界漂移**。marker 缺失/重复必须硬失败；不得使用宽松正则或“取第一处/最后一处”的兼容逻辑。
- **风险 R-03：测试失败与技术失败混淆**。非零退出和 timeout 必须记录为业务 block；schema、启动器、路径和事务错误必须保持上一轮 canonical 证据不变。
- **风险 R-04：原子发布范围不足**。必须复用既有 durable transaction；不得为 test 单独引入新的 journal、run-id 恢复协议或 binary write-set。
- **风险 R-05：重试重复执行或丢失 attempt**。事务故障测试必须覆盖命令执行完成、部分日志生成、canonical 发布前中断和发布后重放，确认不会出现重复账本或部分 attempt。
- **风险 R-06：跨平台差异**。Windows CRLF、路径和 executable 启动行为可能导致 digest/报告不一致；所有解析和 digest 输入统一先规范化 LF，并加入 Windows 回归矩阵。

# 8. 范围排除

- 不建设日志服务、测试结果数据库、远程测试执行平台、配额系统、测试发现器或通用 binary protocol。
- 不公开拆分 `test run` / `test record`，不新增通用 `run/record` API、公共 test ledger 或独立 test-run 恢复命令。
- 不新增完整工作树 hashing、execution grant、强身份认证、test provider/plugin registry 或 schema registry。
- 不允许 Pipeline、Agent 或 Skill 手写 `test-report.md` 机器区、`traceability.yml#tests`、`review-loop.yml` 或其他受控账本。
- 不让 `crctl` 判断 TASK 验收是否充分、测试命令是否覆盖业务、报告分析是否合理或 LLM 评审是否通过。
- 不让 `review-code` 执行测试；不改变现有 code review、approval、checkpoint 和状态机的业务语义，只补齐测试证据前置条件和回修闭环。
- 不修改 CR-2026-040 之外的生命周期切片：writeback 原子化、证据规范化、归档可信化、职责边界清理和 Phase E 端到端验收均不在本 CR 实施范围。
- 不修改 `specs/`、`delivery/` 或主工作区同名 CR 目录；本 PRD 只落盘在本 CR 的 requirement worktree。

# 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-14 | v0.1.0 | Ray | 初始草稿：结构化 test plan、shell:false、机器证据原子发布、marker 分区保护和 review-loop/checkpoint 闭环 |
