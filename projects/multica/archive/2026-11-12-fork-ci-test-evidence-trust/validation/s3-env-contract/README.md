# Slice 3 证据 — 跨语言证据不得靠开发机默认值或 skip 变绿（TC-CBE-004）

> change：`2026-11-12-fork-ci-test-evidence-trust`｜执行时间：2026-11-12 本地｜Node v24.15.0｜Windows
> 本切片不创建容器、不连接数据库、不读取任何凭据值。静态扫描 + 纯函数单测。

## 产出物

| 文件 | 性质 |
|---|---|
| `scripts/aifi45-disposable/go-test-env-contract.mjs` | 新增，静态契约检查（`findViolations` 导出 + CLI，支持 `--repo`） |
| `scripts/aifi45-disposable/go-test-env-contract.test.mjs` | 新增，11 项测试 |
| `server/internal/governance/execution_authorization_test.go` | fork 独有，开发机默认值 → `t.Fatal` |
| `server/internal/governance/execution_authorization_revoke_interop_test.go` | fork 独有，同上 |
| `server/internal/governance/execution_trust_install_test.go` | fork 独有，同上 |
| `server/internal/governance/execution_binding_issue_test.go` | fork 独有，`t.Skip` → `t.Fatal` |

检查范围 = `SC-CBE-004` 点名的两个目录：`server/internal/governance` 与
`server/internal/governance/crosslang_test`（递归去重，实测 **118** 个 `*_test.go`）。
两类违规：`dev-machine-path`（`[A-Za-z]:[\\/]Users[\\/]`）与
`env-skip`（`os.Getenv("CRCTL_MJS"|"AIFI45_TOOLS_ROOT")` 绑定的标识符在 `== ""` 守卫内 `t.Skip`/`t.Skipf`）。
消息一律英文，符合 multica 代码注释/输出约束。

## RED（真实仓库改前状态，非注入样本）

把 governance 全部 `*_test.go` 复制到临时沙箱，再用 `git show HEAD:<path>`
取回这 4 个文件的**改前版本**覆盖，运行 `--repo <沙箱>`：退出码 **1**，
`red-before-fix.txt`：

```
server\internal\governance\execution_authorization_revoke_interop_test.go:100 dev-machine-path cli = "C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts/crctl.mjs"
server\internal\governance\execution_authorization_test.go:614 dev-machine-path crctl = "C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts/crctl.mjs"
server\internal\governance\execution_binding_issue_test.go:856 env-skip AIFI45_TOOLS_ROOT missing: t.Skip("AIFI45_TOOLS_ROOT is not set; skipping real crctl execution-binding verifier interop")
server\internal\governance\execution_trust_install_test.go:56 dev-machine-path crctl = "C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts/crctl.mjs"
go test env contract: 4 violation(s) in 118 file(s)
```

沙箱在命令结束时删除，**真实工作区未被改动**（HEAD 仍为 `903a46c5a`，
这 4 个文件只含本切片的修改）。这同时就是变异验证：改前红、改后绿，检查有牙。

## GREEN

| 命令 | 退出码 | tests | pass | fail | skipped | 文件 |
|---|---|---|---|---|---|---|
| `node scripts/aifi45-disposable/go-test-env-contract.mjs` | 0 | — | — | — | — | `real-repo-scan.txt` |
| `node --test --test-reporter=tap scripts/aifi45-disposable/go-test-env-contract.test.mjs` | 0 | 11 | 11 | 0 | 0 | `tc-cbe-004.tap` |
| `node --test --test-reporter=tap "scripts/aifi45-disposable/*.test.mjs"`（全量回归） | 0 | 86 | 86 | 0 | 0 | `regression-directory.tap` |
| `cd server && go vet ./internal/governance/` | 0 | — | — | — | — | `go-vet-governance.txt`（0 字节） |

真实扫描输出：`go test env contract OK: 118 file(s), 0 violations`。

## 精度验证（不误报，不空检查）

注入样本逐项覆盖旧写法：`/` 与 `\` 两种分隔符、`D:` 盘、两个受管变量各自的
`t.Skip` 与 `t.Skipf`；`t.Fatal`/`t.Fatalf` 一律放行。
**反向精度**测试证明下列不被标记：node 缺失 skip、`KNOWLEDGE_BASE_*` skip、
`CRCTL_PATH` skip、Fatal 与 node-skip 混合。
CRLF 输入行号断言为 **11**（`t.Skip` 实际所在行），证明先归一化再 `split(/\r?\n/)`。
`""`/`null`/`undefined`/`42` 输入 → `throw`（硬失败，不静默返回空违规集）。
CLI 对违规样本树退出 1、对干净样本树退出 0；两个样本树都建了 `crosslang_test`，
因为**范围为空即 `throw`**（"the contract check would be vacuous"），不允许空扫描报绿。

## 未验证项（如实记录，不 skip、不报绿）

1. ~~**改后守卫的运行时行为本切片未观测。**~~ **已于 S7 期间补验，见下节「运行时补验」。**
   governance `TestMain`（`server/internal/governance/crsync_test.go:34`）在没有一次性
   `DATABASE_URL` 时直接退出 1，并在取 advisory lease `(775513, 45001)` 前核验 nonce 身份，
   因此该观测需要一次性 podman 实例。
2. **未执行 `make test`**（U5 排除：会启动旧 `multica-postgres`、连 localhost:5432）。
3. **未执行真实 CI run**（TC-CBE-005 属 manual，依赖推送）。

## 运行时补验（S7 期间执行，一次性 podman 实例）

同一个 selection 文件跑两次，只改环境变量；两次各自新建并释放实例。selection 内容
（临时文件，未入库，此处逐字留档以便复现）：

```json
{
  "selections": [
    {
      "name": "s3-guards-env-absent",
      "package": "./internal/governance",
      "run": "^(TestExecutionGrantCheckAgainstRealCrctlCLI|TestExecutionAuthorizationRevokeHTTPToRealNodeCLI|TestDaemonInstalledRecordVerifiesThroughTrustRoot|TestDaemonFetchesAndInstallsExecutionAuthorization|TestDaemonAuthenticatedDeliveryRunsCrctl|TestDaemonExecutionDeliveryRejectsOversizedResponse|TestDaemonInstallRequiresRealCrctlContractCheck|TestExecutionBindingEnvelopeInteropWithToolsVerifier)$"
    }
  ]
}
```

这 8 个顶层测试覆盖本切片改动的全部 4 个文件（含 `crctlWorkspace` 助手的 5 个调用方）。

| 条件 | pass | fail | skip | runner 退出码 | 实例 | 证据目录 |
|---|---|---|---|---|---|---|
| `CRCTL_MJS` 与 `AIFI45_TOOLS_ROOT` **均缺失** | 0 | 8 | 0 | 1 | `df2689c218f6` released remaining=0 | `runtime-env-absent/` |
| 两者**均注入**（tools HEAD `e52b8081f159`） | 18 | 0 | 0 | 0 | `27208db64bfb` released remaining=0 | `runtime-env-present/` |

缺失时的真实报文（三条各不相同，全部 Fatal，**skip=0**）：

```
execution_authorization_revoke_interop_test.go:100: CRCTL_MJS is required: the revoke interop check needs the real crctl verifier, so a dev-machine default is not evidence
execution_authorization_test.go:614: CRCTL_MJS is required: the byte contract needs the real crctl verifier, so a dev-machine default is not evidence
execution_binding_issue_test.go:856: AIFI45_TOOLS_ROOT is required: the real crctl execution-binding verifier interop is evidence, so a skip is not acceptable
```

注入值：`CRCTL_MJS=C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts/crctl.mjs`、
`AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools`。注入后流里带 crctl 源文件 SHA256
（`d99ff820065c78860ae4f7d85a3471aac9fc9a74931e5d7f57917842baaac7c6`）与真实 node argv，
证明确实调到了真 crctl，不是回落到内联 fixture。

结论：**「缺变量就 Fatal 而不是 skip」已在真库上观测成立**，且注入后这些跨语言证据测试仍全绿。
两次运行前后容器清单只有两个既有旧容器（均 Exited），未连接 `localhost:5432`。
注：两次沿用同一 selection 名 `s3-guards-env-absent`，靠证据目录区分条件。

## 范围外发现（上报，不擅自修改）

扫描范围内还有 5 处 skip，**不属 SC-CBE-004 点名的两类**，本切片未改动：

| 位置 | 内容 | 判断 |
|---|---|---|
| `approval_crosscheck_test.go:217` | `t.Skip("crctl.mjs or node not available; ...")` | 变量名是 `CRCTL_PATH`，非受管的 `CRCTL_MJS`；是否应统一口径待裁定 |
| `execution_tc_auth010_test.go:30` | `t.Skip("node is not available")` | node 缺失，非本切片两类 |
| `execution_authorization_test.go:648` | `t.Skipf("git init unavailable: %v (%s)", ...)` | git 能力探测，非本切片两类 |
| `reconcile_live_test.go:21` | `t.Skip("KNOWLEDGE_BASE_REMOTE_URL / KNOWLEDGE_BASE_TOKEN not set")` | 外部知识库凭据，非本切片两类 |
| `supervisorjob_test/job_windows_test.go:102` | `t.Skip("manual Windows Job probe; opt in only after safety review")` | 显式人工探针，属有意设计 |

其中第 1 项与第 2 项在 CI 上同样可能把「未验证」变成绿，但扩大受管变量集属规格变更，
按流程留待用户裁定，不在本切片静默扩围。