# 2026-11-18-defensive-trim-multica 任务清单

## 1. 签发与重放（P0 / S1）
- [x] 1.1 用签发 HTTP 及固定样本验证补值、冲突、幂等与基线字节；移除重复请求准备，迁移构建器的 Go 调用与夹具（TC-RUN-201）。
- [x] 1.2 `run-default-contract-issue` S1 初验 30 pass（27 叶），S3 删重复比较用例及 C1 复验后 29 pass（26 叶），均 0 fail/skip；`run-authz-boundary` 4 pass；fork 台账 #349–#350。

## 2. 固定 Tools 取材（P0 / S2）
- [x] 2.1 经真实 Tools 阶段和临时 Git 仓库验证合法 pin、拒绝降级、固定树和显式 overlay；复用 `parsePin`，固定引用与工作树分流（TC-CBE-101）。
- [x] 2.2 三文件 Node 检查 50 pass / 0 fail / 1 个 Windows skip；fork 台账 #348。

## 3. 历史批准与撤销（P0 / S3，依赖 #1.1）
- [x] 3.1 验证历史可读性和篡改拒绝；返回包内已验证头，迁移生产消费者并清理冗余解析（TC-RUN-202）。
- [x] 3.2 `run-authorization-head` 20 pass（19 叶）、0 fail、0 skip；fork 台账 #351。

## 4. 敏感动作（P0 / S4，依赖 #3.1）
- [x] 4.1 通过实际撤销和动作请求验证双向锁序、回执与额度；在已锁且已验头的事务中结算（TC-RUN-203）。
- [x] 4.2 `run-sensitive-action` 8 pass（7 叶）、0 fail、0 skip；fork 台账 #352。

## 5. 进展与生产路由（P0 / S5）
- [x] 5.1 同一 status 推导进展，坏详情走现有失败出口；覆盖交错、未知状态和 POST 成功回执（TC-EWV-101）。
- [x] 5.2 去除测试专用挂载，使用生产 router 验证 Runner 和真实凭证业务码（TC-EWV-102）。
- [x] 5.3 登记并运行 `ewv-progress`、`ewv-route`，对账实际测试树；修订 #346 旧挂载描述并记录 fork 追溯。

## 6. Gate 3 前验证（P0）
- [x] 6.1 核对切片结果及 Phase 3 验收清单；执行三路评审、项目质量检查和同次执行证据计划。三路评审、差异检查、补测、同次取证及五包 Go/全脚本基线对照已完成。隔离补验 typecheck 与 CI 管理员库测试通过；运行历史 Chromium 冒烟及 Linux `repocache` race 对照通过；当时 Windows 和 Linux CI race 全套未通过，Linux 全套基线对照有少量不同失败，lint 红项在基线逐项复现。未执行 `scripts/check.sh` 或全套 E2E，详见 `test-report.md`。
  用户授权后修复工作区并发测试的观察边界，受控回归先红后绿，三路增量评审完成。最终候选 Linux `test-ci` 通过；全脚本 813 pass / 2 skip，固定 Tools 补跑两项通过。lint、typecheck 和指定 Chromium 测试通过；前端 test 的失败在已登记文件级例外内，不是全绿。用户重审 Gate 2 后，新 run `d6390f73-b7f7-4750-8369-b60d37526b95` 冻结 36 项，6/6 CP 通过。
- [x] 6.2 完成失败模式检查、适用的经验与调整记录、`test-report.md`；提交人工 Gate 3 确认。同 run 自动化 C4 9/9，人工 C4、经验及报告已完成；用户已确认 Gate 3。
