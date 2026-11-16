# multica 执行恢复与证据闭环 - BUILD 任务清单

## 1. 离线事件与接线矩阵（P0，TC-MEC-002）

- [x] MEC-01 编写有限 metadata、完整/缺测选择及 CI wiring 回归；执行代理报告 RED 96 PASS/4 FAIL/0 SKIP。
- [x] MEC-02 扩展已知可选字段验证，保留原拒绝与无 expected 语义。
- [x] MEC-03 锁定四项 governance-run-lock expected、同一发布 pin 与规则 env/必需文件，更新既有测试。
- [x] MEC-04 主会话独立执行 CP-MEC-002：101 PASS/0 FAIL/0 SKIP，SC-MEC-003/004/005 与实际差异一致；真实 tools 完整性及两个生成 --check 均通过。CLI 登记切片1：TC 1/1、new_tests=3（两个新顶层测试和新增 rules.json 缺失检查），verified_at=2026-11-16T02:06:45.731334。

## 2. 三入口锁身份与恢复（P0，TC-MEC-001；依赖 #1）

- [x] MEC-05 在既有 runner_run_lock_test.go 编写一个顶层三入口×三情形身份矩阵，使用合法夹具、独占池与控制连接，不加生产 hook。（TestReconcileRunIdentity，普通表循环九例，独占池 MaxConns=4＋独立控制连接，AcquireCount 增量 3/2/2，B 持锁正向对照。）
- [x] MEC-06 在自建一次性迁移库中确认新矩阵真实 RED，不把环境失败当回归 RED。（git apply -R 撤销守卫后非 race 下 architecture changed 报「first wake advanced B under A's lock (1 tasks), want 0」；cgo 环境失败另行解除，未充当回归 RED。）
- [x] MEC-07 三个恢复入口核对锁后 ID，保持查询/digest/error 及锁原语边界。（runner.go/runner_requirement.go/runner_code.go 锁内重读 current，current.ID != run.ID 本次返回，ErrNoRows 无效果与其余错误传播保留，withRunLock 未改。）
- [x] MEC-08 同一次四测试 selection 带 race 执行、精确对账及验证；通过后由 CLI 登记切片2。（CP-MEC-001 -race -count=1：PASS governance-run-lock pass=4 fail=0 skip=0，NODE_EXIT=0，复跑两次一致，完整四项 expected matched；CLI 登记切片2 tc_coverage=1/1、new_tests=1。）

> 阻塞已解除：用户「授权 cgo/race 环境，以及独立的发布/CI」后建立 mingw-w64 gcc 16.2.0＋CGO_ENABLED=1，go test -race 编译运行通过；BLOCK-MEC-01 清除。GREEN 期间修两处夹具缺陷（requirement inputs.source、跨入口同名 reviewer 冲突），生产守卫未改。

## 3. 当前台账（P1，TC-MEC-004；依赖 #1/#2）

- [x] MEC-09 按实际修改登记本change与MEC任务，不编造CR身份，保持CUSTOM历史、稳定编号与CRLF。（切片2复登完成：M4 新增稳定 ID #344（三入口锁身份守卫＋TestReconcileRunIdentity），M4 索引/标题 29→30，CR 索引行更新为 #343–#344、切片1/2 已验证、模块 M31+M4，#343 追加后续指针更正「尚未实现」；CRLF 1126/裸 LF 0，git diff --check 通过，#344 六单元格、测量行七单元格。切片3 CLI 登记待人工确认后与切片4 一并处理。）
- [x] MEC-10 按跟踪树记录前三数、实际tree/HEAD和时间；第四数写未决，不stage改变测量范围。（切片2落码后复测 629/1722/789，HEAD 294d793a91c8f1dce2f97a549b41cf468e562b1a 未变，5816 个跟踪五类文件无增减，测量时间 2026-11-16T03:08:39.005+08:00；相对上一行 +0 文件/+4 命中行/+4 AIFIRST，逐项落在四个 Go 文件各 1 标记；第四数仍未决、不沿用 314；未 stage。新测量行已落 CUSTOM。）
- [x] MEC-11 人工事实供用户核对，不代签required manual；接受后再登记切片3。（TC-MEC-003 本轮经用户裁定延期为 not_applicable 后，计划级 required manual 仅剩 TC-MEC-004；用户原话「执行 confirm 并继续后续流程」经 `stdd agent confirm … --run 0ccb7130…` 确认 TC-MEC-004/custom-trace，AI 未代写结论。切片3 已 CLI 登记 done：tc 1/1、new_tests 0、verified_at=2026-11-16T11:01:56.826748。原「两项合并一次确认」设想因 TC-MEC-003 延期不再适用。）

## 4. 真实 CI 与最终质量验证（P0，TC-MEC-003；依赖 #1/#2/#3）

- [x] MEC-12 取得独立提交/push/真实CI授权。（用户原话「授权 cgo/race 环境，以及独立的发布/CI」已授予本change的提交/push/真实CI；Gate3 与 required manual 确认不在此授权内，仍须用户原话。提交/push/CI 执行见 MEC-13。）
- [ ] MEC-13 同一次最终业务SHA CI核对六测试真实规则、backend步骤及两个生成--check；阻塞保持未验证，不继承旧N/A。（已提交 f8a23564a 并 push origin/main，触发真实 CI run 43752944966；但所有 job runner_id=0、零步骤、backend-tests 等 skipped——GitHub 托管 runner 因私有库 Actions 额度/账单无法分配，台账 #113。六测试/真实 rules.json/backend/admin/对账/两个生成 --check 均未执行，SC-MEC-006 未验证。**本轮经用户裁定延期为 not_applicable（接受风险，原话「修订计划延期 TC-MEC-003」），受审文档已同步修订并重审 Gate 1+2；权威 CI 验证仍未完成，非代码失败、非绿灯、不继承旧 N/A。** 待用户解除额度后对最终 SHA 重跑再核对以满足 SC-MEC-006 全部 SHALL，不代签。本任务保持未完成。）
- [x] MEC-14 三路独立技术评审、按已配置范围执行可授权质量命令，逐项记录授权/环境缺口；不启动共享服务或安装依赖。（C1 代码→strong/测试→balanced/文档→economy 三路均 NON-BLOCKING，发现已处置；C2 新 run 0ccb7130 两命令 CP 重跑通过、ci check-failures 9/0（TC-MEC-004 确认后），覆盖率 not_applicable，lint/typecheck 无配置义务；未启动共享服务/装依赖。）
- [x] MEC-15 独立生成run，执行同次CP并以相同run审查C4义务，保留原始事实；人工项必须由用户确认。（延期修订后新 run 0ccb7130 已生成，CP-MEC-001/002 同次重跑 PASS，C4 a–n 以同一 run 审查并保留 tc-evidence.json/快照；TC-MEC-004 经用户原话确认，TC-MEC-003 延期 not_applicable，未代签。旧 run 2d5d4330 冻结修订前 test-plan，作废。）
- [x] MEC-16 生成test-report与必要的design-adjustments，完整证据齐备才展示Gate3；本次不自动批准、提交、push或部署。（test-report.md 已如实刷新、design-adjustments.md 已记录用户裁定延期与 Gate 1+2 重审；TC-MEC-001/002 重跑通过、TC-MEC-004 已确认、TC-MEC-003 延期 not_applicable（接受风险，显式标未验证），CLI 机械覆盖 4/4。Gate3 确认框待展示须用户原话，未代签批准。提交/push 系 MEC-12 独立授权下执行，非超范围自动动作；未部署。）

任务编号仅追溯实现；打勾与切片完成必须有实际结果，不等于Gate批准。全部范围在一个change内完成，不把未验证项冒充后续已交付功能。
