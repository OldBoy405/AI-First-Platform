# Phase 2 上下文：2026-11-25-upstream-sync-22f8c793

## 阶段结果

- Gate 2 已通过（dialog，证据原文「确认」），Phase 2 文档锁定；执行模式 `full_auto` 已登记（用户原文：继续 change，长程模式）。
- 上游窗口冻结：FORK=2e50b638f2，UPSTREAM=22f8c793b1，BASE=17b68cef4f；2434 上游提交 / 5879 上游路径 / 527 fork 路径 / 67 双边路径（均已实测）。
- 锚定检查：`stdd ci check-failures` 的 (l) 项 L2 >= L2 通过；TC-ID 唯一性与覆盖义务声明通过。

## 关键决策（BUILD 必须遵守）

1. 独立 worktree `gbrain-sync-2026-11-25-22f8c793` + 分支 `sync/upstream-2026-11-25-22f8c793` + 回滚锚 `pre-sync/2026-11-25-2e50b638f2`；主工作区不动。
2. `git merge --no-ff --no-commit 22f8c793b1`，先真源后生成物；67 双边路径按 CUSTOM.md A–F 类别逐行裁决并汇总台账。
3. fork 迁移 v298-inbox-workflow-frontmatter → v337（SQL payload 字节不变）；registry/latest 由生成器重建；旧库缺失上游 v298 attest_read DDL 只登记不补偿。
4. 生成物：regen:all → check:regen-all → 二次无漂移；build:admin 整组暂存后 check:admin-embedded；admin/bun.lock 在 admin/ 重算。
5. 验证：typecheck + 定向批次 + Admin 套件 + PGLite E2E；Windows 全量 `bun run test` 不冒充通过；未跑项如实登记。
6. Gate 3 前不提交、不推送、不部署、不迁移生产 brain。

## 用户关注点

- 长程模式连续执行，避免重复校验与无意义兜底；Gate 3 仍强制等待确认。
- 迁移撞号与旧库偏差必须如实登记，不做未授权补偿。
- 交付动作（提交/合入/推送/部署/生产迁移）各自单独授权。

## 产出物

- `design.md`（9 决策）
- `canonical/specs/code/upstream-sync-merge.yaml`（8 REQ / 8 SC）
- `canonical/specs/agent/upstream-sync-verification.yaml`（6 CP）
- `test-plan.md`（8 TC + stdd-evidence-plan-v1）
- `specs/upstream-sync-merge/spec.md`（Gate 2 自动生成）
