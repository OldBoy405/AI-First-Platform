---
cr: CR-2026-072
status: pass
tester: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
generated-by: crctl-test
generated-at: "2026-09-29T11:58:40+08:00"
command-digest: e0d223ace60950c1f61a229367af12be05b723e2ff9dc38999ee05b52609bb66
commands:
  - repo: tools
    cwd: skills/shared/crctl/scripts
    executable: node
    args: [--test, test/crctl.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-072/test-evidence/cmd-01.log
  - repo: tools
    cwd: skills/shared/crctl/scripts
    executable: node
    args: [--test, test/caller-contract.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-072/test-evidence/cmd-02.log
  - repo: tools
    cwd: skills/shared/crctl/scripts
    executable: node
    args: [lint-prompts.mjs, --mode, enforce]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-072/test-evidence/cmd-03.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/daemon/, ./cmd/multica/, "-count=1", -v, -run, "Test(InjectTaskCRWorkspaceEnv|DaemonEnvBuildHasNoConfigFirstRootFallback|PreparePipelineTaskHydratesMachineLocalPaths|GitguardDenialAuditAttribution|GitguardExecHelperProcess)"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-072/test-evidence/cmd-04.log
---

# 测试报告 · CR-2026-072

<!-- crctl:analysis-below -->

## 1. 测试摘要

- 结论：`status=pass`。机器区 4 条命令全部 `exit-code: 0`、`timed-out: false`、`skipped: false`（`skipped` 由 crctl 按 CR-2026-057 FR-16 冻结模式表计算，本报告只读不改）。
- 运行面：本机 Windows（go1.26.6 / node），三仓 CR worktree —— tools `2559469`（TASK-02）、multica `9c0edd27b`（TASK-04）、knowledge-base `18332ec1`；跑前 `crctl workspace freshness` 判三仓 `fresh`、`dirty: false`。
- 命令 digest：`e0d223ace60950c1f61a229367af12be05b723e2ff9dc38999ee05b52609bb66`。

| 证据 | repo / cwd | 命令 | 结果 |
|---|---|---|---|
| cmd-01 | tools / `skills/shared/crctl/scripts` | `node --test test/crctl.test.mjs` | exit 0：230 pass / 0 fail / 0 skipped（155.1s） |
| cmd-02 | tools / 同上 | `node --test test/caller-contract.test.mjs` | exit 0：12 pass / 0 fail / 0 skipped（0.24s） |
| cmd-03 | tools / 同上 | `node lint-prompts.mjs --mode enforce` | exit 0：0 findings |
| cmd-04 | multica / `server` | `go test ./internal/daemon/ ./cmd/multica/ -count=1 -v -run "Test(…)"` | exit 0：8 用例 + 4 子用例全 PASS |

## 2. 验证命令与结果解读

**cmd-01（FR-2 / AC-1～AC-3）**：crctl 单测 230 项全绿，含 TASK-02 新增的 A/B 同名 CR 隔离、缺/空/无效 `--workspace` 失败关闭、operational 双值冲突与仅 `CRCTL_OPERATIONAL_WORKSPACE` 冲突的首次读写前 `OPERATIONAL_WORKSPACE_MISMATCH`（A/B 零副作用）用例；既有读写、门禁、CAS、事务语义零回退。

**cmd-02（FR-1）**：既有 caller-01～08 断言保持，新增 caller-09～12 对 CR 数据命令做全量抽取与逐调用点断言（每处含 `--workspace` 且路径 token 非空），并同规则核对已登记扫描面外调用点（`ai-first-platform-docs` 的 `.github/workflows/cr-guard.yml`，三处 crctl 调用本就显式 `--workspace .`，结论 no-action）。

**cmd-03（FR-1 prompt/README 面）**：enforce 模式 0 findings，Agent Prompt 与 crctl 用法无漂移。

**cmd-04（FR-3 / FR-4 / AC-4）**：TASK-03 六项 daemon 绑定用例（无绑定清空三键、唯一 `local_directory` 绑定、多匹配报错不注入、缺 CR 台账拒绝、Pipeline 预检根、源码无 `CRWorkspaceRoots[0]` 回退）＋ AC-4「Pipeline 用预检路径」既有回归 `TestPreparePipelineTaskHydratesMachineLocalPaths` ＋ TASK-04 gitguard 拒绝审计归属两态（无审计根零写入、有根只写本项目 outbox，`FORBIDDEN_*` 错误码逐字不变），全部 PASS。

**cmd-04 范围修订（2026-09-29，Ray 人工批准）**：原计划为全量 `go test ./...`。本机整包基线给不出通过证据 —— `./internal/daemon/` 整包 67 项既有环境性失败（skill 目录 / HOME / 配置回退类，见 multica `CUSTOM.md#已知测试失败基线`），`./cmd/multica/` 整包测试二进制 10 分钟超时且失败输出约 10 MB（超 crctl test 运行器 1 MiB 子进程缓冲，工具侧缺陷已另立 AIFI-38）；两者与本 CR 改动无关。故按 CR-2026-045 cmd-06 既有形态收敛为「定向包集 + `-run` 过滤 + `-v`」，口径即本 CR 在 multica 仓的全部改动面（`server/internal/daemon/`、`server/cmd/multica/`）。修订仅动 plan.md 证据命令表 cmd-04 行与覆盖说明对应句，其余内容未动。

## 3. TASK 验收覆盖矩阵

| TASK | 验收条件 | 覆盖证据 | 结果 |
|---|---|---|---|
| CR-2026-072-TASK-01 | 调用方迁移 + caller-contract 新断言生效（§4.1～§4.3） | cmd-02（caller-09～12）、cmd-03 | ✅ pass |
| CR-2026-072-TASK-02 | 入口失败关闭与 A/B 隔离、operational 冲突（§4.1～§4.4） | cmd-01 | ✅ pass |
| CR-2026-072-TASK-03 | daemon 绑定六态 + 源码无首根回退（§4.1、§4.2） | cmd-04（6 用例 + Pipeline 回归） | ✅ pass（§4.3 措辞见 §7-2） |
| CR-2026-072-TASK-04 | gitguard 审计归属两态 + `FORBIDDEN_*` 不变（§4.1、§4.2） | cmd-04（`TestGitguardDenialAuditAttribution` 两子用例 + 子进程 helper） | ✅ pass（§4.3 措辞见 §7-2） |
| CR-2026-072-TASK-05 | 四条命令真实结果 + 调用点清单 + 同批交付核验 | 本报告机器区 + §4 + §6 | ✅ pass |

## 4. 受影响调用点清单（FR-1 / AC-5 终版）

tools 仓扫描面内（TASK-01 commit `1d13cbf`，45 个文件），逐项迁移结果 = 已显式 `--workspace`，由 cmd-02 全量断言：

| 清点面 | 文件 | 迁移结果 |
|---|---|---|
| 四 Agent Prompt | `agents/requirement-writer.md`、`dev-agent.md`、`quality-reviewer-agent.md`、`delivery-agent.md` | 已迁移，示例命令均含 `--workspace` |
| 共享 crctl 合同与 CLI 文本 | `skills/shared/crctl/SKILL.md`、`scripts/crctl.mjs`（HELP/用法）、`adapters/{claude-code,codex,cursor,qoder}/README.md` | 已迁移，`--workspace` 升为全局必填 |
| Pipeline 模板 | `pipeline-templates/{architecture-design,code-implementation,requirement-authoring,resume-cr}.pipeline.json` | 已迁移 |
| Skill（29 个 `SKILL.md`） | `skills/cr/*`(4)、`skills/develop/*`(11)、`skills/requirement/*`(4)、`skills/shared/{crctl,controlled-shell}`(2)、`skills/sync/*`(4)、`skills/writeback/*`(4) | 已迁移 |
| 注入 hook | `skills/shared/crctl/adapters/claude-code/hooks/inject-cr-status.mjs` | 已迁移：无可信路径时不输出 crctl 建议 |
| 人读文档 | `README.md` | 已迁移：单一正确示例 + `--workspace` 必填说明 |
| 扫描面外调用点 | `ai-first-platform-docs/.github/workflows/cr-guard.yml`（`crctl validate`×2、`crctl gate`×1） | no-action：本就显式 `--workspace .` |
| daemon 注入端（FR-3） | multica `server/internal/daemon/daemon.go#injectTaskCRWorkspaceEnv` | 已迁移：`CRCTL_WORKSPACE` / `CRCTL_TASK_AUDIT_ROOT` 由任务级绑定唯一决定 |

可执行 CR 数据命令显式 workspace 覆盖率：扫描面内 100%（cmd-02 逐调用点断言，任一缺失即非零）；断言覆盖 crctl 全部非 help 子命令分类（`CR_DATA_FIRST_WORDS`，含 `git`、`validate`、`test`）。

## 5. 新增 / 修改测试文件

| 文件 | 内容 | 证据 |
|---|---|---|
| tools `skills/shared/crctl/scripts/test/crctl.test.mjs` | TASK-02 新增 A/B 同名 CR 隔离、失败关闭、operational 冲突用例 | cmd-01 |
| tools `skills/shared/crctl/scripts/test/caller-contract.test.mjs` | caller-09～12：CR 数据命令全量抽取 + 逐调用点非空 `--workspace` 断言 | cmd-02 |
| multica `server/internal/daemon/cr_workspace_binding_test.go` | 6 项绑定 / 清空 / 歧义 / 台账判定 / 首根回退源码断言 | cmd-04 |
| multica `server/cmd/multica/cmd_gitguard_test.go` | 拒绝审计归属两态 + 子进程 helper | cmd-04 |

## 6. 同批交付核验（FR-5 / AC-5）

tools 仓同一 CR 分支：TASK-01 commit `1d13cbf`（调用方迁移 + 合约断言）在前，TASK-02 commit `2559469`（CLI 入口强制 `--workspace`）在后 —— 强校验未在调用方迁移之前单独上线，无破坏性单侧发布。daemon 侧 TASK-03/04 同批在同一分支交付（`8a7733198`、`9c0edd27b`）。四条命令在各自 worktree 实测全 pass，旧调用形态未出现全量失败。

## 7. 未覆盖风险

1. **整包 Go 测试不构成本 CR 证据**（不适用，而非“通过”）：本机整包存在既有环境性失败与输出缓冲超限（见 §2），故不作为验收面；若需整包证据，须在有干净基线的运行面（CI / Linux）另行核验，不阻塞本 CR。
2. **TASK-03 / TASK-04 文件 §4.3 仍写「`go test ./...` 全量通过」**：与该人工批准的 cmd-04 定向范围措辞不一致。本次批准边界仅含 plan.md 的 cmd-04 行与测试计划对应项，故未改 TASK 文件；建议回写期统一措辞（不影响本 CR 验收证据面）。
3. **cmd-04 使用 `-run` 子串匹配**：将来测试改名致模式失配时，命令会以「no tests to run」形态假绿 —— crctl 的 FR-16 skip 检测会将该形态标为 `skipped=true`（review-code 只读该字段即可发现）；本次 `-v` 日志逐条列出 8 用例 + 4 子用例 PASS，可人工复核。
4. **前端/TS、数据库、常驻服务**：本 CR 不涉及，无对应测试面（不适用）。
5. **计划修订对审批证据的影响（事实记录，非代码缺陷）**：plan.md 在 dev-start 审批后被修订（人工批准），`crctl gate --for developing` 当前报两项：`passCondition(dev-start)` dev-plan digest 漂移（annotation `aa39d14c…` vs 重算 `ac985304…`）、`approval(development-start)` `EVIDENCE_DRIFT`（`2728285c…` vs 重算 `58310387…`）。这两键由审批与评审记录固定，在 `developing` 态无刷新通道（`approve --stage dev-start` 仅接受 `task-breakdown`），属本次人工批准修订的既定代价；`code-reviewing` / `code-approved` 门禁的证据集为 `code.yml` + `test-report.md`，不受影响。若需恢复 dev-start 审批证据一致，须由人工决定走一次计划重审或重签。

## 8. 下一步建议

按 `crctl next`：进入 `review-code`，由独立 reviewer 消费本报告机器区与 `test-evidence/cmd-01..04.log`；评审 PASS 后由 reviewer 给出代码审批命令，人工审批由 Ray 本人执行。
