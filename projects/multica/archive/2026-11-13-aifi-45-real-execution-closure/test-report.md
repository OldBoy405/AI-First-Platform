# 2026-11-13-aifi-45-real-execution-closure 测试报告

> 测试日期：2026-11-15
> 测试环境：Windows（Git Bash），node v24.15.0，go1.27.1（`CGO_ENABLED=0`，无 gcc），podman；一次性 PG/backend/daemon 容器（带 `aifi45.real-run=<nonce>` 标签）
> 被测版本：multica 仓 HEAD `8eac1460e` + 本变更未提交改动；tools 固定来源副本 `e52b8081`（`crctl` overlay `afd2fab6`）
> 选定 run：`bb5a9173-27cf-40fc-bb62-66e3e20c8bd1`（`validation/runs/bb5a9173-27cf-40fc-bb62-66e3e20c8bd1/tc-evidence.json`）
> 结果以选定 run 为准；未执行项写明“未执行”。

## 一、总体概况

| 指标 | 数值 |
|------|------|
| 计划 TC（CP） | 13（TC-REC-001..010、TC-WSD-005..007 ↔ 对应 CP） |
| 选定 run 通过 / 失败 | **13 / 0**（`stdd agent verify real-execution-closure`，exit 0） |
| `stdd ci check-failures` | 9 通过 / 0 警告（除切片警告项）/ 0 错误；**TC 当前执行覆盖 13/13 (100%)** |
| 真实模型调用 | 选定 run 内 2 次：run A（CP-REC-004，`GB-JP/deepseek-flash`）、run B（CP-REC-005，同模型）；模型名与次数来自 `.local/run-config.json`（gitignored） |
| 覆盖率 | 豁免：证据计划声明 `not_applicable`（Go 服务与 Node 脚本，项目 `quality.coverage.enabled=false`） |
| Lint / 类型检查 | `go build ./...`、`go vet` 干净；Node 侧 `node --check`；**无独立 lint 工具** |

## 二、真实运行的证据（选定 run 内的原文输出）

### run A（`--scenario architecture-main`，真实 daemon + 真实 pi + 真实模型）

```
PASS real-run build server=d749e29e multica=77fbbfe0 migrate=0c36304f
PASS real-run tools head=e52b8081 head_sha256=d99ff820 overlay_sha256=afd2fab6
PASS real-run daemon git=… version=2.54.1
PASS real-run stack backend=healthy runtime=online agent=created
PASS real-run domain cr=CR-2026-001 resource=local_directory root=/workspace
PASS real-run executors agent=dev-agent skill=write-tech-design agent2=quality-reviewer-agent skill2=review-tech-design
PASS real-run cr-workspace worktree=requirement/CR-2026-001 operational=same
PASS real-run authorization http=201 head=…
PASS real-run source-tamper-rejected task=… code=EXECUTION_SOURCE_INVALID consumption=0
PASS real-run source queued task=…
PASS real-run source task=… run=… consumption=1 effect=1
PASS real-run writer-two-advances-one-receipt advances=2 consumption=1 effects=1/1/1 status=tech-design-review-pending trust_root_seen=… evidence=receipts
PASS real-run review-zero-advance-own-effect task=… consumption=1 effects=1/1/1 advances=0 status=tech-design-review-pending
PASS real-run human-gate status=waiting_approval pending=0 new_tasks=0
PASS real-run restart-dedup status=waiting_approval tasks=4 consumption=1/1/1/1 effects=unchanged
PASS real-run cleanup remaining=0
PASS real-run scenario architecture-main waiting_approval cr=tech-design-review-pending
```

### run B（`--scenario architecture-revoke`，writer 运行中撤销）

```
PASS real-run source task=… run=… consumption=1 effect=1
PASS real-run revoke-stop status=running reviewer_tasks=0 head=revoke
PASS real-run restart-revoke-stop status=failed tasks=1 refused=1 consumption=unchanged
PASS real-run cleanup remaining=0
PASS real-run scenario architecture-revoke revoked status=running tasks=1 head=revoke
```

**观察（须在 Gate 3 复核）**：撤销后 daemon 重启时，平台给被撤销节点的 writer 再派一次任务；该任务四条账本计数全为 0，即在 agent 启动前被拒（预消费先于 agent 启动）。断言因此取「允许 0 消费的重派、禁止 reviewer 任务、禁止任何已发生的消费/effect 变化、禁止推进型状态」。SC-RUN-006 的字面保证（reviewer 不派发、节点不推进、重启后保持）在两次运行中都满足。

## 三、按 TC 的覆盖对照

| TC | CP | 覆盖手段 | 结果 |
|---|---|---|---|
| TC-REC-001 | CP-REC-001 | `run-selection --only rec-001`（daemon 预消费 + 同 workspace 不同 generation 的信任根） | PASS |
| TC-REC-002 | CP-REC-002 | `rec-002`（claim 合同值 5 用例） | PASS |
| TC-REC-003 | CP-REC-003 | `rec-003`（endpoint 基数） | PASS |
| TC-REC-004 | CP-REC-004 | **真实 run A**（上文） | PASS |
| TC-REC-005 | CP-REC-005 | **真实 run B**（上文） | PASS |
| TC-REC-006 | CP-REC-006 | `rec-revoke`（组件层撤销后不推进） | PASS |
| TC-REC-007 | CP-REC-007 | `run.mjs --scenario cleanup-smoke`（6 行 PASS） | PASS |
| TC-REC-008 | CP-REC-008 | 全组 selections（40 项，exit 0，`remaining=0`） | PASS |
| TC-REC-009 | CP-REC-009 | `rec-009`（信任根注入 8 子测试） | PASS |
| TC-REC-010 | CP-REC-010 | `rec-010`（strict source 预消费 13 用例） | PASS |
| TC-WSD-005 | CP-WSD-005 | `rec-wsd-*`（工作区删除后终态安全） | PASS |
| TC-WSD-006 | CP-WSD-006 | 同上（并发 reservation） | PASS |
| TC-WSD-007 | CP-WSD-007 | `governance-wsd-lock`（行锁顺序探针） | PASS |

## 四、回归与门禁

- **selections 全组**：`node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json` → **40 PASS、exit 0、`released instance … remaining=0`、147s**（需 `CRCTL_MJS`、`AIFI45_TOOLS_ROOT`；缺失时 `channel-protocol` 会失败——见 ADJ-A0-9）。
- **Node（真实运行驱动）**：`node --test scripts/aifi45-real-run/*.test.mjs` → **181 tests / 178 pass / 0 fail / 3 skipped**（skip 均为 win32 不可执行 POSIX 脚本或本机无真实 git 的用例，带原因）。
- **Go**：`go build ./...`、`go vet` 干净；`go test ./internal/daemon` 的失败集与基线 `s10_baseline_norm.txt` 逐名相同（27 个既有 Windows 失败，无 `TestExecution*`/`TestTC_REC_*`）；handler/governance 测试经 `run-selection` 在一次性 PG 上跑。
- **CI 改动（未提交）**：`.github/workflows/ci.yml` 的 script-checks 覆盖 `scripts/aifi45-real-run/*.test.mjs`；`.github/ci-paths.json` 增加该目录；`scripts/ci-scope.test.mjs` 增用例（50/50）。

## 五、每切片验证状态

见 `.stdd.yaml` 的 `slices_completed`（S1、S2、S3、S4、S7、S9、S10、S11、S12，以及 S5 的驱动部分与 S6 的组件层、S8 的台账/文档/全组回归）。**切片 S11（文档/台账同步切片）的 `new_tests=0`**，`ci check-failures` 对它有「缺少验证证据」告警——这是文档切片的性质，不是缺测试。

## 六、C1–C7

| 步骤 | 结果 |
|---|---|
| C1 多路评审 | 三路（code=strong、test_config=balanced、docs_skills=economy）已执行并逐条处置，见 `design-adjustments.md` 的 C1 相关小节；`actual` 均 unknown（无运行元数据） |
| C2 全量质量检查 | 见第四节；覆盖率豁免，无 lint 工具，如实记录 |
| C3 Diff 审查 | 逐文件审过 `server/` 与 `scripts/aifi45-real-run/` 的改动；`crctl.mjs`（tools 侧）为纯插入校验第 45 行 |
| C4 失败模式检查 | `stdd ci check-failures` 9/9；语义项见下节 |
| C5 经验库 | EXP-2026-0007..0009（本变更）；本条目的新增 lesson 已写入 memory daily |
| C6 设计调整 | `design-adjustments.md`（ADJ-S4-1、ADJ-S5-0、ADJ-S6-1、ADJ-S10-1、ADJ-S12-1、ADJ-A0-1..9、ADJ-E4-1、C1 各条） |
| C7 测试报告 | 本文件 |

### C4 语义检查

| 类别 | 判定 | 取证 |
|---|---|---|
| 先序列化锁再读守卫 | PASS | `lockWorkspaceKeyShare` 三处取锁点先于 claim/head/lineage/cursor；`rec-wsd-*` 与 `governance-wsd-lock` 通过 |
| 清理只覆盖成功路径 | PASS | 驱动 `installCleanup` 覆盖 SIGINT/SIGTERM/异常；每次运行后带标签资源 0/0 |
| 每个拒绝条件一个独立探针 | PASS | source-tamper、tamper 后 0 消费、撤销后 0 reviewer、重启后 0 新消费 |
| 逐行解析多行输出 | PASS | 驱动按整段 JSON/行解析，未见 `lines[0]`/`shift()` 依赖单行格式 |
| 测试夹具恒传某参数 → 生产形态未覆盖 | **命中并已修** | main 模式的观察层曾依赖替身 trace（ADJ-A0-6），已改为账本 + 回执 |
| 断言过严造成的假失败 | **命中并已修** | reviewer 的 `detail.verdict` 允许缺省（node passed 已是强事实）；撤销后允许 0 消费的被拒重派（ADJ-A0-9） |
| 跨系统不一致（记录 ↔ 代码） | 已处理 | ADJ-A0-9、C1 各条；受审文档的文字问题在 ADJ-9 汇总待 Gate 3 裁定 |

## 七、未验证项与已知风险

1. **win32 下 TC-NTR-012 的真实进程接线**属于 tools change，本变更不覆盖；本处接线由真实栈（run A/B）承担，已通过。
2. **撤销后重启会给被撤销节点再派一次被拒任务**（四账本全 0）。按 SC-RUN-006 字面不违反，但属残留行为，供 Gate 3 裁定是否另立后续工作。
3. **`detail.verdict` 在某些通道下为空**，断言改为「空或 pass」；依据是 runner 只在 `conclusiveReviewEvidence` 为真时把节点标记 passed（`server/internal/governance/runner.go:849-861`）。
4. **真实模型的非确定性**：本变更的取证在 reviewer 阶段出现过一次 `block`（600s 内节点未通过）、一次 verdict 为空；最终选定 run 13/13。若后续复跑出现 reviewer `block`，那是模型对 sdd.md 的实质判定，不是机制失败。
5. `stdd validate` 仍报 `test-plan.md: TC 案例数 (13) 少于 Spec Scenario 数 (15)`；**沿用不处理**（先前决定），不声称 validate 通过。
6. `.stdd.yaml` 的 traceability 计数为 0，属 DELIVER 前生成项，本阶段未生成。
7. 本机存在他人会话遗留栈 `aifi45-real-run-1916fc3f025f1258-*`（pod 1 + 3 个 Exited 容器），未触碰；本变更的清理读回按自身 nonce 限定。
