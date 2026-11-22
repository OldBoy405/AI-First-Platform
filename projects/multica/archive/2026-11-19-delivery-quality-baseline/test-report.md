# Multica 交付质量基线 — BUILD 定向验证记录

## 最终同次验收 `c7d6ab92-0988-46a8-a526-4cad1e5322e2`

**Gate 3 历史拒绝与后续处理（2026-11-21）**：用户已确认本 run，但此前 Windows 业务工作树执行 `stdd gate approve` 返回「当前输入/文件集与冻结输入不一致」，未签发回执。只读诊断用 STDD 原生快照算法：4,816 输入路径集合相同，4,710 项原始字节不同，逐项核对均为 CRLF→LF 后与 run 一致，未见其他字节差异。旧判定器还要求记录的 `cwd=/work/multica` 与 Windows 项目根完全相等，因路径不同将四项判为无效来源。只读挂载记录根、重建 run 的 Linux 路径及原始冻结候选后，官方证据判定器验证 TC 4/4、无问题；该验证没有签 Gate、没有重跑测试。STDD 现将保留 run 的 Gate 3 证据审批与后续业务提交绑定分开，当前环境的 Gate 3 只读前置检查已通过；截至本记录更新尚无 Gate 3 回执。实际业务提交仍须在独立授权后由 `bind-commit` 对照冻结范围和内容验证，不以此预检代替绑定。

原生证据：[CP 报告](validation/runs/c7d6ab92-0988-46a8-a526-4cad1e5322e2/agent-verification-report.md)、[TC 及输入摘要](validation/runs/c7d6ab92-0988-46a8-a526-4cad1e5322e2/tc-evidence.json)。非 root Linux，基点 `0c47c67e7e930ba7d28d4e6efd795e1e3741ecaa`，Go 1.27.4、Node 22、锁定依赖离线安装，Tools 固定干净检出 `71d05871a3f937f29a7f68fbf5b022741ab242e8`。58 个候选路径逐文件审查，全部与原生冻结 SHA-256 一致（候选 manifest `315c3361c3743a604f7a2c15b1a9f71b1fd8caee68beec7199d59b02d15ab612`）。C1 三路评审发现及处置见本报告历史段和 PA-010/011；增量复核确认两处旧预期和日志写尽修复未改变运行选择及判定。C3 无调试残留或额外路径。

| 场景 → TC → CP | 同次实际观测 |
|---|---|
| SC-DQB-CBE-001 → TC-DQB-001 → CP-DQB-001 | exit 0；固定入口、hosted 接线、regular/admin/agent 隔离和失败传播；`PA008 recovery: reserved=1 uncertain-drops=0`。真实 PostgreSQL 验证未确认保留、外来角色拒删和部分回收重试。 |
| SC-DQB-CBE-002 → TC-DQB-002 → CP-DQB-002 | exit 0；5 个必需包与 20 条许可 skip 对账，regular 24,579 pass / 20 skip / 0 fail，admin 3/3，agent 包通过（3,117 pass，该组 2 skip）；7 个夹具、迁移 seam、Pi、claim 等指定 25 项均有终结 `pass`。主库、七夹具和独立 Chromium 库均在本轮创建与迁移。 |
| SC-DQB-CCF-001 → TC-DQB-003 → CP-DQB-003 | exit 0；lint 7/7、typecheck 10/10；Turbo test 完整 6/7，仅 Views 一任务失败，674/677 文件、8,628/8,639 测试通过；11 个失败属 `inbox/components/inbox-snooze-menu.test.tsx`、`issues/components/issue-detail.test.tsx`、`issues/components/issues-header.property-filter.test.tsx`，均在批准的六文件内；无未处理错误、异常关闭或缺摘要，presenter 文件 14/14。 |
| SC-DQB-CCF-002 → TC-DQB-004 → CP-DQB-004 | exit 0；Node 精确路径与点击顺序回归通过；本轮独立 API/web/数据库上原单条 Chromium 1/1，通过 compact、own、subtree 内容与请求范围的断言。 |

- 全量脚本 `pnpm test:scripts` **815/815**，0 失败／取消／跳过；原独立 Go、脚本和前端结果均取本 run。计划/实际 TC **4/4**，切片 **4/4**：S1 `1/1, new_tests=3`，S2 `2/2, new_tests=3`，S3 `1/1, new_tests=1`，S4 `1/1, new_tests=1`。覆盖率按计划 `not_applicable`，不适用 pytest-cov；**无覆盖率保证**。
- `verify.exit=0`、`c4.exit=0`、`fixture-cleanup.exit=0`、`remaining-counts.txt=0|0`、`resource-cleanup.exit=0`、`launcher.exit=0`。同次辅助日志 `C:/Users/GOBAO/Downloads/AI/dqb-final-c7d6ab92/out/`：`verify.log`、`test-scripts.log`、三份 `aifi45-*-test.json`、`cp003-stdout.log`、`cp003-stderr.log`、`cp003-views-task.log`、`live-cleanup.log` 及回收日志。原始 `c4.log` SHA-256 `5ebc22eb1fc2ddc4ee2549e2d95d953d71bfb8e61354ec54226b51477017ba74`，CP-003 外层输出 `5c61c30dea203401d62fdc6c44436408dede700638247ba7ae63a8d139d03f1b`，Views 任务日志 `b09c422ae8dfe4eb16536a675c07c125b0a60774283d5052557f3725759356a3`。

### C4：同次失败模式（14/14；CLI 9/9，0 告警／跳过／错误）

下列均使用上述 run 的原生证据或同运行伴随日志，并对照其实际冻结候选。

| 类别 | 结果与依据 |
|---|---|
| (a) 幻觉 | CLI 必需文件与规格存在；报告数字取实际日志。 |
| (b) 范围蔓延 | C3 确认 58 个实际变更均在批准清单；未改实际 pin、skip 或 Views 例外的批准值，Chromium 未扩用例。 |
| (c) 级联错误 | CP-001 验证下游不吞前置失败，正式 `test:scripts` 和四个 CP 均 exit 0；真实 PA-008 回收异常不会删错资源，部分回收可重试。 |
| (d) 上下文丢失 | CLI 验证四个 TC-ID 唯一。 |
| (e) 工具误用 | 按受审命令和锁文件运行，`verify` 与 `check-failures` 同一 UUID；本轮未把诊断或缓存当验收。 |
| (f) 运行时偏差 | CLI THEN/SHALL 结构通过；真实 PostgreSQL、Go、前端与 Chromium 观察量见上表。 |
| (g) 管线断链 | CLI AND 数量正常、四切片均有验证证据；脚本、CP、C4 和回收均保留退出码。 |
| (h) 内容质量 | 外层 CP-003 日志与 Views 原生任务日志均完整，三份 Go 事件可解析并查到必需叶子；原始失败报告仍保留，不与本轮结果拼接。 |
| (i) 指令衰减 | 最终候选仍只允许原六文件级例外；未处理错误、异常退出、集外失败及缺摘要仍红；fixture 无法确认归属仍不删除。 |
| (j) 覆盖真空 | CLI 实际 TC 4/4；覆盖率按计划豁免，无覆盖率保证。 |
| (k) 契约断层 | CLI 两 capability 契约一致；后端凭据边界及前端结果判定未被日志修订改变。 |
| (l) 锚定缺失 | CLI 判定 Non-critical，不要求锚定。 |
| (m) Agent CP 失败 | 四 CP 各自为 exit 0 且全部 native assertions 通过；SC→TC→CP→实际观测见上表，不依据单一 PASS 字样。 |
| (n) 跨系统不一致 | 原生快照对齐业务目录 58 个 SHA；Go、前端、浏览器及回收记录均属同次，固定 Tools SHA 与检出一致。 |

C5 本地经验：`EXP-2026-0013`（文件例外误放行异常关闭）、`EXP-2026-0014`（强制退出丢失管道诊断）。C6 见 [设计调整](design-adjustments.md)。**已知限制**：文件级例外不证明清单内没有新增回归；历史某次 Views 未处理错误未能归因，本次没有复现，其拒绝条件保留。未改或重跑 hosted CI；只验证现有接线。

## PA-011 正式同次运行 `ea270ddf-5e2c-4d11-b1a2-82ef63263c40`（3/4，不作 Gate 3 候选）

| 检查 | 实际观测 |
|---|---|
| `pnpm test:scripts` | **814/814**，0 失败／取消／跳过；两条固定预期通过。 |
| CP-DQB-001 | exit 0；hosted 接线、regular/admin/agent 环境隔离、夹具 fail-closed；`reserved=1 uncertain-drops=0`。真实 PostgreSQL 拒删、部分重试与残留检查也通过。 |
| CP-DQB-002 | exit 0；5 个必需包与 20 条 regular 许可 skip 对账，regular **24,579 pass / 20 skip / 0 fail**；admin **3/3**，agent 包通过（3,117 个 test pass、该组自身 2 skip）。7 个夹具案例、迁移 seam、Pi 参数与清理用例、claim 负例等指定 25 项均有本次 `pass` 事件。 |
| CP-DQB-003 | exit 1；lint **7/7**、typecheck **10/10**。检查器在实际 Views 日志识别到未处理错误并保持红；其强制退出截断了转发日志，未保留栈。没有据此归因。 |
| CP-DQB-004 | exit 0；新增 Node 路径与定位顺序用例通过，原单条 Chromium **1 passed**；S4 CLI 登记为 `1/1, new_tests=1`。 |

- 原生证据见 `validation/runs/ea270ddf-5e2c-4d11-b1a2-82ef63263c40/`；辅助原始产物 `C:/Users/GOBAO/Downloads/AI/dqb-final-ea270ddf/out/`；本次候选 58 项，manifest SHA-256 `9a8511d428be222779f080c539d808051a0cdd15fa7f76ee3b1fc6c344270871`。`fixture-cleanup.exit=0`、`remaining-counts.txt=0|0`、`resource-cleanup.exit=0`；C4 按成功前置未执行，无选定证据。
- **同合同诊断修复（#394）**：非 root Linux Node 22 通过实际 CLI 管道先重现红路径尾部诊断丢失；以自然退出保留原退出码 1 后，12/12 通过（`C:/Users/GOBAO/Downloads/AI/dqb-front-diag-ea270ddf/{pipe-red,pipe-green}.log`）。只改日志转发，不改测试选择、超时、上游测试、产品逻辑或六文件例外。
- **前端诊断（非正式证据）**：独立同锁的全项目 test 命令出现 3 个已知文件共 11 个失败，但转发输出缺 Views 终结摘要，仍红；直接执行三文件 164/164，通过后直接执行全 Views 得到 677 文件、8,639 测试的完整摘要（3 文件/9 测试失败，均在例外内，未见未处理错误）。已修复的正式入口在同锁依赖下定向运行 exit 0：lint 7/7、typecheck 10/10、Turbo test 6/7，Views 674/677 文件、8,632/8,639 测试通过，7 个失败属于 3 个已知文件，完整摘要与任务日志都有保留。未复现原始未处理错误，不声称已归因。日志同目录 `test.*`、`leaf.*`、`views.*`、`checker.*`。
- 仅上述日志修复及台账字节变化；重新冻结同一 58 路径后启动正式 `c7d6ab92-0988-46a8-a526-4cad1e5322e2`，现次保留 CP-003 完整输出和已有 Views 原生任务日志。不得与前次或诊断拼接。

## PA-011 正式运行的脚本红项（未进入四 CP）

- `5dd8e0ba-c11a-4e54-8dbf-7c4a504c9fa7` 在 `pnpm` 安装 1556/1558 后无进展，确认剩余锁定 tarball 可直接下载后停止安装进程；`d2419588-06cc-45ac-a7f4-ce9c6ac6f158` 在隔离安装参数类型报错。均未执行验收测试，回收 `0|0`、资源退出 0。显式 `--store-dir` 的离线探针确认复用了 1541 个下载，仅需补齐未缓存项；在无库/凭据的准备容器补齐，随后从同一锁文件完成离线安装。
- `6be2a648-685b-4414-bf7b-7bc77a8a8ca6`：Go/Node 隔离环境锁定依赖安装通过，真实 PostgreSQL PA-008 检查 `reserved-preserved=1 foreign-role-refused=1 partial-retry=1 remaining=0|0`。`pnpm test:scripts` 退出 1，814 条中 **812 pass、2 fail、0 skip/cancel**：`TC-TOR-001` 仍期待 11 条；`TC-CBE-003` 仍期待旧 SHA。该次无四 CP、无 C4；`fixture-cleanup.exit=0`、`remaining-counts.txt=0|0`、`resource-cleanup.exit=0`。原始日志 `C:/Users/GOBAO/Downloads/AI/dqb-final-6be2a648/out/`。本次不作 Gate 3 候选。

## PA-010 固定 Go 参数与 S4 等待回归（定向，非最终验收）

- 实际 `test-ci` 配方在 Linux stub 中先因保留调用方 `-run`／`-count=0` RED；固定本地 Go flags 后，regular/admin/agent 按组接线、失败传播和隔离一起通过。S4 负对照仅在临时副本移除 `await`，因提早定位按钮而 RED；实际代码 Node 22 **1/1**。日志 `C:/Users/GOBAO/AppData/Local/Temp/dqb-pa010-final-redgreen-v8lu7kyx/{go-flags-red.log,final-targeted.log}`。同次 Chromium、真实 Go、C4 及回收另行验证。

## PA-010 终验前同合同修复（定向，非最终验收）

- 非 root Linux Node 22 的 `GITHUB_ENV` 路径别名与 Vitest 关闭超时反例先红（2 失败、1 既有变体通过），统一边界修复后 5 个脚本测试文件 **187/187，0 失败／取消／跳过**；非 root Linux `scripts/test-go.test.sh` 的 `PGPASSWORD`、`PGOPTIONS`、`POSTGRES_PASSWORD` 哨兵先红后绿。日志根 `C:/Users/GOBAO/AppData/Local/Temp/dqb-pa010-js-jbqkrdxt/`（`red.log`、`green.log`、`make-credentials-{red,green}.log`）。
- claim 外部／空身份恢复空 owner，匹配 runtime 的有效夹具保留 owner，原 HTTP 断言不变。核对了三个文件的差异与格式；尚未运行真实 Go。台账 #386–389。现次未运行同次四 CP 或 C4，待以最终候选验证。

## 2026-11-20 C1 全候选复核（历史发现，非最终验收）

代码、测试配置、文档评审报告已返回。临时非 root Linux 文件系统复现 `GITHUB_ENV` 的目录软链接后接 `..` 时，比较目标不同而实际写入目标相同；使用现有前端评估函数与锁定 Vitest 的真实 `close timed out after …ms` 诊断文本复现 known-red 叠加关闭超时仍被放行。Go 1.27.1 的临时包探针显示 `GOFLAGS=-run=^TestWanted$` 可跳过另一个会失败的测试且包通过；这不是项目测试或最终 Linux Go 1.27.4 的运行结果。实际 Makefile 在非 root Linux 临时目录配合 fake 命令和哨兵值时，regular、agent 均继承 `POSTGRES_PASSWORD` 与 `PGPASSWORD`，未连数据库。均未证明历史 run 发生选测或泄漏真实凭据。claim 负例、范围与切片账目还需处理，详见 `pending-adjustments.md` PA-010；此次未运行同次四 CP 或 C4，早前 144/144 不能代替它们。

## 2026-11-20 C1 后续边界回归（非最终验收）

请求 strong `OpenAIPersonal/gpt-6.2-sol:high` 的只读聚焦复核（实际模型元数据未返回）发现五项同合同缺陷：`socket:` 管理员 URL 的实际端点未被绑定；末级软链接可让环境输出与夹具记录落在同一文件；数据库 `dbname`／`database` query 可能覆盖派生 DSN 路径；后续预留更新失败且回滚成功时上次完整记录被移除；环境输出文件过宽权限可能暴露 DSN。六个针对性用例在非 root Linux Node 22 **0/6 RED**，证据 `C:/Users/GOBAO/AppData/Local/Temp/dqb-pa009-c1-red-4llfx0zv/node-tests.log`；同一入口修复后六个反例均过。环境文件在 POSIX 写入前设置 0600；Windows 的文件访问仍由系统 ACL 决定。

首次组合回归中六个反例均过，但现有 `ci-scope.test.mjs` 有两个子测试未被父测试等待，Node 22 取消其一（141 pass / 1 fail / 1 cancelled，`C:/Users/GOBAO/AppData/Local/Temp/dqb-pa009-c1-green-8aaq8gpa/node-tests.log`）。将它们作为独立测试注册、不改断言后，三个现有测试文件非 root Linux Node 22 **143/143，0 fail/cancel/skip**：`C:/Users/GOBAO/AppData/Local/Temp/dqb-pa009-combined-green-5fsna1za/node-tests.log`。后续只读复核发现末级软链接的相对目标中，目录软链接后跟 `..` 时仍被错误地按字符串折叠；真实 CLI 反例 RED：`C:/Users/GOBAO/AppData/Local/Temp/dqb-symlink-dotdot-red-iw7p4jpv/node-tests.log`。独立非 root Linux 探针证实普通 `realpathSync` 会先规范化 `..`、`realpathSync.native` 则遵循文件系统实际遍历；首次修复仍因普通 realpath 失败（143 pass / 1 fail，`dqb-pa009-boundaries-green-k_exr4s1/node-tests.log`），改用原生 realpath 后三个文件 **144/144，0 fail/cancel/skip**：`C:/Users/GOBAO/AppData/Local/Temp/dqb-pa009-boundaries-native-green-yvkidhsg/node-tests.log`。上述结果不替代最终候选同次验证；冻结清单的三条遗漏已由 PA-009 修订覆盖。

## 2026-11-20 C1 边界复核与修复（非最终验收）

- 三路只读增量评审：配置与请求分别为代码 `OpenAIPersonal/gpt-6.2-sol:high`、测试 `OpenAIPersonal/gpt-6.1-terra:xhigh`、文档 `GB-JP/deepseek-flash:high`；会话未返回实际模型元数据，actual 未知。覆盖 PA-008 代码、测试／证据链与当前记录，不宣称替代先前完整候选评审。
- 代码／测试评审发现并由模拟复现：连错 PG 实例可删除唯一记录，文件内夹具映射丢失句柄可误清理，query 凭据可泄漏并覆盖受限角色，环境与夹具输出同目标破坏记录，普通终端直接打印 mask 密码。共同边界修复为记录有效端点、核对映射、同目标拒绝、派生 DSN 去除 query 凭据、统一脱敏及仅 Actions 输出 mask；不改 marker 许可。定向 RED `C:/Users/GOBAO/AppData/Local/Temp/aifi45-c1-red-3CtdKzQ9.log`（初次 CLI hook 参数无效的四项不计证据），修正参数后 CLI RED `C:/Users/GOBAO/AppData/Local/Temp/dqb-c1-cli-red-t0s01vse/result.log`。非 root Linux Node 22 GREEN **66/66**、0 skip：`C:/Users/GOBAO/AppData/Local/Temp/dqb-c1-final-linux-d137h6bx/node-tests.log`，含目录别名用例。创建回执丢失的真实调用路径已用 fake 客户端覆盖。
- hosted 接线测试先在注释掉真实命令的反例上 RED（`dqb-comment-red-e7ktzqic/result.log`），共享 run 正文提取移除整行 shell 注释后 GREEN；同文件 Windows 跨行 workflow 匹配的 CRLF 缺口一并归一，Windows `ci-scope.test.mjs` **72/72**（`dqb-ci-scope-green-mlvbx2j5/result.log`）。不改变 hosted workflow。台账 #382–383。
- 文档评审指出旧四文件结果与六文件授权、旧 pin 和历史 run 表述不清；已保留事实并标注当次上下文，补记 `fe30d5ba` 实际 CP 结果。模板路径缺失意见不成立：绑定的资源根是 `../stdd`，现行 `<STDD_RESOURCE>/.stdd/skills/_shared/revision-rules.md` §3 明确使用两个 `.md` 调整文件，而非业务仓旧副本；当前资源根的模板先前已读取。

## 2026-11-20 PA-008 隔离真实 PostgreSQL（非最终验收）

使用 pgvector/pgvector:pg17 的临时独立数据库容器、临时网络与随机凭据，非 root Linux Node 22 调用共享供给 seam 与 `downAll`：`reserved` 时数据库和角色均保留，外来 role marker 时均拒删，数据库先移除后的 confirmed 记录可重试清掉角色并删除记录。成功结果 `live-pa008: reserved-preserved=1 foreign-role-refused=1 partial-retry=1 remaining=0|0`；运行退出 0，独立 SQL 余量 `0|0`，容器／网络清理退出 0。证据 `D:/multica-trim-quality.o41bVk/dqb-pa008-live-o7nrlz_1/{live-check.log,live-check.exit,remaining-counts.txt,resource-cleanup.exit}`。这是 focused 实例验证，不是 `ciProvisionUp` 的端到端全流程，也不代替最终同次四 CP。

两次先前测试环境错误均保留在 `attempt-mount-failed/`、`attempt-fixture-path-failed/`：分别因 Podman 未共享 D 盘导致测试模块不可见、测试脚本引用未挂载的 `/out`；两次记录退出非零、资源余量 `0|0` 和清理退出 0。排明根因后把测试及现有 pg 依赖暂存于可共享目录、将运行期记录改用容器 `/tmp`；不修改业务实现以适应环境错误。

## 2026-11-20 PA-008 定向验证（非最终验收）

- RED：旧实现的定向测试复现首记录冲突后仍创建、记录更新／回滚双故障丢失身份、未确认身份不安全回收和显式缺失文件误报成功；原始日志 `C:/Users/GOBAO/AppData/Local/Temp/pa008-ci-provision-red-0YLcWoXO.log`。随后复用同一生命周期测试，补齐第二个对象双故障和临时记录权限断言。
- GREEN：非 root Linux 容器内 `node --test scripts/aifi45-disposable/ci-provision.test.mjs scripts/aifi45-disposable/provision.test.mjs` 为 46/46、0 skip；日志 `C:/Users/GOBAO/AppData/Local/Temp/dqb-pa008-linux-0k4kpzpf/node-tests.log`，观测 `PA008 recovery: reserved=1 uncertain-drops=0`。已确认对象可先清理，未确认身份和记录仍保留。该次使用 fake 客户端，不代替真实 PostgreSQL 验证。

## 2026-11-20 C3 回收边界复核（非最终验收）

- 角色 marker：纯模拟证实数据库 marker 正确但角色为外部 marker 时旧实现仍尝试 `DROP ROLE`；真实 CI 回收入口新增反例，共同删除边界先校验库与角色。原回归先红，修复及测试桩调整后 `provision.test.mjs`＋`ci-provision.test.mjs` Linux Node 22 38/38；证据 `dqb-cause-lab/role-marker-red.log`、`role-marker-cp-green.log`、`role-marker-linux.log`。真实 PostgreSQL 验证待运行。
- 记录机制：纯模拟 `cleanup-boundary-repro.{mjs,log}` 证实第二次写文件失败＋回滚连接失败后，两库已创建但文件仅含一份句柄；指定夹具文件缺失时无环境句柄仍返回 0。均违反当时已批准 Canonical 的可重试回收记录／缺失硬失败义务；PA-008 将该绝对回收承诺调整为预留身份、可安全重试已确认对象及人工核实未确认对象；下方另记录后续实现及验证。该次模拟未连接真实数据库。
- 本轮最终同次四 CP、C4、仓库全量脚本与资源回收尚未执行；预分配 run id `2dae2320-700f-4d7c-8a03-b6182736089f` 未运行且候选 overlay 已过时。此前选定历史 run 的成功不替代最终验收。

> **验收勘误（2026-11-20）**：run `fc71831b-6758-496e-a42d-d069c85644c5` 的 CLI 结果确为 4 CP 通过，Linux 重建环境的 C4 确定性检查为 9/9；但 CP-DQB-003 的执行脚本 `scripts/aifi45-disposable/frontend-quality.mjs` 不在该 run 的冻结输入清单中。其当前解析逻辑在已识别允许文件的失败时，可能放行同时出现的异常退出或未解析错误；已有 clean 基线日志出现 `Unhandled Errors` 与允许文件失败并存。故下文“无集外失败”“前置齐备”不足以证明完整验收，须补齐执行脚本冻结和失败识别后重验。已知红按批准的文件级口径，不证明这些文件内不存在新回归。此前将 CP-DQB-004 的失败归因为 dev 栈负载退化并称已修复的结论未经完整失败日志证实；生产栈同次运行通过仅证明该次结果。C4 当时只检查到 1 个已登记切片，S2–S4 在其后登记；旧 S1 登记不能单独证明修订后的切片验收。

> 日期：2026-11-19。候选：`../multica-delivery-quality-build`，基点 `0c47c67e7e930ba7d28d4e6efd795e1e3741ecaa` + 本 change 未提交 diff。证据目录：`D:/multica-trim-quality.o41bVk/`。选定 run：无；以下结果来自不同范围的执行，不合并为正式 CP，未测覆盖率。

## PA-005 定向验证（不替代正式同次 run）

- 旧判定逻辑的定向 RED：8 项中 4 项失败，分别复现混合失败、未处理异常、异常退出与不完整结果未被拒绝；记录 `dqb-pa005/red.log`。
- 修复后：Linux Node 22 `node --test scripts/aifi45-disposable/frontend-quality.test.mjs` 9/9 通过；受控 `pnpm` 子进程的全通过、清单内失败返回 0，混合失败、未处理异常、信号退出返回 1；记录 `dqb-pa005/linux-unit.log` 与 `linux-cli-*.log`。
- 用已留存日志验证解析：候选已知红失败日志被接受；clean 基线的未处理异常及先前截断日志被拒绝。真实同次 run 和覆盖率未执行/测量，不据此声称整体验收通过。

### PA-005 后的 C1 定向修复（任务 2.22–2.24、3.5）

- 配置修复后，`stdd config models --format json` 返回 configured/schema 1。当前三路：代码 `OpenAIPersonal/gpt-6.2-sol:high`（会话 `01a1f6f5-f46e`）、测试/配置 `Gobao/qwen4-max:xhigh`（`01a1f6f5-f479`）、文档 `GB-JP/deepseek-flash:high`（`01a1f6f5-f462`）；实际后端模型元数据未由宿主返回，标 unknown，不以思考长度推断。三路均已返回，发现见下。
- **前端**：新增反例先在旧实现上 3/9 失败，复现嵌套同后缀路径、Unhandled Rejection 和缺终结摘要的漏判；修复后 9/9（`dqb-pa005/review-red.log`、`review-green.log`）。锁定 Vitest 4.1.0 的最小真实失败运行确认 `Test Files`/`Tests`/`Duration` 摘要格式（`reporter-example.log`）；旧 formal 日志没有 Turbo 汇总，是截断后的实际 fail-open，而非仅理论风险。
- **私有进度**：真实 `ReportProgress` 的新回归测试先显示 owner 空而 recipient 有值；从同一已解析 creator 填 owner 后，私有/共享/未知 owner 三路径定向通过（`progress-red.log`、`progress-green.log`）。路由未知 owner 丢弃规则未改。
- **回收与 GOFLAGS**：新回收负例先复现错配文件、up 回滚失败仍删文件、遗留角色重试三个缺口；修复后 ci-provision/provision 37/37（`cleanup-red.log`、`cleanup-green.log`）。真实 PostgreSQL 的部分回收检查由最终同次环境执行，不重复启动服务。skip 范围反例先红后绿 31/31，既有后端流仍为 5 包/20 skip（`skip-red.log`、`skip-green.log`）；shell/Node 接线断言覆盖 GOFLAGS 有无两种输入与 admin/agent 隔离。
- **文档**：Gate 1 提案已同步既有已批准的范围、20 skips 和六文件例外，避免与 Gate 2 规格相反；仅补台账 pin/404 负例及过时状态，不新增权限或业务承诺。S3 将在最终 run 后按新增 checker 测试重新登记。结构增量通过既有 CLI 在最终 run 生成；结构索引合并仍为用户可选项，未擅自初始化。
- 上述定向证据不替代最终同次 run。旧 `fc71831b` 的 4-pass/C4 只保留为历史事实。

### C1 定向复核再发现与整体方案（PA-006）

- **前端误拒（实证）**：锁定 Vitest 4.1.0 对一个断言失败＋afterEach 抛错的测试输出 `Failed Tests 1` 但两条 `FAIL`（`dqb-pa005/multi-error.log`）。原检查器 `failures.length === expected` 会误拒清单内合法失败。修为 `failures.length >= expected`（每个失败至少一条 FAIL，多错误更多），保留终结摘要与 header/footer 一致性检查；同合同实现修复，仅 Gate 3。
- **回收同根缺口（实证代码路径）**：环境句柄与持久文件分裂——up 写文件后首个 appendEnv 与回滚均失败时无已发布句柄，down 无法重试；文件/夹具句柄属 A 而环境主库句柄属 B 时，现有匹配只查不重复，会删 B 主库＋A 夹具并删 A 文件、泄漏 A 主库。整体方案：夹具文件作唯一持久记录（`fixtures` 映射＋`handles` 主库/夹具无密码句柄），up 随创建增量写入，down 只读文件句柄、逐库重读 marker、全部成功才删文件；删除环境句柄匹配与 FIXTURE_HANDLES_ENV，isolated_db.go 只读 fixtures 字段。不逐异常加检查，净删匹配机制。属 D2-B 机制修订，需 Gate 2。
- **PA-006 定向验证**：`dqb-pa005/frontend-final.log` 10/10、`cleanup-final.log` 37/37、`ci-scope-final.log` 1/1、`skip-green.log` 31/31；`dqb-pa005-final/live-cleanup.log` 记录真实 PostgreSQL foreign marker 拒删、owned role 删除及重复 no-op。上述定向结果不代替同次四 CP 验收。
- **台账更正**：基点 `execution_start_claim_test.go` 的 empty_authenticated_daemon 旧断言为 403（非 409）；#364 应记外部 daemon 409→404、空身份 403→404。
- **提案同步**：C1 补已批准的 hosted regular 包级串行；success_criteria 展示六文件级例外（不证明清单内无新回归）；C3 改为已采用 pin。不新增授权。后端 spec Human View 经官方 scoped 渲染器重生（`canon generate --all` 被无关预存坏 YAML 阻塞，单 change 命令仅渲染 proposal）；canon verify 2/2。

## 同次 run 51c2571d（3/4 CP，CP-003 红）及独立诊断

- run `51c2571d-eafd-4184-ada1-0f7e4311ad5e`（job 03b9fce4df85341c，非 root Linux、同 pin Tools、Git2.45、本轮迁移主库＋七夹具）：**CP-001 PASS、CP-002 PASS、CP-004 PASS（E2E 1 passed）、CP-003 FAIL exit1**。regular 24579 pass/0 fail/20 skip，admin 3/3，agent package pass（3117）。资源回收 `0|0`、fixture/resource cleanup exit0、无残留容器（失败路径回收亦正确）。structure delta 已生成；切片/C4 因 verify 失败未执行。证据：`dqb-pa005-final/`、run 目录 tc-evidence.json。
- **独立候选复现**：`dqb-frontend-diag/frontend-diag.log` 报 `failure outside known-red: common/date-only-picker.test.tsx`；Views 8 文件失败/669 通过，其中清单外 `date-only-picker.test.tsx` 与 `custom-property-picker.select.test.tsx` 均为 `Test timed out in 5000ms`，其余 6 个为已批准例外文件；无未处理异常；Turbo 仅 Views 失败（6/7）。候选未直接修改两个清单外测试文件。正式 run 的完整输出未留存，不能据此断言它因同一原因失败。
- **对照与限制**：clean 基线 `0c47c67e7` 的一次全量运行出现六文件内的超时、断言失败及清单外 `data-table-resize.test.tsx` 未处理异常，没有出现上述两个清单外文件的失败。该基线已包含此前二开，并非纯上游。隔离 A/B 的 170/170 仅覆盖四个其他文件（见下文 Linux Views 四文件隔离），不能证明清单外两文件预存失败或排除候选的间接影响。
- **纯上游与串行对照（诊断，非正式同次证据）**：Linux Node 22.23.5、pnpm 10.28.2、16 逻辑 CPU；纯上游 `ff41e7a77` 的 `pnpm test` exit 1，记录到六个既有例外文件中的超时和其他失败，Views 终结摘要未留全（`dqb-cause-lab/upstream-test.log`），证明部分同类失败在纯上游即可观察到。相同候选 overlay 的默认并发诊断出现 8 文件/22 测试失败；包级串行 `pnpm test --concurrency=1 --continue=always` 完成 7 个任务（6 成功、Views 失败），Views 677 文件中 3 失败/674 通过、10 测试失败/8629 通过，失败均在既有清单内且无未处理异常；底层命令 exit 1，现有 `assessTestRun` 评估为通过（`dqb-cause-lab/candidate-serialized.{log,exit}`、`candidate-serialized-assess.txt`）。这一次对照支持资源竞争假设，但不证明因果或可重复绿。早先 `VITEST_MAX_WORKERS=2` 对照因 Turbo 严格环境过滤未传入 Views 进程而中止，无有效结果。
- **结论**：独立默认并发复现中 checker 正确拒绝清单外失败，符合 SC-DQB-CCF-001；固定六文件例外无法保证每次全量验证通过。纯上游与叉仓对照证明部分异常先于本次候选，不足以排除候选间接影响或确定所有失败的共同根因。
- **PA-007 实现定向结果**：检查器真实入口的参数测试先红（预期参数缺失，10/11）后绿（11/11）；同一测试文件在 Linux Node 22 11/11，既有混合失败、异常、清单外失败反例通过。证据：`dqb-cause-lab/pa007-red.log`、`pa007-green.log`、`pa007-linux-unit.log`。此结果不代替最终同次四 CP。

## 一、定向结果

| 范围 | 结果与证据 |
|---|---|
| TC-DQB-001 脚本与接线 | `dqb-fixtures.ZtwQU1/provider-final.tap`：29 过、0 失败/跳过/取消，含七库供给、迁移中途失败回收、数据库名冲突不删除既有库。`dqb-fixture-wiring-green.log`：regular/admin/agent 次数、缺输入、隔离、失败传播，两个 `test-ci` 信号齐全。`dqb-fixture-hosted-green.tap`：指定 `ci-scope` 生命周期用例 1/1；未触发 hosted。 |
| TC-DQB-002 部分：真实夹具、迁移引用 | `dqb-fixtures-runtime.iXWxHV/`：非 root UID/GID 1000、umask 022、Linux Go 1.27.4 / Node 22.23.5、专用 PostgreSQL 17，固定业务基点及本次 fixture/迁移 overlay。四包均过，40 个测试终结事件通过（含父例）；0 失败/跳过、无 race warning。七个真实夹具实例全部执行，既有非污染与池关闭断言通过；迁移 happy path、orphan/ambiguous 预检及回滚通过。8 个库、8 个受限角色各自独占 CONNECT，fixture 文件 `0600`。`down.exit`、`resource-cleanup.exit` 均 0，`remaining-counts.txt` 为 `0｜0`。此前 `dqb-fixtures.ZtwQU1/container.log` 记录默认迁移调用缺少路径转换函数而未进入 Go 测试，已修正，失败轮次同样回收至零。 |
| TC-DQB-002 部分：Pi 参数 | `pkg/agent` 的 `TestBuildPiArgs` / `TestBuildOmpArgsOwnsSessionSelection` 定向运行（委派会话 `01a1f188-79b3-73a1-b419-00ee83d5808b`，Windows Go 1.27.1、离线）：原实现三个叶子因 Pi 参数成对重复失败；修复后父子合计 18/18。保留 Pi 顺序与 OMP 发现；未执行 POSIX 进程收尾测试。 |
| TC-DQB-003 前端 | `dqb-fixtures.ZtwQU1/frontend-*.log`：Turbo 强制执行、0 缓存，lint 7/7、typecheck 10/10。首次 `pnpm test` 因 `ui/icons/{glyphs,index}.ts` 的 Windows CRLF 与生成器 LF 逐字节断言不一致；规范化后两份与 HEAD 完全相同。仅恢复这两份文件到原 Git LF 字节、不产生业务 diff 后，项目 `pnpm test` 仍 exit 1（5/7）：ui 16 文件均通过；desktop `scripts/package.test.mjs` 解析错误、`src/main/voice/worker-protocol.test.ts` 的 Qwen3-ASR 路径断言失败；views 未取得完整总结果。见 `frontend-test-lf.log`。 |

## 二、Chromium — 唯一运行历史路径

- `dqb-run-history.9wS5nX/`：未进入浏览器测试，初次 launcher 选错 Windows `bash`，没有将 `MULTICA_E2E_DATABASE_URL` 传入命令；migrate 与 cleanup exit 0。
- `dqb-run-history-shell.Tg2vkM/`：改用已验证接收环境变量的 Git Bash，使用专用 API、Next.js、数据库和本机 Chromium。仅 `e2e/issue-task-history.spec.ts`，0 通过 / 1 失败 / 0 跳过。compact 与 own 断言走过；`:77` 的 `Include sub-issues` 控件在操作时脱离 DOM，60 秒内未得到 subtree 响应。保留 `playwright.log` 和 `error-context.md`；根因尚未确认，不归因为此次图标或后端改动。`cleanup.exit=0`。未重试失败断言、未跑评论路由或其他 E2E。

## 三、后续定向归因（不是全量复验）

| 失败 | 本轮区分结果 | 仍未验证 |
|---|---|---|
| Desktop 语音与打包 | `dqb-desktop-linux-test.FK331e/`，非 root Linux、Node 22.23.5、pnpm 10.28.2、Vitest 4.1.0；使用与候选相同的两个原始测试、原 Vitest 配置和 setup。定向工具依赖装在临时根，未采用项目完整依赖图；前面的安装/配置失败没有执行测试。语音 6/6；`scripts/package.test.mjs` 同样收集失败，0 个测试。Vite 8.0.1 的 SSR 转换在正文 offset 1261 保留 `#!/usr/bin/env node`；直接编译该正文重现 `SyntaxError: Invalid or unexpected token`，只在内存去掉那一行后可编译。仓库中的打包命令均显式调用 `node scripts/package.mjs`，文件 Git mode 为 `100644`。 | 未改打包入口、测试或 lock；未取得修复后断言通过或全项目 Vitest 结果。临时容器已回收。 |
| Chromium subtree | 原失败日志显示对话框内复选框曾匹配，随后脱离 DOM；最终快照只剩侧栏的同名控件。通过与失败的两轮均访问 UUID 并随后请求规范 issue identifier；`issue-detail-route.tsx` 说明 Web 路由替换会重新挂载页面，`execution-log-section.tsx` 的对话框状态是局部的。规范 URL 替换与打开对话框竞争是首要解释，现有日志不足以确定两者先后。 | 未重跑。只建议在现有 spec 打开对话框前等待规范 URL 就绪，保留原三个网络断言及对话框定位，不能以侧栏操作替代。 |
| Pi/OMP 自然退出 | 原 Linux 流的失败限于 detached tool 的自然 `exit` 与成功留驻后台服务，取消的 `graceful/ignore` 通过。测试子进程继承两条管道；自然退出监视先结束 stdout，`piBackend.Execute` 在调用收尾前等 `stderrDone` 或 10 秒 backstop。`dqb-pi-stderr.19NzKE/stack.log` 在原 `TestPiCleanupDetachedTool/pi/exit` 用例 2 秒诊断快照命中 `pi.go:829` 的 stderr `select`。Go 1.27.1 本机交叉编译、Linux UID 1000、断网无 DB；刻意中断 exit 2，非原用例通过或 race 证据，容器已回收。 | 未改生产收尾、宽限、超时或存活规则。需分别保持活动工具回收与合法后台服务留存，不能靠延长断言或直接取消进程。 |
| Pi 技能身份测试与旧 claim 夹具 | `TestPiSkillDeliveryIdentitySurvivesPreparation` 已走过真实准备响应检查，在 `pi_skill_identity_test.go:85` 序列化整个 `agent.ExecOptions` 时碰到 `OnUsage func(map[string]TokenUsage)`，无法证明后续字段检查。governance 的 claim fixture 向 `daemon_token` 插入时没绑定 `owner_id`；新版 `DaemonAuth` 在无法从 legacy task token 恢复归属时不会给该身份补 owner，`daemon.go` 的运行时绑定检查在 generation 检查前返回保护性的 404。开始用例的外部 daemon 还受到同一运行时绑定校验；不能用放宽权限来找回 409。 | 只核对原日志和代码，未改用例。应先核对受审状态码契约，再用真实 owner 夹具覆盖合法调用者的 stale generation 与外部调用者隔离；保持真实准备响应检查。 |
| 9 条名单外跳过 | 旧 `regular-evidence.log` 与 NDJSON 对应为四个缺 `systemctl` 的 autostart 案例、一个缺 `pwsh` 子例、一个 macOS app bundle 布局案例、三个 subprocess/helper 入口。其他 shell 兄弟子例通过不等于 PowerShell 已验证。 | 未改 allowlist、selector 或测试归属；环境缺件与平台/夹具组织分开处置。 |

## 四、三处修订后的定向结果

- **Pi 身份，任务 2.6：通过。** `dqb-three-point-revision.l83PQ9/pi-identity.ndjson`，Windows Go 1.27.1、离线、不传数据库凭据。唯一选择 `TestPiSkillDeliveryIdentitySurvivesPreparation`，测试和包均终结 `pass`，exit 0。经过真实准备 helper，核对响应、运行时交付记录的身份/路径/内容摘要及空准备清空；不覆盖 Pi/OMP 进程收尾。
- **运行历史，任务 4.2/4.3：通过。** `dqb-canonical-history.PVuEc2/`，新建 API/Next.js/数据库，API 二进制与上轮相同、此次只改 Chromium spec 的规范 URL 等待。一次执行唯一用例，1 pass / 0 fail / 0 skip（7.8 秒）；compact、own、subtree 及对话框控件断言原样执行。迁移、Playwright 及清理均 exit 0，无本轮容器残留。不替代正式同次 CP，不把一次通过当成竞态稳定性证明。
- **Desktop 打包，任务 3.3：通过。** `dqb-three-point-revision.l83PQ9/desktop-vitest.log` 保留去除 shebang 后的失败：Vite `client` 在默认 jsdom 环境外置 `node:child_process`、`node:os`、`node:fs`、`node:path`，随后 `No such built-in module: node:`，0 个用例、exit 1。原文件用 `--environment node` 对照为 30/30（`desktop-node-probe.log`）；文件级 `// @vitest-environment node` 后，常规命令无覆盖参数也为 30/30、exit 0（`desktop-file-environment.log`）。全局配置、选择器及断言未改；通过不替代全项目 Vitest。

## 五、Linux 项目 Vitest

- `dqb-frontend-linux.wfpmvH/` 初次尝试在按锁下载依赖时达到容器 540 秒期限，未执行项目测试；容器已回收。`dqb-frontend-linux-resume.NMkNil/` 用同一归档和单独容器重启安装，非 root Debian、Node 22.23.5、pnpm 10.28.2；冻结安装 exit 0，未改锁或仓库配置。
- 原根命令 `pnpm test`：6/7 Turbo 任务通过、0 cache hit、exit 1。Desktop 89 文件、1,006/1,006 通过，其中打包 30/30、Qwen3-ASR 文件 6/6；原 Windows 路径故障不在 Linux 重现。UI、Docs、Web、Core 通过，保留 UI/Core 各一项原 skip。
- 仅 Views 出错：4 个失败文件（`inbox-snooze-menu`、`issue-detail`、`issues-header.property-filter`、`project-date-pickers`），12 条失败输出，其中 5 条 5 秒超时、7 条长历史虚拟列表断言失败。此轮不能归因于候选，也不能算通过。容器回收已核实；未跑正式同次 4 CP、未触发 hosted。
- Windows 四文件 A/B（`dqb-views-four-files-retry.YQXkHU/`，无数据库，单 worker）不适合归因 Linux 失败：两边均 exit 1；三文件在 Vite 收集时报 `No such built-in module: node:`，另一文件的失败断言均为 `React.act is not a function`，143 条按文件和用例名匹配的失败首行一致。未改测试环境、断言或超时。首次离线缓存不全未执行测试（`dqb-views-four-files.K3ACwI/`）。Git 移除临时 worktree 记录后遭 Windows 长路径，已仅清理经核对可重建的残留，保留对照证据，`long-path-cleanup.exit=0`。

## 六、换 pin 与两项后端修复的定向验证（任务 2.7/2.8/2.9）

- 重签：用户原话「确认重签 Gate 1 和 Gate 2，长程模式」，官方依序重签 Gate 1 `14:02:31`、Gate 2 `14:02:39`（dialog）。pin 改为 `71d05871a3f937f29a7f68fbf5b022741ab242e8`（parsePin 通过）；Pi 自然退出 stderr 期限（pi.go，台账 #363）；两个合法 claim 令牌插入点补 owner（台账 #364）。原精简补丁仍逐字节一致。
- **2.7 换 pin：通过。** Windows Go 1.27.1 `dqb-pin-71d0587.S0MaoH/gitguard.ndjson`：`TestRealRulesPrepareSurface`＋`TestCallerEnforcement` 126 终结事件全 pass、exit 0（含 agent show 现被放行）。同提交 crctl 定向 `crctl-merge-report2.tap`：多条目合并＋report 完整性 12/12、exit 0；caller-contract 全 pass。Linux 非 root `-race`（`dqb-batch-71d0587.o0tMpC/`）gitguard 109 pass、execenv 真实准备 9 pass，均 0 fail、无 race warning。
- **2.8 Pi stderr：通过。** 同 Linux 批次 `pi-cleanup.log`：`TestPiCleanupDetachedTool`、`TestPiCleanupSuccessfulBackgroundServiceSurvives`、`TestPiExecuteReportsRefusedResume` 共 13 终结事件全 pass、0 fail、无 race；原挂起的 `pi/exit` 叶子现通过。未改取消/终止/等待兜底/测试超时。
- **2.9 claim owner：通过（经裁定对齐负例期望）。** 两个合法插入点补 owner 后，合法 stale-generation/ownership/围栏用例到达真正判定。用户原话「同意改这 4 处期望为 404」；按 MUL-8154 binding 掩蔽契约（`daemon.go#daemonRuntimeBindingAllowed`：token daemon_id 与 runtime 不一致或为空 → 404）对齐负例：start_claim 的两个 foreign daemon 与 empty_authenticated_daemon 由 409/403 改 404；terminal 的 changed_daemon×2 与 foreign replay 由 409 改 404；ownership_change_during_start 竞态实测仍走 stale-claim 409，保留原期望（首轮误改 404 已纠正）。拒绝与零写入断言全部保留，不改生产授权。最终 Linux 非 root `-race`（`dqb-claim-recheck2/claim.log`）claim 选择器 54 pass、0 fail、无 race；launch/down/resource-cleanup 均 0，remaining 0|0，无残留容器。中间轮 `dqb-claim-recheck/` 保留 51 pass/3 fail 的归因过程。
- 资源：首批 `dqb-batch-71d0587.o0tMpC/` 专用 PG 为 tmpfs 容器，已随容器移除，无残留 dqb 容器/卷；其容器内 `down` 因 harness 清理 cwd 在 server 子目录报 MODULE_NOT_FOUND（脚本缺陷，非产品问题），数据库已随 tmpfs 销毁。claim 复核轮修正 cwd 后 down 正常 exit 0、remaining 0|0。未触发 hosted、未跑后端全量。
- 后续修订 backlog：用户要求将其余后端红项（chat/presence、handler、service wakeup/telemetry）、Linux Views 四文件、9 条名单外 skip、Pi/OMP 其余收尾记录在案，已汇总于 [pending-adjustments.md](pending-adjustments.md) 「后续修订 backlog」，均不在本 change 范围。

## 七、剩余失败及范围

- [PA-001](pending-adjustments.md)：用户已裁定采用 Tools main `71d05871a3f937f29a7f68fbf5b022741ab242e8` 并接受 agent git show 对现有 5 形状开放；换 pin 和该提交上的定向复验已完成（任务 2.7，见第六节）。七个 fixture 和迁移修复不能单独推导 Go 全量通过。
- 原 Linux 日志的 Pi/OMP 收尾超时及 daemon/handler/governance/`cmd/server`/service 未归因断言、9 条名单外 skip 保留。未提升角色权限、改测试选择、修改 SQL 或加跳过；没有将局部结果写成正式通过。
- `git diff --check` 通过；pin、迁移 SQL、生成图标 Git 内容不变；原精简补丁与保存件逐字节一致。未执行正式同次 4 CP、同 run `ci check-failures`、hosted 或 Git 交付。

## 八、历史 27 文件候选审查（已被后续 PA-005 与 C1 审查取代）

- C3：已逐文件复核当前 27 个业务仓变更（基点 `0c47c67e7`，`git diff --binary HEAD` SHA-256 `9850e9ba391a01cbe3ba64d65f2d4492bb18fa52878b32ac9effa63b832b46f3`）；两个生成图标文件与 HEAD 逐字节相同，不计入差异。未纳入 Pi/OMP 收尾、claim 夹具、Views 失败用例或 pin 变更。
- C1 三路只读评审已返回。CLI 配置、原生请求与会话元数据一致：代码 `OpenAIPersonal/gpt-6.2-sol:high`（`01a1f21c-14c2-73a1-b419-01042ac706f2`）；测试/配置 `Gobao/qwen4-max:xhigh`（`01a1f21c-14d1-73a1-b419-01071af80653`）；文档 `Gobao/deepseek-flash:high`（`01a1f21c-14db-73a1-b419-0108bdfb09bc`）。未采用「缺选模配置」判断：规范入口 `stdd config models --format json` 返回三个有效档位。已修正旧规格备份引用及历史状态措辞；未改受审设计或回执。
- 代码审查发现当前 D1/D2-B 的隔离缺口，均未修：`isolated_db.go` 的映射只核对同服务器和库名，不能拒绝指向同服务器普通库或管理员角色的错误映射；`ci-provision.mjs` 的 `downAll` 会删除未同 up 绑定的路径，空句柄数组也可能不清夹具却返回成功；Make 命令行覆盖可通过 `MAKEFLAGS` 传给子进程，即使 shell 已 unset 原变量（仅用合成占位值验证，不是已观察到正式运行泄露）。这些是已审隔离合同内的缺口，不把它们扩成通用凭据或清理框架。
- 证据审查：TC-001 的 shell 断言会先验证真实顺序、清理与失败退出，再打印两条固定文字；文字不是独立的观测值，旧 S1 登记也不能覆盖修订后的同次结果。TC-002 后端有定向验证但固定 pin 契约仍红；TC-003 lint/typecheck 与 Desktop 有绿证据，Linux 根测试仍 6/7；TC-004 经专用栈定向 1/1，非同次 CP。未改 CP 或改写 traceability / S1 历史记录。
- 5.1 不勾完成：没有选定 run，C4 的正式检查未执行，C1 发现未关闭。最终报告仍缺同次 4 CP 及对账；不以文档审查替代，也不为此再跑已知红的全量。

## 九、backlog 红项根因聚类与 C4 修复（任务 2.10）

- 用户「处理 backlog 里的红项，不要过度设计，不要逐异常打补丁」。只读取证聚类（子代理 `01a1f2a6`，Gobao/qwen4-max:xhigh）表明这些是基线预存、跨子系统的独立根因，不是单一共同原因；详见 [pending-adjustments.md](pending-adjustments.md) backlog C1–C8。
- **C4 已修并验证**：`TestBuildSearchQuery_ProjectFilter` 原断言连续子串被 CR-2026-006/009 的 origin_type 防泄漏谓词打断；生产 workspace+project 过滤语义正确。仅改测试期望容纳防泄漏谓词（`search_test.go`），Windows Go 1.27.1 `dqb-pin-71d0587.S0MaoH/search-fix.log` 通过、exit 0。不改生产、不弱化过滤。
- **C1/C2 已修并活库验证**（`dqb-c1c2-verify/`，非 root Linux `-race`，专用一次性库）：C1 仅测试夹具——`chat_submission_contract_test.go` 用 `NewRouterWithOptions`＋`ModelCatalogCache.Put` seed 真实 catalog，使 CR-2026-056 发送校验可解析，不改生产/不弱化校验；C2 生产修复——迁移 709 CASCADE→SET NULL 后 teardown 显式删 system carrier 的 private session（保留 project_shared Discussion，FR-21）、`DeleteChatSession` 容忍 NULL agent（`runtime_teardown.go`、`chat.go`、新 query `DeleteChatSessionsBySystemRuntimeAgents`）。handler-delete 2 pass、chat-submission 5 pass、0 fail、0 race，down/资源 0、remaining 0|0。台账 #365–#367。
- **C3/C5 已修并活库验证**（`dqb-c3c5-verify/`，用户采纳建议）：C3 核实 `isChatPrivateEvent` 覆盖 chat:*（全部）与 task:message（transcript）、lifecycle 无内容后，删合并残留的 CR-2026-008 `ChatSessionID != ""` 拦截块，恢复 MUL-8374 lifecycle→workspace 扇出，内容隐私仍由上游 creator-private 守住（`listeners.go`）；C5 保留 CR-2026-004 FR-4 收紧授权，cancel 测试对齐为非 originator 成员 403、owner 200、保留 outsider 404（`private_project_test.go`、`private_project_task_scope_test.go`），不改生产。listeners 72 pass（含 privacy）、private-cancel 4 pass、0 fail/0 race，资源 0|0。台账 #368–#369。
- **C6 已修、C7/C8 隔离重跑通过**（`dqb-c6c7c8-verify/`）：C6 恢复 `issue.go` createOnce 中丢失的 MUL-8161 member delegation 记录块，活库 -race service telemetry 4 pass，不改测试（台账 #370）。C7/C8 隔离重跑 service 4、handler 10 个终结 pass；迁移 004 存在 runtime 级 CASCADE，跨包夹具干扰是待验证假设，不能由隔离通过推断全套失败根因或产品正确。
- **Linux Views 四文件隔离 A/B**（`dqb-views-ab/`）：同 Linux 环境只跑四文件，clean 与 candidate 均 170/170 pass、0 fail；原全套仍有 12 失败。隔离通过不能确定全套失败根因或排除候选影响，须保持断言并继续完整验证。
- **regular 包级串行已实施**（任务 2.17，台账 #371）：Makefile test-ci 与 hosted backend-tests 的 regular 子进程追加 `GOFLAGS=-p=1`（保留已有值）；admin/agent/普通 make test 不变。`test-go.test.sh` 与 `ci-scope.test.mjs` 接线断言通过。尚未跑正式全套。
- **隔离缺口重判与 downAll fail-closed 已实施**（任务 2.18，台账 #372，Gate 2 重签 18:09:15）：用户裁定个人使用、仅防人和 agent 误操作。三项评审缺口重判后仅保留 downAll fail-closed（夹具文件存在⇒句柄非空否则硬失败、文件仅成功清理后移除）；撤销夹具映射前缀检查（可信 producer 不产生该输入、现有检查已覆盖）与 MAKEFLAGS 回归（Win/Linux GNU Make 4.3 实验已封闭、现有测试已覆盖）。`ci-provision.test.mjs` 30 pass 含新用例；旧自动生成 spec.md 逐字节保全。尚未跑正式全套。
- 不 unilateral 改隐私/授权，不逐测试翻断言。本轮未跑后端全量/hosted/正式 CP。

## 十、最终候选 C1 三路评审与正式 CP（49 文件）

- **C1 三路评审**（最终 49 文件候选，配置档位）：代码 `OpenAIPersonal/gpt-6.2-sol:high`（01a1f42b-8afb）、测试/配置 `GB-JP/qwen4-max:xhigh`（01a1f42b-8b0a）、文档 `GB-JP/deepseek-flash:high`（01a1f42b-8b15）。旧 27 文件评审作废。
- **发现处置**：
  - 高（测试评审）：C3 删块后 `task:progress`（Summary 自由文本＋ChatSessionID，ReportProgress 注释明说 CR-2026-008 per-user）不在 isChatPrivateEvent→私聊进度广播 workspace。**已修**：isChatPrivateEvent 纳入 task:progress，补私有＋无 owner 丢弃用例；task.go lifecycle 陈旧 per-user 注释更正为 MUL-8374 content-free workspace。listeners 定向 -race **75 pass/0 fail**。task:failed error 经 redact＋projectOutbound 剥离核实安全（台账 #375）。
  - 中（测试评审）：frontend-quality.mjs 忽略 pnpm test 退出码，崩溃/OOM 无 FAIL 时 fail-open。**已修**：status≠0 且 fails 空→硬失败（#375）。
  - 中（代码评审）：ownership 2 条 skip 行号「有误」——**驳回**：grep 实证 :160/:149 正确，评审声称的 :28/:44 反而错。
  - 中（代码评审）：test-ownership.mjs check 不验 allowed-skips 测试存在——预存工具缺口，非本变更引入，记已知问题不扩范围。
  - 低（文档评审）：design-adjustments 旧快照、tasks 2.10 尾部交叉引用陈旧——**已更新**。其余低风险提示记已知。
- **正式 CP 实质结果**（完整 Linux 环境，49 文件前的 47 文件候选）：CP-DQB-002 `make test-ci` **exit 0**（dqb-formal-backend7：regular 24571/0、admin 3/0、agent 34/0，ci evidence OK 5包/20skip，admin OK 3，回收 0|0）；CP-DQB-003 `frontend-quality.mjs` **exit 0**（dqb-frontend-formal：lint 7/7、typecheck 10/10、Vitest 无集外失败）。隐私修复后 listeners 75 pass。
- **正式同次编排**：CP-DQB-001 已经 stdd agent verify PASS（run 0784b5e0，证据入记录根）。stdd run-id 按调用绑单 task 不可复用→单次 verify（不带 --cp）执行全 4 CP，需全工具链 CI 容器。全 CI 镜像（Go1.27.4＋Git2.45＋Node＋pnpm＋playwright＋Chromium＋stdd）构建时预备 run-id fe30d5ba，含容器内 E2E 栈。该 run 后续实际结果为 CP-001 PASS、CP-002 FAIL exit 2、CP-003 PASS、CP-004 FAIL exit 1；未形成最终同次验收，详见其 `validation/runs/fe30d5ba-86ca-41a8-9310-6779d9e81796/agent-verification-report.md`。
- **全 CI 同次 verify 迭代（run f6456a0d）**：单次执行全 4 CP，**CP-001/002/003 正式 PASS**（CP-002 非 root regular 24574/0＋admin 3＋agent pass，ci evidence OK 5包/20skip）；CP-004 E2E 容器内 FAIL。逐层修复 harness：NODE_PATH（pg 驱动）、去 --internal（pnpm 需外网）、非 root 切换（root 下 TestRunTask_* 失败）、git safe.directory（/record dubious ownership）、Next.js cwd（apps/web）。CP-004 完整错误：`browserType.launch: Executable doesn't exist at /work/home/.cache/ms-playwright/...`——镜像构建 Chromium 装 /root/.cache，非 root 找 /work/home/.cache。**修复**：harness 复制浏览器到 /opt/ms-playwright＋PLAYWRIGHT_BROWSERS_PATH（探针验证非 root Chromium 启动 OK）；候选业务代码零改动。最终同次 verify（新 run-id）重跑中。**历史快照**：此句仅指当时进度；后续结果见下节及各 run 目录，并非当前运行状态。

- **历史 run 补记**：`validation/runs/bd924a2a-57ce-4d55-bbeb-696fc27c6f41/agent-verification-report.md` 与 `validation/runs/4b39ed7b-ccb0-4a84-8955-7db20eb583ae/agent-verification-report.md` 均记录 CP-001/002/003 返回 PASS、CP-004 FAIL（exit 1）；其 CP-003 使用历史检查器，不能当作当前有效验收。此处只补录报告结果，不推断 CP-004 的失败原因。

## 十一、历史同次编排（run fc71831b，4 CP 返回通过，不足以验收）

- **单次 stdd agent verify 执行全 4 CP，Results: 4 passed, 0 failed**（verify exit 0，remaining 0|0）：
  - CP-DQB-001 接线：exit 0，三信号齐全。
  - CP-DQB-002 后端：`make test-ci` exit 0，regular 24574 pass/20 skip/0 fail＋admin 3＋agent pass，`ci evidence OK: 5 required package(s), 20 declared skip(s)`＋`admin evidence OK: 3`。
  - CP-DQB-003 前端：旧 `frontend-quality.mjs` exit 0，但脚本未冻结，且混合异常与不完整输出识别不足；不能据此证明无集外失败。
  - CP-DQB-004 E2E：exit 0，运行历史 1 passed。使用 Next.js 生产构建；此前 dev 栈失败的具体原因未由完整日志确认，不声称已证明修复。
- **C4 check-failures（同环境 Linux 容器跑，解 CRLF 哈希摩擦）：9/9 通过、0 错误**，TC 当前执行覆盖 4/4 (100%)。CLI 确定性子集 a/d/f/g/j/k/l＋TC 覆盖全过。
- **C4 人工项处置**（C1 三路评审＋主会话分析覆盖）：(b)scope_creep——变更均在声明范围（D2-D 平台 skip/known-red 经 Gate 2 重签）；(c)cascading——隐私回归 task:progress 已修并补测；(e)tool_misuse——无；(h)content_quality——文档评审无高/中风险；(i)instruction_decay——长程中纠正子代理虚构证据、误判（均记录）；(m)agent_cp_failure——4 CP 均含可区分观测值且实测通过；(n)cross_system_mismatch——code/agent 两轨一致（文档评审核实）。
- **切片证据**：S1 1/1(new_tests 3)、S2 2/2(3)、S3 1/1(1)、S4 1/1(0，诊断复用原 spec) 均登记 done。
- **冻结输入一致性**：stdd agent verify 与 ci check-failures 均在同一 Linux 容器环境执行（业务仓 LF），4807 输入哈希一致；host Windows CRLF 会致哈希不符，故 C4 须在容器跑。

> **历史勘误**：以上四条保留当时记录，现未定位可独立复核的 C4 原始产物，不作为当前候选的同 run C4／冻结证据。CP-003 检查器当时未冻结且判定不完整，(m) 的“实测通过”不能视为有效验收；PA-010 的范围、内容和安全问题须重新处置。S4 修改了既有 E2E，作为实现切片的零新增测试问题尚未解决，不能仅按原文“诊断”通过。
- **Gate 3 前置不齐备**：上述 CLI 通过是历史记录，但 CP-003 检查器未冻结、判定不完整，C4 仅覆盖当时声明的输入/切片。当前候选必须取得新同次 run 和有效切片证据后再请求 Gate 3。
