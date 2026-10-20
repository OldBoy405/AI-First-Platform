# M00 隔离数据库治理基线（首次真实执行）

## 环境（已按要求清理）

- 运行时：podman 5.8.3（machine `podman-machine-default`，Linux/overlay），镜像 `docker.io/library/postgres:16`（本地已有，未拉取）。
- 容器：`aifi45-pg-da386e56`，随机专用库 `aifi45_m00`／用户 `aifi45`／随机口令，仅绑定 `127.0.0.1:50545`（非默认5432）。
- 未读取、未使用仓库`.env`或任何既有`DATABASE_URL`；未连接本机既有数据库或共享/生产库。
- 结束后：`podman rm -f -v` 删除容器及其匿名卷；复核无残留容器/卷、端口已关闭；multica 工作树仍 clean。

## 迁移

| 项 | 值 |
|---|---|
| 命令 | `go run ./cmd/migrate up`（显式 `DATABASE_URL` 指向上述临时库） |
| native exit | 0 |
| 耗时 | 21.4s |
| `schema_migrations` | 651 行，最高版本 `621_issue_context_refs_gin` |
| public 表数 | 135 |
| pg_bigm / pg_cron | 迁移内已包装为可缺失；本次按缺失跳过，不影响建表 |

## 执行结果

### 1. 哨兵（M00.2）

- `TestParseCoreRegistryFixedContract`：**exit 0，PASS，1 case 实际执行**，耗时 7.0s。
- 无 `Skipping governance integration tests` 输出，`TestMain` 未提前退出，证明是真跑而非空跑。

### 2. 整包基线（`./internal/governance/`，`-count=1 -v`）

- **native exit 1**，墙钟 18.9s（Go 报告 17.4s）。
- **192 PASS / 1 FAIL（父用例，含 2 个子用例）/ 1 SKIP**，无 `Skipping governance integration tests`。
- SKIP：`TestReconcileLiveGitHub`（需外部实时 GitHub，非本次范围）。
- FAIL：`TestGrantCrossVerifiesWithCrctlCodeStage` 的两个子用例
  - `code approve with release-subjects and adjacent replay`
  - `code reject rollback and adjacent replay`
  - 报错：`KEY_NOT_FOUND 公钥不存在: <ws>/001/.crctl/keys/approval-crosscheck.pub（公钥在安装根 .crctl/keys/，不在 CR worktree 内）`

### 3. 失败归因（已证明与本次候选无关）

- 测试代码：`server/internal/governance/approval_crosscheck_test.go`
  - 非 code 阶段用 `newCrosscheckWorkspace`，其中 `:143–151` 会在 `ws/.crctl/keys/` 写入 `approval-crosscheck.pub`；
  - code 阶段用 `newCrosscheckCodeWorkspace`（`:321` 起），**从未写该公钥**，但同样把 `--workspace` 指向 CR worktree，crctl 按安装根 `ws/.crctl/keys` 查找 → 必然 `KEY_NOT_FOUND`。
- 对照实验：把 `CRCTL_PATH` 指向 `git archive a5ecb5783fd8f7b5fa1d0d3b328b704199bbe011`（tools 未污染 HEAD 导出，259 文件），同一用例 **同样 exit 1、同样两个子用例失败、同样 `KEY_NOT_FOUND`**，5.6s。
- 结论：**既有 latent 缺陷**（fixture 少写公钥），仅在有可解析 crctl 的环境中暴露；与 tools S0/T01–T03 未提交候选无关，也不是 T01–T03 引入的回归。CI 中没有 sibling tools 时会 `t.Skip`，所以一直未被发现。

### 4. 反向对照（证明“exit 0 ≠ 通过”）

- `DATABASE_URL` 指向不可达 `127.0.0.1:9`（`connect_timeout=2`）跑同一哨兵：**exit 0，零 case 启动**，输出 `Skipping governance integration tests`，3.3s。
- 这实证了 M00.1 的伪绿风险：没有数据库前置时，exit 0 完全不代表任何断言被执行。

### 5. 编译（候选可构建性）

- `go build ./...`：exit 0，13.1s，无输出。

## 证据

```text
C:/Users/GOBAO/AppData/Local/Temp/aifi45-m00-pg/
  migrate-stdout.log / migrate-stderr.log / migrate-result.json
  sentinel-stdout.log / sentinel-stderr.log / sentinel-result.json
  gov-stdout.log / gov-stderr.log / gov-result.json      # 整包 192P/1F/1S
  head-baseline-code-crosscheck.log                      # HEAD tools 同样失败
  negative-unreachable-db.log / negative-result.json      # 无DB伪绿对照
  go-build.log
  conn.json / cleanup.json                               # 临时库与清理事实
  tools-head/                                            # git archive HEAD 只读导出
```

## 边界

- 本次只覆盖 governance 包，未跑全仓 Go/TS/E2E，未跑跨仓 Runner/daemon 集成；不代表四阶段平台闭环。
- 该 1 项失败使 M00 “整包绿”不成立；是否修 fixture 属下一步范围决策（修 fixture 不改产品行为，但会动 multica 测试文件）。
- 未提交、未推送、未部署、未触碰真实 CR 或存量数据。

## AIFI-45 / M00 fixture 修复与定向交接（2026-10-19 追加）

### 历史归因勘误（上文原记录保留，以本节纠正措辞）

- 上文“code 阶段从未写该公钥／fixture 少写公钥”不精确。已重新读取两个 workspace helper、签名／发布／grant helper 的全部调用方，以及当前 crctl 和 pristine HEAD 导出中的 `verifyGrantSignature`、`deriveInstallRoot`：两个 code 子例都会调用 `signCrosscheckGrantWithDigest(t, worktree, ...)`，原 helper 确实生成随机 Ed25519 密钥并写入公钥，但落点是 **CR worktree 的 `.crctl/keys/approval-crosscheck.pub`**。
- crctl 从 Git `--git-common-dir` 推导安装根，只读 **安装根的 `.crctl/keys/approval-crosscheck.pub`**；两个 code 子例丢弃了 `newCrosscheckCodeWorkspace` 返回的安装根，把同一个 worktree 参数同时用于公钥发布和 grant 落盘。精确根因是 **fixture 混淆公钥安装根与审批工作区**，不是未生成公钥，也不是产品密钥解析缺陷。
- 上文“CI 中没有 sibling tools，所以一直未被发现”未经历史执行证据证明，撤回该推断。只读核实当前 `.github/workflows/ci.yml:122–134` 确有 pinned tools checkout（`.aifirst-tools`）供生成器检查；不能将某个 job 的 checkout 或 helper 可 skip 的源码分支当作历史治理接缝执行／skip 原因。
- 上文 **192 PASS / 1 FAIL（父用例，2 个失败子例）/ 1 SKIP**、pristine tools HEAD 同样两个 `KEY_NOT_FOUND` 的对照、不可达 DB exit0 零 case 等执行数字仍为历史事实；本轮未重跑或改写这些历史结果。

### 新隔离目标与执行约束

- 本轮使用主会话新建的 `aifi45-m00-repair-izez2oby`，不是已删除的旧容器或旧 `conn.json`。
- 主会话提供的归属信息：Podman **5.8.5**，容器 `aifi45-m00-repair-izez2oby-pg`、专属命名卷 `aifi45-m00-repair-izez2oby-data`；`127.0.0.1:34131`，库 `aifi45_test`／用户 `aifi45`，已应用 651 迁移、最高 621。fixture 执行者仅校验私密配置中的目标身份并跑指定测试，未另行操作 runtime、迁移或容器；资源清理由主会话负责。
- 私密配置只从 `C:/Users/GOBAO/AppData/Local/Temp/aifi45-m00-repair-izez2oby/private-connection.json` 读取。`DATABASE_URL` 与 `CRCTL_PATH` 均显式取该文件；未输出口令／完整 DSN，未读仓库 `.env`，未使用继承的连接。
- Go 及其 Node／Git 子进程只继承白名单运行必需环境；不传 `KNOWLEDGE_BASE_REMOTE_URL`／`KNOWLEDGE_BASE_TOKEN` 或外部认证、Node 配置、任务绑定变量。显式 `GOTOOLCHAIN=local`、`GOPROXY=off`、`GOENV=off`；Git system/global 配置只在子进程环境禁用，不改机器全局设置。
- `CRCTL_PATH` 指向当前冻结 tools checkout 的 `skills/shared/crctl/scripts/crctl.mjs`，不使用旧 HEAD 导出替代候选。259 个 tracked tools 文件 canonical-LF manifest 在全部三次运行前后均为 `eb99e18aad2292a614a133b35a9265b6505c852a0bf7897c519e4dbf973d6984`；HEAD 仍 `a5ecb5783fd8f7b5fa1d0d3b328b704199bbe011`，不以 HEAD 冒充未提交候选身份。

### 最小修复

- 仅改 `server/internal/governance/approval_crosscheck_test.go`，Git numstat **8 行增／7 行删**：
  1. `signCrosscheckGrantWithDigest` 增加独立 `keyRoot` 参数，公钥只通过已有 `publishCrosscheckKey` 写到该根；grant 仍通过原 `writeSignedGrant(t, ws, grant)` 写入审批工作区。
  2. 普通三阶段 wrapper 传 `(ws, ws)`；两个 code 子例接住 fixture 返回的安装根，传 `(ws, worktree)`。
  3. 增加一行英文说明；两个 code 子例的 `--workspace` 与 grant 位置继续使用真实 linked worktree。
- 不复制公钥到多个根、不改产品 resolver／fallback、不固定新假密钥、不旁路验签，不新增 skip。保留 `ed25519.GenerateKey(rand.Reader)`、原 key ID、approver 和所有 approve／reject rollback／adjacent replay／release-subjects 断言。
- 现有两个 code 子例已经在真实 Go 签名 → crctl 验签／权威回退接缝上先红后绿，不增冗余测试框架或更浅的 helper 测试。

### 本轮实际 RED → GREEN（父／子分别计数，不相加冒充独立用例）

工作目录均为 `multica/server`，原生命令前缀均为 `go test -count=1 -json -v ./internal/governance/ -run`：

| 运行 | 精确选择器 | native exit | 单调耗时（秒） | 父测试 | 子测试 |
|---|---|---:|---:|---|---|
| 修复前 RED | `^TestGrantCrossVerifiesWithCrctlCodeStage$` | 1 | 5.661143 | 1 FAIL | 2 FAIL |
| 修复后 code GREEN | `^TestGrantCrossVerifiesWithCrctlCodeStage$` | 0 | 6.202398 | 1 PASS | 2 PASS |
| 修复后全部跨阶段接缝 GREEN | `^TestGrantCrossVerifiesWithCrctl(CodeStage)?$` | 0 | 9.715584 | 2 PASS | 8 PASS |

- 三次都有正数 `run`／终态事件；均 **0 SKIP**，没有 `Skipping governance integration tests`。RED 确认恰有两个安装根 `KEY_NOT_FOUND`；两次 GREEN 均无该错误。
- 全部接缝覆盖 requirement／tech-design／dev-start／code 四阶段各一项 approve+replay 和一项 reject rollback+replay。reject 的业务非零退出仍由原断言校验，不把它改成产品成功返回。
- 每次运行前后 3592 个 tracked `server/` 文件 canonical-LF 哈希均未变；RED→最终 GREEN 唯一 server 源码差异就是指定 fixture，生产源码及其它测试无变化。全部 `if`／`t.Fatal*` 行逐行对照 HEAD 保持原样，随机密钥生成仍保留。
- `git diff --check` native exit0。直接 `gofmt -l` 会因本机 checkout 的 CRLF 列出该文件；LF 规范化后送入原生 `gofmt`，exit0 且输出字节不变。保留原 CRLF，不做全文件行尾重写。
- 冻结 fixture canonical-LF SHA-256：`3785cd12d4f7001d000884134efeeb648241d04c07e5bea60c37f00adb011885`；本机 CRLF 原字节 SHA-256：`d15c31c393412e9725287ee1d3b2f578f613dd5adcd9eb964cf018315b6fb68f`。

### 持久证据与交接边界

证据根：`C:/Users/GOBAO/AppData/Local/Temp/aifi45-m00-repair-izez2oby/fixture-evidence/`（显式 OS Temp 目录，不依赖会话自动清理临时文件）。

- `run-target.py`：白名单环境／目标身份校验、原生命令、单调计时、父子计数与源哈希采集器；配置值不落公开结果。
- `{red-code,green-code,green-all-crosschecks}-{stdout.jsonl,stdout.log,stderr.log,result.json,before.json}`：完整原生证据、各次实际计数、运行前文件哈希与前后比较；结果只含非秘密目标身份及环境键名。
- `diff.log`／`numstat.log`／`diff-check.log`／`fixture-review.json`：最小 diff、断言不变和源身份；`gofmt-current-diff.log`／`gofmt-baseline-diff.log` 保留 CRLF 格式诊断，不能把直接 `gofmt -l` 称作空输出。
- `m00-original.md`：追加前记录原字节快照，用于核对历史前缀没有覆盖。

**源码已冻结并释放给主会话。** 本轮未运行 governance 整包回归；本定向 GREEN 不能替代 M00 整包 actual green，业务 feature 实施仍须等待主会话唯一整包复测。未改 `CUSTOM.md`、tasks、phase contexts、任何 `.env` 或账本；主会话负责登记及 owned 命名资源清理。无提交／push／部署／真实 CR／审批状态操作。

建议主会话按现行六列表结构补充既有 `CUSTOM.md` 明细 #26：沿用原追溯，追加“**AIFI-45 / M00：签名 fixture 分离公钥安装根与 grant/worktree；8 个跨阶段子例全部真实通过，随机 Ed25519 与原断言不变；test-only，不改产品密钥解析**”，并在合并注意中保留显式配置、真实 DB 前置和父／子分别计数要求。不由本执行者改台账或分配新编号。

## 主会话最终整包复测与 M00 交接（2026-10-19）

在上述 fixture writer 交回所有权后，主会话独占运行 `go test -mod=readonly -count=1 -v -json -timeout 1500s ./internal/governance/`；未传 `-run`、skip 或文件排除。仍只用本次明确自建的 Podman PG，子进程白名单运行必需环境及显式私密 DB/CRCTL_PATH，`GOTOOLCHAIN=local`、`GOPROXY=off`；不继承外部 GitHub/KB 认证或仓库 `.env`。

| 事实 | 原生结果 |
|---|---|
| native exit / package final action | **0 / pass** |
| 单调耗时 | **20.688403600128368 秒** |
| 父测试 | **193 PASS、0 FAIL、1 SKIP** |
| 子测试 | **75 PASS、0 FAIL、0 SKIP** |
| RUN / 完结事件 | **269 / 269**（父/子分层事件，不能相加冒充独立父用例） |
| 既有外部跳过 | 仅 `TestReconcileLiveGitHub`；未授权连接实时 GitHub，不以该项为已验证 |
| DB 空跑提示 | 无 `Skipping governance integration tests`；正数实际用例，不以 exit0 单独判绿 |
| 源冻结 | 3592 个 tracked `server/` 文件运行前后一致；259 个 tools 文件前后一致，manifest 仍 `eb99e18aad2292a614a133b35a9265b6505c852a0bf7897c519e4dbf973d6984` |

证据（主会话稳定 OS Temp 根 `C:/Users/GOBAO/AppData/Local/Temp/aifi45-m00-repair-izez2oby/`）：

- `setup-result.json`、`migrate-stdout.log` / `migrate-stderr.log`：服务版本 5.8.5、专属容器/已知 named volume/标签、回环动态端口、651 条迁移；不把服务版本差异称作安装/升级。
- `governance-full.jsonl`、`governance-full.stderr.log`、`governance-full-result.json`：完整原生事件、单调耗时、命令/分层统计及前后不漂移结论。
- `fixture.diff` 及 `fixture-evidence/`：本次唯一 M00 server diff 为测试 helper +8/-7；后续 M10 改动不回填为本次 baseline 的源码身份。

独立审查者 `01a1542e-a81c-75ce-a57c-1b9a4ea12e0d` 已只读核对实际 diff/所有 helper caller、安装根 resolver、随机 Ed25519 与原安全断言；Standards/Spec **无硬问题**。该审查者未运行整包，其报告中的“未验证整包”是审查边界，不覆盖上表主会话原生结果。

主会话已更新既有 `CUSTOM.md` #26（保留原 CR-2026-030 TASK-07 历史，追加本维护 Issue AIFI-45 / STDD M00，不另注册 CR），并勾选 M00 三个验证动作。已核对 TC-MDISPATCH-007 → M-CP-DISPATCH-007：最终 CP 还要求后续 `TestMDispatch001` / `TestMDispatch005` 实际 PASS；M00 哨兵和这次整包不能代替它们或完整四阶段验收。

用户最新“按建议继续，需要我参与时再停下来”授权正常范围内连续实施；随后进入既有任务 **M10a/M10b → M11–M15**。上一回复“M02–M09”是编号不准确，未重编号任何 canonical/任务。本次具名容器和 named volume 随后供 M10 授权整包测试占用，结束后已按确切名称/run-id 标签核验后删除，两 remove exit0/两 exists exit1，端口复核关闭、私密连接文件已删；没有触碰已有库/资源。后续 M10 整包三个 source 传递回归及独立审查工具禁用的停点见 M10-build-report.md，不用这份历史 M00 绿基线替代新候选结果。未提交/push/部署/真实 CR/Gate3。
