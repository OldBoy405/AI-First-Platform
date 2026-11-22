# 恢复 Multica 交付质量基线

<!-- source_hash: aefc5b42953eda16 -->
<!-- generated_at: 2026-11-20T22:39:18.043477 -->
<!-- canonical: canonical/proposals/2026-11-19-delivery-quality-baseline.yaml -->

## Why

2026-11-18-defensive-trim-multica 的 6 项定向验收已通过，但项目质量检查阻塞交付。 干净基线与变更版的 lint 均报相同的 21 个错误；隔离 Linux CI 对照中两侧的全量 Go 测试均未通过。 原项目配置的 make test 和 scripts/check.sh 未在已授权的隔离数据库边界内验证，且 critical_paths 为空。 非 root Linux 复核确认固定 Tools 合同不匹配、隔离夹具无建库权限、迁移测试引用漂移及 Pi 技能参数重复；换 pin 不能单独恢复全绿。

## What Changes

- 项目配置与 CI：对齐正式验证入口；现有 hosted backend-tests 只允许修改隔离夹具供给、凭据隔离、回收接线和 regular 包级串行，不新增 runner 或改测试分组。
- 代码和测试：修复基线 lint、迁移测试引用与重复 Pi 技能参数，解除 Desktop 测试收集和运行历史时序阻塞。经用户批准，另纳入 Pi 自然退出读取期限、合法 claim 夹具 owner 与对应掩蔽负例对齐、迁移 709 teardown 残留、chat 私有内容路由与创建者投递、丢失的 member delegation 记录，以及仅测试的 catalog/搜索期望对齐。任务 2.19 仅对齐 daemon/execenv 的既有测试：仓库检出鉴权夹具、技能身份与来源、技能列表路由规则；不改对应生产行为、鉴权边界或测试选择。保留原行为与拒绝、零写入断言；未经裁定的其他红项不预批修复。
- 基础设施与证据：确需空库的测试分别使用本轮预置的独立空库和受限凭据；采用经用户单独裁定的固定 Tools `71d0587`（含已接受的 agent git show 五形状放宽），规则与 crctl 取自同一提交。夹具文件作为本轮唯一回收记录，含测试映射与主库/夹具身份；归属不明时保留记录并报错，不自动删除。

### Modified Capabilities

- **ci-backend-environment**：正式全量后端检查继续使用受管的一次性库、Tools pin 和既有证据对账。
- **ci-credential-and-frontend-typecheck**：项目级验证明确执行前端 lint、类型检查及选定的必跑 E2E，并以实际结果判定。

## Success Criteria

- [ ] 正式质量入口与配置一致；必跑 E2E 路径明确且实际执行，现有必跑检查未被降级。
- [ ] 修复后的干净检出通过正式全量测试、lint、类型检查和指定 E2E，结果与对应源码可追溯；自建服务和一次性库已回收。前端按已批准的六文件级例外判定，不据此证明清单内无新回归。
- [ ] 原精简补丁及其现有证据未变更；基线通过后方可按原变更流程推进最终验收。
