---
id: CR-2026-050-plan
type: PLAN
cr-ref: CR-2026-050
sdd-ref: "change-requests/CR-2026-050/sdd.md"
target-version: tbd
status: draft
created: 2026-08-21T11:57:27+08:00
updated: 2026-08-21T11:57:27+08:00
---

# 1. 交付里程碑

按 PRD AC-14 与 SDD §4.4 的两阶段 gate 划分；阶段二内部按 PRD §18.2 的 pipeline 顺序推进。

| 里程碑 | 内容 | TASK | 估算 |
|---|---|---|---|
| M1 阶段一：正确性门 | P0 输入契约与受保护路径修复 + 四个 approve 节点收敛 + 阶段 gate | TASK-01 ~ TASK-06 | 21h（约 3 人天） |
| M2 阶段二：CR Pipeline 职责收敛 | architecture → requirement-authoring → code-implementation → resume-cr → feature-writeback | TASK-07 ~ TASK-12 | 24h（约 3 人天） |
| M3 规划类下沉与全量自检 | 三条规划 Pipeline 章节/路径下沉 + FR-13 全量自检 | TASK-13 ~ TASK-14 | 5h（约 1 人天） |

估算总工时：**50h（约 6~7 人天，单开发）**。

**阶段 gate（AC-14）**：M1 完成判定 = TASK-06 完成标志全绿（三条自检命令 + 阶段一断言清单）后，才允许开始 TASK-07。

# 2. 任务依赖图

```text
TASK-01 (FR-01 三条 human approval 修复)
   │
TASK-02 (FR-05 approve 节点收敛 + approve-* SKILL --approver)
   │
TASK-03 (FR-02 product-planning)  TASK-04 (FR-03 market-to-plan)  TASK-05 (FR-04 competitive-radar)
   │                                │                              │
   └──────────────┬─────────────────┴──────────────┬───────────────┘
                  ▼                                 │
TASK-06 (阶段一 gate：自检 + 断言清单) ◄─────────────┘
   │
   ├──▶ TASK-07 (architecture JSON 收敛 + multica 再生 + CUSTOM.md) ──▶ TASK-08 (write/review-tech-design SKILL)
   ├──▶ TASK-09 (requirement-authoring 收敛 + 顺序断言)         （TASK-08 依赖 TASK-06/07）
   ├──▶ TASK-10 (code-implementation 收敛 + 顺序/ replayNodes 断言)
   ├──▶ TASK-11 (resume-cr + cr-show SKILL)
   ├──▶ TASK-12 (feature-writeback node-1)
   │
   └──▶ TASK-13 (规划类 FR-09 下沉；依赖 TASK-03/04/05 同文件顺序)
             │
             ▼
          TASK-14 (FR-13 全量自检 + DD-7 提交前缀扫描；依赖 TASK-07~13)
```

- 同一 pipeline JSON 被多个 TASK 修改时（requirement-authoring：01/02/09；architecture：01/02/07；code：01/02/10；规划类：03/04/05/13），依赖按「先正确性、后收敛」顺序声明，**单开发者顺序执行，不做并行编辑**。
- TASK-07 与 multica 再生同批闭环（SDD §4.2 实施顺序约束）。

# 3. 资源与分工

| 角色 | 人员 | 范围 |
|---|---|---|
| 开发 | Ray | 全部 TASK |
| 测试 | Ray | TASK-06/TASK-14 的自检与断言验证 |
| 需求 | Ray | AC-05 改判口径确认、回写期 PRD revision（SDD §3.4 偏离） |

# 4. 风险与回滚策略

| 风险 | 缓解与回滚 |
|---|---|
| 过度删除真实业务判断（PRD R-01） | 每节点保留五要素；负向断言只针对 SDD §3.1 明确列出的反模式；误删发现即在该 TASK 内恢复原文 |
| 与既有断言冲突（BLK-2） | 严格按 SDD §5 DD-4 处置清单执行；任何为通过测试而回退 CR-2026-044/045 语义的改动一律拒绝 |
| multica registry 漂移（SDD §4.2） | pipeline 修改与 gate_nodes_gen.go 再生同批提交；再生后跑 `generate-gate-nodes.mjs --check` + `go test ./server/internal/governance/`；失败回滚同批 |
| 规划流程闭环破坏（PRD R-03） | competitive-radar 按 SDD §4.1 顺序验证：draft 不落盘、reportDraft 可消费、confirmed=true 落盘在前 |
| lint R1 新触发（SDD §3.1） | 收敛后的 prompt 不残留 deny 路径字面量；`lint-prompts.mjs` 每个阶段 gate 都跑 |
| 在跑 architecture run 命中 TEMPLATE_DIGEST_MISMATCH | 部署新 digest 前等待在跑 run 收敛，或回滚 digest；本 CR 不改该语义 |

# 5. 验收与发布策略

发布前 checklist（TASK-14 完成标志）：

1. tools 根目录：`node -e "…JSON.parse 8 条 pipeline…"`、`node skills/shared/crctl/scripts/lint-prompts.mjs`、`node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` 全绿；
2. multica：`node server/internal/governance/gen/generate-gate-nodes.mjs --check` 通过、`go test ./server/internal/governance/` 通过；
3. Skill 自检（SDD FR-13.5）：`skills/_index.yml` 与 `agent-skill-matrix.yml` 无漂移、写入型 Skill 有 validate-doc 等价校验、Git/shell 走 controlled-shell、CR 摘要统一 `crctl next`、无直接写受保护账本、CRLF/硬失败纪律；
4. 提交前缀扫描（DD-7）全绿。

无 feature-flag：本 CR 是 tools 方法论包与 multica 生成产物的文本契约变更，发布 = 双仓（tools + multica）merge；multica 侧仅 gate_nodes_gen.go（生成产物）+ CUSTOM.md（台账）。

# 6. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-21 | v0.1.0 | Ray | 初始计划：M1 正确性门 / M2 CR Pipeline 收敛 / M3 规划类下沉，14 TASK，50h |
