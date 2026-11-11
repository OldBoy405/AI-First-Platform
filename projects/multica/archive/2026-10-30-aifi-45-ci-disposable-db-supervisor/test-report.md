# AIFI-45 一次性库实例生命周期与测试守卫边界 — BUILD 测试报告（C7，2026-11-11）

> 范围：只陈述本轮**实际执行**的检查，未执行的写「未验证」或「不适用」并给理由。长程模式只用于 Gate 2 之后的 BUILD；Gate 3、提交、推送仍待你另行确认或授权。
> 本报告取代此前版本：此前版本称「`check-failures` 两项错误未消除」，该状态已被同次执行证据解除（第三节）；同时更正了此前对真实测试清理逻辑的描述（第六节 C1）。

## 一、结论

10 个计划 TC 经 STDD 同次执行证据**全部通过**（planned 10 / actual 10）；`stdd ci check-failures --run` 为 **9 通过 / 1 警告 / 0 错误，TC 当前执行覆盖 10/10**。回归（完整入口 13 个选择）**229 PASS / 0 FAIL / 0 skip**。真实 podman 步骤前后，容器与卷集合逐位相同，受保护的 `multica-postgres`、`multica-backend`、`multica-pgdata` 未变。

不能当作已通过的：CI 未验证（本 change 不改 CI）；覆盖率无任何保证（第四节）；`make test` 与逐切片全量回归未执行（第五节，含理由）。

## 二、TC 覆盖（planned 10 / actual 10）

| TC | Scenario | CP | 执行的检查 | 结果 |
|---|---|---|---|---|
| TC-DTI-001 | SC-DTI-001 | CP-DTI-001 | `instance.test.mjs` 7 个用例：信封参数写死、越界寿命与畸形 nonce 拒绝、密码只经环境、回环 URL、非回环与「多出一行绑定」拒绝并释放、就绪超时释放、非完整 ID 输出不删任何东西 | PASS |
| TC-DTI-002 | SC-DTI-002 | CP-DTI-002 | `run-selection.test.mjs` 2 个用例（空 PATH 下运行）：`--admin-url` 在创建实例前被拒；不再读 `AIFI45_ADMIN_URL`（均 RED 先行） | PASS |
| TC-DTI-003 | SC-DTI-003 | CP-DTI-003 | `instance.test.mjs` 2 个：按完整 ID 释放、归属核对后 `rm -f -v`、读回为零才成功；读回仍存在则失败 | PASS |
| TC-DTI-004 | SC-DTI-004 | CP-DTI-004 | `instance.test.mjs` 2 个：名称或标签对不上不发 `rm`；畸形 ID/nonce 在调 podman 前拒绝。变异（标签改子串匹配）使其失败，说明用例有效 | PASS |
| TC-DTI-005 | SC-DTI-005 | CP-DTI-005 | `instance.real.mjs`：子进程起实例后 SIGKILL，TTL 加宽限内实例消失，集合回到基线（真实 podman） | PASS |
| TC-DTI-006 | SC-DTI-006 | CP-DTI-006 | `instance.real.mjs`：一个真实通过、一个零选中的选择，退出码非零，输出含 `released instance … remaining=0`，集合不变（真实 podman） | PASS |
| TC-DTI-007 | SC-DTI-007 | CP-DTI-007 | 入口运行 `selections.identity.json` 的两个单测试选择：`governance-nonce-gate`（错误 nonce 的子进程在取 lease 前退出且 fixture `updated_at` 不变）与 `governance-identity-check`（畸形/他人 nonce、库注释不符被拒）。RED 先行：加检查前子进程 15 秒不退出 | PASS |
| TC-TWG-001 | SC-TWG-001 | CP-TWG-001 | `test-go.test.sh`：guard 对含 `:` 的 TMPDIR 非零退出并给出明确信息，假命令未执行（退出码 2）。**修复前复现**：status 0、假命令被执行 | PASS |
| TC-TWG-002 | SC-TWG-002 | CP-TWG-002 | `test-go.test.sh`：脚本自己的 mktemp 对不存在的含 `:` 的 TMPDIR 同样拒绝，不会走到 PATH 改写 | PASS |
| TC-TWG-003 | SC-TWG-003 | CP-TWG-003 | `test-go.test.sh`：TMPDIR 为空仍回退 `/tmp`，假命令执行且退出码 7 原样传出 | PASS |

## 三、同次执行证据

- run id：`28a37e50-a05d-4634-8830-e8e8637f089e`，由调用方生成，同值传给 `stdd agent verify disposable-test-instance --change … --run <id>` 与 `stdd ci check-failures … --run <id>`，两者之间未再运行其他 `agent verify`。
- `agent verify`：**10 passed, 0 failed**；每个 CP 的全部断言（退出码、TC 名、TAP `# pass N` 或完整 PASS 行）均成立。
- `check-failures --run`：**9 通过 / 1 警告 / 0 错误**；`(j)` 为「已声明无覆盖义务」，`TC 当前执行覆盖 10/10 (100%)`，`5 个切片均有验证证据`。
- 证据记录 `validation/tc-evidence.json`：`run_id` 与 `selected_run` 同为上述值，冻结输入 1631 项（含迁移 SQL 与整个 governance 包目录），`coverage_files` 为空（见第四节）。
- 冻结边界：TC 的被测对象 + 入口在测试前直接执行的数据与命令（迁移入口与 SQL）；**不含** Go 编译期传递依赖，也不含 Podman 与镜像（属环境）。
- 同次运行前后容器与卷集合比对：一致。
- **归档后的状态**：归档会把 change 目录移到 `archive/`，`tc-evidence.json` 的对象路径与之不再相同，按 STDD 的比较规则它此后**只能作历史留存，不能再作为当前执行证据复验**。归档前须向你说明并取得确认，不伪称归档后同次验证仍有效。
- 执行环境：Windows、Git Bash 在 `cmd.exe` 的 PATH 中排在 WSL 启动器之前；node 命令用 `--test-reporter=tap`（执行器用 cp936 解码，默认 reporter 的 `✔` 会令 stdout 解码失败）。

## 四、覆盖率状态

**配置豁免，无覆盖保证。** 证据计划声明 `coverage: not_applicable`，理由：被测对象为 Node 脚本、shell 脚本与 Go 测试，覆盖率采集目前只支持 pytest-cov；项目配置 `quality.coverage.enabled=false`。这是被评审过的明确声明（Gate 2），不等于覆盖率达标。

## 五、回归与质量检查（C2）

### 完整入口（最终代码上运行一次，非冻结证据）

命令：`AIFI45_TOOLS_ROOT=<同级 tools 仓库> node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json`（`channel-protocol` 本来就需要该变量，见 ADJ-001）。退出码 0；运行前后容器与卷集合一致；输出 `released instance 5fe19df00515 remaining=0`。

| 选择 | pass / fail / skip | 结果 |
|---|---|---|
| run-routes | 16 / 0 / 0 | PASS |
| run-admission-support | 49 / 0 / 0 | PASS |
| run-root-and-dispatch | 11 / 0 / 0 | PASS |
| run-daemon-contract | 18 / 0 / 0 | PASS |
| notice-routing | 9 / 0 / 0 | PASS |
| channel-migration-up | 19 / 0 / 0 | PASS |
| channel-migration-down | 22 / 0 / 0 | PASS |
| channel-migration-reapply | 15 / 0 / 0 | PASS |
| channel-protocol | 46 / 0 / 0 | PASS |
| wp4-original-mapping | 1 / 0 / 0 | PASS |
| wp4-concurrent-replay | 1 / 0 / 0 | PASS |
| m005-consumption-effect | 20 / 0 / 0 | PASS |
| governance-identity | 2 / 0 / 0 | PASS |

合计 229 PASS。`governance-identity` 与 TC-DTI-007 用的两个测试相同，但 TC-DTI-007 的证据来自两个单测试选择（零匹配即失败），这里只作回归。

### 其他检查

| 项 | 结果 |
|---|---|
| `node --test scripts/aifi45-disposable/*.test.mjs` | 39 / 39 PASS，0 skip（真实 podman 文件 `instance.real.mjs` 不含 `.test.`，默认通配不执行，不存在 skip 状态） |
| `go vet ./internal/governance` | 退出码 0 |
| `gofmt` | 本 change 改动的 `crsync_test.go` 无输出；同包另有 50 个文件被列出，是 Windows `core.autocrlf=true` 的 CRLF 检出所致，均未被本 change 修改 |
| `pnpm lint` / `pnpm typecheck` | **不适用**：工作区只含 `apps/*`、`packages/*`，本次改动在根目录 `scripts/` 与 `server/`，且无 `.ts/.tsx` 文件；`apps/desktop` 的 eslint 规则指向它自己的 `scripts/`，与本次无关 |
| `make test`（`quality.test`） | **未执行**：它先 `ensure-postgres.sh` 并执行迁移，会访问或启动共享 Postgres（受保护资源，本 change 约束不得触碰）。其替代是上面的完整入口：它为每个选择自建一次性库并跑同一批 Go 测试，但不是 `go test ./...` 全量 |
| 逐切片全量回归 | **未做**。切片期只跑了聚焦测试与 RED/GREEN；全量回归只在最终代码上执行一次（上表）。事后重演不会增加对最终产物的信心，故不补做逐片历史 |
| governance 包其余测试 | 未单独运行。`TestMain` 的改动在通过身份校验的路径上行为不变，该路径由完整入口里 governance 相关选择覆盖 |

## 六、切片验证与评审

| 切片 | TC | RED | GREEN | 备注 |
|---|---|---|---|---|
| S1 TMPDIR 拒绝 | TWG-001/002/003 | TWG-001 首跑失败（假命令被执行） | 3/3 | |
| S2 `instance.mjs` | DTI-001/003/004 | 模块不存在 | 11/11（含评审后新增 1 个） | 变异检查见第二节 |
| S3 真实 TTL | DTI-005 | — | 通过 | 本切片只验证已实现的 `--rm --timeout`，无单独 RED；前置探测 `--timeout=12` 约 12 秒移除 |
| S4 入口接线 | DTI-002/006 | DTI-002 两个用例首跑失败 | 通过 | |
| S5 governance 身份 | DTI-007 | 子进程 15 秒不退出 | 通过 | 评审后追加 1 个拒绝用例 |

### C1 三路评审（BUILD 阶段）

`stdd config models` 取 `values.review`；configured=strong `GB-JP/kimi-k3.1-pro:max` / balanced `OpenAIPersonal/gpt-6.1-terra:xhigh` / economy `Gobao/deepseek-flash:high`；requested=经 Agent 的 `model` 参数按此传入；**actual=unknown**，子代理均未返回运行元数据。

| 路 | 发现 | 处置 |
|---|---|---|
| code（strong） | `podman port` 只取首行，漏掉第二条非回环绑定（medium） | 已修：要求恰好一行；先写失败用例（RED）再改实现 |
| code | `run-selection.mjs` 日志后 `process.exit()` 可能截断管道输出（low） | **不修**：沿用既有写法；释放已同步完成，TC-DTI-006 经管道读到了完整释放证据；改成自然退出有挂住的风险 |
| test_config（balanced） | 真实测试在 ready 失败或入口中途失败时不清理（high）；查询不验退出码、全局标签检查并发下误报（medium） | 已修，**后又更正**：当时用「测试前快照之外、名称符合」的扫描清理，后经复核发现并发时可能删到别人创建的同格式实例（名称与标签只证明格式，不证明归属）。现改为**只释放测试自己拿到的实例 ID**，拿不到 ID 时不扫描，由实例自身 `--timeout` 兜底（残留风险：TC-DTI-006 的入口中途崩溃时，实例最多存活 3600 秒）。断言 podman 状态码；删除全局标签检查 |
| test_config | governance 身份检查是复制品，只测错误 nonce（medium） | 已修：新增 `TestVerifyDisposableTestDatabaseRejectsMismatch`（ADJ-005） |
| test_config | 空 PATH 测试不能证明「没调 podman」（medium） | **不修**：尝试启动 podman 必然以 ENOENT 出现在 stderr，目标等价；假命令方案在 Windows 不可移植（ADJ-003） |
| test_config | CP-DTI-005/006 的断言可被 skip 满足（medium） | 已在 Gate 2 重签批中根治：真实测试文件改名 `instance.real.mjs` 并去掉环境开关（无 skip 状态），断言加 TAP `# pass N`（ADJ-004 已 resolved） |
| docs_skills（economy） | design.md 释放步骤与身份条件枚举落后于实现；test-plan 的 TC-DTI-002 方法文字不符；slices.md 依赖图矛盾；同包仍有 20+ 处指向旧 `scripts/aifi45-db/run.mjs` 的陈旧注释 | slices.md 已改；design.md 与 test-plan 已在 Gate 2 重签批中校正（ADJ-002/003 resolved）；陈旧注释本 change 只修 `crsync_test.go` 的一处，其余不在范围 |

### Gate 2 重签批的评审（同次 BUILD，补接线证据链）

balanced（`OpenAIPersonal/gpt-6.1-terra:xhigh`）三轮实施，strong（`GB-JP/kimi-k3.1-pro:max`）两轮独立只读审核，actual 同样 unknown。审核发现与处置：

| 发现 | 处置 |
|---|---|
| CRITICAL：CP-DTI-007 把 TC 证据与 13 选择全仓回归绑在一起，冻结面无法覆盖，且依赖 `AIFI45_TOOLS_ROOT` | 在共同边界修：证据 run 只跑两个单测试选择，13 选择改作 C2 回归（本节上表）；证据 run 不再需要 tools 前置 |
| CRITICAL（复审）：迁移是入口直接执行的输入，未冻结 | 采纳：`inputs` 加迁移入口与 SQL，并把冻结边界写成明文（第三节） |
| MAJOR：Node CP 可接受「只跑了一部分」 | 六个 Node CP 各加 TAP `# pass N`（7/2/2/2/1/1）。它是子串匹配，`# pass 1` 也匹配 `# pass 10`；这些 CP 同时断言 TC 名且要求退出码 0，增删测试本就须重签 |
| MINOR：目录型 `inputs` 多冻结两份无关测试 | **不采纳**：整目录只会向更安全的方向失效，展开清单更难维护 |
| 审核末尾建议的两个反控 | **不加**：单测试选择在构造上不可能「部分通过」；冻结输入变更使证据失效是 STDD 工具自身已测的行为 |

## 七、C2–C4 汇总

**C2** 见第三、五节。`check-failures` 的 (b) 范围蔓延警告：11 个文件，恰为业务仓工作树的全部改动（6 个已改 + 5 个新增），均为本 change 产物，无关改动为 0；它们超出的是声明范围的字面清单。

**C3** 已逐文件看 diff：无调试残留、无注释掉的旧逻辑；`console.error` 是面向用户的失败诊断。

**C4** 失败模式：`check-failures` 确定性子集 10/10 项已执行；语义类逐项（依据：C1 三路评审、Gate 2 批的 strong 审核、主会话 diff 审查、同次证据）：

| 类别 | 结论 |
|---|---|
| (a) 幻觉 | 通过：命令与参数经评审对照实现与实测核对；`podman` 输出格式、TAP 输出、运行器 PASS 行格式均以实际输出为准 |
| (b) 范围蔓延 | 警告：11 个文件均为本 change 产物，见上 |
| (c) 级联错误 | 通过：释放失败使退出码非零，不吞错；真实测试清理改为按句柄，不再扫描 |
| (d) 上下文丢失 | 通过：与 proposal/design 一致，偏离见 ADJ-001..005 |
| (e) 工具误用 | 通过：未用 `podman inspect` 读环境变量；未触碰受保护容器与卷 |
| (f) 运行时偏差 | 通过：同次真实执行；另发现并规避了 Windows 下执行器的解码问题（TAP） |
| (g) 管线断链 | 通过但曾失败：证据链此前未接线（缺计划块、spec 路径、环境变量写法），已在 Gate 2 重签批补齐 |
| (h) 内容质量 | 通过：评审后更正 design/test-plan/spec 措辞 |
| (i) 指令衰减 | 通过：评审按分层派发，actual 未知已如实标注 |
| (j) 覆盖真空 | 豁免：`not_applicable`，无覆盖保证，见第四节 |
| (k) 契约断层 | 通过：CLI 检查 2 capabilities 一致 |
| (l) 锚定缺失 | 不适用（非 critical） |
| (m) Agent 检查点 | 通过：10/10 CP |
| (n) 跨系统不一致 | 不适用（单系统；CI 不在范围） |

经验库：既有 2 条，命中 0；本次新增 3 条 discovered（EXP-2026-0003/0004/0005：多行输出只验首行、资源测试只清理成功路径、复制品检查只测一个失败条件），未验证、未上传。

## 八、已知问题与未完成项

| 项 | 原因 | 影响 | 补完计划 |
|---|---|---|---|
| fork CI 后端任务多因失败 | 本 change 不改 CI，也不负责让 CI 变绿 | CI 仍红；推送会再触发一次失败的 run | 见 `docs/analysis/fork-ci-failure-register-20261111.md`，待负责人取舍后另立 change |
| 信号路径（SIGINT/SIGTERM） | Windows 下 Node 不能向目标投递 SIGTERM，不可测 | 入口被强杀后靠 TTL（最长 3600 秒）兜底，期间容器仍占用端口与内存 | 不打算补；TTL 已验证 |
| TC-DTI-006 中途崩溃的残留 | 测试不再扫描清理，只靠 `--timeout` | 最多存活 3600 秒 | 与上一行同一兜底，不补 |
| `--rm --timeout` 只验证了本机 | 仅在 podman 6.1.4 machine（rootless）上实测 | 其他版本或 Linux 原生行为未验证 | 换环境时重跑 TC-DTI-005 |
| 冻结范围不含 Go 传递依赖 | 无法也无必要冻结整个闭包 | 依赖变更不会使本次证据失效 | 由 DELIVER 的两仓逐文件差异审查拦截，不由证据保证 |
| 执行器解码缺陷（STDD） | 中文 Windows 用 cp936 解码，非 ASCII 输出令 `stdout=None` 并在断言处崩溃 | 本 change 以 TAP 规避；失败信息若含非 ASCII 会崩溃（响亮失败，不会变成通过） | 并入 STDD 问题文档，另立 STDD change |
| 业务仓安装的 `stdd-*` Skill 副本滞后于资源根 | 同步会修改业务仓文件，需单独授权 | 本 change 按资源根现行 Skill 执行；DELIVER 的结构索引须在归档之前 | 单独执行并授权，先 `--dry-run` 看差异 |
| 项目级 `canonical/` 不存在 | 沿用 M005 做法，不造空基线 | 归档用 `--skip-specs`；两个新 capability 无同 ID 冲突，是否可直接复制 specs 以 `archive --dry-run` 为准 | DELIVER 时核对 |
| 同包旧 `scripts/aifi45-db/run.mjs` 陈旧注释 | 超出本 change 范围 | 只是误导性注释 | 另行清理 |
| 未 `git add/commit/push`、未打 tag | 未获专项授权 | 业务仓工作树 6 个已改 + 5 个新增；本地 `main` 另比 `origin/main` 多 1 个提交 | Gate 3 后由你授权 |
