---
id: CR-2026-053-plan
type: PLAN
cr-ref: CR-2026-053
sdd-ref: "change-requests/CR-2026-053/sdd.md"
target-version: tbd
status: draft
created: 2026-08-28T11:15:00+08:00
updated: 2026-08-28T11:15:00+08:00
---

# 开发计划 — CR-2026-053 独立评审与人工审批命令闭环

## 1. 交付里程碑

### 阶段划分

| 阶段 | 主要交付物 | 工时估算 |
|------|-----------|---------|
| **M1: Track A (tools 仓)** | matrix/agent/pipeline 改造 | 2 人天 |
| **M2: Track B (Multica 仓)** | 绑定接口 + 前端审批卡 | 3 人天 |
| **M3: 集成测试与验收** | 接口测试 + 人工审批卡可见性验证 | 1 人天 |
| **M4: 存量 CR 修复** | CR-2026-051/052 走同一接口修复 | 0.5 人天 |

**估算总工时**: 6.5 人天

### 关键路径

```
M1 (Track A tools 改造) 
    ↓
M2 (Track B multica 绑定接口 + 前端)
    ↓
M3 (集成测试 + 验收)
    ↓
M4 (存量 CR 修复)
```

## 2. 任务依赖图

```
Track A (tools 仓):
  CR-2026-053-TASK-01: 修改 agent-skill-matrix.yml (owner 归属调整)
  CR-2026-053-TASK-02: 修改 agents 文件 (requirement-writer/dev-agent 评审意图改委派)
  CR-2026-053-TASK-03: 修改 pipeline 节点 prompt (review-* 节点)
  CR-2026-053-TASK-04: 修改 review Skill 绑定前置步骤

Track B (Multica 仓):
  CR-2026-053-TASK-05: 新增绑定接口 POST /api/crs/{cr_id}/bind-current-task
  CR-2026-053-TASK-06: 修改 CreatePipelineTask SQL 继承 issue_id/project_id
  CR-2026-053-TASK-07: 前端审批卡可见性修复
  CR-2026-053-TASK-08: CLI 薄包装命令
  CR-2026-053-TASK-09: CUSTOM.md 台账登记

集成:
  CR-2026-053-TASK-10: 集成测试
  CR-2026-053-TASK-11: 存量 CR-2026-051/052 修复

**依赖关系**:
- CR-2026-053-TASK-01, CR-2026-053-TASK-02, CR-2026-053-TASK-03, CR-2026-053-TASK-04 可并行
- CR-2026-053-TASK-05, CR-2026-053-TASK-06, CR-2026-053-TASK-07, CR-2026-053-TASK-08 需在 M1 完成后开始，可并行
- CR-2026-053-TASK-10 依赖 M1+M2 完成
- CR-2026-053-TASK-11 依赖 M3 完成

## 3. 资源与分工

| 角色 | 负责 |
|------|------|
| dev-agent | 全流程开发 |
| quality-reviewer-agent | review-dev-plan 评审 |

## 4. 风险与回滚策略

| 风险 | 影响 | 回滚策略 |
|------|------|---------|
| 绑定接口事务失败导致 task 无法推进 | 高 | 检查 FOR UPDATE 锁顺序；测试 CAS 冲突场景 |
| review Skill 绑定失败静默降级 | 高 | 硬失败不降级，零绑定写入 |
| 存量 CR 修复遗漏 | 中 | 按 AC-D1~D6 验收清单执行 |
| 前端审批卡渲染异常 | 中 | 检查 pending_stage 非空分支逻辑 |

## 5. 验收与发布策略

### 发布前 Checklist

- [ ] tools 仓改造通过 `check-skill-matrix.mjs` 校验
- [ ] Multica 绑定接口通过 7 种错误场景测试
- [ ] 前端审批卡在 pending_stage 非空时正确渲染
- [ ] 存量 CR-2026-051/052 绑定验证通过
- [ ] `crctl approve` 人工审批流程闭环验证

### Feature Flag 策略

无 feature flag，本次为确定性功能修复，直接全量发布。
