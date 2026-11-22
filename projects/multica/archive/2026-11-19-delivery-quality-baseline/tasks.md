# Multica 交付质量基线 — 任务清单

## 1. 后端入口接线（S1，P0）

- [x] 1.1 用现有 shell fixture 覆盖 `test-ci` 的 regular/admin/agent 次数、环境隔离与失败传播。
- [x] 1.2 在现有 Makefile 接入已批准的薄配方及 `quality.test`，保留托管工作流和开发命令。

## 2. 代表性 Linux 后端全量（S2，P0）

- [x] 2.1 非 root Linux 复核干净基线，只诊断可复现阻塞，不降低现有检查。见 [待裁定调整](pending-adjustments.md)。
- [x] 2.2 在独立干净 Tools 检出评估 `6dacbaf`：实际 orchestrator/agent allow/deny、execenv、crctl 规则和 report 定向通过。该评估后被用户新裁定取代：改为采用 Tools main `71d0587`（见 2.7）。
- [x] 2.3 通过既有 `ci-provision` 为七案例各供独立已迁移空库；Make 与 hosted 接线合同通过，真实 Linux PostgreSQL 定向证据验证七例、受限角色与回收；未触发 hosted。见[测试记录](test-report.md)。
- [x] 2.4 更新迁移测试引用 `689–696`、删除重复 Pi 技能参数追加；Linux 迁移断言和 Windows Pi/OMP 参数定向验证通过，不改 SQL、收尾或业务选取。
- [x] 2.5 定向归因后端红项、不重跑干净基线；最终 run `c7d6ab92` 的 CP-DQB-002 正式入口通过 regular、admin、agent 与完整对账。

- [x] 2.6 直接检查 Pi 运行时技能交付字段，保留真实 helper 的 wire、摘要及清空断言；原用例定向 1/1，不动生产收尾。
- [x] 2.7 pin 改为 `71d05871a3f937f29a7f68fbf5b022741ab242e8`；Windows gitguard 126 pass、crctl 多条目合并/report 12 pass，Linux 非 root `-race` gitguard 109/execenv 9 pass，均 0 fail。不改 Multica 生产代码与 agent show 测试期望。
- [x] 2.8 Pi 自然退出 stderr 复用 stdout 现有 250ms 期限；Linux `-race` 三个清理/诊断用例 13 pass、0 fail、无 race，原挂起叶子通过。不改取消/终止/等待兜底/测试超时。
- [x] 2.9 两个合法 claim 令牌插入点补 owner；经用户裁定将外部/已改 daemon 与空身份负例期望对齐为 MUL-8154 掩蔽的 404（ownership_change 竞态仍为 409），保留拒绝与零写入。Linux `-race` claim 选择器 54 pass、0 fail、无 race，资源回收 0|0。不改生产授权。
- [x] 2.10 backlog C4：搜索测试期望容纳 CR-2026-006/009 的 origin_type 防泄漏谓词（生产语义正确，仅改测试），Windows `TestBuildSearchQuery_ProjectFilter` 通过。其余 backlog 根因聚类见 [pending-adjustments.md](pending-adjustments.md)；C1–C6 已修（2.11–2.15、2.19），C7/C8 隔离重跑通过（2.16），9 平台 skip 登记（2.20），Views 6 文件上游已知红声明（D2-D）。
- [x] 2.11 backlog C1：为 Private Ask 发送测试 seed 真实 catalog cache（仅测试夹具，不改生产/不弱化校验），活库 `-race` chat-submission 通过。
- [x] 2.12 backlog C2：修复迁移 709 CASCADE→SET NULL 后的 teardown 残留（显式删 system carrier private session、保留 project_shared）与 DeleteChatSession NULL agent 容忍；活库 `-race` handler-delete 2 pass、chat-submission 5 pass、0 race、资源 0|0。台账 #365–#367。
- [x] 2.13 backlog C3：删合并残留 CR-2026-008 拦截块，恢复 MUL-8374 lifecycle→workspace 扇出；内容隐私仍由 isChatPrivateEvent 守住。活库 `-race` listeners 72 pass（含 privacy）、0 fail/0 race。台账 #368。
- [x] 2.14 backlog C5：cancel 测试对齐 CR-2026-004 FR-4（非 originator 成员 403、owner 200，保留 outsider 404），不改生产授权。活库 `-race` private-cancel 4 pass。台账 #369。
- [x] 2.15 backlog C6：恢复 issue.go createOnce 中丢失的 MUL-8161 member delegation 记录块（产品回归）；活库 `-race` service telemetry 4 pass。台账 #370。
- [x] 2.16 backlog C7/C8：隔离 `-race` 重跑 wakeup / worker-reply，service 4、handler 10 个终结 pass；共享库 CASCADE 干扰仅为未证实假设，未据此改生产或弱化断言；完整入口由最终同次 run 判定。
- [x] 2.17 regular 包级串行：Makefile test-ci 与 hosted backend-tests 的 regular 调用追加 `GOFLAGS=-p=1`（保留已有值），admin/agent/普通 make test 不变；test-go.test.sh 与 ci-scope.test.mjs 断言通过。
- [x] 2.18 隔离缺口重判后仅纳入 downAll 回收 fail-closed：夹具文件存在⇒句柄非空否则硬失败、文件仅成功清理后移除；ci-provision.test.mjs 30 pass（含新用例）。撤销夹具映射前缀检查与 MAKEFLAGS 回归（个人使用、仅防误操作）。台账 #372，Gate 2 重签。
- [x] 2.19 后端真实基线红诊断与修复（完整环境：迁移＋Redis＋Tools＋Git2.45）：56 红＝daemon 26＋execenv 30。execenv worktree 24 为 Git2.40 环境需求（源码编译 Git2.45.2 派生镜像）；其余 32 为上游预存陈旧测试（repo checkout activeTaskAuth、ConvertSkills ID/Source、BriefSkillsList skillsRoutingRule），同契约仅测试对齐，定向 34 pass/0 fail。台账 #373。两个 balanced 诊断子代理虚构文件路径/commit，经主会话抽查纠正后自诊。

- [x] 2.20 allowed-skips 11→20 经用户批准实施；ci-evidence 对既有后端流确认 5 个必需包及 20 个声明 skip。文件级前端例外的已知限制另记于 D2-D。
- [x] 2.21 C3 隐私评审修复：chat 的 task:progress 归入创建者私有内容，listeners 定向 -race 75 pass；后续创建者字段补全见 2.24。
- [x] 2.22 C1 回收复核：夹具句柄与文件对应、up 回滚失败保留文件、已删库后按 marker 重试删遗留角色；当时实现允许无文件或句柄的 always() down 为 no-op。新增错配、失败保留和重试用例，ci-provision/provision 定向 37/37。后续 C3 确认显式夹具文件缺失时此 no-op 与批准合同冲突，见 PA-008；未恢复已撤销的库名前缀检查。
- [x] 2.23 C1 skip 对账复核：新增 subtests 声明只限定 pwsh 子例，原父级 skip 兼容不变；正反例 31/31，既有后端流仍 5 包/20 skip OK。GOFLAGS 测试同时覆盖已有值保留、无已有值及 admin/agent 不受串行追加影响。
- [x] 2.24 C1 私有进度投递复核：真实 ReportProgress 缺 ChatSessionOwnerID 导致创建者收不到消息；从同一已解析 creator 填该字段，新增私有/共享/未知 owner 生产路径回归，定向通过；未知 owner 仍丢弃，不放宽路由。
- [x] 2.25 C1 回收根因修复（PA-006，Gate 1/2 已重签并实施）：夹具文件作唯一持久回收记录（fixtures 映射＋handles 主库/夹具句柄），up 随创建增量写入，down 只读文件句柄、逐库重读 marker、全部成功才删文件；删除环境句柄匹配与 FIXTURE_HANDLES_ENV，isolated_db.go 只读 fixtures 字段。后续 C3 发现写记录与回滚同时失败时身份仍可能丢失，故原认为已闭合的部分失败缺口仍开放，见 PA-008。

- [x] 2.26 C3 回收角色 marker 复核：共享删除入口在库存在与否两条路径均先核验角色 marker，拒绝外部角色前不删除任一对象；CI 实际回收入口新增反例，ci-provision/provision Linux Node 22 定向 38/38，台账 #380。真实 PostgreSQL 验证纳入最终环境。
- [x] 2.27 PA-008：既有入口已实施身份预留与原子记录更新；后续 C1 发现的一次更新失败未保留记录已修并回归，非 root Linux 关联用例最新 144/144。早期隔离真实 PostgreSQL 验证保留、拒删与部分回收重试且余量 0|0；最终同次验收另验，不改非夹具回收路径或新增 runner。
- [x] 2.28 C1 首轮同合同边界修复：记录有效 PostgreSQL 端点并核对 fixture 映射，拒绝输出路径同目标，修正 query 凭据覆盖和非 Actions 明文 mask，CI 接线检查不把注释当命令；当时非 root Linux 定向 66/66、Windows CI-scope 72/72，隔离真实 PostgreSQL 边界验证通过；后续复核又发现同合同缺陷，见 2.30。
- [x] 2.29 PA-009：补充三个候选文件的冻结输入并展示完整差异；用户审阅后 CLI 已记录 Gate 2 重签，原话和调用者审计见 pending-adjustments。
- [x] 2.30 C1 后续复核：socket 端点、末级软链接同目标、DSN 数据库 query 覆盖、记录更新失败后保留、环境文件权限六个反例先 RED 后 GREEN；复核再发现目录软链接后跟 `..` 的同类别名，按文件系统真实语义修复并先 RED 后 GREEN。Node 22 取消未等待子测试的既有问题统一改为独立注册，关联三个测试文件最新 144/144、0 取消／跳过。最终同次验收另验，未扩大安全合同或新增 runner，台账 #384–385。

## 3. 前端质量（S3，P0）

- [x] 3.1 替换 10 处外部图标导入并补 presenter 按钮可访问名称回归；不改 lint 规则和现有行为。视图包 lint、定向回归通过；不替代 #3.2。
- [x] 3.2 最终 run `c7d6ab92` lint 7/7、typecheck 10/10；项目 test 6/7，仅 Views 三个批准文件失败且结果完整；依原六文件例外通过 CP-DQB-003，见[测试记录](test-report.md)。

- [x] 3.3 去掉 Desktop 打包脚本的 shebang，并为原打包测试单文件声明 Node 环境；无需 CLI 覆盖，原测试收集并通过 30/30。全局配置、选择器和断言不变。
- [x] 3.4 PA-005：补前端检查器正反例并修复混合失败漏判；完整收集并对账现有 Turbo 输出。Linux Node 22 定向 9/9，受控 pnpm 子进程覆盖全绿、清单内失败、混合失败、未处理异常和信号退出；检查器及其测试已列入同次冻结计划，最终同次验证仍由 5.2 完成。不改六文件例外和上游测试。
- [x] 3.5 C1 检查器复核：用锁定 Vitest 的实际输出补终结摘要、失败数对账、Unhandled Rejection 和精确六文件路径判定；新增反例先复现漏判，修复后定向 9/9。另以真实 Vitest 4.1.0 复现一个失败测试多条 FAIL（断言＋afterEach），将 FAIL 行数判定由严格相等改为不少于声明失败数，避免误拒清单内合法失败（同合同实现修复）。完整文件级失败仍按批准例外处理，未知输出、异常、截断与清单外路径失败不放行。
- [x] 3.6 PA-007：Gate 2 重签后，前端检查器仅将 test 调用改为 `pnpm test --concurrency=1 --continue=always`；新增实际调用参数测试先红后绿，Linux Node 22 的前端测试 11/11，通过既有混合失败、异常、清单外失败反例。六文件例外、测试选择/断言/超时及 hosted workflow 不变；最终同次验证另由 5.2 完成。

## 4. 运行历史 Chromium（S4，P0）

- [x] 4.1 更新 `quality.e2e`，唯一必跑原有运行历史路径。
- [x] 4.2 专用 Chromium 栈的唯一运行历史 spec 通过，数据库及进程已回收；历史失败和本轮定向通过均保留在[测试记录](test-report.md)。
- [x] 4.3 原 spec 只加规范 URL 等待，原 compact、own、subtree 断言历史 1/1 通过，不增加浏览器场景；不替代同次正式 CP。
- [x] 4.4 PA-010：Node 顺序回归对漏等待先红后绿；`ea270ddf-5e2c-4d11-b1a2-82ef63263c40` 的 CP-DQB-004 含唯一 Chromium 通过且已回收；官方 CLI 登记 S4 `1/1, new_tests=1`。整体同次验收仍待 5.2。

## 5. 交付质量验证（P0）

- [x] 5.1 C1 三路已返、发现已处置；增量同合同修复已定向复核，C3 最终 58 路径均在批准范围，见[测试记录](test-report.md)。
- [x] 5.3 提案同步已批准范围（hosted regular 串行、六文件例外可见性）与回收机制修订；该轮完整差异经用户确认后 Gate 1、Gate 2 于 2026-11-20 12:45 逐道重签；其后 PA-007 和 PA-008 又按各自修订逐道重签，详见调整记录。该同步不新增业务权限或测试例外。
- [x] 5.1a PA-010 同合同修复：路径、Vitest 关闭超时、数据库环境隔离先红后绿；claim 仅恢复非法令牌的空 owner。台账 #386–389；真实 Go 与整体验收待执行。
- [x] 5.1b PA-010 本地 `test-ci` 固定 Go flags，现有 Make 回归模拟调用方选测先红后绿；台账 #390。真实 Go 全量由 5.2 执行。
- [x] 5.2 `c7d6ab92-0988-46a8-a526-4cad1e5322e2` 同次四 CP 通过，脚本 815/815，C4 14/14 检查，数据库／角色 `0|0`；C5–C7 已完成，证据见[测试记录](test-report.md)。
