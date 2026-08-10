---
id: CR-2026-028-plan
type: PLAN
cr-ref: CR-2026-028
sdd-ref: "change-requests/CR-2026-028/sdd.md"
target-version: tbd
status: draft
created: "2026-08-10T18:09:06+08:00"
updated: "2026-08-10T18:09:06+08:00"
---

# 开发计划 — CR-2026-028 tools 流程步骤优化 v2 前移优化项

## 1. 交付里程碑

| 里程碑 | 内容 | 涉及 FR | 估算 | 交付物 |
|---|---|---|---|---|
| M1 前置修复 | crctl `worktree-path` 嵌套路径 bug（linked worktree 下拼出 `<worktree>/.rayai-worktrees/...`） | FR-2（依赖项） | 0.5 人天 | crctl.mjs 修正 + 回归用例 |
| M2 resolver 与 loader 收敛 | `deriveInstallRoot` + `resolveToolsRoot` + 四 loader 改读 Tools Root；删除 `GATES_PATH`/默认 `RULES_PATH` 常量；`TOOLS_PACKAGE_NOT_FOUND` 错误契约 | FR-1/3/4 | 1.5 人天 | crctl.mjs 改动 |
| M3 双根与 worktree 定位 | `cmdWorktreePath` 以 InstWS 为根；`--workspace` 显式传入工具仓场景验证 | FR-2 | 1 人天 | crctl.mjs 改动 |
| M4 active 执行入口路径统一 | Skill/Pipeline/Adapter/AGENTS.md 白名单路径表达改 `{TOOLS_ROOT}`；七禁止模式零命中 | FR-5 | 1 人天 | 12 个文件批量修订 |
| M5 Registration 复用 | requirement-register 一次传齐 cr-init 元数据；删二次补 frontmatter | FR-6 | 0.5 人天 | SKILL.md + pipeline prompt |
| M6 清理与台账 | tools `dir-graph.yaml` 删 `target_install_path`；multica CUSTOM.md 核账 | FR-7/8 | 0.25 人天 | dir-graph.yaml；CUSTOM.md 已随注册提交 |
| M7 测试与回归 | fixture/表驱动/linked-worktree/四 sentinel/CRCTL_RULES_PATH/cr-init metadata 用例；全量回归 | FR-9 | 1 人天 | crctl.test.mjs 扩展 |
| M8 发布与联调 | tools 仓 merge → knowledge-base merge；真实 worktree 场景走查 | 全部 | 0.5 人天 | 双仓合并提交 |

**估算总工时：约 6.25 人天**

## 2. 任务依赖图

```text
M1 前置修复（worktree-path bug）
  │
  ▼
M2 resolver/loader 收敛 ──► M3 双根与 worktree 定位
  │                            │
  ▼                            ▼
M4 active 入口路径统一 ────► M5 Registration 复用
  │                            │
  ▼                            ▼
M6 清理与台账（可并行，随 M4 提交）──► M7 测试与回归
                                          │
                                          ▼
                                    M8 发布与联调
```

依赖规则：
- M2/M3 均依赖 M1（worktree-path 是 FR-2 修正的入口依赖，M1 先行可减少 M3 联调噪音）；
- M4 依赖 M2/M3 完成（路径统一以 resolver 语义为前提）；
- M5 依赖 M4（requirement-register SKILL 的 `{TOOLS_ROOT}` 表达与 pipeline 提示词同批修订）；
- M7 依赖 M2-M6 全部实施面（测试断言对准最终接口）；
- M8 依赖 M7 全绿。

## 3. 资源与分工

| 角色 | 承担 | 工时 |
|---|---|---|
| 开发（Ray） | M1-M7 全部实施（单文件 crctl.mjs + 提示词文件，单人顺序推进） | 5.75 人天 |
| 测试（Ray） | M7 测试编写与回归；M8 联调验证 | 计入 M7/M8 |
| 架构评审（Ray/人类） | 代码评审、开发启动审批、合并审批 | 评审窗口期 |

分工原则：crctl.mjs 改动集中在 tools 仓 worktree；提示词/文档改动在 knowledge-base worktree；两者均以 `--workspace <knowledge_base_worktree>` 显式驱动 crctl。无并行人手需求（改动面小、互相耦合），按依赖图串行。

## 4. 风险与回滚策略

| # | 风险 | 概率 | 影响 | 缓解 | 回滚 |
|---|---|---|---|---|---|
| R1 | linked worktree 场景 git common-dir 语义与预期不符（分离 git dir / 无 .git 目录） | 低 | M2/M3 解析基准错误 | `deriveInstallRoot` 失败即回退 OpWS；测试覆盖非 git 目录 | 单提交 revert M3 |
| R2 | 路径统一后残留 `tools/skills/` 旧引用，运行提示词漂移 | 中 | FR-5 采纳不完整 | 白名单 grep 验证七禁止模式零命中；lint-prompts 复查 | 单提交 revert M4 |
| R3 | `CRCTL_RULES_PATH` 覆盖语义在重构 loader 时被误删 | 低 | 自定义 rules 失效 | 测试显式断言覆盖优先（AC-7） | 单提交 revert M2 |
| R4 | 测试误触真实 tools checkout | 中 | 环境污染 | 全部 fixture 走临时目录；`makeToolsFixture()` 隔离 | 无（测试自清理） |
| R5 | multica 台账登记与实际代码不符 | 低 | rebase 核对遗漏 | M6 核账对照其当时实际结构（纪律 #10） | 修订 CUSTOM.md |
| R6 | 状态机/gates 来源切换后旧 checkout 调用 crctl 失败（无 dir-graph 声明） | 中 | 过渡期工具不可用 | 主 checkout 先更新 tools 子模块再切分支；发布顺序 tools 先行 | 保留旧 checkout 分支回退 |

**回滚总原则**：每个里程碑独立提交、独立可 revert；tools 仓与 knowledge-base 仓独立合并，互不阻塞；无数据迁移，回滚零成本。

## 5. 验收与发布策略

**发布前 checklist**：

- [ ] M1：linked worktree 下 `crctl worktree-path` 输出为 `<主checkout>/.rayai-worktrees/...`，无嵌套路径
- [ ] M2：四类 sentinel 证明状态机/Pipeline/gates/rules 均来自同一 Tools Root；执行脚本换 checkout 结果不变
- [ ] M3：`--workspace <knowledge_base_worktree>` 场景下 tools/multica worktree 的 InstWS 派生正确
- [ ] M4：七禁止模式在全部 active 文件零命中；`{TOOLS_ROOT}` 占位符统一
- [ ] M5：cr-init 一次写齐 summary/source/target-version（AC-11/AC-12）
- [ ] M6：tools `dir-graph.yaml` 无 `target_install_path`；CUSTOM.md 台账与注册提交一致
- [ ] M7：`crctl.test.mjs` 全量通过（含既有用例，无回归）
- [ ] 代码评审 pass + 开发启动人工审批 + 合并人工审批

**发布顺序**：

1. tools 仓 `requirement/CR-2026-028` merge → main（crctl 新语义生效）；
2. knowledge-base 仓 `requirement/CR-2026-028` merge → main（AGENTS.md/ADR/分析文档）；
3. multica 仓无代码改动，仅台账，随下个 rebase 周期核对。

**Feature-flag**：无。本 CR 为工具链内部行为修正，不引入产品功能开关；过渡风险由 R6 的发布顺序缓解（tools 先行，避免旧 checkout 在新 config 下失配）。
