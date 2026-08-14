# tools 流程步骤优化 v2：后续候选整理

> 文档定位：排除现有 Phase 0、Phase 1，以及《tools流程步骤优化v2-前移优化项.md》后，保留的后续候选路线。
>
> 当前状态：全部为候选，不构成当前实施授权。每项必须在前置证据满足后重新确认，并另立 Spec/CR。

## 1. 候选路线总览

```text
Phase 2  PRD Runner 垂直试点
    ↓
Phase 3  最小公共能力与 Registration 上下文
    ↓
Phase 4  其余 Authoring / Review
    ↓
Phase 5  Implement / Test / Code Review
    ↓
Phase 6  Merge / Writeback / Archive
    ↓
Phase 7  按数据触发的可选恢复机制
```

顺序是晋升条件，不是一次性承诺的实施计划。

## 2. Phase 2：PRD Runner 垂直试点

前置条件：Phase 0、Phase 1 及前移优化项完成，并重新确认是否需要 Runner。

候选新增：

```text
write-requirement-prd/scripts/prepare.mjs
write-requirement-prd/scripts/finalize.mjs
```

试点范围：

- 复用现有 CR 阶段 PRD frontmatter、章节和回修语义；
- 复用 `crctl backlog-set`、`next`、`review-record`、`git`；
- 支持 `create` 与 `repair`；
- 校验 CR 阶段 PRD 的必填字段、章节、FR/AC 编号及 CRLF；
- 验证 create → BLOCK → repair → PASS → approval 闭环。

不恢复 engineering-docs 通用 PRD schema、历史 Ajv/gray-matter validator，也不预建公共 Runner 库。

## 3. Phase 3：最小公共能力与 Registration 上下文

前置条件：PRD Runner 通过真实闭环，且 Registration 构成第二个真实 Runner。

### 3.1 shared Runner library

仅从两个真实调用者提取已经重复且语义稳定的最小交集，例如：

- CRLF 规范化读取；
- 稳定 JSON 输出；
- 统一 `fail(code, message, extra)`；
- 显式路径验证；
- `spawnSync(..., { shell: false })`；
- crctl CLI 薄封装。

不得预建通用 workflow、patch、YAML serializer、状态缓存或动态加载框架。

### 3.2 Requirement Register Runner

候选新增：

```text
skills/requirement/requirement-register/scripts/run.mjs
```

只编排现有能力：

- `crctl cr-init`；
- `crctl worktree-path`；
- `crctl git`；
- `dir-graph.yaml#repositories`。

不新增 `register-preflight`、`registration-check`、`stage-context`。

### 3.3 Repo/worktree/base context

如真实恢复案例证明跨节点无法可靠传递上下文，再定义最小注册输出：

```yaml
repositories:
  - id:
    role:
    trunk:
    worktree:
    base-sha:
    branch:
```

本项不增加每 CR 仓库选择模型，所有参与仓仍来自 `dir-graph.yaml#repositories`。

### 3.4 Checkpoint 语义

先复用现有 `checkpoint-add`。只有真实恢复案例证明 remote progress 无法表达 branch-base 或 approved-source 时，才讨论 `kind` 扩展；不预先批准多个 checkpoint 类型。

## 4. Phase 4：Authoring 与 Review

按 Skill 逐个晋升，不一次性建设所有 Runner。机械步骤少的 Skill 可以继续使用 prose。

### 4.1 Requirement Review

- 候选增加 prepare/finalize；
- 评审维度契约保留在 `review-requirement/`；
- `crctl` 继续校验通用 payload 形态；
- Runner 只负责 stage 维度的确定性校验与编排。

### 4.2 SDD

prepare 候选读取：PRD、目标 repo、ARCHITECTURE、相关 Pipeline/gates、真实代码基线和 review feedback。

finalize 候选校验：frontmatter、章节、FR 覆盖、Prompt 采纳影响、embedded 状态并提交。

### 4.3 Plan/TASK

候选由 Runner 编排：

- TASK-ID、slug；
- frontmatter；
- `tasks/_index.yml`；
- 依赖图、estimate、接口签名和验收条件结构。

TASK 完成后的 `done` 仍由后续 Implement 路线处理。TASK-ID 分配应继续复用现有 `crctl task allocate`，不得在 Runner 中重复实现编号逻辑。

### 4.4 Review Runners

统一候选模式：

```text
prepare：subject + contract + previous evidence + attempt
LLM：verdict / blockers / dimensions / suggestions
finalize：review-record + 状态路由 + commit
```

不得让每个 review Skill 重新实现账本写入和轮次记账。

## 5. Phase 5：Implement、Test 与 Code Review

前置条件：Authoring/Review 候选已经稳定，并完成至少一个单仓代码 CR、一个多仓代码 CR，以及一次 code review BLOCK → repair → PASS。

### 5.1 Implement Code Runner

候选新增 `implement-code/scripts/prepare.mjs` 与 `finalize.mjs`：

- prepare 输出 repo/worktree、依赖、涉及文件、上游接口、定向测试计划和 review feedback；
- finalize 输出 changed files、定向测试结果，调用 `crctl task done`，提交并返回下一批 TASK；
- 普通代码修改仍使用宿主 patch 工具。

### 5.2 Structured Test

继续优先使用现有 `crctl test --cmd`。只有真实多命令测试计划证明现有参数传递无法可靠恢复时，才候选增加：

```text
crctl test --plan <test-plan.json>
```

候选记录 argv、cwd、timeout、exit、log、repo HEAD、dirty 和 generated-at。

### 5.3 Test Report Runner

候选由 prepare 调用 `crctl test` 并生成 coverage skeleton，LLM 只补结果解释、覆盖矩阵和未覆盖风险；finalize 保护 crctl 生成区并更新 canonical test evidence。

### 5.4 Code Review Runner

候选由 registration/checkpoint context 提供 diff base，不从 Git log 猜测。prepare 读取 changed files、完整 diff、SDD/TASK/test-report、验证命令 replay 和 subject digest；finalize 写入 review-record、推进 PASS/BLOCK 状态并提交。

### 5.5 用户主动扩大范围

继续优先复用现有 `review-note`、reject 路由和 subject freshness。只有出现多个并行 scope change、跨设备恢复或独立统计需求，才创建 scope-change ledger。

## 6. Phase 6：Merge、Writeback 与 Archive

前置条件：repo context、approved checkpoint、全部 TASK done、代码评审/测试证据、候选 Runner 基础和一次临时远端多仓演练。

### 6.1 Merge Runner

候选新增 `merge-feature-branch/scripts/run.mjs`，负责：

- 全仓预检；
- merge-tree；
- 本地 no-commit merge；
- commit、freshness、顺序 push 和补偿；
- merge journal；
- 复用现有 advance、merge-metadata 和 `crctl git`。

不预建大型 merge-record。只有批量元数据确有需要时，才讨论 `merge-metadata --from result.json`。

### 6.2 Writeback orchestration

继续复用：

```text
writeback-prd-sdd.mjs
writeback-tasks.mjs
writeback-traceability.mjs
```

候选新增 `writeback/scripts/run.mjs`，编排全局预检、dry-run/apply、writing-back 推进、traceability prepare/finalize 及现有恢复边界下的 commit/push。

首版不增加持久化 plan artifact，apply 前重新校验关键 hash。

### 6.3 Traceability

候选新增 `writeback-traceability/scripts/prepare.mjs` 与 `finalize.mjs`：

- prepare 生成完整 skeleton；
- LLM 只填写编辑性字段；
- finalize 复用现有 writeback 逻辑完成 canonical 写入。

### 6.4 Archive Runner

候选新增 `cr-archive/scripts/run.mjs`，首版只支持 `--mode normal`，编排：

1. 前置 gate；
2. embedded archived；
3. archive-move（事件与 backlog/history/index 同一 CAS）；
4. 归档 commit/push；
5. 确认远端发布；
6. 清理全部 repo worktree；
7. 删除允许删除的远端分支；
8. 生成 cleanup-report；
9. cleanup commit/push。

只有真实出现可独立恢复的 publish 或 cleanup 半完成案例，才增加对应 retry mode。

## 7. Phase 7：按数据触发的可选机制

以下机制不预建：

### 7.1 Control-plane SHA pin

前移补充项只解决稳定 tools root。只有再次出现 gate 自举冲突，才实施 control-plane SHA pin。

### 7.2 Scope-change ledger

只有 `review-note`、reject 和 subject freshness 无法满足审计时实施。

### 7.3 Task reconcile

第二个真实 late-done 恢复案例出现后，再升格为 crctl 命令。

### 7.4 Writeback plan artifact

出现真实 dry-run/apply TOCTOU 故障后再增加。

### 7.5 crctl 模块化

单独建立架构 CR，不作为 Runner 优化的附带改动。

### 7.6 并行 remote push

当前 repo 数量少，继续使用顺序 push。只有指标证明 push 成为瓶颈时再考虑并行化。

## 8. 后续候选的共同准入条件

每个后续 Spec 必须说明：

1. 为什么能力属于 crctl、Runner 或 LLM；
2. 复用了哪些现有 purpose-specific command；
3. 是否新增权威事实源；
4. 是否直接或间接写账本；
5. 失败如何重试和恢复；
6. 是否依赖历史 CR 形态；
7. 是否改变状态机 declared/expanded 数量；
8. 是否改变人工审批强度；
9. 没有真实证据时，为什么不能继续保留现有 Skill prose。

