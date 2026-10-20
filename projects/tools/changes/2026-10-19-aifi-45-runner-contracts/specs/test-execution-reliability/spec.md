# Spec: test-execution-reliability

> Change: 2026-10-19-aifi-45-runner-contracts | Auto-generated Human View

## Requirements

### Requirement: 保留全量测试发现范围并区分慢测试、阻塞与报告错误。

#### Scenario: SC-T-TEST-001

- **GIVEN** crctl 当前有 31 个测试文件，output-guard 有 3 个，registry 有 1 个，且部分文件此前未在 15s/200s 内结束。
- **WHEN** 执行基线诊断并定义最终 Gate 3 命令。
- **THEN** SHALL 发现并保留全部 35 个文件和新增回归，不因前次限时结果排除文件。
- **AND** 测试文件数与实际 case 数分别统计，未完成不得报告通过。
- **AND** 使用真实子进程 exit code 和单调时钟耗时，不使用 tail 管道状态代替测试状态。
- **AND** 原始 stdout/stderr 存安全日志，摘要区分失败、超时、skipped 与完成。

#### Scenario: SC-T-TEST-002

- **GIVEN** 一个此前超时文件及一个相似可完成文件，运行环境和版本已记录。
- **WHEN** 选择最小用例并检查真实调用路径、子进程和外部依赖后逐一检验假说。
- **THEN** SHALL 用可重复命令和实测耗时区分套件正常耗时、缓冲输出、环境问题与真实阻塞。
- **AND** 不预先断言所有 12 个文件有同一种代码缺陷。
- **AND** 诊断使用隔离夹具，不写真实 CR、生产数据库或全局配置。
- **AND** 只清理本次启动且归属已核实的进程，不按进程名批量终止其他会话。

### Requirement: 真正缺陷按根因修复并留下可红可绿的最小回归，不削弱测试。

#### Scenario: SC-T-TEST-003

- **GIVEN** 诊断证据已经定位导致超时或平台失败的根因。
- **WHEN** 进入获批的 BUILD 切片实现修复。
- **THEN** SHALL 先用最小回归复现失败，再在共享根因处修复，并验证原调用路径与全量测试。
- **AND** 不仅调大 timeout、不 skip、不删除断言、不全局关闭安全 Hook 来获得绿灯。
- **AND** 若根因只是正常慢套件，只调整基于实测的执行预算和可观测输出，不凭空修改业务逻辑。

#### Scenario: SC-T-TEST-004

- **GIVEN** 修复后存在全量测试运行日志，且跨仓验收需要引用这些结果。
- **WHEN** 编写 test-report 与 PR/Issue 的证据摘要。
- **THEN** SHALL 报告命令、版本、全部文件与 case 统计、退出码、耗时和 skipped，并明确标出未执行项。
- **AND** 任何未完成运行或意外跳过均不得计作本需求已验收。
- **AND** 不把原 15s/200s 诊断预算当成产品业务重试预算。
- **AND** 临时诊断日志与进程不成为新运行时系统或新测试平台。

### Requirement: 修复已经证实的authority夹具错位与已知事务错误分类丢失，不削弱生产信任边界。

#### Scenario: SC-T-TEST-005

- **GIVEN** cmdReviewRecord从CR工作副本读取相对payload，但五个既有测试把payload写在主checkout而收到PAYLOAD_NOT_FOUND。
- **WHEN** 修正夹具根或显式绝对from路径并重跑原测试。
- **THEN** SHALL 使测试真正到达原目标分支，保留原forged、回修、证据漂移与零写入断言，而不是更改生产authority解析或放宽安全条件。
- **AND** 若测试目标是payload缺失则保留该反例，不能一律复制payload掩盖路径错误。
- **AND** 修复前最小原测试自然exit1，修复后原断言自然exit0。

#### Scenario: SC-T-TEST-006

- **GIVEN** cmdTaskDone的authority解析抛出已知TxError(CR_WORKTREE_STATUS_MISSING)，目前总catch包装成INTERNAL_ERROR。
- **WHEN** 核查全部authorityWorkspace调用点，在共享解析出口的既有容忍分支判定之后格式化已知TxError。
- **THEN** SHALL 让task done与同源caller保留原CR_WORKTREE_STATUS_MISSING及非零退出、零业务写入，未知异常仍抛给INTERNAL_ERROR边界。
- **AND** 不只给单caller打补丁，不按任意异常code全局透传，不改总catch扩大可信错误边界。
- **AND** 保留显式override及无绑定模式既有容忍，不把合法单仓退化路径变为硬失败。
- **AND** 保留原R1测试，补同源caller、合法容忍与未知异常边界的最小回归。
