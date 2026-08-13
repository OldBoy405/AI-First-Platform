# Tools merge 与 workspace 事务链优化实施方案（TCA-005/006/007/008/009/015/016）

> 核对基线：`../tools@ee230e44f79019abcc39532ec13ab6c8b5a5ed7f`（`custom/main`）  
> 核对日期：2026-08-10  
> 来源：`docs/analysis/tools-text-contract-audit.md` 的 CR-B 范围  
> 文档性质：现状核对与实施设计，不是运行时事实源；状态机、仓库声明、权限、Git 白名单仍分别以 tools 仓 `dir-graph.yaml`、目标 workspace `dir-graph.yaml#repositories`、`agent-skill-matrix.yml`、`rules.json` 为准。

## 1. 结论

TCA-005/006/007/008/009/015/016 在当前基线仍成立，而且实际问题比原审计条目更宽：问题不只是“几条命令缺失”，而是 merge、worktree 创建/恢复/清理、状态与 metadata 发布、writeback workspace 交接仍由 Pipeline/Skill 文本拼接，没有一个代码化事务 owner。

本轮应采用以下最小方案：

1. **不再声称跨仓远端 push 原子**。Git 不提供跨多个 remote 的原子提交；正确语义是“单仓 ref CAS + 跨仓可恢复 saga”。
2. **把 merge 与 workspace Git 算法下沉到 crctl**。Pipeline 只保留顺序和上下文传递；Skill 只保留业务前置、一次原语调用、结果分类。
3. **每项业务事务只暴露一个幂等入口自动开始或续跑**，不暴露必须由模型按顺序拼接的低级命令：
   - `crctl register --registration-key <key> ...`：CR-ID 分配、三账本写入、registration commit/push、参与仓 workspace ensure 自动续跑；
   - `crctl merge <CR-ID>`：prepare、publish、reconcile、finalize 自动续跑；
   - `crctl merge status <CR-ID>`：只读事务状态；
   - `crctl workspace ensure <CR-ID> --mode resume`：幂等恢复；
   - `crctl workspace cleanup <CR-ID> --mode partial|archived`：只清理由 journal/归档事实证明可删的资源；
   - `crctl archive <CR-ID> [--spec-id <id>]`：状态/四账本/archive event 发布与 workspace/ref 清理自动续跑；archive commit 经 origin 确认后业务状态不可回退，清理失败仅进入 journal `cleanup-pending`。
4. **采用 roll-forward 恢复，不再默认自动 revert 已发布 merge**。revert 只能反转文件树，不能让 merge commit 和源提交从历史中消失；且源分支已成为 merge commit 祖先后，简单重跑通常得到 `already up-to-date`，当前“补偿后重跑”契约不可兑现。
5. **固定事务 graph digest**：零副作用时若 repositories 变化，可在同一 tx 自动丢弃旧 prepare 并按新 graph 重建；已有任一账本、workspace 或 remote 副作用后返回 `GRAPH_CHANGED_DURING_TRANSACTION`，输出 old/new digest 与 repo diff，不提供 force，必须先恢复原 graph 完成事务。
6. **merge 完成时一次发布完整事实**：`cr.md status=merging`、完整 `merge-commits[]`、机器生成的 `merge-verification.md` 在同一个 knowledge-base finalize commit 中出现；废弃逐仓公开 `merge-metadata` 写入口。
7. **post-merge authority 固定切到 crctl 管理的 knowledge-base Transaction Workspace**。CR worktree 自 finalize 起只读等待清理；用户主 checkout 不作为事务执行位置；后续 writeback 节点必须消费 `operational_workspace`，禁止 `--workspace .` 或 `<knowledge-base worktree>` 模糊占位。
8. **把 `casWriteMulti` 改为有 redo journal、fsync、启动恢复和故障注入的 recoverable write-set**。不宣称文件系统提供多文件瞬时原子可见性，但保证 crctl 观察者不会把中断半状态当成完成态；并发采用 operation lock + 短时 Installation Workspace publish lock，不预先实现 per-repo 锁。
9. **如实收敛权限边界**：当前 caller 只是自报审计标签，不是授权。最小修复是删除“调用者三元放行”的安全承诺和公开 `--caller`，由矩阵/Pipeline 做路由授权，由 crctl 做状态、路径、ref、workspace containment 和操作前置强制。若未来要做跨主体强授权，应另建签名 capability，不用可伪造 caller 字符串冒充。

明确不做：

- 不引入数据库、消息队列、分布式锁、通用 saga 框架或新的 YAML 账本框架；
- 不增加 `merge-recovering` 等状态，部分发布期间仍保持 `code-approved`，恢复指针由 merge journal 暴露；
- 不让版本化 writeback 脚本负责状态推进、Git push 或人工审批；
- 不让 Pipeline/Skill 继续维护 merge 命令序列；
- 不自动 reset 用户分支、不自动 stash、不自动删除无法证明归属的目录；
- 不把本地 `.crctl` journal 宣称为业务历史；最终业务事实仍以 Git 中的 finalize commit 为准。

## 2. 核对范围与当前绿灯

### 2.1 实际核对文件

- `pipeline-templates/feature-writeback.pipeline.json`
- `pipeline-templates/requirement-authoring.pipeline.json`
- `pipeline-templates/resume-cr.pipeline.json`
- `skills/writeback/merge-feature-branch/SKILL.md`
- `skills/writeback/writeback-{prd-sdd,tasks,traceability}/SKILL.md`
- `skills/requirement/requirement-register/SKILL.md`
- `skills/sync/resume-from-remote/SKILL.md`
- `skills/cr/cr-archive/SKILL.md`
- `skills/shared/controlled-shell/{SKILL.md,rules.json}`
- `skills/shared/crctl/{SKILL.md,scripts/crctl.mjs}`
- crctl/lint/writeback 测试、CI workflow、README/AGENTS/索引与 Agent 路由声明

### 2.2 当前验证结果

```text
lint-prompts --mode enforce: 0 findings
skill matrix: 57 active skill，通过
agents.contract: 9 agent，通过（不变式 4 明确未静态检查）
crctl/contract tests: 226/226 通过
writeback tests: 9/9 通过
8 个 Pipeline JSON: 可解析
```

这些绿灯不证明事务链正确：

- `casWriteMulti` 测试只抽取函数源码并断言“CAS 失败发生在 rename 前”，没有在第 N 次 rename 前后杀进程；
- merge 测试只断言 Skill/Pipeline 文本中含 `merge-verification.md`，反而固化了 Pipeline 复制 Skill 箭法；
- 没有三 bare remote 的真实跨仓 push/recover 测试；
- 没有 registration/resume 在第二仓失败后的重入测试；
- 没有 caller、cwd 越界、worktree 路径碰撞测试；
- CI 只运行 matrix 与 Agent contract，不运行 lint、crctl、writeback、Pipeline contract。

## 3. 目标职责边界

本轮所有实现严格按 ponytail 阶梯取第一个可行解：**复用现有实现 > Node 标准库 > Git/文件系统原生能力 > 已安装依赖 > 一行实现 > 最小新增代码**。禁止为推测需求增加 npm 依赖、通用 saga/事务框架、单实现 interface、class 层级、插件机制或可配置但当前只有一个值的抽象；安全、数据恢复和已明确的跨平台校验不得以“极简”为由删减。

| 层 | 本轮应拥有 | 本轮必须删除/下沉 |
|---|---|---|
| Agent | 识别 `/requirement`、`/resume`、`/writeback` 意图；选择 Pipeline；展示结构化结果 | 仓库遍历、worktree 路径、Git 命令、merge 状态判断、恢复算法 |
| Pipeline | 节点顺序、输入输出 mapping、`operational_workspace` handoff、`onFail=abort` | merge 十步算法、worktree add 算法、账本字段、补偿命令、脚本内部转换细节 |
| Skill | 业务前置、调用一个深原语、解释业务结果、决定中止/继续 | 逐仓 Git、状态 + metadata 拼装、手写恢复、手写 cleanup report、重复 crctl |
| crctl | repository resolver、状态/gate、ref CAS、workspace 生命周期、merge saga、journal、CAS/write-set、审计、精确 commit/push、恢复 | PRD/SDD 内容判断、LLM review、CUSTOM.md 语义判断、下一业务 Pipeline 选择 |
| 版本化脚本 | PRD/SDD/TASK/traceability 的确定性转换、dry-run、自检、只读 baseline 后生成 candidate bundle（after-images + before/after hash manifest） | 直接修改 baseline、状态推进、worktree、审批、push |
| README/ARCHITECTURE | 阶段总览、关键语义、权威入口链接 | Git 命令表副本、补偿步骤、状态机副本、固定命令计数 |

Agent 层当前没有直接执行 merge 的可部署 Agent；`system-orchestrator` 是 matrix 中的 system actor，这一方向可以保留。需要收缩的是 `requirement-writer` 对 Pipeline 内部步骤的复述，而不是再新增 `writeback-agent`。

## 4. 当前所有不符合项

### 4.1 Pipeline 越权与第二事实源

| 编号 | 当前实例 | 违反原则 | 风险 |
|---|---|---|---|
| MWP-01 | `feature-writeback.pipeline.json:40` 复制 10 步 merge、补偿、metadata、验证算法 | Pipeline 复制 Skill/crctl 完整算法 | Skill、Pipeline、代码三份事实漂移；当前测试要求两份文本同步，主动固化错误架构 |
| MWP-02 | `requirement-authoring.pipeline.json:80` 复制 repo 解析、`cr-init`、commit/push、worktree 创建及 execution_context 拼装 | Pipeline 拥有 Git/路径/账本细节 | 失败后无法机器重入；路径和返回字段继续漂移 |
| MWP-03 | `resume-cr.pipeline.json:24,33` 重复远端预检和 worktree add 算法 | Pipeline 拥有恢复算法 | node 1 与 Skill 重复查询，结论可能不同；部分创建无法续跑 |
| MWP-04 | feature-writeback 后续节点使用 `--workspace .` | Pipeline 未机器传递 phase handoff | 执行目录不同会把 baseline 写到旧 CR 分支或错误 checkout |
| MWP-05 | Pipeline prompt 复制 writeback 脚本标题、字段、幂等算法 | Pipeline 复制版本化脚本算法 | 脚本改变后 prompt 成为第二事实源；本轮至少删到输入/输出/passCondition 级别 |

### 4.2 Skill 越权

| 编号 | 当前实例 | 违反原则 | 风险 |
|---|---|---|---|
| MWS-01 | `merge-feature-branch/SKILL.md:18-245` 持有预检、本地 merge、push、revert、metadata、冲突处理、验证提交 | Skill 持有 Git 算法、状态/账本事务 | 事务只存在于文本，进程中断后没有权威恢复状态 |
| MWS-02 | 同 Skill `:40-48` 允许 Agent 在设置环境变量后裸跑 Git | Agent/Skill 绕过受控执行层 | 审计、白名单和 cwd containment 全失效 |
| MWS-03 | `requirement-register/SKILL.md:39-93` 持有 repository 解析、commit/push/worktree add | Skill 持有 workspace 算法 | 注册后半状态没有真实恢复入口 |
| MWS-04 | `resume-from-remote/SKILL.md:32-64` 持有远端预检与 worktree add | Skill 持有 workspace 恢复算法 | healthy 资源不能跳过，重跑遇 `already exists` 即失败 |
| MWS-05 | `cr-archive/SKILL.md:109-133` 持有 worktree/远端分支清理、Windows `Remove-Item`、`prune` 和 cleanup report 写入 | Skill 持有 destructive Git、路径删除和确定性报告写入 | 绕过规则、可能删错目录，且恢复入口仍是文本 |
| MWS-06 | `writeback-prd-sdd/SKILL.md:57-66` 先提交 baseline，再单独 advance | Skill 用两个提交拼同一 phase 事实 | commit 成功、advance 失败时 baseline 已变但状态仍为 merging |

### 4.3 merge 事务完整性问题

| 编号 | 证据 | 具体问题 |
|---|---|---|
| MWT-01 | `merge-feature-branch:160-172` + `cmdMergeMetadata():1800-1815` | status 先由 embedded advance 写 `cr.md`，N 个 repo 再逐条 CAS 写 backlog，任一步失败都会留下部分 metadata |
| MWT-02 | `merge-metadata` 只按 SHA 去重 | 不按 repo 唯一；不校验 repo/trunk 来自当前 graph；不验证 SHA 是该 repo 的已发布 merge；允许 `writing-back` 后继续补写 |
| MWT-03 | merge 全过程无 durable journal | 进程在任一 push 后退出，下一次无法知道 prepare/pushed/finalized 边界 |
| MWT-04 | 当前先 checkout/pull/merge/commit 修改每个本地 trunk | 远端 stale 或后续仓失败时，本地多个 trunk 已前移；“重新运行”没有清理这些候选 commit |
| MWT-05 | 自动 revert 后建议重跑 | revert 不删除 merge 历史；源分支已是 merge commit 祖先，重跑可能 `already up-to-date`，无法再次发布同一改动 |
| MWT-06 | 文本声称补偿后“未包含本 CR” | Git 历史仍包含 merge commit、源提交与 revert；只能说工作树效果被反转，不能说 CR 未包含 |
| MWT-07 | metadata publish 失败再全仓 revert | 在更多远端副作用之上增加第二轮副作用，任一 repo 被其他提交推进后补偿即阻塞；恢复空间反而更大 |
| MWT-08 | embedded advance 在 commit 前发 pending status outbox（`crctl.mjs:1262-1267`） | metadata commit/push 最终失败时，外部已经观察到并不存在的 merging 投影 |
| MWT-09 | merge verification 在 finalize 后另起 commit | 状态/metadata 已成功但验证提交失败时，Pipeline 把已完成 merge 报成失败；重试边界不清晰 |
| MWT-10 | Skill 的 `cr.md` 冲突解法按“状态机位置更靠后”整侧取值 | 权威状态机是图，含自环、回退、wildcard，没有声明线性位置；整侧取值还可能丢 Owner 等同文件更新 |
| MWT-11 | README `:495` 声称“两阶段合并避免多仓半成功” | 本地两阶段只能减少 prepare 阶段副作用，不能让多个 remote push 原子 |

### 4.4 workspace 生命周期问题

| 编号 | 证据 | 具体问题 |
|---|---|---|
| MWW-01 | requirement-register 错误表明确“不做跨进程续跑” | TCA-007 未修；`cr-init` 成功后 commit/push/worktree 失败只能人工记住 CR-ID |
| MWW-02 | resume 遇已有 worktree 直接建议 pull-progress | healthy/missing/branch-only/stale-metadata 没有统一状态分类；第一仓成功、第二仓失败后无法重入 |
| MWW-03 | resume 建议 `git worktree prune`，规则无该形态 | 恢复建议本身不可执行 |
| MWW-04 | archive 使用 `Remove-Item -Recurse -Force` | 绕过 controlled-shell，且删除目标由文本拼接，缺 canonical containment 校验 |
| MWW-05 | `cmdWorktreePath():2896-2901` 把 `knowledge-base`、`ai-first-platform-docs` 写死 | 声称从 repo role 解析，实际不读 repositories；重命名 knowledge-base repo 即得到错误 bucket |
| MWW-06 | worktree-path 不校验 repo id 是否存在、active、path/trunk 是否完整 | 任意字符串都可派生路径，不能作为 destructive 操作的权限边界 |
| MWW-07 | 没有 workspace 锁/operation journal | 同一 CR 两个进程可同时创建、清理或 merge worktree/ref |
| MWW-08 | cleanup report 由 Skill/模型写 | 报告是确定性执行结果，应由 crctl 生成，模型不应决定哪些资源已删除 |

### 4.5 phase authority 与 writeback handoff

| 编号 | 证据 | 具体问题 |
|---|---|---|
| MWA-01 | `detectStatusDivergence():1140-1156` 永远声明 CR worktree 为事实源 | 在 merge 前合理，finalize 后错误；trunk 已是 merging，旧 worktree 仍是 code-approved |
| MWA-02 | merge Skill `:187-191` 把主 checkout divergence 视为预期，却在 CR worktree 调 `next` | CR worktree 会再次建议 merge，而不是 writeback；“不得有 STATUS_DIVERGED”只因函数对当前 worktree短路，并不代表状态正确 |
| MWA-03 | 三个 writeback Skill 使用 `<knowledge-base worktree>` | 术语把 CR linked worktree 和 trunk checkout 混为一谈 |
| MWA-04 | writeback 脚本调用使用 `--workspace .` | 运行目录隐式决定 baseline 落点；Pipeline 没有机器可读 authority handoff |
| MWA-05 | CR worktree finalize 后仍可写 | 没有只读/阶段守卫，旧分支可继续产生不会进入 trunk 的证据或状态提交 |

### 4.6 `casWriteMulti` 与 commit 边界

| 编号 | 证据 | 具体问题 |
|---|---|---|
| MWC-01 | `casWriteMulti():776-798` 连续 rename | 第 N 次 rename 前后崩溃会留下多文件半状态，源码注释已承认 |
| MWC-02 | 无 manifest、before/after hash、fsync、启动恢复 | 进程重启无法判断应 redo 还是阻断；临时文件也无统一清理 |
| MWC-03 | 无互斥锁 | CAS 只挡读取后的内容变化，不挡两个事务交错 rename 和 Git stage/commit |
| MWC-04 | 多个命令写完再由外层 Skill commit | 文件 write-set 与 Git commit 不是同一恢复边界；“同一 commit”依赖模型正确 add |
| MWC-05 | 现有测试 `crctl.test.mjs:1291-1327` 只测 stub 调用次数 | 没有真实文件、真实 kill、真实 restart/recover，因此无法证明崩溃恢复 |

### 4.7 权限控制与命令真实性

| 编号 | 证据 | 具体问题 |
|---|---|---|
| MWP-SEC-01 | `rules.json:3` 明说 callers 仅记录；`controlled-shell/SKILL.md:63` 声称调用者三元放行 | 文档安全承诺与实现相反（TCA-015） |
| MWP-SEC-02 | `loadShellRules():519-526` 丢弃 callers；`cmdGit():3446` 接收自报 `--caller` | 即使加载 callers，自报字符串也不是不可伪造身份 |
| MWP-SEC-03 | `cmdGit --cwd` 直接 `path.resolve`，无 repo/worktree containment | 可对 workspace 外任意 Git 仓执行 allowlisted 写命令 |
| MWP-SEC-04 | rules 对 `worktree add .+`、`add ^[^-].*$`、`push origin \S+` 等形态过宽 | 虽 `shell:false` 防 shell 注入，但仍允许非预期 Git flags/ref/path组合 |
| MWP-SEC-05 | generic `crctl git` 暴露 merge/revert/worktree remove 等 destructive 原语 | 这些动作迁入 merge/workspace 深模块后不应继续向任意 Skill公开 |
| MWP-SEC-06 | requirement-register 把 crctl 专属 `--template/--cr` 传给抽象 `runGit` | 平台 runGit 若只包装 Git，该示例不命中真实入口（TCA-016） |
| MWP-SEC-07 | writeback 失败恢复写 `crctl git checkout --` | rules 的 checkout 只允许单 ref，且命令没有文件参数，必然不可执行 |
| MWP-SEC-08 | controlled-shell 文档写“19 条”，rules 实际 20 个 sub 且表格漏 `symbolic-ref` | README 型解释文档继续维护可计算事实副本 |

### 4.8 `crctl.mjs` 冗余排查与本轮删减

按当前基线静态引用、active Skill 调用与目标接口交叉核对，以下冗余在本轮直接删除或收敛，不另建兼容 wrapper：

| 编号 | 当前位置 | 结论 | 本轮处理 |
|---|---|---|---|
| CRR-01 | `writeApprovalSection():1634-1645` | 函数仅有定义、无调用，是确定死代码 | 删除函数及无效注释；保留实际使用的 `buildApprovalSectionText/buildApprovalBlock` |
| CRR-02 | `cmdCrMetrics():2967-2970` + help/dispatch/tests | `cr-metrics` 只是给 `report` 强塞默认 `7d` 的无调用别名；active dashboard 全部调用 `crctl report` | 删除 `cr-metrics` 命令、函数、help、索引说明和别名测试；周期查询统一 `crctl report --period <N>d` |
| CRR-03 | `casWriteMulti():784-803` 与 `tryCasWriteMulti():2447-2464` | 同一“校验→temp→rename”算法复制两份，只因一个 `fail()`、一个 throw | 由 `durable-tx.mjs` 单一 recoverable write-set 返回/抛结构化错误；删除两份旧实现，单文件写也复用 one-element write-set |
| CRR-04 | `cmdMergeMetadata()` + `editMergeMetadata()` | 新 merge finalize 已一次写完整 metadata/status/verification，逐仓 metadata 写入口成为冲突事实源 | 删除公开命令、编辑函数、help/dispatch/单元测试；不保留 deprecated wrapper |
| CRR-05 | `cmdCrInit()` 与 `cmdWorktreePath()` 的公开 dispatch | 注册已收敛为 `crctl register`，路径由 repository resolver/workspace inspect 返回；旧低级入口只会重新暴露模型拼装面 | `cr-init` 逻辑内联复用为 register 内部阶段；删除两个公开命令、help/dispatch，删除 hard-coded knowledge-base repo id；调用方改深原语/结构化上下文 |
| CRR-06 | `COMMIT_TEMPLATES.register/writeback`、`cmdGit()` register 后置事件分支 | register/writeback 已由专命令精确 commit/push；generic git 不应继续理解这两个事务模板 | 事件与 commit message 移入 register/writeback transaction；删除两种 template、register 特判与对应测试，只保留仍有真实调用者的 template |
| CRR-07 | `migrate-backlog` + `resolveCrState()` v1 fallback | 当前核对 workspace 已是 `cr-backlog/v2`，active Skill 不调用迁移；继续永久携带一次性迁移与 ghost cleanup 没有当前消费者 | 最低支持版本提升为 v2；删除迁移命令、ghost cleanup、legacy fallback/warning 与测试。启动读取 v1 时只返回 `UNSUPPORTED_BACKLOG_SCHEMA`；旧 workspace 必须在升级前用旧 tools 迁移 |
| CRR-08 | `cmdTaskAllocate()` + `scanMaxTaskNumber()/appendTaskEntry()` | 除 help/自测外无 active Skill/Pipeline 调用；`write-dev-tasks` 已一次生成完整 TASK 集合与索引，预分配空索引条目是未接线的第二模型 | 删除 `task allocate` 命令、三个函数、help/index 描述与专用测试；未来只有出现真实并发 TASK 创建需求时再设计，不保留 dormant API |
| CRR-09 | 公开 `archive-move` + Skill 内 advance/commit/push/cleanup 算法 | 归档状态、四账本、事件、发布和清理被拆成模型必须拼接的低级步骤，与 register/merge 的深原语方向相反 | 新增单一幂等 `crctl archive`，复用内部账本纯变换与 workspace cleanup；删除公开 `archive-move`、Skill/Pipeline 算法副本和模型生成 cleanup report |

明确保留：

- 内置 YAML 子集解析器有二十余真实调用点，tools 无 package dependency；Node 标准库不含 YAML，换依赖反而违反 ponytail；
- `evidenceSha16` 仍读取 CR-2026-001/002 历史审批字段，属于真实兼容需求，不是死代码；它与 backlog v1 schema 迁移是不同兼容面，本轮继续保留；
- `report`、canonical evidence digest、状态机/gate 解析均有多个真实调用者，不为“文件变短”复制到新模块。

验收要求：用静态引用检查保证零未调用内部函数；删除命令后同步 help、Skill/index、contract tests 与文档引用；`crctl.mjs` 必须因 dispatch/旧算法删除而净缩短，新事务代码只进入已确认的两个内部模块。

## 5. 正确的事务语义

### 5.1 必须明确的边界

本轮不能承诺“所有 remote 要么一起成功、要么一起失败”。可承诺的是：

1. **prepare 零远端副作用**：所有 repo 的 base/source/ref/冲突先验证，生成候选 merge commit object 和 durable journal；不 checkout、不移动本地 trunk、不 push。
2. **代码评审证据形成、审批签入唯一 release snapshot**：不新增账本；`crctl review-record --stage code` 从真实已推送 ref/worktree 机器注入 `code.yml#release-subjects`（逐仓 reviewed source SHA + CRLF 规范化、路径排序后的 PRD/SDD/plan/TASK 集合 digest），模型 payload 不得提供/覆盖。既有 TTY/Ed25519 approval 签整个 code evidence digest；approve 时重核 remote ref/worktree HEAD/artifact，一致才原样复制到 `approval.yml#code.release-subjects`，否则 `RELEASE_SUBJECT_DRIFT` 零写入拒绝并要求重跑测试/评审。merge/writeback 只消费 approval 中已签入 snapshot。code/source/TASK drift 且尚无 trunk publish 时，crctl 将原审批标记 stale，并经 proposed 转换 `code-approved -> developing`（trigger=`merge-feature-branch:release-drift -> implement-code`）返回对应回退结果；PRD/SDD drift 返回 `APPROVED_ARTIFACT_DRIFT` 硬阻断，不能由代码审批替代上游审批。若已有任一 trunk publish，则保持 `code-approved`/blocked；新提交拆到新 CR，管理员恢复原 ref 后原 tx 才续跑。Skill 不判断 SHA/hash、不写审批/状态，Pipeline 只按结构化结果中止。
3. **单仓发布 CAS**：每个 repo 以预检 trunk SHA 为 lease，只有 remote ref 仍等于 base 才允许更新。register/merge finalize/writeback/archive 复用一个只分类 Git 事实的 `classifyRemoteCommit`：remote 包含 candidate=`confirmed`、remote=expected base=`pushable`、未发布且 remote 前进=`rebuild`、journal 声称已发布但 remote 不再包含 candidate=`history-rewritten`；具体处理器各自重建业务 commit，不向 helper 传业务 callback。
4. **跨仓发布可恢复**：每次远端副作用前写 intent，副作用后立即观测 remote 并更新 journal；崩溃后根据 remote ref/ancestry 重建事实。
5. **部分发布不伪装成功**：CR status 保持 `code-approved`，`crctl next/status` 返回 active merge transaction 和 recover command；writeback gate 不放行。
6. **默认 roll-forward**：已发布 repo 保持不动，未发布 repo重新核对后继续；remote 被外部推进时，未发布 repo 可基于新 base 重新 prepare，已发布 repo 若候选 merge 已是 ancestor 则视为成功。
7. **finalize 单一提交**：所有 repo 均 confirmed 后，才在 knowledge-base trunk 一次写入 status + 完整 metadata + verification，并确认 finalize commit 已到 origin。
8. **成功事实以远端 Git 为准**：本地 journal 只是恢复状态；最终 `merging` 只能在 origin trunk 包含 finalize commit 后返回成功。
9. **Git trailer 是跨机器恢复锚点**：所有事务 commit 由 crctl 追加固定 `AI-First-Op/Tx/CR`；register 只记录 `AI-First-Registration-Key-SHA256`，merge 另记 repo/base/approved-source。journal 丢失时结合 remote refs、approval snapshot 重建；冲突时硬阻断。不新增远端 journal 分支或 YAML 事务账本。

### 5.2 为什么不默认自动 revert

- revert 是新提交，不是删除已发布 merge；
- 其他提交可能已基于该 merge，自动 revert 会改变后来者基线；
- revert 后源分支通常仍是历史祖先，直接重跑不能重新 merge；
- 多仓 revert 本身仍是多次非原子 push；
- “自动补偿成功”会制造比“部分发布待续跑”更难判断的历史。

若将来确有业务级取消，应新增显式、人工确认的 `merge abort` 设计，并把“效果已反转但历史保留”作为语义；本轮不实现。

## 6. 最小深模块接口

### 6.1 repository resolver

在 crctl 内收敛一个 resolver，所有 merge/workspace/status/cleanup 复用：

```text
resolveRepositories(operationWorkspace) -> {
  installRoot,
  knowledgeBaseRepo,
  repositories[]: {
    id, role, repoRoot, trunk, remote,
    bucket, branch, worktreePath
  },
  graphDigest
}
```

强制校验：

- `id/path/trunk/role` 必填，id/path 唯一；
- active 口径仍为 `active != false`；
- 恰好一个 `role=knowledge-base`；
- repoRoot realpath 存在且是 Git repo；
- worktreePath 必须在 `{installRoot}/.rayai-worktrees/{bucket}/requirement/{cr}` 内；
- repo id 必须来自 graph，删除 `ai-first-platform-docs` 等代码常量；
- remote 默认 `origin`，如后续需要非 origin，可在 repository 条目显式声明 `remote`，不要让 Skill推导。

删除公开 `worktree-path`；相同只读字段并入 `workspace inspect` 的 repository view，不再保留第二个路径接口或自行拼 role：

```json
{
  "repo": "docs",
  "role": "knowledge-base",
  "repoRoot": "...",
  "trunk": "master",
  "remote": "origin",
  "bucket": "knowledge-base",
  "branch": "requirement/CR-...",
  "path": "..."
}
```

### 6.2 workspace 命令

```text
crctl register --registration-key <key> --title <title> --owner-requirement <id> --owner-development <id> --owner-test <id> [注册元信息]
crctl workspace inspect <CR-ID>
crctl workspace ensure  <CR-ID> --mode resume
crctl workspace cleanup <CR-ID> --mode partial|archived [--tx <tx-id>]
```

`register` 是注册期唯一公开写入口：内部完成 CR-ID 分配、三账本 recoverable write-set、精确 registration commit/push，并复用 workspace ensure 内部逻辑创建所有参与仓 worktree。`registration_key` 由 Pipeline Runtime 创建并持久化，Pipeline/Skill 只透明传递；同 key 重试必须续跑同一 transaction/CR-ID，不同 key 允许相同业务输入创建不同 CR，已绑定 key 的输入摘要变化返回 `REGISTRATION_INPUT_MISMATCH`。IDE 独立入口未收到 key 时由 crctl 用 Node 标准库生成并在任何业务写入前持久化。

`drafting` 只表示 CR 业务身份已注册，不承诺参与仓 workspace 已全部就绪；不新增 `registering` 技术状态。存在未完成 register journal 时，`crctl status/next` 必须优先返回 `REGISTRATION_INCOMPLETE` 与同 key recover command，禁止进入 PRD 节点。只有所有参与仓均为 healthy 后，`register` 才返回成功 `execution_context`。

workspace ensure 对每个 repo 分类，而不是遇到第一个 exists 就失败：

| 状态 | register 内部 / resume 行为 |
|---|---|
| `missing` | 创建 branch + worktree |
| `healthy` | 校验 branch/path/HEAD 后跳过，`changed=false` |
| `branch-only` | 在 canonical path 挂接已有 branch |
| `remote-only` | resume 模式创建 tracking branch + worktree |
| `registered-missing-dir` | 仅在 metadata 指向 canonical path 时执行受控 prune/修复 |
| `path-unregistered` | 阻断，不删除未知目录 |
| `wrong-branch` | 阻断，不 checkout/reset |
| `dirty` | 保留并报告；ensure 不自动 stash |
| `remote-missing` | resume 在任何创建前整体阻断 |
| `head-drift` | 报 expected/actual；由 pull-progress 或用户决策处理 |

`cr-init` 降为 `register` 内部阶段，不再公开给 Skill/Pipeline；register journal 在首次分配后持久化 CR-ID、输入摘要、已完成步骤与已创建资源，重跑不得再次分配 CR-ID。注册失败默认 roll-forward：保留已验证 healthy 的资源，相同 key 重跑跳过它们并补齐失败仓；不得自动回收 CR-ID、revert registration commit 或删除已成功资源。

`cleanup --mode partial` 只删除指定 tx journal 记录为“本事务创建”、且仍 clean、未被外部推进/发布的资源；`cleanup --mode archived` 只在远端归档 commit 和 merge ancestry 校验通过后清理。Windows 兜底由 crctl 内部执行 canonical `fs.rmSync` + targeted worktree metadata reconcile，Skill 不再出现 `Remove-Item`。

### 6.3 merge 命令

对外只保留两个入口，内部 phase 不暴露给模型拼装：

```text
crctl merge <CR-ID>              # 无 journal=开始；有未完成 journal=自动 reconcile/续跑
crctl merge status <CR-ID>       # 只读
```

成功返回：

```json
{
  "op": "merge",
  "cr": "CR-2026-NNN",
  "txId": "merge-CR-2026-NNN-...",
  "phase": "finalized",
  "status": "merging",
  "finalizeCommit": "<sha>",
  "mergeCommits": [{"repo":"...","trunk":"...","sha":"...","branch":"requirement/..."}],
  "skippedRepos": [{"repo":"...","reason":"source-already-contained"}],
  "executionContext": {
    "phase": "writeback",
    "operational_workspace": "<Installation Workspace>/.rayai-worktrees/knowledge-base/transaction/<tx-id>",
    "readonly_worktrees": ["..."]
  },
  "sideEffects": {"remoteRefs": ["..."], "files": ["..."]},
  "recoverCommand": null
}
```

失败统一带：

```json
{
  "error": {
    "code": "MERGE_*",
    "txId": "...",
    "phase": "prepared|publishing|finalizing",
    "sideEffects": {"confirmed": [], "pending": [], "unknown": []},
    "recoverCommand": "crctl merge CR-... --workspace ..."
  }
}
```

### 6.4 writeback candidate apply

所有 writeback 阶段复用一个固定枚举的窄入口：

```text
crctl writeback-apply <CR-ID> --stage baseline|tasks|traceability --spec-id <id> --target-version <version>
```

- 生产入口不接受 `--manifest`、任意脚本路径或任意输出目录；crctl 按固定 stage 从 Tools Root 选择 `writeback-prd-sdd.mjs`、`writeback-tasks.mjs` 或 `writeback-traceability.mjs`；
- 固定脚本只读取权威输入并通过内部协议在受保护 transaction 目录输出 after-images + changed-files/before-after hash manifest，不直接修改 baseline、delivery 或 traceability；脚本 CLI 仅保留受测的 dry-run/output 内部模式；
- manifest v1 固定字段为 `v/stage/cr/specId/targetVersion/inputDigest/generator{id,sha256}/files[]`，其中 file 仅含 `path/beforeSha256/afterSha256/blob`；path 必须是唯一、字典序的 POSIX workspace-relative 路径，禁止 absolute/`..`/反斜杠/重复分隔符/symlink；parent realpath 必须在 Transaction Workspace；
- v1 只支持 `missing -> create` 与 exact before hash `-> replace`，不支持 delete/rename/chmod/executable bit；blob 只能引用当前 tx candidate 目录内以 SHA-256 命名的 regular file，实际 hash 必须等于 `afterSha256/blob`；
- `writeback-apply` 先校验当前 PRD/SDD/plan/TASK 集合与 `approval.yml#code.release-subjects.artifacts` 一致；`inputDigest` 必须覆盖 signed snapshot、stage/spec/version、baseline before hashes 与 generator SHA；随后校验脚本退出码、Transaction Workspace、manifest schema、blob hashes、before hashes、固定路径 allowlist，应用后要求 Git staged set 与 manifest path 集合精确相等；不提供任意路径写入口；
- `baseline` 只允许 `specs/{id}/PRD.md`、`SDD.md` 与 spec index，并把这些文件和 `cr.md status=writing-back` 放入同一 commit；
- `tasks` 只允许 `delivery/task/` 与索引，不推进 CR 状态；`traceability` 只允许目标 spec 的 `traceability.yml`，执行 archive 前完整性门禁但不代替 archive；
- 每个 stage 各自通过 recoverable write-set、精确 commit 与 lease push 发布，不把三个节点合成巨型事务。origin 已包含 stage commit 则确认；origin 前进但本 stage 尚无远端副作用时，丢弃旧临时 commit/candidate，在新 origin SHA 的 detached Transaction Workspace 重新运行固定 generator 并重验 snapshot/hash/allowlist；不 rebase/cherry-pick。新基线自检/语义冲突返回 `WRITEBACK_BASE_CHANGED`；已发布 commit 从 origin history 消失返回 `WRITEBACK_REMOTE_HISTORY_REWRITTEN`，均保留 journal 并硬阻断。

这是 TCA-008 的必要收口，不是把文档转换塞进 crctl。

### 6.5 archive 深原语与清理策略

`crctl archive` 固定策略，不接受 Skill `cleanup_branch` 开关：

| final status | 本地 worktree | remote requirement ref |
|---|---|---|
| archived | clean 且 approved source/merge ancestry 已进入 trunk 后删除 | ancestry 成立后按当前 SHA lease 删除 |
| rejected/withdrawn | clean 才删除；dirty 进入 cleanup-pending | 未合并 ref 始终保留，并输出 `preservedRefs[].reason=unmerged-terminal-cr` |

无法证明 clean/ancestry/ref ownership 时不删除。成功 archive record 已发布后 cleanup 失败不回退业务状态；同一 `crctl archive` 续跑。未来若确需删除 rejected/withdrawn ref，另作人工确认且按 SHA lease 的管理命令设计，本轮不增加。

## 7. 公共 journal envelope 与具体处理器

### 7.1 路径与权威性

```text
.crctl/transactions/register-{registration-key-sha256}.json
.crctl/transactions/{op}-{CR-ID}.json
.crctl/transactions/blobs/{tx-id}/{before|after}-N
```

- `.crctl` 继续 gitignore；journal 是执行恢复状态，不是业务 baseline；
- `rules.json#protectedPaths.deny` 增加 `.crctl/transactions/`，禁止模型编辑；
- register 在 CR-ID 分配前按 key hash 定位，分配后仍沿用同一 txId；同一 op 重跑同一 journal，不同 op 不得同时占有同一 CR operation lock；
- merge finalize 后由 crctl 生成并提交 `change-requests/{cr}/merge-verification.md`，这是可审计业务证据；
- journal 丢失时，结合 remote refs/ancestry、approval release snapshot 与固定 Git trailer 重建；prepared 但未 push 的本地 object 丢失可直接重新 prepare。

### 7.2 最小公共 envelope

```json
{
  "v": 1,
  "txId": "...",
  "op": "register|merge|writeback|archive",
  "cr": "CR-2026-031",
  "phase": "<op-specific>",
  "graphDigest": "sha256:...",
  "inputDigest": "sha256:...",
  "createdAt": "...",
  "updatedAt": "...",
  "sideEffects": {"confirmed": [], "pending": [], "unknown": []},
  "commit": {"expectedBase": null, "sha": null, "remoteConfirmed": false},
  "lastError": null,
  "register": null,
  "merge": {"repos": [], "finalize": {}},
  "writeback": null,
  "archive": null
}
```

只允许与 `op` 对应的一个 payload 非空。`durable-tx.mjs` 只校验 envelope 并提供 lock、durable save、recoverable write-set、fault injection 与 blob cleanup，不理解业务 phase/Git 意义；`workspace-transactions.mjs` 仅用 `registerCr/ensureWorkspace/mergeCr/applyWriteback/archiveCr` 五个具体函数维护 op-specific payload。不得新增 Transaction class、通用 phase engine、handler registry、adapter 或 plugin。

每次写 journal 均为 temp + fsync(file) + rename + 尽力 fsync(parent)。每次远端副作用前先持久化 intent；若进程死在副作用与 journal 更新之间，恢复时以 remote ref/ancestry 裁决。

仅当至少三个处理器出现相同非平凡阶段控制、同一恢复缺陷需三处修复、出现真实第三方事务扩展，或事务数量/dispatch 成本有测量证据时再考虑框架。届时只从三个真实调用点向现有 `durable-tx.mjs` 提炼最小 phase runner，保留 op-specific payload/reconcile，逐个迁移并复跑 crash/fault/remote observation tests；没有真实外部扩展前不增加 registry 或第三个事务模块。该延期决策登记 `tools/CUSTOM.md#CUSTOM-TODO-008`。

### 7.3 prepare 实现

1. 获取同一 CR operation lock。
2. 解析 graph 并固定 `graphDigest`。
3. 校验 status=`code-approved`、approval/test/review gate，并只从审批时已由 signed code evidence 原样复制的 `approval.yml#code.release-subjects` 读取完整 per-repo approved source SHA 与 artifact digests；每个 remote requirement ref、本地 worktree HEAD 和受控 CR artifact 必须与 snapshot 一致。code/source/TASK drift 且尚无 trunk publish时，由 crctl 原子标记审批 stale、执行 `merge-feature-branch:release-drift -> implement-code` 回退；PRD/SDD drift 返回 `APPROVED_ARTIFACT_DRIFT`；Pipeline 均 abort。
4. fetch 所有 repo，记录 base/source。
5. source 已被 base 包含则 `skipped`；否则执行 `merge-tree --write-tree`。
6. 有任一冲突则全体停止，零 push；删除 Skill 的“按状态位置选整侧”算法。
7. 用 Git 原生 `commit-tree` 创建候选 merge commit object，parents 固定为 base/source；message 由 crctl 追加 `AI-First-Op/Tx/CR/Repo/Base/Source` 固定 trailer，不接受调用方覆盖；不 checkout、不移动本地 trunk。
8. durable 写 journal 后才进入 publish。

内部 Git 参数由 crctl 代码构造，用户不能传 repo path/ref/merge SHA；因此不需要把 `commit-tree` 加到公开 `rules.json`。

### 7.4 publish/reconcile

对每个 repo：

1. fetch remote trunk；
2. 若 remote=base，以 `--force-with-lease=<trunk>:<base>` 推 `<mergeSha>:<trunk>`；这是精确 ref CAS，不是无条件 force；
3. 若 remote=mergeSha 或 mergeSha 是 remote ancestor，记 confirmed；
4. 若 repo 尚未发布且 remote 已变化，基于新 remote 重新 prepare 该 repo并更新 journal；
5. 若 journal 认为已发布但 remote 已不包含 mergeSha，返回 `MERGE_REMOTE_HISTORY_REWRITTEN`，禁止自动覆盖；
6. 每个远端动作后立即 fetch/观测并持久化。

发布顺序建议代码仓在前、knowledge-base 在后，以缩短“代码已发布但 CR 主账本尚未合入”的窗口；这只是风险排序，不改变可恢复语义。

### 7.5 finalize

全部 repo confirmed 后：

1. 在最新 knowledge-base origin trunk 确认 SHA 上创建 detached HEAD 的 canonical Transaction Workspace（`{Installation Workspace}/.rayai-worktrees/knowledge-base/transaction/{tx-id}`），不复用旧 CR worktree或用户主 checkout，不创建私有事务分支；
2. 从 journal 一次生成完整 `merge-commits[]` 候选，repo 集合必须与 `confirmed` 集合一一对应；
3. 内存生成 `cr.md status=merging` 与 `_backlog.yml` 目标 CR 块；
4. 机器生成 `merge-verification.md`：graph digest、base/source/merge SHA、publish observation、skipped 原因、txId；不让 Agent填写 timestamp/SHA；
5. 通过 durable write-set 写三文件，精确 stage，复核 staged set，单 commit；
6. 以 knowledge-base finalize base 为 lease push；stale 时丢弃临时 worktree，基于新 base 重建 finalize commit，绝不 revert 已发布代码仓；
7. fetch 确认 origin 包含 finalize commit 后，才发带真实 SHA 的 status outbox、标记 finalized，并把同一 Transaction Workspace 作为 `operational_workspace` 交给 writeback；
8. 后续 writeback commit 只以 journal 中的精确 commit SHA 和 `--force-with-lease=<trunk>:<expected>` 从 detached HEAD 发布到 trunk；用户主 checkout 不自动 checkout/reset，也不参与 authority 选择；可选 `pull --ff-only` 同步失败只返回 warning，不影响事务成功。

公开 `merge-metadata` 从 dispatch/help/Skill/tests 删除，不保留 deprecated wrapper；已有事务只能用升级前 tools 完成，或由新 `crctl merge` 根据远端事实重建。

## 8. recoverable write-set（TCA-009）

### 8.1 最小实现

用一个小型 Node 标准库模块替换现有 `casWriteMulti`：

```text
recoverPendingTransactions(ws)
applyWriteSet({ txId, op, writes[] })
completeWriteSet(txId)
```

流程：

1. operation lock；
2. 全量校验 expected hash/expected missing；
3. 把 before/after image 与 hash 写入 tx 目录并 fsync；
4. 原子发布 manifest=`prepared`；
5. 逐文件写同目录 temp、fsync、rename，fault point 前后均可退出；
6. 全部目标 hash=after 后标记 `applied`；
7. 命令若还负责 Git commit，则 commit/push 成功后标记 `completed`；失败按 candidate hash 恢复 before image，或保留 `recoverCommand`；
8. 每个 crctl mutating command 启动前先恢复 pending tx：目标为 before/missing 时 redo after；目标已是 after 时跳过；目标为第三种 hash 时 `TX_RECOVERY_CONFLICT` 并停止所有新写入。

这是 redo-log 语义：crctl 观察者最终看到完整 after set。它不能让外部进程在 rename 间永远看不到中间态，因此文档用“recoverable write-set”，不再写“文件系统全有或全无”。

### 8.2 迁移调用点

本轮先把所有现有 `casWriteMulti` 调用迁到新原语，避免同一底层函数继续保留已知崩溃窗：

- approve：approval + cr.md；
- review-record：annotation + review-loop + traceability；
- register 内部账本阶段：cr.md + backlog + index；
- archive 内部账本阶段：cr.md + backlog + history + index；
- owner-set：cr.md + backlog；
- merge finalize：cr.md + backlog + verification。

删除单独 `casWrite/casWriteMulti/tryCasWriteMulti` 算法；单文件写作为 one-element recoverable write-set 复用同一路径。本轮迁移所有现有调用点，不保留并行旧实现。

### 8.3 fault points

仅测试环境识别：

```text
CRCTL_FAULT_AT=tx:after-manifest
CRCTL_FAULT_AT=tx:before-rename:N
CRCTL_FAULT_AT=tx:after-rename:N
CRCTL_FAULT_AT=git:before-commit
CRCTL_FAULT_AT=git:after-commit
CRCTL_FAULT_AT=merge:before-push:<repo>
CRCTL_FAULT_AT=merge:after-push:<repo>
CRCTL_FAULT_AT=merge:before-finalize-push
CRCTL_FAULT_AT=merge:after-finalize-push
```

fault injection 必须强制进程退出，再启动真实 crctl recover；不再通过正则抽源码 + stub 调用次数代替崩溃测试。

### 8.4 锁粒度

锁使用本机文件系统原子目录 `.crctl/locks/{op-key|publish}.lock/owner.json`；owner 只含 `token=crypto.randomUUID()`、pid、hostname、txId、acquiredAt。竞争失败时：同 hostname 且 PID 存活（Windows EPERM 也视为存活）返回 `OPERATION_LOCKED`；ESRCH/明确不存在才删 stale lock 并重试一次；foreign hostname 返回 `LOCK_OWNER_UNVERIFIABLE`。解锁必须 token 与 realpath 同时匹配。无 TTL、无 force-unlock；PID 复用时宁可保守阻断。Installation Workspace 只支持本机本地文件系统，未来真实跨主机共享需求需另作分布式锁决策。

- operation lock 按 `registration_key` 或 CR-ID，覆盖 register/merge/workspace 单项事务，阻止同一事务并发续跑；
- Installation Workspace publish lock 由所有会修改共享账本或 knowledge-base trunk 的命令共用，只在 recoverable write-set、精确 stage、commit、push 的短临界区持有；fetch、prepare 与确定性文档转换不占用；
- 不引入数据库锁、分布式锁或预先细分的 per-repo publish lock；若未来通过锁等待指标证实跨进程吞吐不足，再细分 per-repo 锁，该延期项登记在 tools `CUSTOM.md`。

### 8.5 远端 commit 事实分类

`workspace-transactions.mjs` 内只保留一个有多个真实调用者的小 helper：

```text
classifyRemoteCommit({ remoteSha, expectedBase, commitSha, commitIsRemoteAncestor, journalSaysPublished })
  -> confirmed | pushable | rebuild | history-rewritten
```

它不执行 push、不理解业务 phase、不接收 prepare/publish/compensate callback。register、merge finalize、writeback、archive 在持久化 intent 后按分类分别执行 lease push 或各自的确定性 rebuild；`history-rewritten` 一律硬阻断。该复用是 Git CAS 事实判定，不是通用事务框架。

### 8.6 临时产物生命周期

- candidate 尚未应用时 baseline 保持不变；输入摘要与 baseline before hash 未变可复用，否则删除旧 after-images 后重建；schema/path 非法的 candidate 立即删除内容，只在 audit 保留 hash 与错误码；
- write-set 已开始或 commit/push 未经 origin 确认时，完整保留 journal、before/after images 与 Transaction Workspace，不设 TTL，不自动清理；
- 单阶段 commit 经 origin 确认后，先 fsync 标记 `completed/cleanup-pending`，再删除该阶段大体积 blobs/candidate，仅在 journal 保留 txId、输入摘要、文件 hash、commit SHA 与完成时间；
- archive commit 经 origin 确认后标记 `archive-confirmed`；随后幂等清理剩余 candidate/blobs、CR worktrees/refs 与 Transaction Workspace。全部 cleanup done 后才删除本地 journal；任一步中断保留 `cleanup-pending` marker 并由同一 `crctl archive` 续跑；
- 放弃/人工终止只允许显式 cleanup，且必须证明无待发布副作用、目标未被第三方修改、资源确属该 tx；不能证明则阻断。最终业务事实只保留在 Git commit、CR history 与 traceability。

## 9. phase authority 与 execution context

### 9.1 authority 规则

| 阶段 | 可写 authority | 其他 checkout |
|---|---|---|
| drafting ～ code-approved | knowledge-base CR worktree + 各代码 CR worktree | 主 checkout 只读注册/视图 |
| merge transaction 未 finalize | merge coordinator；CR worktree 冻结写入 | 主 checkout不得开始 writeback |
| merging / writing-back | crctl 管理的 knowledge-base Transaction Workspace | 用户主 checkout 不参与；CR worktree 只读等待清理 |
| archived/rejected/withdrawn | history + 已发布 trunk | worktree 应清理；archive journal 为 cleanup-pending 时业务终态不回退，status/next 只提示续跑 cleanup |

`detectStatusDivergence` 改为 phase-aware：不能永远宣称 linked worktree 为事实源。若从旧 CR worktree 调用 status/next，而 origin trunk 已含 merge finalize，返回专用 Transaction Workspace authority：

```json
{
  "code": "WORKSPACE_AUTHORITY_MOVED",
  "authority": "<knowledge-base trunk>",
  "readonly": true,
  "status": "merging"
}
```

`next` 应先检查 active transaction/authority：

- incomplete registration：返回同一 `registration_key` 的 `crctl register` recover command，不得因 status=`drafting` 建议撰写 PRD；
- archive commit 已确认但 cleanup-pending：即使 status=`archived`，仍只返回同一 `crctl archive <cr>` recover command，不重跑账本/事件；
- partial merge：返回 `crctl merge <cr>`；
- finalized 且调用点是旧 worktree：返回 authority redirect；
- 只有 operational trunk 才返回 writeback 节点。

### 9.2 Pipeline handoff

feature-writeback 第一个节点只保留：

```text
输入 cr_id -> 调用 merge-feature-branch
成功输出 execution_context.operational_workspace
失败 abort，并透传 txId/sideEffects/recoverCommand
```

节点 2～5 显式消费该字段：

```text
--workspace {execution_context.operational_workspace}
```

禁止：

- `--workspace .`
- `<knowledge-base worktree>`
- 从 node 文本重新拼 `.rayai-worktrees/...`
- finalize 后在 CR worktree 执行 `crctl next` 或 writeback 脚本。

## 10. controlled-shell 与权限收敛

### 10.1 caller 的最小诚实修复

本轮不实现伪强授权：

1. `rules.json` 删除 `callers` 或明确改名为非安全 `auditSources`；
2. `crctl git` 删除公开 `--caller`；内部 caller 由代码常量生成，只用于 audit；
3. controlled-shell/README/crctl Skill 统一改成“subcommand + argv shape + workspace containment”放行；
4. Agent/Skill 是否可调用某能力由 matrix + Pipeline contract 静态检查；
5. crctl 对 merge/cleanup 的安全性来自不可任意传 path/ref、状态/gate、graph resolver、lease 和 canonical path校验。

若威胁模型要求阻止同一 OS 用户下的恶意 Agent 调用合法命令，只能采用平台签名 capability/独立执行服务；环境变量或 CLI caller 名不构成权限边界。该能力不与本轮混做。

### 10.2 generic Git 面缩小

merge/workspace 深命令落地后，从公开 rules 删除仅供这些事务使用的写形态：

- `merge-tree`、`merge`、`revert`；
- `worktree add/remove`（保留只读 list，或也由 workspace inspect 内部执行）；
- branch destructive delete；
- trunk push 形态由 merge 内部 lease push替代。

仍需公开的 checkpoint/pull/review Git 形态按 argv 逐项收紧。`cmdGit` 在执行前校验 cwd realpath 属于 graph repoRoot 或 canonical CR worktree；越界返回 `GIT_CWD_OUTSIDE_WORKSPACE`。

### 10.3 TCA-016 命令修复

- requirement-register 不再调用 `cr-init`、带 `--template` 的抽象 runGit 或 workspace 子命令；整个 registration transaction 交给单一 `crctl register`；
- writeback 自检失败恢复使用新 write-set before image，不再写不存在的 `crctl git checkout --`；
- `worktree prune` 与 Windows 删除留在 workspace 内部实现，不加入模型可调用的通用示例；
- cr-archive 只调用 `crctl workspace cleanup --mode archived`，cleanup-report 由 crctl 生成；
- linter R12 对所有 `crctl git`/runGit 示例实际执行 rules matcher，并校验 crctl 专属旗标没有传给裸 Git adapter。

## 11. 各层最终文本应缩成什么

### 11.1 `merge-feature-branch` Skill

只保留：

1. 输入 `cr_id`；
2. 业务前置：代码已审批、应进入回写；
3. 调用 `crctl merge <cr_id>`；
4. `finalized` 才成功；`prepared/publishing/blocked` 原样返回并中止；
5. 输出 merge SHA、txId、operational workspace、recover command。

删除逐仓命令、revert、metadata、冲突侧选择、verification 手写格式和裸 Git说明。

### 11.2 requirement/resume/archive Skills

- requirement-register：只校验业务输入、透明传递 `registration_key`、调用一次 `crctl register` 并汇总权威输出；
- resume-from-remote：`workspace ensure --mode resume`，只展示状态；
- cr-archive：删除 `cleanup_branch` 参数，只校验归档业务参数、调用一次 `crctl archive` 并解释 `archived|cleanup-pending|blocked` 与 `preservedRefs`；状态、账本、commit/push 与 cleanup 都不在 Skill 展开；
- 三者都不解析 bucket、不拼 branch/path、不执行 worktree/prune/Remove-Item。

### 11.3 Pipelines

- feature-writeback：节点 1 只传 cr_id；节点 2～5传 `operational_workspace/spec_id/target_version`；
- requirement-authoring：node 1 只传注册输入并接收 execution context；
- resume-cr：可合并“远端预检 + 恢复”为一个 Skill 节点，或保留 list 作为纯展示，但不得把 list 结果当作 workspace 原语的安全前置；
- Pipeline prompt 不包含 Git 子命令、账本字段写算法或恢复步骤。

### 11.4 README/AGENTS/crctl Skill

- README 只写“跨仓合并为可恢复 saga，完成后 authority 切 trunk”，链接到 Skill/crctl；
- 删除“两阶段避免半成功”、完整补偿算法、resume Owner 旧说明；
- controlled-shell 不写可计算的固定命令数量；
- crctl Skill列能力/输入输出/失败语义，不复制 journal 状态机；
- AGENTS 只保留禁止手改、必须走 Skill/crctl 的行为约束。

## 12. 详细实施步骤

### Phase 0 — 先建立红测与术语

1. 新增 `merge-workspace.test.mjs`，搭建 3 个临时 bare remote + checkout；
2. 增加真实 kill/restart fault harness；
3. 先写当前实现必失败的场景：第二仓 push 失败、rename:2 退出、resume 第二仓失败后重跑、caller/cwd越界、post-merge authority；
4. 删除/改写只检查文本 `includes()` 的 merge 测试；
5. 固定术语：`Operational Workspace`、`CR worktree`、`Transaction Workspace`、`merge journal`、`finalize commit`。

完成门：红测能稳定重现 TCA-005/006/007/008/009/015/016，而不是只检查文案。

### Phase 1 — repository resolver + recoverable write-set

1. 实现唯一 repository resolver，删除公开 worktree-path 并把只读 repository view 并入 workspace inspect；
2. 实现 operation lock、Installation Workspace 短时 publish lock、journal 原子写、before/after blob、启动恢复；
3. 把现有 `casWriteMulti` 调用迁移到新 write-set；
4. 加 rename N 前后 fault tests；
5. 所有读入先 CRLF→LF，逐行解析用 `/\r?\n/`，结构匹配失败硬失败。

完成门：任一 rename fault 后重启，所有目标最终都等于完整 after set，或明确 `TX_RECOVERY_CONFLICT`；不存在静默半状态。

### Phase 2 — register + workspace ensure/cleanup

1. 实现 inspect 状态分类与 workspace ensure 内部复用逻辑；
2. 实现带 `registration_key`、输入摘要绑定和 durable journal 的单入口 `crctl register`；
3. register 内部接管 CR-ID 分配、三账本写入、精确 registration commit/push 与参与仓 worktree 创建；
4. 实现公开的 resume ensure、partial cleanup 和 archived cleanup；
5. requirement-register/resume/cr-archive 分别改为一次 `register` / `workspace ensure --mode resume` / `archive` 深原语调用；
6. 收缩 rules 中 worktree destructive 形态。

完成门：第二仓失败后重跑跳过第一仓 healthy worktree并完成其余仓；未知目录/错分支/dirty 资源从不被自动删除。

### Phase 3 — merge saga

1. 扩展 `review-record --stage code`，由 crctl 注入不可由 payload 覆盖的 release-subjects；approve-code 重核并把 signed evidence 中该块原样复制到 approval，覆盖 TTY 与 Ed25519 grant 的漂移测试；
2. 在 tools 权威状态机新增 proposed 转换 `code-approved -> developing`（trigger=`merge-feature-branch:release-drift -> implement-code`），统一承接 code/source/TASK drift，避免为每种漂移复制转换；同步 gate/help/tests。实现合入前当前口径仍是 27 条声明/49 条 wildcard 展开，合入后变为 28/50，具名状态仍为 15；
3. 实现 journal schema 与 `merge status`；
4. prepare 使用 merge-tree + commit-tree，不移动本地 trunk；
5. publish 使用 per-ref lease；
6. 每个 fault point 进行 remote reconcile；
7. finalize 一次写 status/metadata/verification 并发布；
8. `merge-metadata` 从公开 dispatch 移除；
9. merge Skill 缩成一次调用，只解释 crctl 结果，不判断 SHA 或推进状态。

完成门：任一 push 前后杀进程，重跑都能 confirmed/continue/block，不需要模型解释现场；没有自动 revert。

### Phase 4 — authority handoff + writeback-apply

1. merge 成功输出 machine-readable Transaction Workspace，且该路径不因用户主 checkout clean/dirty 改变；
2. status/next 增加 phase-aware authority redirect；
3. feature-writeback 传递 operational workspace；
4. 三个 writeback 脚本都只生成 after-images + changed-files/before-after hash manifest，不直接修改权威文件；
5. 三个 Pipeline 节点分别调用 `writeback-apply --stage baseline|tasks|traceability`；baseline stage 把首批 spec 变更与 `writing-back` 状态放进同一 commit；
6. CR worktree post-merge 写操作由 hook/crctl 返回只读错误。

完成门：所有 writeback 变更只出现在 trunk authority；旧 CR worktree 不会再次建议 merge或产生 baseline commit。

### Phase 5 — controlled-shell/文本/检查器/CI

1. 删除 caller 安全承诺与公开 `--caller`；
2. 加 cwd containment，收紧 argv shape；
3. 实现 R10 command existence、R12 Git shape、Pipeline 算法重复与 workspace authority 检查；
4. 新增轻量 `check-pipeline-contract.mjs`；
5. 精简三条 Pipeline、相关 Skills、README/crctl/controlled-shell 文档；
6. CI 运行 lint、matrix、Agent、Pipeline、crctl、writeback 和 JSON parse；Windows job 跑 path/CRLF/worktree 关键向量。

完成门：Pipeline 不含逐仓 Git/补偿/账本算法；文档中的每条恢复命令都能命中真实 dispatch 和规则。

## 13. 建议修改文件

### 13.1 代码与规则

| 文件 | 改动 |
|---|---|
| `skills/shared/crctl/scripts/crctl.mjs` | dispatch 接线、resolver、authority、临时只读 upgrade-check、register/workspace/merge/writeback-apply/archive 入口，删除公开 cr-init/worktree-path/merge-metadata/archive-move/caller 与冗余命令 |
| `skills/shared/crctl/scripts/lib/durable-tx.mjs` | 新增：lock、journal、write-set、fsync、fault injection；保持小而通用，仅服务 crctl |
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 新增：用具体函数封装 resolver、register、workspace、merge、Transaction Workspace 与 writeback-apply；不建 interface/class/plugin，不解析业务文档内容 |
| `skills/shared/controlled-shell/rules.json` | caller 诚实化、cwd配套、缩小 destructive Git 面、保护 transactions |
| `skills/writeback/scripts/writeback-{prd-sdd,tasks,traceability}.mjs` | 只读权威输入，分别输出 stage-scoped candidate after-images + changed-files/before-after hash manifest；不直接写权威文件、不推进状态 |

只新增 `durable-tx.mjs` 与 `workspace-transactions.mjs` 两个内部 lib，避免把事务代码继续堆进已达 3,628 行的 `crctl.mjs`；不新增 npm 依赖、interface/base class/factory/plugin，只有出现第二个真实变化轴后才允许继续拆分。

### 13.2 Skill/Pipeline/Agent

- `skills/writeback/merge-feature-branch/SKILL.md`
- `skills/requirement/requirement-register/SKILL.md`
- `skills/sync/resume-from-remote/SKILL.md`
- `skills/cr/cr-archive/SKILL.md`
- `skills/writeback/writeback-{prd-sdd,tasks,traceability}/SKILL.md`
- `skills/shared/{crctl,controlled-shell}/SKILL.md`
- `pipeline-templates/{feature-writeback,requirement-authoring,resume-cr}.pipeline.json`
- `agents/requirement-writer.md`（只保留选择 requirement Pipeline，不复述其节点）
- 对应 `_index.yml` brief；节点数变化时更新 Pipeline `_index.yml`

### 13.3 检查与 CI

- 新增 `skills/shared/crctl/scripts/check-pipeline-contract.mjs`
- 更新 `lint-prompts.mjs` 与测试
- 更新 `crctl.test.mjs`，新增 `merge-workspace.test.mjs`
- 更新 writeback tests
- 更新 `.github/workflows/check-skill-matrix.yml`，可改名为 `contracts.yml`

### 13.4 人读文档

- `README.md`
- `AGENTS.md` 中 workspace/cleanup 行为约束
- `ARCHITECTURE.md` 的模块边界与命令能力入口
- OpenWiki 不手工改生成页，由源码/文档更新后再自动刷新

### 13.5 release snapshot 升级门禁

采用一次硬协议切换，不实现 legacy snapshot 合成器：

| 升级时旧 CR 事实 | 处理 |
|---|---|
| developing 或更早 | 可升级；后续 code review 按新协议生成并签入 snapshot |
| code-approved 且确认零 trunk publish | 可升级；首次 merge 按 `release-drift` 回 developing，重跑测试/评审/审批 |
| partial merge、merging 或 writing-back 且无 snapshot | 阻止激活新版本；先用当前旧流程完成并归档 |
| 新协议 CR | 缺 signed snapshot 一律禁止 merge/writeback |

升级 preflight 使用临时只读 `crctl upgrade-check --workspace <Installation Workspace>`：fetch 后直接从 knowledge-base origin trunk 与 active repo remote refs 判断，不读取可能陈旧的用户主 checkout、不创建 Transaction Workspace、不修改任何文件。输出 `safe[]|requiresReapproval[]|blocksUpgrade[]|canActivate`；无 blocker exit 0，有 blocker或事实无法确定 exit 1。协议切换完成并确认所有安装不再存在旧在途事务后，连同 dispatch/help/tests 整体删除（`CUSTOM-TODO-009`）。若发现 authority 冲突或无法证明零 publish，按 blocker 处理。不得从 merge metadata/current branch 合成 signed snapshot，不自动改写历史 approval，不用 `approve --resign` 补签。实现本重构的 CR 自身继续由旧 Installation Workspace crctl 完成 merge/writeback/archive；之后才激活 trunk 中新版本，从下一个 CR 起强制新协议。

## 14. 测试矩阵

### 14.1 merge 三仓沙箱

| 场景 | 预期 |
|---|---|
| 三仓成功 | 三个 ref confirmed；单 finalize commit含完整 metadata/status/verification |
| 一仓无改动 | journal 记 skipped；不伪造 merge SHA；cleanup 仍覆盖该仓 |
| prepare 第三仓冲突 | 零 remote push、零本地 trunk移动 |
| 第二仓 push 被拒 | 第一仓 confirmed、第二仓 pending；status 仍 code-approved；重跑 roll-forward |
| operation lock owner 存活/被 kill/PID 复用/foreign hostname/token mismatch | 分别 locked/同主机安全回收/保守阻断/不可验证阻断/拒绝解锁；无 TTL/force unlock |
| 第一仓 push 后 kill | journal 可能仍 publishing；重跑从 remote=mergeSha 恢复 confirmed |
| register/merge finalize/writeback/archive 使用同一 remote/base/candidate 夹具 | 四者得到一致的 `confirmed|pushable|rebuild|history-rewritten` 分类；各自 rebuild 仍断言业务产物 |
| archived / rejected / withdrawn cleanup | archived 仅删已证明合入 trunk 的 refs；rejected/withdrawn 只删 clean 本地 worktree并保留未合并 refs，dirty 返回 cleanup-pending |
| push 前 trunk remote 推进 | lease 拒绝；未发布 repo 基于新 base 重新 prepare |
| upgrade-check 面对 developing/旧 code-approved 零 publish/legacy partial merge/authority unknown | 分别输出 safe/requiresReapproval/blocksUpgrade；只有无 blocker 才 exit 0，且全程零写入 |
| code review 记录后、approve-code 前 remote ref/worktree/artifact 漂移 | `RELEASE_SUBJECT_DRIFT`，approval.yml/cr.md 零写入；TTY 与 Ed25519 grant 均要求重跑测试/评审 |
| prepare 前 code/source/TASK 与 release snapshot 不同，且零 trunk publish | crctl 标记原审批 stale，经单一 proposed `release-drift` 转换回到 developing并返回对应结构化结果；Skill 解释、Pipeline abort，随后重新测试/评审/审批 |
| PRD/SDD 与 release snapshot 不同 | `APPROVED_ARTIFACT_DRIFT` 硬阻断，不由代码审批代替需求/架构重新审批，不进入 merge/writeback |
| 任一 trunk publish 后 requirement ref 移动 | `MERGE_SOURCE_MOVED_AFTER_PUBLISH`；保持 code-approved/blocked，禁止自动 reset/force/二次 merge；新提交拆新 CR，管理员恢复 approved ref 后续跑 |
| 已发布后 remote 正常追加 | mergeSha 是 ancestor，视为 confirmed，不覆盖后来提交 |
| 已发布后历史重写 | `MERGE_REMOTE_HISTORY_REWRITTEN`，禁止自动 force |
| 全仓 publish 后 finalize push stale | 重建 finalize commit，不 revert code repos |
| finalize push 后 kill | fetch 发现 origin 已包含 commit，幂等标 finalized且只发一次事件 |
| journal 丢失 | 从 requirement ref、trunk ancestry、commit trailer重建或安全重做 prepare |
| prepare 后 graph 变化且零副作用 | 同一 tx 更新 digest/repo snapshot 并自动 reprepare |
| 任一副作用后 graph 变化 | `GRAPH_CHANGED_DURING_TRANSACTION`，输出 repo diff，不自动增删参与仓 |
| 重复执行已 finalized CR | `changed=false`，不重复 merge/metadata/verification/outbox |

### 14.2 workspace

- 相同 `registration_key` 在任一步失败后重跑，复用同一 CR-ID 并续跑；
- 已绑定 key 的业务输入变化返回 `REGISTRATION_INPUT_MISMATCH`；不同 key 允许相同业务输入创建不同 CR；
- status=`drafting` 但 register journal 未完成时，status/next 只返回恢复入口且不产生成功 execution context；
- 第 N 个仓失败后不补偿删除前 N-1 个 healthy worktree；重跑只创建缺失仓；
- 全缺失首次创建；
- 全 healthy 幂等；
- branch-only 挂接；
- remote-only resume；
- stale worktree metadata targeted repair；
- path 已存在但未注册，阻断且不删除；
- wrong branch/dirty 阻断；
- resume 任一远端缺失时零创建；
- 第二仓创建失败后重跑完成；
- linked worktree 调用不产生 `.rayai-worktrees/.rayai-worktrees`；
- repo id 改名但 role=knowledge-base，bucket 仍正确；
- Windows 路径空格、long path、CRLF。

### 14.3 write-set/authority/权限

- `rename:1..N` 前后 kill + restart；
- `writeback-apply` 内部脚本已生成任一 stage candidate、尚未应用时 kill，权威文件保持不变且重跑可复用或重建 bundle；
- candidate manifest 的 absolute/`..`/反斜杠/重复或乱序 path、symlink parent、tx 外 blob、blob hash mismatch、before 第三值、delete/rename/chmod 字段均 hard fail 且 staged set 为空；
- writeback candidate 准备后 origin trunk 前进：本 stage 未发布则从新 origin detached HEAD 重新生成并重验，不 rebase/cherry-pick；origin 已包含 stage commit 则 confirmed；journal 记录已发布但远端不再包含时 `WRITEBACK_REMOTE_HISTORY_REWRITTEN` 硬阻断；
- 远端确认前 cleanup 被拒；阶段确认后只删大体积 blobs 留 journal 摘要；archive-confirmed 后 cleanup 失败返回 `CR_ARCHIVE_CLEANUP_PENDING`，业务状态保持 archived，重跑不重复账本/事件并可幂等续跑；
- 第三方在中断期间改目标文件，返回 conflict，不覆盖；
- 同 CR 并发命令只有一个拿到 operation lock；不同 CR 的共享 trunk 发布由 Installation Workspace publish lock 串行，且 fetch/prepare 不持有该锁；
- finalize 前 CR worktree 是 authority；finalize 后 detached HEAD 的专用 Transaction Workspace 是 authority，且不创建 transaction 分支；
- post-merge old worktree 写入被拒；
- fake `--caller` 不存在；
- cwd 指向 workspace 外 repo 被拒；
- generic Git 不再允许 merge/revert/worktree remove；
- 文档中的每个 crctl 命令都命中 dispatch/help/必填旗标；
- Pipeline prompt 超长且含多 Git 命令时 checker 失败。

## 15. CI 与验收命令

```bash
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node skills/shared/crctl/scripts/check-pipeline-contract.mjs
node --test skills/shared/crctl/scripts/test/*.test.mjs
node --test skills/writeback/scripts/test/*.test.mjs
node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8'));"
```

最终验收：

1. 任一 remote push/rename/commit/finalize 中断均返回或重建 `txId/phase/sideEffects/recoverCommand`；
2. status 与 N 条 merge metadata 不再分 N+1 次写入；
3. 部分 remote 发布是可观测、可续跑的 saga，不再伪装“自动回滚后未合并”；
4. registration/resume/cleanup 对 healthy/missing/partial 状态幂等；
5. post-merge 唯一可写 workspace 是 knowledge-base trunk authority；
6. writeback 第一个 baseline commit 与 `writing-back` 状态同 commit；
7. Pipeline 不复制 Skill/crctl 算法，Skill 不手写 Git/账本事务；
8. caller 文档与真实安全边界一致，cwd/ref/path 均受 graph containment；
9. README 不维护另一份 merge/恢复执行手册；
10. Ubuntu + Windows CI 均覆盖关键事务向量；
11. 同一 CR 的 TASK 索引随完成即时标记 done，中间提交不激活半套新协议，也不引入 feature flag/compat wrapper/双写。

## 16. 单 CR 交付边界与小提交顺序

本方案作为一个 CR 完整交付，不拆成会产生半协议状态的多个 CR；在同一 requirement branch 内拆约 12 个 TASK并即时登记 done。新公共协议在最终 contract 切换前只供分支内测试，本 CR 自身仍由旧 Installation Workspace 流程完成 merge/writeback/archive，下一 CR 才启用新协议。禁止为分批发布增加 feature flag、compat wrapper 或双写。

建议 TASK 对应：fault tests；冗余删除；resolver；durable-tx；register/workspace；signed release snapshot；recoverable merge；Transaction Workspace/writeback；archive；Skill/Pipeline/controlled-shell；upgrade-check；docs/contracts/双平台 CI。

建议小提交：

1. `test(crctl): add failing merge and workspace recovery scenarios`
2. `refactor(crctl): remove dead helpers duplicate aliases and superseded low-level dispatch`
3. `refactor(crctl): centralize repository and worktree resolution`
4. `feat(crctl): add durable recoverable write sets`
5. `feat(crctl): make registration workspace ensure and cleanup idempotent`
6. `feat(crctl): execute merge as a recoverable multi-repo saga`
7. `feat(crctl): finalize merge metadata and status in one commit`
8. `fix(writeback): hand off authority to transaction workspace and apply candidates atomically`
9. `refactor(skill): delegate merge and workspace algorithms to crctl`
10. `refactor(pipeline): keep orchestration and pass operational workspace`
11. `fix(controlled-shell): enforce workspace containment and remove fake caller auth`
12. `test(contracts): validate commands git shapes and workspace authority`
13. `ci: run prompt pipeline transaction and writeback checks`
14. `docs: align merge workspace and recovery contracts`

每个提交都应保持现有测试可运行；涉及 schema/dispatch 的提交同时更新 help、Skill、checker，不留“代码已改、文本稍后补”的漂移窗口。

## 17. 风险与诚实边界

1. 多 remote 不可能获得数据库式原子 commit；本方案提供的是 ref CAS + durable reconcile + 最终单一 finalize fact。
2. 本地 `.crctl` journal 不是跨机器业务账本；跨机器恢复依赖远端 ref/commit trailer重建，最终审计依赖 Git finalize commit。
3. 同一 OS 用户仍可绕过 CLI 直接运行绝对路径 Git；hook/CLI 是治理层，不是操作系统 sandbox。真正跨主体授权需要平台签名 capability。
4. write-set 能保证 crctl 级恢复一致性，不能让任意外部文件读取者在多次 rename 之间完全看不到中间态。
5. graph 在事务中途变化时：零副作用自动丢弃旧 prepare 并按新 digest 重建；已有任一副作用则硬阻断，必须先恢复原 graph 完成事务，不能把新仓静默加入旧事务或用 force 绕过。
6. merge conflict 本轮只在任何 push 前硬失败，不尝试自动选择 `cr.md`/YAML 冲突侧；确定性 ledger 投影若后续需要，应由 crctl 单独实现并测试。
7. `CUSTOM.md` 等仓库特定治理检查不是通用 tools merge 算法。它们应在目标 workspace 的业务 gate 中声明；merge verification 只记录机器可证明的 Git/状态事实。
8. code-approved 分支冻结由 hooks/CI/平台受控 push 尽力执行，不构成 remote/OS 强隔离；绕过且发生在部分发布后时只硬阻断，不在本轮增加自动 source 修复命令。

最终目标不是把 Skill 写得更长，而是把当前“文本承诺的两阶段原子合并”改成代码可证明的、失败后仍能继续的最小事务链。
