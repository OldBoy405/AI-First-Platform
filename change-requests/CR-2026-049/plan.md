---
id: CR-2026-049-plan
type: PLAN
cr-ref: CR-2026-049
sdd-ref: "change-requests/CR-2026-049/sdd.md"
target-version: 0.23
status: draft
created: 2026-08-20T20:59:46+08:00
updated: 2026-08-20T20:59:46+08:00
---

# 开发计划 — P3 组织智能 CR-C：跨 CR 追溯与漂移检测

> 输入：`change-requests/CR-2026-049/sdd.md`（第 2 轮评审通过版）。本计划与任务拆分严格以 SDD §0 回修摘要、§2 迁移清单、§3 契约与 §7.2 AC 测试矩阵为界；不扩散范围。步骤粒度约束引用 `coding-discipline` §2，仅在实现期生效。

## 1. 交付里程碑

| 里程碑 | 内容 | 对应 TASK | 估算 |
|---|---|---|---|
| M1 tools E4 深原语 | trace 语义对象/候选 manifest、journal intent、archive pending 门 | TASK-01~03 | 30h / 3.75 人天 |
| M2 multica schema/ledger | drift_finding 与 workspace 迁移、trace 入账事务 | TASK-04~06 | 34h / 4.25 人天 |
| M3 trace 读侧 | spec 时间线 / spec-search API | TASK-07 | 12h / 1.5 人天 |
| M4 E5 声明与仓库访问 | dir-graph 声明 + 生成器、repo binding resolver | TASK-08~09 | 18h / 2.25 人天 |
| M5 扫描与 drift 面 | 扫描 job、drift API、前端 | TASK-10~12 | 42h / 5.25 人天 |
| M6 收尾与集成 | CUSTOM.md 台账、AC 集成测试、静态契约 | TASK-13 | 8h / 1 人天 |

估算总工时：**144h（18 人天）**，单人（Ray）串行执行。上表里程碑小时合计 144h、天数合计 18 人天；E4 与 E5 的代码面在 M2/M4 可部分并行，但 M6 集成前不宣告任一交付物完成。

## 2. 任务依赖图

```text
TASK-01 → TASK-02 → TASK-03                              （tools：语义→journal→archive 门）
TASK-04 ─┐
TASK-05 ─┴→ TASK-06 → TASK-07 ───────────────┐
TASK-08 → TASK-09 → TASK-10 → TASK-11 ───────┼──→ TASK-12
                                             └──→ TASK-13（等待 TASK-01..12 全部完成）
```

- TASK-04/TASK-05 互不依赖，可并行；TASK-06 显式等待二者完成，保证 schema/ledger 契约在 trace 入账前同时可用。
- TASK-08 的 knowledge-base 声明与 TASK-01/02 无代码依赖，但 M4 必须在 M1 之后开始（避免 tools 深原语与声明同时变动时的交叉验证噪声）。
- TASK-13 的 `depends-on` 显式列出 TASK-01..12，只有全部代码面、API 与前端完成后才能执行跨仓联调与台账收口。

## 3. 资源与分工

| 角色 | 承担 |
|---|---|
| 开发（Ray） | 全部 TASK，串行为主，TASK-04/05 可并行 |
| 评审（ai-reviewer + 人工） | review-dev-plan / approve-dev-start（本 CR 之外） |
| 环境 | multica 单实例（迁移按 SDD §2.5 维护窗口执行）；daemon 至少一个用于 trace 端到端 |

## 4. 风险与回滚策略

| 风险 | 影响 | 应对 / 回滚 |
|---|---|---|
| 迁移 390 回填不确定 | 旧事件无法租户隔离，启动阻塞 | preflight 断言失败即停，不启动新代码；旧版本+旧约束保持可用（旧约束删除在后） |
| `yaml-subset` 加固破坏既有解析 | 已归档 CR 的受控账本解析回归 | TASK-01 用 191KB 累积 traceability 与既有全量测试做 fixture；解析失败硬失败，禁止静默降级 |
| GitHub 限流 / trunk 历史重写 | 扫描 FAILED 或游标错位 | 固定 HEAD=B、分页到精确 A，任何异常不推进 cursor；FAILED 在治理板块可见，不伪装零 finding |
| trace pending 在归档前未补发 | 追溯事件永久丢失 | archive 前置门硬阻断 + 保留现场；重跑同一 archive 恢复 |
| 单次 >10k 新提交 | fail-safe | 人工确认后重建 baseline；运维步骤写入 runbook |
| 前端未知 enum | 页面崩溃 | 所有新响应 Zod + `parseWithFallback`，未知 enum 显示 `unknown` fallback |

回滚整体策略：M2 迁移在维护窗口执行，窗口内任一失败即中止（旧约束未删、旧 server 可继续）；代码发布与迁移同窗口。E4/E5 无数据删除语义，finding 与 trace 均为新增数据，回滚不影响 CR 权威（git）。

## 5. 验收与发布策略

发布前 checklist（对应 SDD §7.2 测试矩阵）：

1. AC-1~AC-15 分层测试全部通过（tools fault/golden、PG migration/governance、fake GitHub scheduler、handler CAS、core fallback、shared views）。
2. 跨语言 golden：Go `yaml.v3` 与 Node 事件 payload 对同一 traceability 深比较一致。
3. 迁移 386/388/389/391/392/393/396 通过 concurrent-index cleanup registry 测试。
4. PRD 成功指标复核：trace 落库率 100%、误报 0、24h 重复 finding 0、跨 workspace 泄漏 0。
5. 发布顺序：knowledge-base 声明（remote/commit_prefixes）→ tools 深原语 → multica 迁移/job/API → 前端。`commit_prefix_scan` 首轮只建 baseline，治理板块在未初始化/异常状态下显示正确。
6. 无需 feature-flag：读侧为新增面；`not_configured/uninitialized` 健康态覆盖部署前空窗。
