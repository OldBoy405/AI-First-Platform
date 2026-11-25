# 按二开合并规则同步上游 v0.60.772.0

<!-- source_hash: 1f03034d4edabb50 -->
<!-- generated_at: 2026-11-25T17:34:08.845887 -->
<!-- canonical: canonical/proposals/2026-11-25-upstream-sync-22f8c793.yaml -->

## Why

fork 已完成 v0.60.638.0（17b68cef）合并，当前 master 的 VERSION 为 0.60.638.0。
上游最新 tip 已到 22f8c793b1 / 0.60.772.0；相对 17b68cef 的初步评估为
2434 提交、5879 个改动路径、67 个双边改动路径。上游迁移区间已到 v336，
其中新增 v298，与 fork 的 v298-inbox-workflow-frontmatter 撞号。
本轮只追赶这个上游窗口，不扩展 Graph 修复或新定制。


## What Changes

- 冻结本轮 FORK/UPSTREAM/BASE、同步分支和回滚锚点，重新核对 fork 归因与双边路径清单。
- 合入上游 22f8c793b1，按行为处理双边文件和无文本冲突；不新增 Graph 修复或其他定制能力。
- 将 fork Inbox 迁移从 v298 顺延到上游 v336 之后，重生成 registry/latest 与受影响生成物。
- 执行受影响链路和常规质量检查，更新台账与 STDD 证据，经 Gate 3 后再按授权交付。

### Modified Capabilities

- **upstream-sync-merge**：在新上游窗口内合并更新，保持 fork 已登记行为、权限、顺序和生成物一致性。

## Success Criteria

- [ ] 冻结的 FORK/UPSTREAM/BASE、上游 VERSION 0.60.772.0、回滚锚点和同步分支均有 Git 证据；主工作区未被合并改变。
- [ ] 相对 BASE 的 fork 改动继续全部归因，67 个初步双边路径按行为裁决；保留能力无丢失、无重复实现。
- [ ] 上游 5879 个改动路径均已核对；Inbox、Admin、query.trace、来源隔离和权限行为保持。
- [ ] fork Inbox 迁移位于上游 v336 之后，registry/latest 由生成器重建，无重复 version。
- [ ] 生成物由真源重建；freshness 检查通过，同输入第二次生成无漂移。
- [ ] typecheck、受影响定向回归、Admin 测试和必要 E2E 取得候选树信号；失败逐条定性，未运行/超时/skip 不冒充通过。
- [ ] 台账记录本轮 SHA、迁移顺延、冲突裁决、验证结果和未跑项；Gate 3 通过前不落地。
- [ ] 交付动作仅在单独授权后执行；不创建 release tag，不执行生产 brain 内容同步。
