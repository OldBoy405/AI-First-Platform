# 按二开合并规则同步上游 v0.60.638.0

<!-- source_hash: 1d17581f3c476d01 -->
<!-- generated_at: 2026-11-24T19:18:23.260759 -->
<!-- canonical: canonical/proposals/2026-11-24-upstream-sync-58352363d0.yaml -->

## Why

fork 最近登记的上游基底是 v0.60.636.0（553b547334）。截至 2026-11-24，
上游 master 已到 v0.60.768.0，落后 132 个 patch release；直接追平会形成
2388 提交、34 个新增迁移和广泛跨模块验证面。按 CUSTOM.md 的小增量
原则，本轮先同步 v0.60.638.0，恢复短周期同步，并把后续版本作为独立变更。
目标取 upstream/master 的同版本 merge 17b68cef，而非不含后续 master 合并的
release commit 58352363d0。既有规则与台账拆分已完成路径级核账：相对
553b547334 的 516 个 fork 改动均可归入台账 #1–#32、生成物登记或本地文档；
未发现未登记路径。


## What Changes

- 将 fork 的代码基底从上游 v0.60.636.0 更新到 v0.60.638.0，并按行为保留仍有效的二开增量。
- 按冲突决策表处理共享文件与无文本冲突的行为交叉，移除已被上游吸收的重复实现；对阻断本轮已承诺合同的 Inbox managed 内容、Graph 可见性和 query.trace 诊断三项既有基线缺口仅做最小修复，并更新台账状态。
- 从各自真源重建受影响的生成物，验证候选树可重复生成且不产生漂移。
- 补齐受影响的高风险链路回归与迁移顺序证据，记录固定 fork 基线和候选树的 A/B 结果；三项基线缺口修复须与合并引入变化分别归因。
- 更新二开台账与本轮 STDD 证据，提供仅通过验证的同步分支候选，交付动作另行授权。

### Modified Capabilities

- **upstream-sync-merge**：在明确的上游窗口和回滚锚点下合并更新，保持 fork 定制的行为、权限、顺序和生成物一致性。
- **fork-custom-behavior**：继续提供 Inbox 工作流、真理沉淀、Graph 扩展、Admin Brain 层和查询诊断等已登记能力。

## Success Criteria

- [ ] 冻结输入可复核：FORK=8f0e2d99983885d980fef98d6d5088c2649b38e5、UPSTREAM=17b68cef4f4267ca0e5710b42f6ddc95acf9fe51、BASE=553b5473344af4b8d9e09ebb8078e4e51a6d15eb、59 个 fork 侧提交、13 个上游侧提交和回滚锚点均有 Git 证据，且 master 工作区未被合并改变。
- [ ] 相对 BASE 的 516 个 fork 改动继续全部归因；候选中仍保留的 #1–#32 能力无丢失，已上游化项无重复实现。
- [ ] Inbox unmanaged 与 managed 捕获都实际消费处理后的 frontmatter/content 和 provenance；Admin op 代理先鉴权后分派且审计不重复；两条路径均有定向行为证据。
- [ ] query.trace 开启时在 trace.retrieval 保留完整上游诊断且 Admin 不丢弃 MCP _meta，关闭时保持上游结果形状；Graph 遍历与无根总览在双引擎和 source/private/软删除约束下不漏列、不越权，不可见边不污染 degree。
- [ ] 本轮上游末位仍为 v297，fork Inbox 迁移保持 v298；迁移顺序与 registry 检查通过，且不把版本号相等当作旧库结构完整的证据。
- [ ] 生成物从真源重建后 check:regen-all 与 check:admin-embedded 通过，同输入二次运行相对候选暂存区无漂移。
- [ ] typecheck、根单测、Admin 测试及受影响链路定向回归取得候选树信号；必需 E2E/引擎检查按影响面执行，未跑项明确列出且不放行。
- [ ] 所有失败均与固定 FORK 的同项同因结果对照并定性；Inbox/Graph/trace 三项既有基线缺口与合并引入回归分别归因，新增回归已修复并复跑，环境超时未被伪装为通过。
- [ ] 最终不存在未解决索引冲突；cached diff 的 whitespace 告警逐条对照冻结 FORK/UPSTREAM 基线，本轮新增告警为零，并分别对 FORK 与 UPSTREAM 完成分父审计。
- [ ] 台账记录本轮 SHA、裁决、挂钩归因、迁移结论、验证结果和未跑项；Gate 3 前候选仍位于独立同步分支，未经授权不落地。
