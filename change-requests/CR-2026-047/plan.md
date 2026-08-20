---
id: CR-2026-047-plan
type: PLAN
cr-ref: CR-2026-047
sdd-ref: "change-requests/CR-2026-047/sdd.md"
target-version: 0.21
status: draft
created: 2026-08-20T01:25:00+08:00
updated: 2026-08-20T02:18:49+08:00
---

# 开发计划 — CR-2026-047 P3 组织智能 CR-A

> 输入：`change-requests/CR-2026-047/sdd.md`（技术设计）与 `prd.md`（需求）。实现期步骤粒度遵循 `coding-discipline` §2（2-5 分钟切分，只在实现期生效）；本计划层只定义 TASK 粒度（1-3 天）与里程碑。

## 1. 交付里程碑

| 里程碑 | 内容 | TASK | 估算 |
|---|---|---|---|
| M1 配置与计分地基 | 配置声明 schema + 零依赖生成器 + 迁移 375–379 + 计分纯函数 | TASK-01/02/03 | 26h（≈3 人天） |
| M2 快照数据流水线 | 8 项指标 SQL、治理护栏 SQL、rollup 事务编排、scheduler job | TASK-04/05/06/07 | 56h（≈7 人天） |
| M3 成熟度读 API | 6 个 maturity GET API + core schema/client | TASK-08 | 16h（≈2 人天） |
| M4 Org Admin 与周报闭环 | system key 幂等初始化 + 内置周报 skill + 既有 Autopilot schedule + envelope 回传 | TASK-10 | 20h（≈2.5 人天） |
| M5 看板与质量收口 | 三件式看板 + 建议最新/历史/追问入口 + 全量测试矩阵 + CUSTOM.md | TASK-09/11 | 32h（≈4 人天） |

**估算总工时：150h（≈19 人天）**。M1/M2 为数据发布阻塞路径；M3 依赖 M2 的 snapshot 写语义；M4 依赖 M3 API；M5 的前端依赖 M3/M4，测试矩阵对 M1–M4 交叉收口。

## 2. 任务依赖图

```text
TASK-01 ─┬─> TASK-03 ─────────────────────────────┐
         └─> TASK-04 ─> TASK-05 ──────────────────┤
TASK-02 ──────────────────────────────────────────┼─> TASK-06 rollup ─> TASK-07 scheduler
TASK-01/02/06 ─> TASK-08 读 API ─> TASK-10 周报 ─┐
TASK-08 ─────────────────────────────────────────┼─> TASK-09 看板 + 建议历史/追问
TASK-01..10 ─────────────────────────────────────┴─> TASK-11 测试 + CUSTOM.md
```

- 01/02 可并行；03 与 04 在 01 完成后并行；05 必须等 01+04（与 TASK-04 顺序追加同一 `maturity.sql`）；06 等 01–05 全部完成。
- 07 依赖 06 的 `service.RollupMaturitySnapshot`；08 依赖 01/02/06；10 依赖 02/05/08；09 同时依赖 08 的读 API 与 10 的 Org Admin 初始化 client；11 等 01–10。
- 关键路径：01 → 04 → 05 → 06 → 08 → 10 → 09；07 在 06 后与 08 分支并行。
- 每条边同时是接口契约依赖：消费方引用产出方在 TASK 卡中声明的精确签名。

## 3. 资源与分工

| 角色 | 工时 | 说明 |
|---|---|---|
| 后端（multica Go/sqlc） | 88h | TASK-01/02/03/04/05/06/07/08 |
| 前端（packages/views + core） | 26h | TASK-08 的 core schema/client + TASK-09 |
| 服务集成（Org Admin/周报/测试） | 36h | TASK-10、TASK-11 |

按当前团队配置 1–2 人并行，预计日历时间 10–12 个工作日；M1 起即可与 M5 的迁移/生成器测试并行推进。

## 4. 风险与回滚策略

| 风险 | 影响 | 缓解/回滚 |
|---|---|---|
| 迁移 375–379 在热库执行阻塞 dispatch | 全站任务派发中断 | 严格 CONCURRENTLY 单文件；上真实 PG up/down/up 预演；失败按 down 顺序 379→375 即时回滚 |
| 8 项公式与权威口径漂移 | 看板数字被质疑 | 每条 SQL 落 DB fixture 测试钉死口径；与 `docs/product/P3-组织智能设计.md` §4/§5 逐条对拍；config 变更走生成器 `--check` |
| `PlansForScope` 补偿 bug（丢 plan/搁浅 FAILED） | 快照缺日 | hook 单测钉死 retry-eligible 合并与 7 日 oldest-first；`MAX(bucket_date)` no-op 水位可安全重跑；不进 handler 二次扩窗 |
| 观察期数据不足（<21 天样本） | 基线建议不可用 | P10/P75 显式 unavailable/degenerate，不写 config；第 4 周报告说明样本缺口 |
| daemon local_directory 未绑定 | 周报无法生成 | UI 显式 unavailable + 绑定入口；schedule enqueue 校验绑定，缺失即 skip 并在 `sys_cron_executions.result` 记原因 |
| 用户隐私越界（个人榜泄漏） | 合规风险 | user 趋势 self-only、rankings 仅 project 且服务端 400；契约测试断言响应不含他人 ID；无任何 user ranking 开关 |
| 治理指标通道未交付（CR-C） | trace 卡无数据 | 显式 `unavailable` 文案“数据通道待 CR-C”，绝不显示 0；不影响总分 |
| CR owner 身份不可验证 | 项目协作规模可能失真 | 不做名称匹配/UUID 强转；受影响 org/project scope 的指标写 `unavailable`，scores 为空，样本跳过基线；身份桥另立 CR |
| 成本双算/错标 | 看板成本误导 | `cost_usd_ticks` 权威优先，价目只估算 NULL 行；cost_status 四态契约测试 |

回滚总原则：任何单里程碑失败，按 TASK 粒度 revert 对应 commit；snapshot 是纯投影可重建，错误口径行不允许 UPDATE 修改，一律以新 `config_rev` 新行或整表重建兜底。

## 5. 验收与发布策略

发布前 checklist（全部通过才允许 `approve-code`）：

1. 迁移真实 PG up/down/up + EXPLAIN 命中 378/379，migration lint 零错。
2. `generate-config.mjs --check` 一致为 0；生成文件头 SHA 与 knowledge-base HEAD 一致。
3. fixed-clock scheduler 测试全绿（首次/停机/超窗/FAILED 重试/00:30→前一日）。
4. 8 项 + 治理 DB fixtures 全绿；AC-1~AC-22 无未映射。
5. API：401/403/400（user scope、非 self 趋势、invalid range）、空态 200、观察期 total=null。
6. UI：观察期无雷达图、数量与治理同屏、无个人入口、cost_status 四态渲染。
7. E3：周报 4/4、同周 report_key 幂等、文件不进 git；建议最新/历史按 ISO week 渲染，chat_session_id 可进入既有 Team Agent 连续追问。
8. multica `CUSTOM.md` 逐项登记（新 migration/生成器/scheduler/handler/service/内置 skill/前端组件），双周 rebase 前可对照。

feature-flag 计划：不引入运行时 flag——CR-A 全部为新增只读看板与新增内部 job，回滚粒度=TASK 级 revert；`maturity-config.yaml` 初始 `calibration_status='observing'` 天然使计分关闭（scores={}），观察期即灰度期。周报 Autopilot 以“未绑定 local_directory 不产生任务”为事实开关。
