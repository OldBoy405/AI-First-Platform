# BUILD 实现任务清单

> change: 2026-11-25-upstream-sync-22f8c793 · 长程模式（full_auto）

## Slice 1 — 隔离候选与冻结证据（TC-USM-001）

- [x] 新建 worktree `gbrain-sync-2026-11-25-22f8c793` + 分支 `sync/upstream-2026-11-25-22f8c793`（从 FORK 2e50b638f2）
- [x] 回滚锚 `pre-sync/2026-11-25-2e50b638f2` → FORK
- [x] 冻结证据：BASE=17b68cef4f、62/2434、UPSTREAM VERSION=0.60.772.0、无 MERGE_HEAD、主工作区未动
- [x] 依赖：junction 复用主仓 node_modules / admin/node_modules
- [x] 验证 helper（freeze 动作）+ 自测
- [x] 执行 CP-USM-001（`stdd agent verify` 或 helper 直跑）并登记 Slice 1

## Slice 2 — 三方合并与行为裁决（TC-USM-002/003）

- [x] `git merge --no-ff --no-commit 22f8c793b1`
- [x] 冲突清单与解决（真源 → 测试 → 手写门禁 TSV → 生成物）
- [x] 67 双边路径裁决表（A–F 分类）写入台账草稿
- [x] 527 fork 增量归因核对；上游删除/改名去向说明
- [x] 三项门禁 TSV 与技能路由贴合上游新增项
- [x] CP-USM-002 证据

## Slice 3 — 迁移顺延（TC-USM-005）

- [x] `git mv v298-inbox-workflow-frontmatter.ts v337-...`，改导出/版本/注释，SQL payload 不变
- [x] 重建 registry/latest（build:schema-migrations / regen:all）
- [x] 基线 TSV、迁移金标准、台账 #5 同步
- [x] 顺序检查（base=22f8c793b1）、registry 测试、空库双跑探针
- [x] 旧库偏差登记；CP-USM-003 证据

## Slice 4 — 生成物重建（TC-USM-006）

- [x] regen:all → check:regen-all → 二次 regen 无漂移
- [x] build:admin → 整组暂存 → check:admin-embedded
- [x] admin/bun.lock 重算 + frozen 复验
- [x] VERSION=0.60.772.0 与版本门禁；CP-USM-004 证据

## Slice 5 — 质量验证（TC-USM-004/007）

- [x] typecheck、定向批次（Inbox/Admin guard/trace/来源隔离/op 合同/合同金标准）
- [x] Admin 套件、PGLite E2E；失败对照基线 A/B
- [x] 上游 5879 路径覆盖核对（人工）
- [x] 未跑项登记；CP-USM-005 证据

## Slice 6 — 审计与台账（TC-USM-008）

- [x] 双父 diff 审计、`git ls-files -u`、whitespace 检查
- [x] CUSTOM-LEDGER 本轮记录与 #N 更新
- [x] 交付边界确认（未提交/未推送/未部署）
- [x] CP-USM-006 证据；test-report.md
