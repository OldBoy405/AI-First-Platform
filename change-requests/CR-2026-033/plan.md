---
id: CR-2026-033-plan
type: PLAN
cr-ref: CR-2026-033
sdd-ref: "change-requests/CR-2026-033/sdd.md"
target-version: tbd
status: draft
created: 2026-08-13T19:06:07+08:00
updated: 2026-08-13T19:17:50+08:00
---

# 开发计划 — CR-2026-033 tools Checkpoint 收敛

## 1. 交付里程碑

| 里程碑 | 内容 | 对应 SDD | 估算 | 交付物 |
|---|---|---|---|---|
| M1 契约与红测（T01） | 冻结 checkpoint schema、错误码（§3.5）、fault points（§2.4）；新增旧实现下预期失败的契约测试；253+10 基线保持绿 | §2.3/§2.4/§3.5/§10.1.1 | 1 人天 | durable-tx 契约 + checkpoint 红测 |
| M2 深原语底座（T03） | durable-tx checkpoint envelope；`matchEntryBlock` 下沉 yaml-subset；`editLatestCheckpoint`/`checkpointBatchId`/`classifyCheckpointRemote` 纯函数与单测 | §1.4/§2.2/§3.2 | 2.75 人天 | 三纯函数 + editor + 单测 |
| M3 事务与 CLI（T04） | `checkpointCr` 多仓 publish/recover；`cmdCheckpoint` dispatch/help/audit/outbox；三 bare remote 集成测试矩阵 | §3.1/§3.4/§4/§9.2 | 3 人天 | checkpoint 命令可用，旧 caller 未切 |
| M4 迁移与删除（T05） | 4 个 Skill、4 个 Pipeline 文件（6 节点）、README/index/ARCHITECTURE 迁移；删除 checkpoint-add 及旧测试/文案；全量回归 | §8/§10.1.4 | 2 人天 | 单一命令面，无 checkpoint-add 残留 |

**估算总工时：70h（约 8.75 人天）**

## 2. 任务依赖图

```text
TASK-01 契约冻结与红测（T01）
   │
   ▼
TASK-02 durable checkpoint envelope + matchEntryBlock 下沉（T03a）
   │
   ▼
TASK-03 latest-checkpoint editor 与三个纯函数（T03b）
   │
   ▼
TASK-04 checkpointCr 事务 + cmdCheckpoint CLI + 集成测试（T04）
   │
   ▼
TASK-05 Skill/Pipeline/README/ARCHITECTURE 迁移与 checkpoint-add 删除（T05）
```

依赖规则：

- 全部线性推进：T03 纯函数依赖 T02 的 journal envelope 与条目定位器；T04 依赖 T03 的纯函数；T05 只能在 T04 命令可运行后同提交切换 caller/reader 并删除旧入口（SDD §10.2）。
- M2 内部 T03a→T03b 顺序提交，各自可回滚。

## 3. 资源与分工

| 角色 | 承担 | 工时 |
|---|---|---|
| 开发（Ray） | TASK-01～05 全部实施（单人顺序推进） | 70h |
| 测试（Ray） | TASK-01 红测、TASK-04 集成矩阵、TASK-05 静态扫描与回归 | 计入各 TASK |
| 人工审批 | approve-dev-start / approve-code / 合并确认 | 评审窗口期 |

## 4. 风险与回滚策略

| 风险 | 控制 | 回滚 |
|---|---|---|
| remote 在 preflight 与 push 间前进 | 精确 lease + push 后再次 fetch 确认（SDD §4.4） | 不自动 revert；重跑继续完成 |
| metadata commit 自引用或空转 | snapshot KB source 固定为 metadata 直接父（SDD §4.5） | T03/T04 单独 revert 不影响旧 caller |
| 旧 complete journal 阻塞下一批 | authority 确认后清理；残留时先验证再清理（SDD §2.3） | 重跑同一 `crctl checkpoint`，由 handler 验证 metadata authority 后清理；禁止人工删除事务目录 |
| 迁移时 writer/reader 协议错位 | T05 同一提交切换 caller/reader 并删除旧入口（SDD §10.2） | T05 整提交 revert，不单侧恢复 |
| checkpoint outbox 丢失/重复 | metadata-confirmed 后按 cr+metadataCommit 确定性去重（SDD §3.4） | 事件丢失不影响 Git authority，接受 best-effort 投影 |
| `pull-progress` 读取已删除字段 | T05 仅改摘要为 metadata Git 事实，不改 ff-only 行为（SDD §8） | T05 revert 覆盖 |

## 5. 验收与发布策略

发布 checklist（全部满足才可提交 code 审批与 merge）：

1. 新增红测在旧实现下按预期红；253 crctl + 10 writeback 基线全绿，无放宽断言（PRD AC-10）。
2. 三 bare remote 矩阵 15 项全覆盖（SDD §9.2），Ubuntu/Windows CI 全绿。
3. `crctl checkpoint` 成功输出固定字段；help 无 `checkpoint status`（PRD AC-01）；敏感命中零 index/commit/push（AC-02）。
4. 首次成功后 `_backlog.yml` 无 `checkpoints[]`/`remote-ref`/`last-push-*`，batch-id 内容寻址（AC-03）；no-op 在 journal 前 `changed=false`（AC-04）。
5. 静态扫描证明 4 个 Pipeline 文件 6 节点无 Git 命令/账本字段（AC-07）、无 `checkpoint-add` 残留（AC-09）。
6. 发布顺序：tools 仓 `requirement/CR-2026-033` merge → knowledge-base 合并；无 feature flag（工具层单分支交付，PRD 未要求灰度）。

**估算总工时：70h**（与 `crctl task init` 的 `totalEstimateHours` 交叉校验）。
