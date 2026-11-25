# BUILD 任务清单

## 1. 隔离候选与三方合并（P0）

- [x] 1.1 核对冻结 SHA、回滚标签、提交计数、VERSION 与主工作区未改变（TC-USM-001）。
- [x] 1.2 从 FORK 创建独立 worktree/分支，执行 `merge --no-ff --no-commit`，禁止提交（TC-USM-001）。
- [x] 1.3 逐路径归因 516 个 fork 改动，确认仍保留项均有台账或生成物真源（TC-USM-002）。
- [x] 1.4 裁决 6 个双边路径，保留 fork 例外与路由并吸收上游新增门禁（TC-USM-003）。
- [x] 1.5 运行合并切片的定向检查并登记实际新增测试数。

## 2. 上游行为、迁移与生成物（P0）

- [x] 2.1 验证恢复文件、保留已提交文件、purge、world-row/repair 行为（TC-USM-004）。
- [x] 2.2 以冻结 UPSTREAM 为 base ref 验证迁移顺序、registry、v297/v298 和无新增迁移（TC-USM-005）。
- [x] 2.3 从真源重建生成物，运行 freshness 与二次无漂移检查（TC-USM-006）。
- [x] 2.4 保存完整命令、退出码、耗时、skip/timeout 和定向用例证据。

## 3. Inbox managed 内容最小修复（P0）

- [x] 3.1 增补 managed/unmanaged 实际落库与 auto-link 守卫测试并确认 RED（TC-FCB-001）。
- [x] 3.2 让 managed 分支消费预处理后的 content，保留 provenance/source 快照/权限守卫。
- [x] 3.3 运行 Inbox 定向与相关回归，确认 GREEN。

## 4. Admin 鉴权与审计合同（P0）

- [x] 4.1 增补无会话拒绝、合法分派、恰好一条独立审计测试并确认 RED 或识别已有等价覆盖（TC-FCB-002）。
- [x] 4.2 仅在发现缺口时做最小修复，保持 requireAdmin 优先与 remote=true。
- [x] 4.3 运行 Admin route guard 与 embed-spawn 回归。

## 5. query.trace 完整诊断链（P0）

- [x] 5.1 增补 trace 开/关/空结果/page cap、MCP、CLI 与 Admin `_meta` 测试并确认 RED（TC-FCB-003）。
- [x] 5.2 在 `trace.retrieval` 保留 op 实际 emit 的完整对象，保持 MCP `_meta.retrieval` 独立。
- [x] 5.3 Admin client 保留 ToolResult `_meta`，Ask 合并入可见 trace，不改变默认结果形状。
- [x] 5.4 运行根定向、CLI 合同和 Admin 测试：合并面批次 224/225，路径归一化修复后 1/1，serial 8/8，Admin 229/229。全量 `bun run test` 因 Windows runner 基线未完成，不能记为全量通过。

## 6. Graph 可见性与双引擎 parity（移出本次范围）

- 该缺口位于本次上游窗口未改动的 FORK 文件，属于既有问题，不在“拉取上游更新”合并范围；未实现、未登记。

## 7. 其余 fork 能力回归（P1）

- [ ] 7.1 运行 AI、Truth、Jobs、op/manifest/parity、skills、doctor、llms 定向回归（TC-FCB-005）。本次仅覆盖合并面变更文件与 Slice 2-5 既有定向证据，未声称全量覆盖。
- [x] 7.2 运行 Admin 全套测试：28 文件 / 229 用例通过，0 fail。
- [x] 7.3 合并面批次无新增产品回归；唯一失败为 Windows 反斜杠路径误判，已在测试侧归一化并复跑通过。

## 8. 综合复核、质量门禁与最终审计（P0）

- [x] 8.1 对照 L2 与台账复核 Inbox/Admin/trace，分别归因基线缺口和 merge 变化（TC-USM-007）；Graph 按用户指令移出范围，未实现、未登记。
- [ ] 8.2 在候选树运行 typecheck、根定向、Admin 测试和所需 E2E；typecheck/根定向/Admin 已有信号，全量根单测与 Postgres E2E 受 Windows/数据库基线限制，未声称通过（TC-USM-008）。
- [x] 8.3 回填台账（候选树 `CUSTOM-LEDGER.md` 已暂存 2026-11-24 记录），执行无冲突、whitespace 双亲基线、分父 diff 和交付边界审计（TC-USM-009）；final audit `20261125T072507Z` 通过。
- [x] 8.4 完成 C1-C7、生成 test-report/design-adjustments 并确认 Gate 3（run `20261125T084500Z`，evidence “确认”）；未提交、未推送、未合入 master。
