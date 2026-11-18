# 2026-11-18-defensive-trim-tools 测试报告

> 测试日期：2026-11-18；Windows、Node v24.15.0、Git `core.autocrlf=true`。  
> 最终被测版本：Tools `ae7e5ff7f836b0078a3c096b13a0d8566e234f4b` + 18 个未提交的文件变更（含 1 个删除）。更早证据基于 `6dacbaf64db69d57fe70c935c0dd640ef00e086d`；变更后的完整树与 Linux 最终组合验证一致，见第十二节。  
> Gate 3 拟选 run：[dt-20261118-201625](validation/runs/dt-20261118-201625/tc-evidence.json)；15 个项目输入在基线更新后仍一致。此前两个 run 的代码已变更，不作为本报告的拟选证据。

## 一、总体概况

同次运行 `stdd agent verify evidence-delivery-contract` 与 `stdd ci check-failures` 均退出 0。三个 capability 的 **15/15 CP 通过、0 失败**，计划与实际执行 TC 均为 15，自动化检查 9/9。覆盖率状态为**豁免**：计划声明 `not_applicable`（Node 栈，仓库覆盖率检查只支持 pytest-cov）；无行／分支覆盖率保证。

| 门禁／套件 | 退出码 | 通过 / 失败 / 跳过 | 耗时 |
|---|---:|---:|---:|
| 初次 `quality.test`（按 `config.d/quality.yaml` 原样：crctl、OutputGuard、pipeline-templates，双引号 glob） | 1 | 2245 / 40 / 121 | 792.8 s |
| `suite-gate.mjs --run`（CI 口径，crctl） | 1 | 2243 / 2 / 0（顶层） | 808.5 s |
| `node --test skills/writeback/scripts/test/*.test.mjs` | 0 | 24 / 0 / 0 | 3.36 s |
| `node --test output-guard/test/*.test.mjs` | 0 | 37 / 0 / 0 | 4.84 s |
| `node --test skills/shared/metrics/test/*.test.mjs` | 0 | 11 / 0 / 0 | 0.08 s |
| `node --test pipeline-templates/*.test.mjs` | 0 | 69 / 0 / 0 | 5.52 s |
| `quality.lint`（`lint-prompts.mjs`） | 0 | 0 findings | <1 s |
| `quality.typecheck`（`check-agents-contract` + `check-skill-matrix`，非类型检查器） | 0 | 两项通过 | 约 1 s |

`suite-gate`：100 个文件、2245 个顶层用例、98 个文件通过，verdict=`block`。另有 1 个 POSIX 专用嵌套用例在 Windows 跳过，不计入顶层数。`lint-prompts.mjs --mode enforce` 也退出 0。两种全量命令的并发、参数和计数口径不同，不合并统计。

## 二、按模块与切片统计

| 切片 | 验收覆盖 | 新增用例 | 相关套件 | 结果 |
|---|---:|---:|---|---|
| S1 OutputGuard 首行标记 | 2/2 | 2 | `output-guard/test/core.test.mjs`（22 顶层用例） | 通过 |
| S2 交付配置和 findings | 4/4 | 4 | `evidence-delivery-gate.test.mjs`（14）、`delivery-contract.test.mjs`（15） | 通过 |
| S3 回写候选同源读取 | 3/3 | 3 | `writeback.test.mjs`（24） | 通过 |
| S4 新事务冲突与冻结续办 | 6/6 | 6 | `writeback-tx.test.mjs`（43） | 通过 |

四个切片已登记验证，未发生切片第三轮修复。`gate-registry.json` 同步为 100 个测试文件；交付门禁 10→14、回写事务 37→43，删除旧 `evidence-components-false.test.mjs` 登记。可达的组件保证迁入真实入口，保留报错、放行及 findings 共存断言。

## 三、E2E 与平台

E2E 未执行（`quality.e2e.enabled: false`）；未跑完整多版本矩阵。新增用例在 Windows 默认配置及 `core.autocrlf=false` 覆盖配置下均通过。随后在 `AIFI-ISO` WSL 用已有 Linux Node v22.23.4 和 Git 2.56.0 实跑（见第九节）；这不是 CI 指定版本的矩阵。

## 四、全量失败分析

- **`quality.test`：39 个 VM 测试失败。** `read-hash-memory` 35 个，其余 4 个来自 `durable-lock-release-memory`、`execution-transaction-cleanup-memory`、`git-run-raw-bytes-memory`、`repair-origin-kind-memory`，均因启用 VM modules 的前置条件不满足。已核对 HEAD：这些测试原有该要求；配置中的命令未加 `--experimental-vm-modules`，CI suite-gate 对相关文件按需加旗标，这五个文件在最终 suite-gate 均通过。未改项目质量配置，也未用 CI 命令替换配置命令的结果；带进程级 VM 参数和真实身份的复跑见第九节。
- **两种命令首次均失败：`execution-control-isolation.test.mjs:74`。** 初始执行未提供 `AIFI45_ISOLATION_PROFILE` / `AIFI45_ISOLATION_AGENT`，触发 HEAD 已有的“隔离证明不能空跑”断言；真实受限身份用例未运行。该文件只运行了 1 条用例，低于登记的 3 条，且无登记例外。suite-gate 同时报告 `SUITE_COUNT_BELOW_BASELINE_WARN`、`SUITE_MANIFEST_CASE_DROP`、`SUITE_FAILURES_UNREGISTERED`。
- **最终 suite-gate 额外失败：`competitive-report.test.mjs:302`（AC-B18）。** `TX_LOCK_HELD` 判为同机活进程持锁；单独复跑 15/15 通过，约 9 秒。同类错误在首次全量出现于 `version-set`，单独复跑 12/12 通过；中间一次全量无该错误。未改锁实现，现象与并发时偶发锁争用相符，未在干净 HEAD 上做完整对照，不能确定具体 PID 是否被复用。

三次 suite-gate 均退出 1：初次 817.9 s（隔离身份、`version-set`），中间 804.6 s（仅隔离身份），最终 808.5 s（隔离身份、`competitive-report`）。前两次非最终代码，仅保留为复现历史。

## 五、功能覆盖与差异审查

- **交付**：TCEVD101–104 区分读取失败／非列表、缺省／空列表、有无有效合同，验证配置错误信封及组件和授权、验证 findings 原有顺序。删除第二次 `ready` 判定；TTY 回答走 `await`，异常回到 CLI 错误映射。真实 PTY 审批后续已补验（第九节）；未专门验证回写事务清理顺序。
- **回写**：TCWSC001–009 验证同一次读取决定正文和摘要、空任务索引保留空内容摘要、读错显式失败、三方冲突不覆盖目标及冻结候选续办。D-04 对新事务仍成立；续办遵守 REQ-WSC-003，不再读取或比对当前生成器。摘要仍按 UTF-8 解码后、换行归一化前的文本计算。
- **OutputGuard**：TCOGE001/002 验证 LF/CRLF 首行仍能识别逃生标记、第二行不作为逃生口；`singleLine` 已从实现及策略删除，`parseEscapeHatch` 仍导出并供 metrics 使用。
- **C3**：最终 diff 逐文件对照验收表，`git diff --check` 通过。17 个改动文件在设计范围表内，额外 `CUSTOM.md` 是既有台账的同步更正；同文件内的 TTY 入口调整另记于 [design-adjustments.md](design-adjustments.md)。未残留调试代码或被替代的旧校验。

## 五-B、多路评审与处置

| 路 | 配置值 | 请求值 | 实际模型 |
|---|---|---|---|
| code | `OpenAIPersonal/gpt-6.2-sol:high` | `OpenAIPersonal/gpt-6.2-sol:high` | 未知（未核到运行元数据） |
| test_config | `GB-JP/qwen4-max:xhigh` | `GB-JP/qwen4-max:xhigh` | 未知（未核到运行元数据） |
| docs_skills | `Gobao/deepseek-flash:high` | `Gobao/deepseek-flash:high` | 未知（未核到运行元数据） |

- **已处置**：TTY 回调绕过 CLI 异常映射（改为 `await` 用户回答，不在采集器退出）；TCEVD104 验证授权与验证 finding 共存；TCWSC001 以 A 的特征行替代弱断言；TCWSC004 由夹具显式生成 CRLF；删去 `CUSTOM.md` 两处过时边界说明。仓内未发现 `EVIDENCE_*` 错误码的独立登记表。
- **不纳入本次实现**：归档读错可能留下初始 journal（所述省略 `--spec-id` 重试后果未复现）、归档 `_history.yml` 先探测再读、续办不复核目标父目录 junction，均为既有行为；设计 C3 约束同读在生成侧，C4 保留冻结续办校验面。分别作为后续评估项记录，不以本报告宣称已解决。TCWSC001–003 的测试临时目录在断言失败时可能残留，与文件既有清理方式一致，未修改。

## 六、设计调整

[design-adjustments.md](design-adjustments.md) 记录三项：将 `checkGenerator` 和原 `checkBefore` 收敛为 `fresh`；让 TTY 答复接回主错误处理；更新 `CUSTOM.md` 台账一行。受审设计与测试计划未改，`design.md` 仍写 `checkGenerator`，`test-plan.md` 执行矩阵仍写“待 Phase 3”，实际执行以本报告和 run 为准。

## 七、C4 失败模式核对

以下核对对应 `validation/runs/dt-20261118-201625/`；人工项结合该 run、最终 diff 和回归日志。

| 类别 | 核对结果 |
|---|---|
| (a) hallucination | CLI 文件检查通过；测试数量从实际报告取值 |
| (b) scope_creep | C3 核对逐文件范围；增补记录已披露 |
| (c) cascading_errors | 命中 TTY 异常脱离主 Promise；已修，真实 PTY 复验见第九节 |
| (d) context_loss | CLI：15 个 TC-ID 唯一；人工发现一度遗漏清理约束，已撤销该修法 |
| (e) tool_misuse | 早期 runner 拒绝不匹配的 task 名；最终预览后用单 task 执行全部 15 CP；质量命令按配置原样跑 |
| (f) runtime_deviation | CLI：所有 THEN 含 SHALL；CP 验证具体观测值 |
| (g) pipeline_break | CLI：AND 数量正常；4 个切片有验证证据 |
| (h) content_quality | 命中 TCWSC001 弱正文断言，已改用特征行 |
| (i) instruction_decay | 同 (d)：重读设计“为什么”，保留采集器不直接退出的约束 |
| (j) coverage_vacuum | TC 15/15；计划声明覆盖率豁免，无覆盖率保证 |
| (k) contract_gap | CLI：3 个 capability 契约一致 |
| (l) anchor_missing | CLI：非关键变更，无锚定义务 |
| (m) agent_cp_failure | 15 条均检查退出码和精确的单用例通过数，不只匹配标签 |
| (n) cross_system_mismatch | CRLF 夹具宿主依赖已消除；Linux 本地实跑及基线对照见第九节，未跑正式 CI |

### 经验库

新增 EXP-2026-0006（异步回调绕过顶层错误映射）、EXP-2026-0007（CRLF 夹具依赖 Git 配置）、EXP-2026-0008（修评审意见时遗漏设计约束），当时项目共 8 条；独立超时修复后来新增 EXP-2026-0009。0006 关于在采集器就地退出的修法不适用于本变更；已由 0008 和本报告记录正确修法。既有夹具参数经验用于预防，未登记新的命中。

## 八、阶段结论（历史）

该阶段变更验收 15/15，四个切片与补充回归通过；Linux Node 20 全量当时因基线超时缺陷未全绿，任务 5.2 当时未完成。独立修复合入后最终状态及验证见第十二节。

## 九、授权使用本机、Podman、WSL 后的补验

复用 `AIFI-ISO` 的 service `1500:1500`、agent `1501:1501`。Linux 从本地 Podman 缓存取 Node，从 Podman VM 取已有 Git，只放在 WSL 临时目录；未联网、未安装依赖、未使用正在运行的服务容器。Linux 副本从同一 HEAD 应用最终 diff，18 个文件对齐；业务源和选定证据未改。原生 Windows 的受限令牌及 GitHub Actions 矩阵未执行。

| 补验 | 退出码 | 结果 | 耗时 |
|---|---:|---|---:|
| Windows Node v24.15.0 → WSL 真身份隔离 | 0 | 12 通过、0 失败、0 跳过 | 2.93 s |
| Linux Node v22.23.4 → 真身份隔离 | 0 | 12 通过、0 失败、0 跳过 | 1.15 s |
| Linux 定向验收 | 0 | 15 通过、0 失败、0 跳过 | 31.36 s |
| Linux 真实 PTY 审批 | 0 | 2 通过、0 失败、0 跳过 | 2.89 s |
| Windows `quality.test`（真实隔离；仅进程环境加 `NODE_OPTIONS=--experimental-vm-modules`） | 0 | 2425 通过、0 失败、1 跳过、0 取消 | 1086.0 s |
| Windows `suite-gate`（真实隔离） | 1 | 100 文件、2247 顶层；99 文件通过；叶子 2318 通过、1 失败、1 跳过 | 1041.2 s |
| Linux `suite-gate`（真实隔离） | 1 | 100 文件、2247 顶层；98 文件通过；叶子 2312 通过、1 失败、5 取消、2 跳过 | 580.6 s |
| Linux 补充套件 | 0（各套件） | writeback 24/24、OutputGuard 37/37、metrics 11/11、pipeline 69/69；无跳过 | 3.29 / 4.94 / 0.11 / 4.50 s |

- **TTY**：在两个一次性 CR 夹具上用 OS 伪终端输入 `yes`。正常审批写入并进入 `code-approved`；非列表声明返回结构化 `EVIDENCE_COMPONENT_CONFIG_INVALID`，`approval.yml` 不生成，`cr.md` 和 Git HEAD 不变。两项均非模拟 `isTTY`。
- **Windows**：配置的 `quality.test` 命令不变，补齐进程环境后通过；CI 口径的 `suite-gate` 只失败 `planning-entry` B18-a，实际 `TX_LOCK_HELD`；单独重跑 10/10，退出 0，9.65 s，跳过 0。此类恢复用例的持锁错误在历史全量出现在不同文件，未断言发生了 PID 复用。
- **Linux**：初次便携 Git 未带 templates 导致 `checkpoint-tx` 写测试钩子时失败；补齐已有的 Git templates，单跑 32/32，退出 0，44.86 s（墙钟），无跳过。`merge-facts` 返回退出 1（8 通过，0 断言失败，5 取消，0 跳过）；干净 HEAD 与当前变更在同一环境、同名 5 个用例同样取消，证明这一现象不随本 change 引入。未改锁、`merge-facts` 或仓库质量配置以取得通过。

## 十、按顺序完成的最终本机复验

同一份业务源码，先跑完 Windows 再跑 Linux，无并行全量任务。Windows 仅给本次测试进程设 CPU affinity，Node 可用 CPU 从 16 降到 8；不改 `suite-gate`。Linux 从同一 HEAD 应用同一 diff，使用已补齐的标准 Git 模板和真实隔离账号。

| 复验 | 退出码 | 结果 | 耗时 |
|---|---:|---|---:|
| Windows `suite-gate` | 0（`pass`） | 100/100 文件，2247 顶层；叶子 2319 通过、0 失败、1 跳过、0 取消 | 793.2 s |
| Linux `suite-gate` | 1（`block`） | 99/100 文件，2247 顶层；叶子 2313 通过、0 断言失败、2 跳过、5 取消 | 298.3 s |
| Linux writeback（与全量同批） | 1 | 23 通过、1 失败、0 跳过 | 2.81 s |
| Linux writeback（原测试单独复跑） | 0 | 24 通过、0 失败、0 跳过 | 约 2.9 s（墙钟） |
| Linux OutputGuard / metrics / pipeline | 0（各套件） | 37 / 11 / 69 通过，均无失败、跳过 | 4.87 / 0.09 / 3.84 s |

- Linux `checkpoint-tx` 已随全量通过。唯一未通过的文件是 `merge-facts.test.mjs`：5 个用例因事件循环退出被取消；同环境干净 HEAD 也有相同的 5 项取消（见第九节）。本机 Linux 使用 Node 22，未跑工作流指定的 Node 20 矩阵。
- Linux writeback 的间歇失败是旧的跨秒 `noop` 行为。仅在一次性测试副本中，给「模拟应用后再执行生成器」加 1.25 秒间隔：当前源码和干净 HEAD 均稳定返回 `noop=false`，且唯一生成文件 `specs/_index.yml` 只改了 `updated`。生产代码和仓库测试均未改；单次重跑通过不消除该问题。
- Windows `quality.test`（第九节）和 `suite-gate` 已通过；任务 5.2 的 Linux 全量条件仍未满足，未确认 Gate 3。后续 Node 20 对照见第十一节。

## 十一、Linux Node 20 最终复验

经用户授权，仅从 Docker Hub 拉取官方 `docker.io/library/node:20-alpine`（linux/amd64，镜像摘要 `sha256:afdf98210b07b586eb71fa22ba2e432e058e4cd1304d31ed60888755b8c865fb`）。在 `AIFI-ISO` 临时副本使用其中的 Node v20.20.2、既有 Git 2.56.0 及标准模板、真实隔离身份；执行阶段的网络命名空间只有 loopback。运行时主版本与工作流 crctl/writeback 一致；这是本地 WSL 复验，不是 GitHub Actions 矩阵。

| 执行 | 退出码 | 观测结果 | 耗时 |
|---|---:|---|---:|
| 真实身份隔离 | 0 | 12 通过、0 失败、0 跳过 | 0.73 s |
| `suite-gate` | 1（`block`） | 99/100 文件、2247 顶层；2313 通过、0 断言失败、5 取消、2 跳过 | 296.6 s |
| writeback 原套件 | 0 | 24 通过、0 失败、0 跳过 | 3.01 s |
| 干净 HEAD 单跑 `merge-facts` | 1 | 8 通过、0 断言失败、5 取消、0 跳过 | 0.09 s |

当前全量中唯一未通过的是 `merge-facts.test.mjs`：8 通过，5 项因事件循环退出而取消；同一 Node 20 环境的干净 HEAD 取消的用例名和错误成因一致。另在一次性夹具延迟 1.25 秒，当前与干净 HEAD 都返回 `noop=false`，唯一变化是规格索引的 `updated`；原套件本轮通过，不等于消除旧的跨秒波动。两项不在本变更实施范围内，应作为基线问题另行处理。该轮未新增业务源码、仓库测试或质量配置改动，未登记例外。任务 5.2 仍未完成，Gate 3 未确认。

### 独立修复的组合复验

在相同 `AIFI-ISO`/Node v20.20.2 环境，仅在一次性快照组合本精简补丁和独立 `2026-11-18-merge-facts-timeout` 的一行修复。`suite-gate` exit 0 / `pass`：100/100 文件、2247 顶层；TAP 2318 通过、0 失败、0 取消、2 个既有平台跳过，278.021 秒；writeback 24/24，2.805 秒。`merge-facts` 13/13、真实受限身份 12/12。原工作树补丁保持字节不变，未集成独立修复；本次结果仅覆盖组合快照，不替代原工作树的任务 5.2 或原同次证据。日志、补丁身份和确认边界见[独立修复的测试报告](../2026-11-18-merge-facts-timeout/test-report.md)。

随后独立修复按重新确认的 Gate 2 增加裸 Node 子进程测试并再次验证最终 20 路径组合：Linux suite-gate exit 0 / pass，100/100 文件、2248 顶层，TAP 2319 通过、0 失败、0 取消、2 个既有平台跳过；其中 merge-facts 14/14、真实身份 12/12。该轮当时未改变原工作树，后续集成及验收见第十二节。

## 十二、独立修复合入后的最终树验证

`merge-facts-timeout` 独立修复已经 PR #28 合入 Tools `main`，合并 `ae7e5ff7f836b0078a3c096b13a0d8566e234f4b` 保留业务提交 `7ef90674b8aa3cbf280e7d5ef91a70239e54bf65`。已将原 `../tools` main 只快进至该合并提交；原 18 个路径的未提交 patch SHA-256 `e29d2d2a3849c97bdc3bf764a33d46d4d04eee2f8795ab200c268c889a34933c` 字节不变、暂存区为空，未提交原 change。

通过两个独立临时 Git index：一个从旧 HEAD 依次应用已冻结的原精简补丁与独立修复补丁，另一个从新 HEAD 索引当前 18 个变更；二者 `write-tree` 均为 `2736d8cce221db94d3898dc3392d488ad36e67e6`。因此当前完整 Git 树与第十一节已经通过的 Linux 最终组合源码树一致，复用该 `suite-gate` 和 writeback 结果；不把旧版本的失败算作通过，也不重复执行同一 Linux 全量。组合日志 `%TEMP%/dt-regress/mft-r2-linux-gate.{json,ndjson}` 的 NDJSON SHA-256 `62133efcee0021af4aa52f2965c306cbfca9f84b64d1c3d04c0e0e4ee8487fe0`。

原 run `dt-20261118-201625` 的 15 个项目输入逐项 SHA 未变，原 15/15 CP 与 TC 不重跑；以同一 run 重验 `stdd ci check-failures` 为 9 pass、0 warn、0 fail、0 skip。旧 lint、Agent 合同、矩阵和 PTY 输入未变，复用记录。

最终工作树 Windows Node v24.15.0 的配置 `quality.test` 退出 0：2426 通过、0 失败、0 取消、1 个仅 POSIX 接线测试跳过，997.814 秒；本次进程使用 VM modules 参数、8 CPU 亲和性及既有真实隔离身份。日志 `%TEMP%/dt-regress/trim-final-windows-quality.tap`，SHA-256 `d9f2a08e4ded83918a5328c808d1ece6cae1daa59289c27b5b2d4cbde4eebb1b`。结束后原 patch 字节仍不变。任务 5.2 已完成。Hosted CI 因账户支付或支出限额未启动，不计为通过；原生 Windows 受限令牌未验证。
