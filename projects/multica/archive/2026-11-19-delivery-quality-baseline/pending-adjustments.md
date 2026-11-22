# 待裁定调整 — 交付质量基线

## PA-012：Linux 证据与 Windows 业务工作树的 Gate 3 判定不一致（Gate 3 前置问题已解决）

- 用户已确认 `c7d6ab92-0988-46a8-a526-4cad1e5322e2` 的 Gate 3；Windows CLI 因当前输入与冻结输入原始字节不一致而拒绝，未签发回执。官方 `_snapshot` 逐文件对照显示 4,710 处均为 CRLF/LF 字节差异，路径集合无增删，规范化后均一致。
- 另有独立路径问题：该 run 的四条命令实际 `cwd=/work/multica`，官方 `_judge_automatic` 要求与当前项目根字符串完全一致，Windows 路径不同，因此仅修换行仍不能验收。将相同候选在 `/work/multica` 只读重建、记录根只读挂载时，官方证据判定器验证四项通过、无问题；这不是 Gate 回执。
- STDD 已将已保留 run 的 Gate 3 证据审批与后续业务提交绑定分开：当前环境的 Gate 3 只读前置检查已通过，无需修改工作树或冻结证据。先前拒绝保留为历史；截至本记录更新仍未签发 Gate 3 回执。实际业务提交须在独立授权后由 `bind-commit` 对照冻结范围和内容验证；此前不得声称候选或提交已通过绑定。`resolved: true`。

## PA-011：对齐两条既有脚本断言（Gate 2 已重签）

- **事实**：非 root Linux 锁定依赖就绪后，`6be2a648-685b-4414-bf7b-7bc77a8a8ca6` 的 `pnpm test:scripts` 为 812 通过、2 失败、0 跳过。`tools-pin.test.mjs` 仍期待旧 SHA `7a0a2ab`，`test-ownership.test.mjs` 仍期待原 11 条；候选配置分别符合已批准的 D2-A 和 D2-D。四个 CP 未启动；该次回收为 `0|0`。
- **处置**：只更新这两个断言的预期值（固定完整新 SHA、20 条精确用例名），保留其格式、理由、可解析性等检查。两文件补入冻结清单；不改 pin、允许跳过名单、选择、质量/CP 通过标准或提案/规格。用户确认完整差异，CLI 于 2026-11-21T09:51:07 重签 Gate 2。已按上述范围实施（定制台账 #392–393）；`ea270ddf-5e2c-4d11-b1a2-82ef63263c40` 的 `pnpm test:scripts` 814/814，两条修订断言实跑通过；PA-011 的具体断言问题已解决。该 run 的 CP-DQB-003 仍独立失败，不得用于 Gate 3，见 PA-010 与测试记录。`resolved: true`。

## PA-010：C1 全候选评审后续（同次验证通过）

- **同合同缺陷**：只读代码评审发现 `GITHUB_ENV` 原始路径在比较前先被词法折叠、实际写入仍用原路径；临时 Linux 文件系统已复现校验目标不相同、实际目标相同，可破坏唯一回收记录。现有前端检查器对声明文件内失败叠加 Vitest `close timed out after …ms` 的输出返回通过；已用现有评估函数及锁定 Vitest 的真实诊断文本复现。两项已按现行合同修复，新增反例先红后绿，定制台账 #386–387；尚未作最终同次验收。
- **入口风险复现**：测试评审指出调用方 `GOFLAGS` 的选测可能漏跑必需测试，而现有对账主要约束必需包。独立临时 Go 1.27.1 包中，`GOFLAGS=-run=^TestWanted$` 使另一个会失败的测试未执行、包仍通过；这是 Go 行为探针，不是项目测试或最终 Linux 1.27.4 结果。非 root Linux 临时目录复用实际 Makefile、以 fake 命令和非秘密哨兵复现 regular 与 agent 均继承 `POSTGRES_PASSWORD`、`PGPASSWORD`，未连数据库。未证明历史 run 发生选测或泄漏真实凭据。已在本地 `test-ci` 清除继承的 `PG*`／`POSTGRES_*`，真实 Make 配方的哨兵回归先红后绿（#388）。
- **受审文档与范围**：用户曾单独同意部分 claim 负例按现行掩蔽契约改为 404，但原 `design.md`／`test-plan.md` 仍写拒绝断言原样；共用 token helper 给刻意非法 daemon 令牌补了 owner，与已审设计不一致。已恢复原负例 owner 边界，不改生产代码和状态断言（#389）；本轮设计和测试方案同步先前单独裁定的 404 期望及保留的 409 并发负例。历史 C4 结论及 run 归属须如实标明，不能代替新同次 C4。
- **任务 2.19 范围裁定**：用户回复「保留并补入提案」。保留台账 #373 的四个既有 daemon／execenv 测试文件改动，Canonical 提案 C2 与 Human View 明列范围，设计 D2-C 记录具体对齐。四个文件已包含于 `test-plan.md` 原有 `server/internal` 冻结目录；测试选择和验收不变。该回复是范围决定，不是对本次文档差异的 Gate 1／2 重签；PA-010 其余事项不因此解决。
- **本轮方案（已重审、已实施）**：①本地 `test-ci` 三组固定 `GOFLAGS=-count=1 -mod=readonly`，只给 regular 追加 `-p=1`；在现有 Make 回归注入选测参数证实不会影响三组，不增 flags 解析器，不改普通 `make test` 或 hosted CI。②S4 把现有等待与定位按钮放入测试专用小函数，Node 回归验证精确规范路径和等待顺序；CP-DQB-004 先执行该测试，再执行原 Chromium 用例。冻结新增的两个测试资产。旧 `new_tests=0` 是历史登记；新增测试实际通过后才通过 CLI 更新 S4。保持单条 Chromium、原断言和六文件例外。
- **执行／审批状态**：PA-009 已经重签，不能视作 PA-010 的决策或批准。用户审阅任务 2.19 的六文件差异后明确确认重签；STDD CLI 已分别记录 Gate 1（2026-11-20T22:51:56）与 Gate 2（2026-11-20T22:51:57）回执。上述重签仅涵盖任务 2.19。现轮变更影响设计与验证方式，不改提案；用户确认展示的完整差异，CLI 于 2026-11-20T23:12:55 重签 Gate 2。两项实现与非 root Linux 定向验证已完成（#390–391）；首次正式同次运行 CP-001/002/004 已通过并清理，S4 已通过官方 CLI 记 `1/1, new_tests=1`；CP-003 的 Views 未处理错误仍判红（本次原始栈因检查器退出丢失）。保留退出码并修复日志写尽（#394，先红后绿）；仅针对前端继续归因，不重跑已过 Go 和 Chromium 作诊断。最终 `c7d6ab92-0988-46a8-a526-4cad1e5322e2` 四 CP 同次通过，C4 14/14 检查、回收 `0|0`，本轮未复现未处理错误；原错误原因未确定，历史失败保留，判红规则不变。`resolved: true`。

## PA-009：补齐既有候选文件的冻结清单（Gate 2 已重签）

- **发现**：对照历史 run 的原生 `inputs` 与候选实质改动，`scripts/aifi45-disposable/provision.test.mjs`、`scripts/aifi45-disposable/ci-evidence.test.mjs` 及定制台账 `CUSTOM-LEDGER.md` 已在候选内，但不在已批准的冻结清单中。前两者是现有脚本测试资产；前者的三行 fake role marker 适配维护原有用例，后者补充现有 skip 对账负例；台账是项目必需的定制记录。
- **修订草案**：仅在 `test-plan.md` 测试资产表注明 `provision*.mjs`，并将上述三条现有文件路径加到项目输入冻结清单；不更改测试选择、业务承诺、安全不变量、接受风险或证据通过标准。依据 revision-rules §1/§2，受审 test-plan 字节变化须重审 Gate 2，完整差异已准备供用户审阅；不请求 Gate 1 或代签。
- **执行状态**：用户回复 `重签 delivery-quality-baseline 的 Gate 2`，CLI 于 2026-11-20T20:48:41 记录 `confirmed_by: dialog` 与该原文，官方状态 Gate 2 current；调用者字段按工具默认记录 `confirmed_actor: ai`，未手改回执。冻结清单修订已批准，`resolved: true`；C1 后续缺陷与最终同次四 CP 仍须完成，不等于 Gate 3 或交付。

## PA-008：回收记录写前身份及缺失判定（已重审，同次验证通过）

- **触发／事实**：C3 对照已批准 `SC-DQB-CBE-001` 发现回收记录未满足合同。纯模拟复现：第二次写夹具记录失败且回滚连接失败时，两库已创建、文件仅记录一个；显式提供夹具文件路径而该文件缺失、环境无句柄时，`downAll` 返回 0。前者丢失可重试身份，后者与“文件缺失硬失败”直接冲突。复现脚本与日志：`D:/multica-trim-quality.o41bVk/dqb-cause-lab/cleanup-boundary-repro.{mjs,log}`；未连接真实数据库。
- **同边界已修**：数据库 marker 正确但角色 marker 不匹配时原实现会删除角色；共享删除入口现先分别校验库与角色，当时定向 38/38；后续隔离真实 PostgreSQL 边界验证已过，最终同次验证待执行。台账 #380。另修正共享讨论路由的两处注释和新增代码注释的英文规则，不改路由。
- **用户决定**：`change -- 接受：遇到归属不明的资源，宁可保留并报错，也不自动删除。避免重复校验和无意义兜底。` 此为安全取舍决定，不是对尚未展示的 Gate 修订差异的审批。
- **同步方案**：每次创建前写入无密码身份预留，区分 `reserved` 与 `confirmed`；记录用同目录受保护临时文件完整写后原子替换，首次独占创建且写成前不得创建资源。显式 `--fixtures` 的记录缺失、无效或必需身份缺失一律失败，不消费环境句柄；未传 `--fixtures` 的 E2E 路径保持原合同。已确认对象重读库／角色 marker 后可回收；仅预留者一律保留记录并失败，不因相同 marker 或暂未发现对象而自动删除或清除记录，可能须人工核实。范围为单任务顺序使用本轮记录，不支持旧记录可能仍被使用时人为复用 nonce；不防恶意篡改，不承诺断电后持久性。
- **实施与验证状态**：用户确认 Gate 1/2 重审，已分别经 STDD CLI 重签。供给／回收入口及回归已实施，台账 #381；C1 发现的端点错配、记录内身份缺失和凭据／输出路径问题在共同边界修复，台账 #383。非 root Linux 最新定向 66/66，含双故障保留身份、未确认资源零删除及目录别名拒绝。隔离真实 PostgreSQL 已验证未确认保留、外来 role marker 拒删和部分回收重试，资源余量 0|0；后续 C1 五类同合同缺陷及软链接别名变体的七个反例已先 RED 后 GREEN，连同 CI-scope 三个测试文件非 root Linux 最新 144/144、0 取消／跳过，台账 #384–385；最终同次 `c7d6ab92-0988-46a8-a526-4cad1e5322e2` 再次验证真实库拒删／部分回收；CP-001 的拒绝信号通过、数据库与角色计数均为 0、资源回收 exit 0。`resolved: true`；此为验收证据，不是 Gate 3 审批。

## PA-007：前端全量测试包级串行（Gate 2 已重签，同次验证通过）

- **用户原话**：「change -- 从行业专家的角度给出你整体的解决方案并修订，然后持续完成剩余待完成项，方案以最小完整为目标：不做过度设计，不按异常逐个打补丁，不以检查数量为目标；先界定有限、可验证的保证，再用尽可能少且职责清晰的检查支撑这些保证。避免重复校验和无意义兜底。」此话授权本轮方案与修订，不代替对修订后 Gate 的确认。
- **事实**：正式 run `51c2571d` 的 CP-003 原始输出未留存，原因未知。候选默认并发独立复现 8 个 Views 文件失败，其中 2 个在既有例外外；纯上游 `ff41e7a77` 独立全量运行也观察到既有六文件的超时及其他失败，但终结摘要未留全。原 170/170 是另四个文件的隔离 A/B，不证明集外失败的来源。
- **方案及对照**：保持 `pnpm test` 的测试范围、断言和超时；检查器仅对该调用追加 Turbo 的 `--concurrency=1 --continue=always`，包级串行且失败后继续其他任务，最终仍按原规则对账和传播失败。候选独立对照完整执行 7 个任务，Views 3 文件/10 测试失败均在既有六文件内，原检查器的结果评估为通过（底层 `pnpm test` exit 1）；没有未处理异常。默认并发与串行各为一次独立样本，支持但不能证明资源竞争是唯一根因，也不保证日后每次通过。日志位于 `dqb-frontend-diag/frontend-diag.log` 与 `dqb-cause-lab/candidate-serialized.log`；纯上游日志为 `dqb-cause-lab/upstream-test.log`。
- **保证与边界**：六文件例外不变；集外失败、其他任务失败、未处理异常、异常退出与不完整结果仍红。保留 lint/typecheck、hosted workflow 和上游测试/产品；不增白名单、不调超时、不放宽 Turbo 环境过滤。清单内仍可能掩盖新回归，其他进程仍可能争用资源。
- **状态**：`design.md` 和 `test-plan.md` 已同步，业务承诺、Canonical 与 agent spec 不变；用户确认后 Gate 2 于 2026-11-20 15:33:26 重签。检查器参数与真实调用路径测试已实施，新增用例先红后绿，Linux Node 22 定向 11/11。最终同次 `c7d6ab92-0988-46a8-a526-4cad1e5322e2` CP-003 与其余三个 CP 均通过，完整任务与实际结果已记录。`resolved: true`。

## PA-005：前端检查器与同次证据补全（Gate 2 已重签，同次验证通过）

- **用户原话**：「change -- 按此继续。避免重复校验和无意义兜底。」随后「change -- 确认 delivery-quality-baseline 的 Gate 2 修订」完成该轮批准；本轮继续时再次要求避免重复校验和无意义兜底。
- **事实**：run `fc71831b-6758-496e-a42d-d069c85644c5` 的 4 CP 返回通过，但执行 CP-DQB-003 的 `frontend-quality.mjs` 不在其冻结输入中；检查器可能在清单内 `FAIL` 与其他任务失败或异常并存时放行。clean 基线日志实际含超时、断言失败和 Vitest 未处理异常，下文“失败全为超时”“不掩盖新回归”等过强陈述以此勘误及当前 D2-D 为准。
- **修订**：保留用户已批准的 6 文件级例外；检查器和回归测试加入同次冻结，测试覆盖混合失败与异常，测试任务未完整执行、集外失败或未处理异常均不得放行。文件级例外不证明清单内无新回归。不改上游测试、产品、超时或测试选择。
- **状态**：Gate 2 已于 2026-11-20 09:28:00 重签。检查器与回归测试已实施，Linux Node 22 定向 9/9、受控子进程正反例通过；检查器和测试已列入冻结计划。后续 C1 另核实 Vitest 终结摘要、路径精确匹配及创建者投递等具体缺口，见任务 2.22–2.24、3.5；不改已批准的六文件例外。最终同次证据为 `c7d6ab92-0988-46a8-a526-4cad1e5322e2`；检查器及回归已冻结、原始 CP-003 输出及 Views 任务日志齐全。既有 run 留作历史。`resolved: true`。

## PA-001：现有 pin 与非 root 正式 Go 测试的契约不相容

- 状态：**已由用户裁定解决方向**。用户原话「接受 main 中 agent git show 对 5 种形状全开放」「Multica 的 pin 直接改指向 Tools 最新 main 的 71d0587，不再分叉」。新 pin `71d05871a3f937f29a7f68fbf5b022741ab242e8` 取代 `7a0a2ab`；main 已含编排器准备规则与 crctl 多条目合并，原不相容随之消除。换 pin 与在 `71d0587` 上的定向复验已完成（任务 2.7）；此前「保留 7a0a2ab」的决定已被本裁定取代。
- 事实：见 `D:/multica-trim-quality.o41bVk/dqb-nonroot.3tG1Ap/go-regular.ndjson`。基点 `0c47c67e7`、UID/GID 1000、umask 022、Go 1.27.4、Node 22.23.5、一次性 PG/Redis，同 `7a0a2ab57f3f5e2c583c3523bc69d67e7be115c1` Tools。`TestRealRulesPrepareSurface` 要求固定 Rules 未提供的命令形状或调用者区分，`execenv` 也有实际调用失败。Tools 主线含 `6dacbaf` 的后续规则变更；该候选已经定向试跑，但用户决定不采用，候选通过不改变当前 pin 的失败结果。
- 只读核对：本地 `origin/main` 谱系中紧接当前 pin 的候选是 `7a0a2ab → 7345df8 → 6dacbaf`；未见更窄的已发布候选。`6dacbaf` 补了 orchestrator 准备面及对应的 crctl 多规则条目合并；它并非纯兼容更新，`git show` 的调用者从仅 `system-orchestrator` 扩到包括 agent 的 `*`（参数形状未变），同时继承 `7345df8` 的 `crctl report` 校验变化。
- 实际评估：`D:/multica-trim-quality.o41bVk/dqb-tools-candidate.DYuMUc/`；非 root Debian 12、UID/GID 1000、umask 022、Go 1.27.4、Node 22.23.5，断网容器，Multica `0c47c67e7` 与同一完整 `6dacbaf64db69d57fe70c935c0dd640ef00e086d` Tools 干净检出。`TestRealRulesPrepareSurface` 实读 `/work/tools/.../rules.json`：108 个子例＋父例通过，含 27 `agent_denied` 子例和两个 agent `show` 既有形状；execenv 9/9；crctl 合并及 report 9/9，Tools `show` 规则契约 1/1；无失败、跳过或 Go race warning，容器回收 exit 0。未连数据库、未跑宽测、未触发 hosted。
- 影响：`6dacbaf` 的隔离评估只证明已选兼容合同；main 的 rules.json 与 crctl 规则加载解析后与 `6dacbaf` 相同，该部分结论可沿用，但 `71d0587` 另改了 crctl 其他逻辑，Multica 尚未在其上跑过，须按任务 2.7 定向复验。不证明全量 Go 或 `TC/CP-DQB-002` 通过。不用混合版本、规则 stub、弱化拒绝或移出检查达成通过。

## PA-002：并非单一 pin 阻塞；正式运行仍需保留其他失败

- 状态：已分出可直接修复项与需定向诊断项；未改权限、跳过表或业务测试。不能承诺改 pin 即全绿。
- 一次性常规角色 `NOCREATEDB` 下，`IsolatedDB` 直接经所传 DSN 执行 `CREATE DATABASE`，`internal/integrations/lark` 4 个、`internal/service` 2 个及 `internal/testutil` 1 个测试事件明确报 `42501`。Lark 扫全库，部分服务测试也依赖空库全局状态，不能把这些案例合进共享库。建议现有 `ci-provision` 外置建库、迁移和清理，每个需要的案例使用自己的空库与受限 DSN；不引入新 runner 或凭据代理，不改三项 admin owner、不向 regular 传管理员 DSN 或授予 `CREATEDB`。现有 hosted 与本地入口须供给同一夹具合同，修订设计允许 `.github/workflows/ci.yml` 只动现有 `backend-tests` 的夹具供给、凭据隔离与回收接线，不改 job、套件分组、必跑名单和失败判定；Gate 1/2 已重签，供给、接线与真实隔离定向验证现已完成（任务 2.3），尚未执行托管或正式全量。
- 两处有源码与日志共同印证：`server/cmd/migrate/migrate_workspace_seam_test.go` 的八组 up/down 文件仍引用 613–620，当前树同名文件已重编号 689–696；仅拟修测试引用，保留预检与回滚断言。`server/pkg/agent/pi.go` 的 `buildPiArgsFor` 在合并后追加 `PiSkillPaths` 两次，日志出现相同路径成对重复；拟合并为一处带现有 provider 条件的挂钩，保持 Pi 显式绑定及 OMP 原有发现行为。不改迁移 SQL、不碰 legacy change。任务 2.4 已完成并经真实 Linux 迁移测试、Windows Pi/OMP 参数断言验证，见[测试记录](test-report.md)。
- 复用原日志归类：Pi/OMP 收尾报 `timeout waiting for Pi result`；`cmd/server` 同时有 chat 模型配置拒绝和 presence event 缺失，governance 有 `task not found` 的 404，handler 有查不到记录和取消权限的 403，service 有 wakeup/telemetry 断言；这些不是七个夹具的 `42501`，不能跟随夹具或 Pi 参数修复结案。9 条名单外 skip 涉及本机缺 `systemctl`/`pwsh`、macOS 专用路径和仅作子进程入口的 helper；根因未全部确认，不新增 allowlist、调整验收阈值或把超时改成成功。
- 本轮结束：regular 84 包通过、10 失败、12 skip（24,271/270/20 个测试终结事件）；regular、对账均 exit 1（13 问题）；admin 3/3、admin 对账、ownership 均 exit 0；agent 3,107/10/2、exit 1。两道流未发现 race warning，但不是 race 全绿。本轮专用库、角色、容器及网络回收 exit 0；本地诊断，不是同次正式证据或托管 CI。

## PA-003：Linux 前端全量仍不通过；Chromium 已定向通过

- Linux 两文件定向运行曾为语音 6/6、打包收集语法错误。移除脚本 shebang 后不再报语法错误，但 `jsdom` 的 Vite client 外置打包测试的 Node 内建模块，转为 `No such built-in module: node:`、0 测试。用户继续后，用同一文件和 `--environment node` 对照，30/30；只在 `apps/desktop/scripts/package.test.mjs` 使用仓库已有的文件级 Node 注解，不改全局配置、测试选择和断言。常规 Vitest 无覆盖参数时也为 30/30。此修复不改变已审合同，不需改受审材料；不以这个结果替代项目 Vitest。
- Linux 项目 `pnpm test` 6/7、零缓存：Desktop 89 文件、1,006 用例全通过；Views 四个文件出现 12 个失败。失败文件不在本次业务 diff 中，但不能仅凭路径判定为历史问题；不扩大到虚拟列表、日期控件或全局超时。详见 [test-report.md](test-report.md)。
- Chromium 旧失败保留：subtree 操作前对话框曾被卸载。已批准并实施规范 URL 等待；新专用栈中同一用例的 compact、own、subtree 与控件断言一次全部通过，资源回收。该定向问题已有通过证据；正式同次 E2E 仍待执行。详见[测试记录](test-report.md)。

## PA-004：Pi/OMP 收尾与遗留测试夹具不是参数重复

- 单叶栈快照确认 Pi 的 `exit` 路径在 `pi.go:829` 等 stderr，尚未进入收尾；继承管道的已分离子进程是阻塞条件。可送审的最小候选：仅在已观察到主进程自然退出时，让 stderr 与 stdout 共用现有 250ms 读取截止；不动取消、终止、等待兜底或测试超时。风险是迟到的后台 stderr 不再进入本次报告。用原 `TestPiCleanupDetachedTool`、`TestPiCleanupSuccessfulBackgroundServiceSurvives`、`TestPiExecuteReportsRefusedResume` 分别验证活动工具回收、成功后台服务留存与 stderr 拒绝诊断。用户已批准纳入本 change，Gate 1/2 已重签，任务 2.8 已实施并通过三个原用例定向验证；保留上述迟到 stderr 限制。
- Pi 技能身份测试的 `ExecOptions` 序列化已按批准改为直接断言交付字段与清空行为，保留真实 helper 响应的 wire 断言，单用例通过（任务 2.6）；不涉及生产收尾。
- 旧 claim 测试的两个共用插入点（`execution_start_claim_test.go` 的 `request` 与 `execution_task_claim_project_test.go` 的 `mintToken`）均创建无 owner 的 `mdt_`；现有路由绑定先掩蔽为 404，九个治理失败根例观察到同一响应，不表示九个断言都能用同一夹具修复。候选只给本应合法的 token 补对应 runtime owner，使 stale generation 到达真正的判断；刻意外部、空身份、跨 workspace 与零写入断言全部保留，不允许一律绑定同一 owner 或改生产授权、对外状态码。外部拒绝断言若仍与现行契约不一致，另行裁定，不在本候选改期望。用户已批准纳入本 change（任务 2.9）并重签后实施：两个插入点补 owner，合法用例 46 pass。用户另原话「同意改这 4 处期望为 404」，按 MUL-8154 binding 掩蔽契约对齐负例：start_claim 的 foreign×2 与 empty_authenticated_daemon（409/403→404）、terminal 的 changed_daemon×2 与 foreign replay（409→404）；ownership_change_during_start 竞态实测仍为 stale-claim 409，保留原期望。拒绝与零写入断言保留；不改生产授权。最终 claim 选择器 54 pass、0 fail、无 race。其余 chat/handler/service 失败不纳入。
- PA-003/004 仍各有未解决事项。用户「批准，不要过度设计」限定三处，展示材料后「确认重签 Gate 1 和 Gate 2」，以官方命令依序重签；该轮未改 Desktop 测试环境。用户随后要求继续，文件级 Node 运行环境按同一合同修复；未扩大到 Pi/OMP 生产收尾、旧 claim 夹具或其他红项。PA-001 已采用经单独批准的 pin；跳过名单与六文件例外分别按后续用户裁定记录，未在本段擅自扩大。

## regular 套件包级串行（已实施，任务 2.17）

- **原设计**：`design.md` D1 的正式入口与 hosted `backend-tests` 对 regular 使用 `scripts/test-go.sh` 原有包并行，保留分组、selector、失败语义与凭据隔离。
- **用户原话**：「采纳套件隔离方案（串行包 -p 1，或每包独立库）」。选择更小的包级串行：仅对正式 `test-ci` regular 调用及 hosted `backend-tests` 的对应 regular 调用追加 `GOFLAGS=-p=1`，保留既有 GOFLAGS；不影响 admin、agent 或普通 `make test`。包内并行和其他进程不受限制，不宣称根因已确证。
- **原因与影响**：一次 Go 调用内的测试包共享常规库；包级串行消除该调用中的跨包并发，但可能增加总耗时。它不处理 Views 前端全套失败或名单外 skip，完整门禁仍须逐项通过；不改断言、skip、race、证据对账、超时或凭据边界。
- **状态**：Gate 2 已重签（用户原话「重签 Gate 2，并继续 BUILD。避免重复校验和无意义兜底。」）；Makefile、ci.yml、test-go.test.sh、ci-scope.test.mjs 已改并通过接线断言。尚未运行正式全套验证。

## 隔离缺口重判与回收 fail-closed（用户裁定纳入）

- **威胁模型（用户原话）**：「项目是个人使用，不防止恶意破坏操作和故意修改账本，只防止人和 agent 不小心误操作」。据此重判评审提出的三项隔离缺口：
  - **夹具映射前缀检查——撤销**：防的是被篡改／错误夹具文件指向普通库或管理员角色；可信 producer（`ciProvisionUp`）永远写 `aifi45_tmp_<nonce>` DSN，不会产生该输入。现有同服务器／≠共享／无重库／必须绑定检查已覆盖误操作；角色权限是服务端属性、producer 已保证且已测。零新增。
  - **downAll fail-closed——保留（唯一真缺口）**：Make 配方第 360 行 `unset AIFI45_CI_FIXTURE_HANDLES`，外层若忘记在 down 前恢复，`downAll` 只清主库就 `return 0` 并删夹具文件，造成 7 个夹具库静默泄漏＋假成功。修复：夹具文件存在⇒句柄必须非空否则硬失败；夹具文件仅成功清理后移除。marker 拒删外库已在且已测，不动。
  - **MAKEFLAGS 清洗／回归——撤销**：Windows 与 Linux GNU Make 4.3 实验证实命令行覆盖经配方 unset 后，直接子进程与 sub-make 均不可见敏感变量；现有 `test-go.test.sh` 已覆盖误删 unset。零新增。
- **净变更**：1 个生产检查（downAll fail-closed）＋1 个用例；从原拟「2 检查＋3 用例」收缩。属 teardown 安全不变量改动，需重签 Gate 1+2。
- **用户授权**：「据此写同步修订、展示差异、重签实施」。已同步 design.md D2-B、canonical code spec SC-DQB-CBE-001、test-plan.md TC-DQB-001；spec.md 由 Gate 2 重生，agent yaml 命令已含 ci-provision.test.mjs 无需改。
- **状态**：Gate 2 已重签（18:09:15，Gate 1 输入未变仍当前）；旧自动生成 spec.md 逐字节保全于 `dqb-failclosed-revision/`。`ci-provision.mjs` downAll 已改（fail-closed＋成功才删文件，导出 downAll/FIXTURE_HANDLES_ENV），`ci-provision.test.mjs` 30 pass 含新用例。台账 #372，任务 2.18。尚未跑正式全套。

## 正式后端 harness 漏迁移更正与前端上游裁定

- **更正（用户核实指出）**：先前正式 harness（dqb-formal-backend / backend2）漏了主常规库迁移。`make test-ci` 配方本身不迁移；`ci-provision up` 只迁 7 个夹具库、不迁主库；hosted ci.yml:556 有独立 `Run migrations: cd server && go run ./cmd/migrate up`。harness 只 up 就 make test-ci，致用主库的 telegram/lark/daemon/channel 测试撞空 schema。backend2 流实测 **682 条 `relation ... does not exist`**（user 473、channel_reply_delivery 110、workspace 46 等）。故上一轮「后端 262+ 是基线预存功能红项」**误判**：绝大多数是漏迁移的人为失败，非上游功能缺陷也非二开引入。真实基线红项须补迁移后重跑定量。
- **修复**：dqb-formal-backend3 在 source DATABASE_URL 后、make test-ci 前补 `(cd server && go run ./cmd/migrate up)`，保留 Redis 服务与串行 -p=1。backend2 及其 economy 取证结果作废。
- **前端上游裁定（用户原话）**：「前端上游已有的问题不要动」。Views 6 文件 16 失败全是 testTimeout 5000ms（懒加载日历/虚拟列表/tiptap 防抖/Base UI 菜单在 6 包×4 worker 负载下超时），clean 基线零二开改动全负载同样红且多 2 文件，6 个测试文件二开未碰——上游预存时序问题，**本 change 不修**。含义：TC-DQB-003 `pnpm test` 退出 0 在上游 Views 不动的前提下不可达，需后续按 revision 明确上游已知红项的验收口径（不在本轮擅改 spec）。
- **execenv 例外**：30 里有一条 `could not normalize previous uncommitted edits`（git worktree 编辑归一化）属另一类，补迁移后单独看。
- **harness 缺件全清单（对照 hosted ci.yml backend-tests）**：除主库 migrate up 外，还漏①Redis 服务与 REDIS_TEST_URL（hosted env）；②Tools pin 检出与 `AIFI45_TOOLS_ROOT`/`CRCTL_MJS`/`MULTICA_CONTROLLED_SHELL_RULES` 三个 env（hosted 有 Checkout pinned tools 步骤，governance/crosslang 测试 Fatal without them）。backend4 定向补全 Tools env 后 **governance 14＋crosslang_test 3 全消失**（原错误全是 `CRCTL_MJS is required`），证实为装置缺件。
- **真实基线红定量（完整环境：迁移＋Redis＋Tools＋串行）**：backend4 定向跑 daemon/execenv/governance/crosslang 四包，5800 pass/9 skip/**56 fail＝daemon 26＋execenv 30**。daemon：TestRepoCheckout*（HTTP 403 unknown or completed task）、TestConvertSkillsForEnvPreservesBuiltinIdentity（builtin 身份断言）；execenv：TestPrepareLocalWorktree*（could not normalize uncommitted edits）、TestBriefSkillsListIsNamesOnly。候选未碰这些生产代码→上游预存，属本 change 范围。已派 balanced 诊断（01a1f3b8-be37 daemon、01a1f3b8-be48 execenv）。
- **诊断核实与修复（主会话抽查纠错）**：两个 balanced 子代理均虚构关键证据（execenv 谎称 ci.yml:144 core.hooksPath／context.go contextlab；daemon 谎称 repocache/refs.go、skills_for_env.go 路径），经 grep/read 核实不存在，弃用其断言、主会话自诊。真实根因：①execenv worktree 24：local_worktree.go:1746 明说「requires Git 2.40 or later」（merge-tree --write-tree --merge-base），容器 bookworm Git2.39→源码编译 Git2.45.2 派生镜像（Go1.27.4 不变）。②execenv BriefSkillsList 6：生产 CR-2026-070 FR-1 把 skillsRoutingRule 置 Skills 段尾，测试 part1 `want` 漏→补 skillsRoutingRule。③daemon repo checkout 15：health.go:550 activeTaskAuth.Load 是 CR-2026-008 安全门（正确），harness 经 registerActiveRepoCheckoutTask 只填 repoCheckoutTasks 未填 activeTaskAuth→测试补 Store（token mat_repo_checkout_test）。④daemon ConvertSkills 8：生产 fork 8c7e8dd0f 保留 ID/Source/Hash，测试 `want` 漏→补 ID/Source。均同契约仅测试对齐，生产不动；定向 Linux -race 34 pass/0 fail。台账 #373，任务 2.19。backend5 正式全套（Git2.45＋完整环境）运行中。

## A+B 验收口径修订（用户采纳专家建议）

- **用户原话**：「采纳建议，据此写同步修订」。A：9 条平台/helper 合法 skip 登记进 allowed-skips（11→20，附源码行号与触发条件）；B：前端 Views 6 文件声明为上游已知红（文件级），TC-DQB-003 改为 lint/typecheck 退出 0＋Vitest 失败全落在已知红集内。
- **backend5 实测里程碑**：regular 24571 pass/0 fail（56 功能红全清）；make exit 1 仅因 ci-evidence 报 9 条名单外 skip（非功能失败）。economy 子代理曾误报 22 fail，主会话自解析纠正为 0 fail。
- **同步修订**：design.md D2-D＋line17、test-plan TC-DQB-002（11→20）/TC-DQB-003（known-red）、code spec SC-DQB-CBE-002（+9 skip AND）/SC-DQB-CCF-001（known-red then）、agent spec CP-DQB-002（20 declared skip）。属测试选择/验收变化→重签 Gate 2。test-ownership.json +9 为业务仓改动，待 Gate 2 重签后实施。
- **护栏**：名单外 skip 仍红、已知红集外新失败仍红；声明不掩盖功能失败/新回归。上游修复落地后回收 known-red 清单。

## 正式 CP 实质结果（完整 Linux 环境）

- **CP-DQB-002（dqb-formal-backend7，47 文件候选）**：`make ENV_FILE=/dev/null test-ci` **exit 0**。regular 24571 pass/20 skip/0 fail；admin 3 pass；agent 34 pass；`ci evidence OK: 5 required package(s), 20 declared skip(s)`＋`admin evidence OK: 3 ci-admin test(s) passed`。down 0、remaining 0|0。环境：主库 migrate＋Redis＋Tools pin 71d0587＋Git2.45.2 派生镜像＋串行 -p=1。
- **CP-DQB-003（dqb-frontend-formal，47 文件）**：`frontend-quality.mjs` **exit 0**；lint 7/7、typecheck 10/10；本次 Vitest 0 失败（Views 负载 flake 本次未现），“confined to 0 upstream known-red file(s), no new regression”。known-red 机制对 0 失败与集内失败两种情形均覆盖。
- **待正式同次编排**：CP-DQB-001（接线）/CP-DQB-004（E2E）＋stdd agent verify（Linux 执行 4 CP）＋ci check-failures 同一 run-id。stdd record_root 为 Windows 路径、CP 需 Linux，须在装 stdd 的 Linux 容器挂载记录根执行。

## 后续修订 backlog（历史记录）

以下保留当时的诊断与建议，不代表当前结论：Views 全负载失败不能全部归因于时序或排除候选影响；9 条平台／helper skip 后续已裁定纳入 20 条许可项，现行边界见 design.md D2-D。原 backlog 中的「不新增 allowlist」和后续建议不再作为当前决策。

用户原话「其余后端红项与 Linux Views 记录在案，供后续找回修订」；随后「处理 backlog 里的红项，不要过度设计，不要逐异常打补丁」。已按共同根因聚类（只读取证子代理 `01a1f2a6`，Gobao/qwen4-max:xhigh），不是逐测试补丁：

- **C4 搜索 WHERE 子串（已修，任务 2.10）**：`TestBuildSearchQuery_ProjectFilter` 断言连续子串 `WHERE i.workspace_id=$4 AND i.project_id=$N`；CR-2026-006/009 在 `issueWhere` 插入 `origin_type IS DISTINCT FROM 'project_chat'/'project_discussion'` 防泄漏谓词（`handler/issue.go`），打断连续子串。生产语义正确（workspace+project 过滤仍在）。仅改测试期望以容纳防泄漏谓词，Windows 单测通过。不改生产。
- **C1 chat send 400（可修，测试夹具）**：`TestChatSubmissionPreservesProjectContextContract` 报 `invalid_model_or_thinking_level`。CR-2026-056 加发送时 catalog 校验（`service/task.go`、`chat_config.go`）；集成测试服务器未 seed catalog snapshot，`ChatCatalogPort.LiveLoad` 超时→400。需在夹具 seed 可用 catalog（`WireChatCatalog` 机制），不改生产。**已修（任务 2.11）**：`chat_submission_contract_test.go` 用 `NewRouterWithOptions`＋`ModelCatalogCache.Put` seed 真实 catalog，活库 chat-submission 通过；仅测试夹具。
- **C2 builder session 残留（产品 bug，需评审）**：`TestDeleteRuntimeProfile_*` 与 chat teardown 报 session 残留/`failed to lock chat agent`。迁移 `709_chat_session_agent_nullable_set_null`（CR-2026-059 FR-21）将 `chat_session.agent_id` CASCADE→SET NULL，但 `service/runtime_teardown.go` 仍靠旧 cascade。需在 teardown 显式删 system-carrier session 并容忍 NULL agent 锁。不改测试。**已修（任务 2.12）**：新 query `DeleteChatSessionsBySystemRuntimeAgents`（排除 project_shared，FR-21）＋`DeleteChatSession` 容忍 NULL agent；活库 handler-delete 2 pass、chat-submission 5 pass、0 race。
- **C3 生命周期事件丢失（产品 merge 回归，隐私敏感需人工评审）**：`TestRegisterListeners_TaskEventsGoToWorkspace`、`TestTaskDispatchKeepsIssueAndChatRoutingWithoutContext`、`TestChatRealtimeIsPrivateToSessionOwner` 报 workspace fanout=0。上游 MUL-8374 定 lifecycle→workspace；合并后 `cmd/server/listeners.go` 残留 CR-2026-008 `if e.ChatSessionID != ""` 块（SendToUser/drop）拦截了 queued/dispatch/completed。候选删残留块，但它是 fail-closed 隐私块，删除前须确认 `isChatPrivateEvent` 覆盖所有私有内容事件类型，不 unilateral 弱化隐私。**已修（任务 2.13，用户采纳建议）**：核实 isChatPrivateEvent 覆盖 chat:*（全部）与 task:message（transcript），lifecycle 无内容；删残留块后内容隐私仍由上游守住，活库 listeners 72 pass（含 privacy）0 race。
- **C5 成员 cancel 403（需产品/安全裁定）**：`TestPrivateProject*` 期望成员可 cancel，生产 CR-2026-004 FR-4 收紧为 originator/owner/admin（`handler/chat.go`）→`not_task_originator` 403；duplicate-key 是 cancel 失败的级联。哪个契约胜出须人工裁定，不 unilateral 翻期望或改授权。**已修（任务 2.14，用户采纳建议：保留 FR-4 收紧）**：测试对齐为非 originator 项目成员 403、workspace owner 200，保留 outsider 404 可见性门；不改生产授权。活库 private-cancel 4 pass。
- **C6 telemetry（已修，任务 2.15）**：产品回归——MUL-8161 创建时 member delegation 记录块在 createInTx 抽取/上游同步中丢失（`issue.go` createOnce）；恢复 `assignedTaskID.Valid && CreatorType==member → RecordHumanDelegation`，覆盖 immediate/deferred。活库 -race 4 pass，不改测试。
- **C7 wakeup / C8 worker reply（根因待验证，任务 2.16）**：隔离 `-race` 重跑 service 4 个、handler 10 个终结 pass。迁移 004 的 `agent_task_queue.runtime_id→agent_runtime ON DELETE CASCADE` 与跨包共库使夹具干扰成为可能，但尚未捕获实际删除者，也未排除其他原因。隔离通过不证明产品正确；保留原断言，须用完整入口验证串行方案。
- **Linux Views（clean 基线全负载 A/B 已证预存）**：`dqb-frontend-clean-full/` 对**无任何候选改动的 clean 基线**跑全套 `pnpm test`，同样 6/7、Views 失败 6 文件（inbox-snooze-menu、issue-detail、issues-header.property-filter、project-date-pickers、**create-issue、search-command**，比候选版多 2 个）。故全套失败是基线预存的负载时序问题、非候选引入（clean 同样红）。属本 change「恢复绿基线」范围，需诊断时序机制后修复，不弱化断言。隔离 170/170 仅是低负载事实。
- **9 条名单外 skip**：4 缺 `systemctl`、1 缺 `pwsh` 子例、1 macOS ZCode 布局、3 subprocess helper；根因未全部确认，不新增 allowlist。
- **Pi/OMP 其余收尾**：本 change 只修自然退出 stderr 期限（2.8）；取消/终止路径与其他 Pi/OMP 超时红项仍留待后续。
- 证据根：`D:/multica-trim-quality.o41bVk/`；原精简变更 `2026-11-18-defensive-trim-multica` 的补丁与记录冻结，其最终验收走自己的门禁。
