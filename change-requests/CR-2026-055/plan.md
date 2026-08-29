---
id: CR-2026-055-plan
type: PLAN
cr-ref: CR-2026-055
sdd-ref: "change-requests/CR-2026-055/sdd.md"
target-version: tbd
status: draft
created: 2026-08-30T00:20:00+08:00
updated: 2026-08-30T00:20:00+08:00
---

# 1. 交付里程碑

| 里程碑 | 内容 | 预计工时 | 退出条件 |
|---|---|---:|---|
| M1 评审 Skill 合同 | 完成 `review-tech-design`、`review-dev-plan` 的输入、AC/事实核验、增量评审和 UPSTREAM 规则 | 16h | 两个 Skill 的职责边界、输入合同和失败语义与 SDD 一致 |
| M2 输出与权限合同 | 完成 `write-tech-design` 的 AC 输出约束、`controlled-shell` 只读取证说明和 reviewer 权限矩阵 | 16h | 每个 AC 的落点/观察/可达性有生成约束，reviewer 只读权限最小化 |
| M3 Pipeline 传参 | 更新 architecture/code 两条 Pipeline 的 reviewer 资源传递，保持节点与 reviewLoop 不变 | 6h | `workspace`、`resources`、反馈、轮次来源明确且结构未漂移 |
| M4 结构回归与验证 | 扩展 Pipeline 结构测试，执行 prompt lint、矩阵检查、JSON 解析及相关回归测试 | 10h | 所有检查通过，变更文件仅在批准范围内 |

预计总工时：48h（约 6 人天）。TASK-01 与 TASK-02 可并行；TASK-03 至 TASK-06 按接口和权限依赖推进；TASK-07 在全部实现任务完成后执行。

# 2. 任务依赖图

```text
TASK-01 review-tech-design ──┐
                              ├──> TASK-03 SDD 输出约束 ──┐
TASK-02 review-dev-plan ──────┘                            │
                              └──> TASK-04 只读取证 ──> TASK-05 权限矩阵 ──┤
                                                                          ├──> TASK-06 Pipeline 传参 ──> TASK-07 结构回归与验证
```

具体依赖：

- TASK-01：强化技术设计评审输入、AC 闭环、既有依赖核验和回修规则。
- TASK-02：强化开发计划评审的增量职责、TASK 新事实核验和 UPSTREAM 规则。
- TASK-03：补充 `write-tech-design` 的 AC 级输出合同。
- TASK-04：补充 `controlled-shell` 的两个 reviewer 只读取证调用边界。
- TASK-05：将 `controlled-shell` 加入 `quality-reviewer-agent.can-call`，依赖 TASK-04 的权限语义。
- TASK-06：更新两条 Pipeline 的 reviewer 传参，依赖 TASK-02、TASK-03、TASK-05 的输入合同。
- TASK-07：扩展结构测试并执行全部验证，依赖 TASK-01 至 TASK-06。

# 3. 资源与分工

| 角色 | 工作内容 | 预计工时 |
|---|---|---:|
| development owner | 修改 tools 的 Skill、Pipeline、权限声明和结构测试 | 40h |
| test owner | 执行结构、lint、矩阵、JSON 和相关 crctl 回归检查，整理结果 | 8h |
| 合计 | 仅使用现有 tools worktree 和 knowledge-base CR worktree | 48h |

实现时只使用 `crctl workspace inspect CR-2026-055` 返回的 operational workspace 与 resources。文档工作落在 knowledge-base CR worktree，tools 改动落在 sibling tools 的 CR worktree；不拼接 worktree 路径，不读取主工作区替代目标仓。

# 4. 风险与回滚策略

| 风险 | 预防与检查 | 回滚策略 |
|---|---|---|
| reviewer 输入缺少真实资源或读取错误仓库 | Pipeline 结构测试断言 resources 来源；Skill 明确禁止自行发现路径 | 回退对应 Skill/Pipeline 提交，不改状态账本 |
| SDD/plan 评审职责重叠或漏检 | 固定八维度、AC 闭环、TASK 新事实和 UPSTREAM 责任边界 | 回退对应 Skill 文档，保留既有评审合同 |
| reviewer 权限扩大 | 检查 matrix、controlled-shell 文档和 rules.json 未改动 | 回退权限声明，不修改白名单 |
| Pipeline reviewLoop 漂移 | 固定节点数、顺序、replayNodes、UPSTREAM 和 maxAttempts=3 断言 | 回退 Pipeline 文本变更 |
| 结构检查失败或超出 8 个文件 | `git diff --check`、变更清单、lint/matrix/test/JSON 检查 | 普通 Git 修复/回退，禁止手工改 CR 状态 |

# 5. 验收与发布策略

发布前 checklist：

- [ ] tools 变更仅涉及 SDD 批准的 8 个文件。
- [ ] `review-tech-design`、`review-dev-plan` 输入合同与 SDD 一致。
- [ ] 每个 AC 有设计落点、可观测结果和可达性说明。
- [ ] SDD 既有实现依赖可列出并按 resources 核验，纯绿地才记录 N/A。
- [ ] 两条 Pipeline 原样传递 workspace/resources/feedback/attempt，节点和 reviewLoop 不变。
- [ ] reviewer 仅获得 controlled-shell 只读取证能力，不获得写操作、状态或账本权限。
- [ ] 运行以下检查并记录结果：

```text
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
node -e "const fs=require('fs'); for (const f of ['architecture-design.pipeline.json','code-implementation.pipeline.json']) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8')); console.log('json ok')"
```

相关回归测试以实际 tools worktree 文件为准，至少包括 `skills/shared/crctl/scripts/test/lint-prompts.test.mjs`、`skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs` 和 `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`。通过后由既有 code-implementation pipeline 继续人工开发启动审批，不新增发布开关或运行时服务。
