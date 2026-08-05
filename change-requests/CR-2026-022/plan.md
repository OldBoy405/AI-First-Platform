---
id: CR-2026-022-plan
type: PLAN
cr-ref: CR-2026-022
sdd-ref: "change-requests/CR-2026-022/sdd.md"
target-version: tbd
status: draft
created: "2026-08-06T08:30:00+08:00"
updated: "2026-08-06T08:30:00+08:00"
---

# PLAN — tools 包 prompt 审查修复（97 条发现全量落地）

## 1. 交付里程碑

| 里程碑 | 批次 | TASK | 内容 | 估算 |
|---|---|---|---|---|
| M1 机械修正与死内容清理 | 批 1 + 批 2 | TASK-01~02 | 12 处命令串、豁免注释外移、死引用、cr-status-set 下线、validate-doc/focus-briefing 订正、pending 清空、record-adr 下线 | 12h |
| M2 crctl 核心能力补齐 | 批 2.5 | TASK-03~08 | cr-init 旗标、--cr 直传、checkpoint-add LEGAL 派生、approve decline 回退（含状态机两条新转换）、gates.json 死配置、STALE_BASE 降级 | 26h |
| M3 功能正确性修复 | 批 3 | TASK-09~14 | inbox-emit 对齐、HEAD 校验、UUID 迁移、market-insights 统一、owner-set 改调、cmdNext/cr-show、planning 域歧义 | 30h |
| M4 lint 护栏 | 批 3.5 | TASK-15 | R6/R7 + 豁免范围修复 + 测试向量 | 8h |
| M5 冗余收敛 | 批 4 | TASK-16~18 | approve-* 对齐、writeback 抽 shared、sync 收敛、样板抽取、评估项下线 | 20h |
| M6 收尾验收 | 收尾 | TASK-19 | 三台账、check-skill-matrix、JSON 自检、crctl.test.mjs 全量回归、口径 25/47 核查、端到端验收 | 10h |

估算总工时：约 106h（约 13 人天）。

## 2. 任务依赖图

```
TASK-01 ── TASK-02 ── TASK-15 ── TASK-16 ── TASK-19
   │          │          │          │
TASK-03 ── TASK-05 ── TASK-17 ──────┘
TASK-04 ── TASK-06 ── TASK-18
   │        │
TASK-07 ── TASK-08 ── TASK-09 ── TASK-10 ── TASK-11 ── TASK-12 ── TASK-13 ── TASK-14
```

关键链：M2（批 2.5）与 M3（批 3）互相独立可并行；TASK-15（批 3.5）必须先于 TASK-16~18（批 4）；TASK-17 的 push-progress 样板抽取以 TASK-05（FR-11）为前提；TASK-19 收尾依赖全部。

## 3. 资源与分工

- 开发：Ray（全部 TASK，tools 仓单仓作业）
- 测试：Ray（TASK-19 回归 + 各 TASK 验收）
- 评审：Ray（人工审批节点）

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| 批 2.5 改 crctl 核心写入路径 | NFR-5 灰度（先演练注册走通三条新路径）；crctl.test.mjs 全量回归 | 每子项单 commit 可独立 revert |
| 状态机新增两转移（25/47 口径）引发断言失效 | TASK-06 同步更新口径引用 + TASK-19 全仓 grep 核查 | 删除两条转移声明 revert |
| lint R6/R7 落地后误报阻塞提交 | 测试向量先行（TASK-15），全仓复扫清零后再合入 | revert 规则 commit |
| market-insights 迁移破坏历史数据 | 入库版本化脚本 + fixture 测试，原子提交 | revert 迁移 commit |
| UUID 迁移破坏 seed 幂等 | JSON 解析自检 + 两条流水线 seed 幂等验证 | revert UUID 值重新分配前缀 |

## 5. 验收与发布策略

- 验收：AC-1~AC-20 逐条对照；TASK 级验收条件见各 TASK 文件
- 发布：全部改动落在 tools 仓 `requirement/CR-2026-022` 分支，回写期按 writeback 流程合入 trunk
- 前置：lint-prompts enforce 全程零违例（pre-commit 钩子）；批 2.5 灰度演练通过
