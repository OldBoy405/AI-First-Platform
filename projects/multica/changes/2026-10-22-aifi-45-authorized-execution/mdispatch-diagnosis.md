# MDispatch001 本 change 内诊断

## 结论与历史边界

确定复现并修复的是共享测试fixture的**单进程顺序缺陷**及**跨测试进程污染**，不是生产Runner逻辑。不是重跑绿色、sleep或skip修复。最初全包581RUN/578PASS/3FAIL未保留具体错误上下文，不能逐条证明历史首失败一定全部同源；原失败记录保留。LiveGitHub仍未收口、不重发PAT。

## 单进程根因

1. architecture fixture用自己的UUID占有同workspace的`quality-reviewer-agent`。
2. requirement自己的author/reviewer UUID尚不存在。
3. 旧MDispatch清理按`name IN (SELECT name FROM agent WHERE id=ownID)`查冲突。ownID不存在→空集→没有清掉同名agent。
4. requirement fixture `INSERT ... ON CONFLICT(id) DO NOTHING`不能处理另一UUID的`(workspace_id,name)`唯一键，于是SQLSTATE23505。

真实新增反例`TestMDispatch001AfterArchitectureFixture`先seed architecture，再调用原四阶段测试：requirement-authoring报`seed agent quality-reviewer-agent: duplicate key ... agent_workspace_name_unique (SQLSTATE 23505)`，3层FAIL、exit1，其余四子例通过。

修复放在共享`setupRequirement`：从已经解析的registry取目标agent name，按当前workspace/name、排除ownID清理冲突，不再依赖ownID存在；所有setup caller复用。回归又显式reset requirement rows并断言两个ownID不存在，避免初始DB状态隐含前提。

## 并发根因

两个`go test`进程共用固定workspace slug、agent/CR UUID，互相seed/reset/cleanup；旧版两进程各10轮实跑失败，其中process1为RUN60/PASS29/FAIL31/exit1，包含真实23505。不能让一个进程结束cleanup删除另一个的fixture。

`TestMain`新增独立pgx session advisory lock `(775513,45001)`，覆盖seed→m.Run→cleanup；数据库自然释放崩溃连接，无TTL/sleep/force unlock。新`TestGovernanceFixtureLeaseExcludesOtherSessions`在旧版实际1FAIL/exit1，修复后第二session不能拿锁。只约束同DB遵守此TestMain的进程；不宣称抵御其他不遵守lease的writer或已证明全部断连窗口。

## 已执行证据

- 单跑原MDispatch20轮：120/120、exit0，只是历史取证，不当修复。
- 修改后两个Go进程各10轮原MDispatch+phase-order+lease：各RUN140/PASS140/FAIL0/SKIP0/exit0。
- 扩大governance：先`-shuffle=2`，再显式ownID缺失前态加强后`-skip '^TestReconcileLiveGitHub$' -shuffle=3 -count=1 -json`，均RUN588/PASS588/FAIL0/SKIP0/exit0；最新明确`TestMDispatch001AfterArchitectureFixture`实际PASS，包含真实Go→Node授权互操作。
- 所有DB运行前核专用容器ID前缀666bfec52ac3、change label、55432映射及`stdd_aifi45_20261022|stdd`；URL只在内存，移除GitHub/knowledge-base凭据环境，GOPROXY=off。
- 588=旧580个非LiveGitHub执行+新增8个fixture回归执行；排除项不是覆盖，不把包统计当原业务17TC完成。

## 文件与定制台账

M `server/internal/governance/{crsync_test,four_phase_dispatch_cp_test,runner_requirement_test}.go`；`CUSTOM.md` M11/#158。没有生产代码、migration、真实CR/refs、commit或push。
