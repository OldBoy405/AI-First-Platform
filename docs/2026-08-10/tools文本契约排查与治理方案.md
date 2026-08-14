# Tools 文本契约排查与治理方案

## 1. 背景

Tools 仓库由 Skill、Pipeline、Agent、crctl、目录图、权限矩阵和流程说明共同构成。大量运行逻辑以 Markdown、YAML 和 JSON 文本契约表达，文本不仅承担说明作用，也直接影响 Agent 和 Pipeline 的实际行为。

`merge-feature-branch` 审查已经暴露出一类系统性风险：

- 文档描述的命令或恢复入口实际不存在；
- 状态回退路径与状态机不兼容；
- 多文件业务事实由多条命令分步写入，出现半状态后无法恢复；
- 主 checkout 与 CR worktree 使用了不同快照，但 Skill 未区分其权威性；
- Pipeline prompt 复制 Skill 的完整算法，形成第二事实源；
- 自动测试只断言文本存在，未验证真实流程语义。

这些问题不局限于单个 Skill。Tools 仓库中的其他 Skill、Pipeline、Agent 也可能存在类似的合理性、冗余和歧义问题，因此需要建立一套全仓排查和持续治理机制。

---

## 2. 当前规模与已有检查

当前 tools 仓库实际规模：

| 类型 | 数量 |
|---|---:|
| Active Skill | 57 |
| Pipeline | 8 |
| Agent | 9 |
| Skill/Pipeline/Agent 文本资产 | 119 |
| 文本总行数 | 约 13,251 |
| `lint-prompts:ignore` | 88 |
| `crctl ...` 命令引用 | 225 |
| 历史 CR 编号引用 | 125 |

现有检查结果：

- `lint-prompts`：0 findings；
- Skill matrix：通过；
- Agent contract：通过；
- Pipeline JSON：通过。

这些结果说明现有检查器能够覆盖：

- Skill 是否登记；
- owner 是否唯一；
- Agent/Skill 权限是否匹配；
- Pipeline JSON 是否可解析；
- 已知裸 git、受控路径手写、旧命令引用等 prompt 漂移。

但它们尚不能完整覆盖：

- 状态路径是否可达；
- 失败后能否恢复；
- 多文件写入是否原子；
- 文档中要求的命令是否真实存在；
- runGit 形态是否命中 allowlist；
- 主 checkout/worktree 是否选对事实源；
- Pipeline prompt 与 Skill 是否重复维护同一算法；
- 测试是否只验证“文本存在”而非真实行为。
- 是否都遵守了单一事实的原则。

因此，全仓排查不能只依赖当前 lint 结果。

---

## 3. 治理原则

### 3.1 各层逻辑归属

后续审计应先判断一段逻辑是否位于正确层级。

| 层 | 应拥有的逻辑 | 不应拥有的逻辑 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 crctl |
| crctl | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览 | 另一份可执行细节事实源 |

审计时重点识别“逻辑泄漏”：

- Skill 自行拼 worktree 路径，而 crctl 已有 resolver；
- Pipeline prompt 复制 Skill 的完整步骤；
- Agent 直接描述如何修改受控账本；
- 文档要求写受控字段，但没有合法 crctl 子命令；
- Skill 在 prompt 中模拟事务，而 crctl 已有 `casWriteMulti`；
- README、Pipeline 和 Skill 分别维护状态映射；
- 同一错误恢复流程在多个入口各写一份。

### 3.2 单一事实源

运行时事实源继续保持：

| 事项 | 权威来源 |
|---|---|
| 状态机 | `dir-graph.yaml#change-request-track.state_machine` |
| 参与仓与 trunk | 目标 workspace `dir-graph.yaml#repositories` |
| Skill active 清单 | `skills/_index.yml` |
| Agent/Skill 权限 | `agent-skill-matrix.yml` |
| Pipeline 顺序和 reviewLoop | `pipeline-templates/*.pipeline.json` |
| 状态与账本写入 | crctl |
| Git 白名单 | `skills/shared/controlled-shell/rules.json` |

审计报告、临时 payload 和检查结果不得成为新的运行时事实源。

### 3.3 深模块优先

发现复杂文本契约时，不应继续把 Skill 写得更长，而应判断确定性逻辑能否下沉：

- 状态、CAS、账本、audit、outbox → crctl；
- 文档转换、索引生成 → 版本化脚本；
- 顺序和 reviewLoop → Pipeline；
- 业务判断和异常分类 → Skill；
- 路由和权限 → Agent。

目标是缩小 Skill 的调用接口，把复杂性集中到少量可执行、可测试的深模块中。

---

## 4. 风险分层

不按目录字母顺序检查，而按副作用与失败成本分层。

## 4.1 P0：事务型与状态型 Skill

优先审计所有涉及以下行为的 Skill：

- Git merge/push/revert/worktree；
- CR 状态推进；
- `_backlog.yml`、`_history.yml`、`cr.md`；
- 多文件写入；
- 跨仓操作；
- 人工审批；
- 归档与清理。

建议首批清单：

```text
skills/writeback/merge-feature-branch
skills/cr/cr-archive
skills/requirement/requirement-register
skills/sync/push-progress
skills/sync/pull-progress
skills/sync/resume-from-remote
skills/sync/handover-cr
skills/develop/approve-tech-design
skills/develop/approve-dev-start
skills/develop/approve-code
skills/requirement/approve-requirement
skills/shared/crctl
skills/shared/controlled-shell
```

这类 Skill 必须进行真实失败点推演，不能只检查 Happy Path。

## 4.2 P1：写回与评审闭环

第二批审计：

```text
skills/writeback/writeback-prd-sdd
skills/writeback/writeback-tasks
skills/writeback/writeback-traceability
skills/develop/write-test-report
skills/requirement/review-requirement
skills/develop/review-tech-design
skills/develop/review-dev-plan
skills/develop/review-code
skills/develop/write-tech-design
skills/develop/write-dev-tasks
skills/develop/implement-code
```

重点检查：

- reviewLoop 状态和证据是否同步；
- blocker 后的修复节点是否可达；
- 判断 payload 与 canonical 写入是否分离；
- 回写脚本要求的前置状态与 Pipeline 推进顺序是否一致；
- 幂等重跑是否识别已有产物；
- Pipeline 是否遗漏 checkpoint、测试报告或证据重建节点；
- approval 证据 freshness 是否在状态推进前校验。

## 4.3 P2：只读与内容生成 Skill

最后审计 planning、competitive、spec dashboard、知识查询等低副作用能力。

主要检查：

- 路径和输入事实源是否正确；
- 是否声称写入但没有 validate；
- 是否硬编码产品仓、trunk 或本机路径；
- 输出字段是否被下游真实消费；
- 是否重复实现已有查询、报告或文档生成能力；
- Agent 和 Pipeline 是否复制内容生成细节。

P2 问题一般不直接损坏账本，可在 P0/P1 稳定后处理。

---

## 5. 单个 Skill 的统一审计表

不为 57 个 Skill 各写一份长报告。使用一张总表，每个 Skill 按相同维度检查。

### 5.1 接口检查

| 检查项 | 期望 |
|---|---|
| 输入是否完整、必填项是否明确 | 所有运行必需信息均有唯一来源 |
| 前置 status 是否明确 | 与状态机一致且可到达 |
| 成功后的 status 是否明确 | 有真实 crctl 转换 |
| 输出是否真实存在 | 字段、文件和摘要均可生成 |
| 输出是否被下游消费 | 不保留无人消费的格式要求 |
| 下一步提示是否统一 | CR Skill 使用 `crctl next` |

### 5.2 事实源检查

| 检查项 | 期望 |
|---|---|
| repo/trunk 来源 | 目标 workspace `dir-graph.yaml` |
| worktree 来源 | 权威 resolver/crctl |
| status 来源 | `cr.md`/crctl |
| gate 来源 | `gates.json` + Pipeline passCondition |
| owner 来源 | `cr.md` 和 `_backlog.yml#owners` |
| 是否复制状态机 | 不复制 |
| 是否复制 Pipeline 映射 | 不复制 |

### 5.3 写入检查

| 检查项 | 期望 |
|---|---|
| 读取文件明确 | 是 |
| 写入文件明确 | 是 |
| 受控路径有合法命令 | 是 |
| 同一业务事实多文件写入 | 同一 CAS |
| audit/outbox 时机 | 权威写入或 commit 成功后 |
| 写入型 Skill 校验 | `validate-doc` 或等价校验 |
| 失败路径 | 零写入或明确保留完整候选状态 |

### 5.4 Git 与 Shell 检查

| 检查项 | 期望 |
|---|---|
| 所有 Git 操作 | 经 controlled-shell/crctl git |
| 命令形态 | 命中 `rules.json` |
| 非 TTY | 不打开编辑器、不等待 stdin |
| 本地工作区 | dirty 检查 |
| 远端引用 | fetch 后再比较 |
| 远端并发 | push 前 stale 复核 |
| 裸 Git 旁路 | 不允许 |

### 5.5 恢复检查

对每个有副作用的步骤都回答：

1. 步骤前的权威状态是什么？
2. 失败后哪些文件、commit 或远端 ref 已改变？
3. 再次执行能否识别已有结果？
4. 恢复命令是否真实存在并被 allowlist 放行？
5. 恢复会不会重复写入、重复 push 或丢数据？
6. 状态机是否允许恢复入口重新进入？
7. recovery 记录写到哪里，是否有合法写入通道？

以下描述不算完整恢复方案：

```text
失败后重新运行
```

必须说明重新运行如何识别和处理残留状态。

---

## 6. P0 Skill 的场景推演

事务型 Skill 至少覆盖以下场景：

```text
A. Happy Path
B. 第一个副作用前失败
C. 第一个写入后进程中断
D. 多仓只完成一部分
E. Git commit 成功但 push 失败
F. push 成功但 metadata 失败
G. CAS 冲突
H. 重复调用
I. 无改动仓
J. linked worktree
K. 主 checkout 与 CR worktree 分叉
L. Windows CRLF
M. Windows long path
N. 非 TTY
O. 远端 trunk 并发推进
```

每个场景必须给出：

- 初始状态；
- 执行动作；
- 预期退出码；
- 权威文件是否变化；
- Git 本地和远端状态；
- 是否产生 audit/outbox；
- 下一次恢复入口。

---

## 7. 扩展现有检查器

优先扩展现有检查器，不立即创建大型审计框架。

## 7.1 扩展 lint-prompts.mjs

### R10：crctl 子命令存在性

扫描 Skill、Pipeline、Agent 中出现的：

```text
crctl <command>
```

与 `crctl.mjs` dispatch/help 对照。

用于发现：

- 文档要求调用不存在的命令；
- 文档要求写入某受控字段，但没有专用子命令；
- 已删除命令仍被 Skill 引用。

### R11：状态转换可达性

当前 R7 主要检查 `advance` 是否包含 `--to` 和 `--trigger`。应进一步把可识别的：

```text
from → to @ trigger
```

与 `dir-graph.yaml#change-request-track.state_machine` 对照。

无法从文本确定 `from` 时只报告 warning，不猜测。

### R12：runGit 与 allowlist 对照

扫描 Skill 中的：

```yaml
runGit:
  subcommand: ...
  args: [...]
```

与 `skills/shared/controlled-shell/rules.json` 对照，检查：

- subcommand 是否存在；
- 参数形态是否命中 shape；
- 是否包含 forbidden flag。

用于发现文档要求某 Git 命令，但 controlled-shell 实际会拒绝的问题。

### R13：Step/章节/错误码引用检查

检查：

```text
见 Step 4
按 §2.1
见错误表 XXX
```

目标步骤、章节或错误码在当前文件中是否真实存在。

### R14：Pipeline prompt 重复算法提示

先作为 report 级别，不立即阻断 CI。

判据：

- Pipeline node 已声明 `ref`；
- prompt 长度明显过长；
- prompt 与对应 `SKILL.md` 包含大量相同步骤、命令或错误码。

目标是提示人工把算法收敛到 Skill，而不是实现复杂的语义相似度系统。

### R15：lint ignore 审计

当前有 88 个 `lint-prompts:ignore`，应增加：

- 每个 ignore 必须有非空原因；
- 不允许无边界的大段 ignore；
- 触及裸 git、状态推进、受控账本的 ignore 自动升为 review warning；
- 输出 ignore 清单和数量变化；
- 新增 ignore 必须在评审中解释为何不是规则缺陷。

## 7.2 扩展 check-skill-matrix.mjs

在现有 owner 和 active 检查基础上增加：

- Active Skill 文件必须存在；
- `SKILL.md#name` 必须等于 index id；
- 写入型 Skill 必须声明读取、写入、状态推进、失败处理和校验；
- CR 上下文 Skill 的输出摘要必须使用 `crctl next`；
- active 数量与架构文档固定数字不一致时告警；
- Pipeline node.ref 对应 Skill 必须为 active；
- Skill owner 与 Pipeline owner 调用权限必须一致。

当前实际 active Skill 是 57，而 `ARCHITECTURE.md` 仍写“59 Skill”，已经是简单的计数漂移案例。长期应删除多处固定计数，或由检查器验证。

## 7.3 扩展 check-agents-contract.mjs

增加：

- Agent 不得直接描述 `_backlog.yml`、`_history.yml`、`cr.md status` 的写入算法；
- Agent 不得出现裸 git；
- Agent 不得自行拼 worktree 路径；
- Agent 正文引用的 Skill/Pipeline 必须在矩阵允许范围；
- Agent 不得复制 Skill 的完整执行步骤；
- 人工审批后必须路由到 `approve-*`；
- Agent 只负责路由，不直接推进状态或改受控文件。

---

## 8. Pipeline 状态可达性检查

应增加跨节点状态推演。

以 feature-writeback 为例：

```text
merge-feature-branch
  code-approved → merging

writeback-prd-sdd
  要求 merging
  merging → writing-back

writeback-tasks
  要求 writing-back

writeback-traceability
  要求 writing-back

cr-archive
  writing-back → archived
```

检查器应验证：

1. 每个节点的前置状态；
2. 节点成功后是否推进状态；
3. 下一节点前置状态是否满足；
4. 失败路由是否存在合法状态转换；
5. retry 时允许的状态是否覆盖可能残留状态；
6. human_approval 后是否存在显式写入节点；
7. reviewLoop repairRef/replayNodes 是否真实存在；
8. 达到 maxAttempts 后是否会错误进入后续节点。

这类检查可以发现：

- 在 `merging` 中要求执行 `review-tech-design`；
- 脚本要求 `merging`，但 Pipeline 已先推进到 `writing-back`；
- block 路由指向状态机不可达节点；
- Skill 只允许 `code-approved`，但失败后可能留下 `merging`；
- reviewLoop 修复后漏重建测试报告或 checkpoint。

### 8.1 最小机器接口声明

可逐步为真正参与 CR 状态机的 Skill 增加最小 frontmatter：

```yaml
name: merge-feature-branch
states:
  from: [code-approved]
  to: merging
  trigger: merge-feature-branch
writes:
  - change-requests/{cr}/cr.md
  - change-requests/_backlog.yml
```

这些字段不是第二状态机。检查器必须把它们与 `dir-graph.yaml` 的权威状态机交叉验证。

不要求一次给所有 57 个 Skill 增加字段，只给状态型 CR Skill 增加。

---

## 9. 测试策略

仅靠文本 lint 无法发现恢复和原子性问题。P0/P1 Skill 必须配套可执行测试。

## 9.1 文档结构测试

验证：

- 必要章节存在；
- frontmatter 可解析；
- schema 示例有效；
- Pipeline ref 和输出字段存在；
- Step/§ 引用不悬空。

文档结构测试不能代替行为测试。

## 9.2 crctl 命令测试

验证：

- 状态转换；
- gate；
- CAS；
- 多文件全有或全无；
- 幂等；
- 失败零写入；
- commit 失败恢复；
- outbox/audit 时机；
- payload 成功删除、失败保留。

## 9.3 Git 沙箱测试

在临时目录创建 2～3 个本地 bare remote，真实运行：

```text
worktree
merge-tree
merge
commit
push
revert
remote stale
partial push
```

不要只 mock Git 输出。

建议覆盖：

- 两仓成功；
- 一个无改动仓；
- 第二仓 push 失败；
- 第一仓补偿成功/失败；
- metadata push non-fast-forward；
- 本地 commit 后进程中断；
- requirement 分支已 merge 后又被 revert 的重试语义。

## 9.4 Pipeline 合约测试

不必先实现完整 Pipeline Runner。可以静态验证：

- 节点顺序；
- required input 传递；
- 前后状态衔接；
- reviewLoop repair/replay 节点存在；
- human approval 后有显式状态写入；
- Pipeline prompt 不调用不存在的命令；
- onFail 与 Skill 错误语义一致。

---

## 10. 文本去重策略

## 10.1 Pipeline

Pipeline 只保留：

- 输入映射；
- 节点顺序；
- reviewLoop；
- passCondition；
- 输出要求；
- 对 Skill 的调用。

不复制 Skill 的完整操作算法。

## 10.2 Agent

Agent 只保留：

- 何时调用哪个 Skill/Pipeline；
- actor 权限边界；
- 如何向用户展示结果；
- 人工节点何时暂停。

不复制 Skill 的 Git、CAS、状态和账本操作。

## 10.3 Skill

Skill 保留：

- 业务判断；
- 编排；
- 前置/后置；
- 失败恢复；
- 对 crctl 或版本化脚本的调用。

确定性写入下沉到 crctl 或版本化脚本。

## 10.4 README/ARCHITECTURE

只维护流程级说明，不重复：

- 完整 CLI 参数；
- 所有错误码；
- 多仓补偿算法；
- schema 的每个字段；
- 可从索引自动统计的固定数量。

## 10.5 历史 CR 注脚

当前 Skill/Agent/Pipeline 中有较多历史 CR 编号引用。处理原则：

- 对理解当前契约仍必要的保留；
- 纯实施历史迁移到 CR、git commit 或 ADR；
- 不让主流程被历史背景淹没；
- 不在多份文本重复同一历史说明。

---

## 11. 分批实施计划

不建议用一个 CR 修改全部 57 个 Skill。

## 11.1 CR-A：审计能力增强

范围：

- lint R10～R13；
- Skill/Agent contract 补强；
- Pipeline 状态可达性检查；
- 生成第一次全仓审计报告。

不在该 CR 中大规模修改业务 Skill。

## 11.2 CR-B：writeback/cr 事务链

处理：

```text
merge-feature-branch
writeback-prd-sdd
writeback-tasks
writeback-traceability
cr-archive
feedback-writeback
```

重点：

- 原子性；
- 状态推进顺序；
- metadata；
- 回写前置状态；
- 归档；
- worktree 清理；
- 失败恢复。

`crctl merge-finalize` 可作为该批次的第一个试点。

## 11.3 CR-C：registration/sync 链

处理：

```text
requirement-register
push-progress
pull-progress
resume-from-remote
handover-cr
list-remote-checkpoints
```

重点：

- Installation Workspace/Operational Workspace；
- worktree 根；
- 远端新鲜度；
- 部分创建/恢复；
- checkpoint 完整性；
- owner 变更；
- 多仓空分支。

## 11.4 CR-D：develop/review 链

处理：

```text
write-tech-design
review-tech-design
write-dev-plan
write-dev-tasks
review-dev-plan
approve-dev-start
implement-code
write-test-report
review-code
approve-code
```

重点：

- reviewLoop；
- blocker 路由；
- evidence freshness；
- replayNodes；
- 审批门禁；
- TASK 状态；
- 测试报告重建。

## 11.5 CR-E：Agent/Pipeline 去重

最后统一：

- 精简 Pipeline prompt；
- 精简 Agent 中的执行算法；
- 修复 README/ARCHITECTURE 计数漂移；
- 清理无效历史注脚；
- 复核和收紧 lint ignore。

---

## 12. 审计报告格式

建议只生成一个汇总报告：

```text
docs/analysis/tools-text-contract-audit.md
```

示例：

```yaml
summary:
  total: 57
  passed: 0
  p0: 0
  p1: 0
  p2: 0

findings:
  - id: TCA-001
    severity: P0
    artifact: skills/writeback/merge-feature-branch/SKILL.md
    category: atomicity
    evidence:
      - "advance 与 merge-metadata 分离"
    impact: "可能留下 merging + 部分 metadata"
    proposed-fix: "crctl merge-finalize"
    fix-cr: pending
```

这份报告是审计产物，不是运行时事实源。

不建议：

- 为每个 Skill 创建一份额外 YAML 台账；
- 在审计报告复制完整 Skill 内容；
- 在报告中维护第二份状态机；
- 让报告参与运行时路由。

---

## 13. 严重级别与处理规则

| 级别 | 定义 | 处理 |
|---|---|---|
| P0 | 可导致账本损坏、错误状态、部分跨仓发布、审批绕过或不可恢复 | 对应流程再次使用前修复 |
| P1 | 会导致错误路由、证据缺失、恢复不完整或明显漂移 | 分域 CR 修复 |
| P2 | 冗余、历史噪音、轻微歧义、无人消费输出 | 批量精简 |
| Info | 风格或可读性建议 | 不单独建 CR |

处理原则：

- P0/P1 修复必须留下可执行回归测试；
- 不能只改 Skill 文本而不补真实执行能力；
- 文档要求的命令不存在时，要么新增版本化能力，要么删除该要求；
- 不为潜在需求提前引入 Runner、数据库、锁服务或动态框架；
- 同一根因应在共享执行层修一次，不在多个 Skill 分别打补丁。

---

## 14. 建议立即执行的顺序

1. 将 `merge-feature-branch` 优化作为试点 CR 实施；
2. 新建“Tools 文本契约审计”CR；
3. 增加以下机械检查：
   - crctl 子命令存在性；
   - 状态转换可达性；
   - runGit allowlist 对照；
   - Step/§ 引用检查；
4. 对 P0 Skill 做人工场景推演；
5. 产出第一次全仓审计报告；
6. 暂不批量修改 P1/P2；
7. 按 writeback → sync → develop → agent/pipeline 顺序分 CR 修复；
8. 每修一个语义问题，增加至少一个会在旧行为下失败的回归测试；
9. 最后执行 Pipeline/Agent/README 去重和历史说明清理。

---

## 15. 完成标准

全仓文本契约治理完成应满足：

- 所有 active Skill 都有唯一 owner 和真实文件；
- 所有 Pipeline node.ref 都指向 active Skill；
- 所有 Agent 调用都符合矩阵；
- 所有文本中的 crctl 命令真实存在；
- 所有 runGit 形态命中 rules.json；
- 所有状态推进在状态机中可达；
- 所有受控路径写入都有合法执行入口；
- 同一业务事实的多文件写入使用同一 CAS；
- P0 Skill 有失败、重试和中断场景测试；
- Pipeline prompt 不复制 Skill 完整算法；
- Agent 不复制 Skill 执行逻辑；
- `lint-prompts:ignore` 均有明确理由且无大范围逃逸；
- README/ARCHITECTURE 不维护已漂移的固定计数；
- 全量 crctl、writeback、matrix、agent contract、prompt lint 和 Pipeline JSON 检查通过。

核心目标不是让 57 个 Skill 变得更长，而是：

> 文本负责说明与编排；确定性、原子性、状态和账本写入下沉到 crctl 或版本化脚本；Pipeline 负责顺序；Agent 负责路由。

通过这种方式，Tools 包能够逐步减少多事实源、不可达恢复路径和依赖 Agent 自觉的执行风险，同时保持现有 CR 流程、仓库结构和方法论边界不变。
