# AIFI-45 一次性库实例生命周期与测试守卫边界 — 技术设计

> 模式 standard：按 STDD spec 阶段规则，仅 thorough 才派 planner 子代理，所以本设计由主会话起草，未升档。proposal 阶段已有一次 strong 档（`kimi-k3.1-pro:max`）独立挑战，5 条意见已吸收。Step 5.5 设计审查的结果在 Gate 2 确认框中汇报。

## Context

`scripts/aifi45-disposable/` 已有真实可用的**库级**隔离：`provision.mjs` 在给定的 admin 连接上建 nonce 库和角色、写 `AIFI45_DISPOSABLE:<nonce>` 标记，drop 前回读；`run-selection.mjs` 按 `selections.json` 的清单逐个选择建库、跑 `go test`、销毁。`cmd/server` 的 TestMain 核验 nonce。AIFI-45（11 选择/207 PASS）和 M005（12 选择/227 PASS）已用它验收。

缺口：

1. admin 连接来自 `--admin-url` 或 `AIFI45_ADMIN_URL`，入口不校验它指向什么。容器要由各会话手工创建删除，遗留过归档 change 的容器（已于 2026-11-10 释放）。
2. `server/internal/governance/crsync_test.go` 的 TestMain 只检查 `DATABASE_URL` 非空，不核验库身份。
3. `scripts/go-test-with-agent-cli-guard.sh` 与 `scripts/test-go.test.sh` 把 `${TMPDIR:-/tmp}` 下的目录拼进 `PATH="$BIN_DIR:$PATH"`；TMPDIR 含 `:` 时 PATH 被拆开（静态风险，未实测）。

约束：不改 `provision.mjs` 与 `selection.mjs` 的库级逻辑；不改 CI 工作流（fork CI 的失败是多因的，见 `docs/analysis/fork-ci-failure-register-20261111.md`）；Windows 下 Node 不能向目标投递 SIGTERM，信号处理不可测，不作保证。

## Decisions

### 1. 入口自建、自释放实例，不再接受外部 admin 连接

**方案**：新增 `scripts/aifi45-disposable/instance.mjs`，导出 `buildRunArgs`、`startInstance`、`releaseInstance`。`run-selection.mjs` 在取得清单后调用 `startInstance`，用返回的 `adminUrl` 驱动既有的逐选择流程，在 `finally` 里调用 `releaseInstance`。`--admin-url` 参数直接报错退出；不再读取 `AIFI45_ADMIN_URL`。

**为什么**：单一来源决定容器的创建参数，入口不再被动信任调用方给的连接，也就没有"谁来清理"的归属问题。

**排除**：保留 `--admin-url` 并加校验（仍需校验"该主机上的这个端口是不是我们的容器"，且调用方仍要手工建删容器）；沿用 `scripts/aifi45-db/` 下 instance-* / supervisor-* 草稿（fake-I/O 草稿含 journal、恢复协议，是被收窄掉的范围）。

### 2. 容器创建参数固定为一个"资源信封"

`buildRunArgs({nonce, ttlSeconds})` 返回确定的参数数组，`startInstance` 用它调用 `podman run -d`：

| 项 | 取值 | 原因 |
|---|---|---|
| 镜像 | `docker.io/pgvector/pgvector:pg17` + `--pull=never` | 不触发网络拉取；镜像不在本机则直接失败。与 CI 和 multica 的 PG 版本一致 |
| 端口 | `-p 127.0.0.1::5432` | 只绑回环，随机宿主端口 |
| 数据 | `--tmpfs /var/lib/postgresql/data`，无 `-v`/`--volume`/`--mount` | 不留卷；PG17 镜像把该路径声明为 VOLUME，tmpfs 覆盖它 |
| 标识 | `--name aifi45-disposable-<nonce>`，`--label aifi45.disposable=<nonce>` | 释放时核对归属 |
| 生命周期 | `--rm` + `--timeout=<ttlSeconds>`，默认 3600，上限 3600 | 强杀、崩溃时靠 podman 到期自毁兜底 |
| 凭据 | `POSTGRES_PASSWORD` 取随机值，经子进程环境传入（`--env POSTGRES_PASSWORD`，不在 argv 里） | 不进命令行、不进日志 |

`nonce` 为 16 位小写十六进制随机数（与 provision 的 nonce 形态一致，但属于实例，不是库的 nonce）。

**连接交接**：`podman run -d` 返回 64 位十六进制完整 ID（校验形态）。再用 `podman port <ID> 5432/tcp` 取宿主端口，输出必须恰好一行且主机部分为 `127.0.0.1`，否则按"绑定逃逸"处理：释放并报错。`adminUrl` 由密码和端口在内存里拼出，只传给 `provision`，不打印。就绪等待是有界重试：注入的 `connect` 对该 URL 执行 `SELECT 1`，最多 30 次、间隔 1 秒，超限就释放实例并报错，没有"放宽条件继续"的退路。

**排除**：用 `--publish-all` 或 host 网络；用 bind mount 做数据目录（会留文件）；在 argv 里放密码（`podman inspect`/`ps` 可见）。

### 3. 释放：只按完整 ID，核对归属后才删

`releaseInstance({id, nonce})`：

1. `podman ps -a --no-trunc --filter id=<ID> --format '{{.ID}}|{{.Names}}|{{.Labels}}'`；
2. 回读必须恰好一行且首列 ID 等于入参，名称必须等于 `aifi45-disposable-<nonce>`，标签集合（逗号分隔解析）必须含精确的 `aifi45.disposable=<nonce>`；任一不符就**不发出删除命令**，抛错并保留实例（由 TTL 兜底）；
3. `podman rm -f -v <ID>`；
4. 读回：按 ID 查和按 `label=aifi45.disposable=<nonce>` 查都必须为空，否则抛错；成功返回 `{id, remaining: 0}`，入口打印一行证据（ID 前 12 位、remaining=0）。

查询与删除都走 `spawnSync`，所以任何同步或 `finally` 路径都能用。`podman` 调用经注入的 `run(args, {env})`，默认实现是 `spawnSync('podman', ...)`，单元测试用假实现。

**排除**：按名称删除（名称可被同名新容器占用）；`podman rm` 前不回读（本机曾遗留过不属于当前 change 的容器，不能盲删）；清扫器按标签批量删（要处理并发入口的归属，范围外）。

### 4. 生命周期兜底：TTL，不做信号处理、journal 或恢复协议

入口在成功和失败两条自己控制的路径上释放（`try/finally`）；强杀、崩溃、断电、会话丢失由 `--rm --timeout` 兜底，容器在上限内必然消失。TTL 默认 3600 秒是整个入口一次运行的上限；现有两次验收的全部选择远小于此。入口不注册 SIGINT/SIGTERM 处理：Windows 下无法验证，保证写在 TTL 上，不写在信号上。

**排除**：journal + 恢复、lost-ack 对账、进程树证明（已在 proposal 收窄时砍掉）；独立守护进程。

### 5. governance TestMain 核验一次性库身份

**方案**：在 `crsync_test.go` 的 TestMain 里，`pool.Ping` 之后、取 lease 与写 fixture 之前，调用同包的 `verifyDisposableTestDatabase(ctx, pool, nonce)`，条件与 `cmd/server` 的同名函数一致：nonce 为 16 位十六进制、`current_database()` 为 `aifi45_tmp_<nonce>`、会话角色与 `aifi45_role_<nonce>` 一致、库注释等于 `AIFI45_DISPOSABLE:<nonce>`、同时核对库角色注释为 `AIFI45_DISPOSABLE:<nonce>`、角色不是超级用户且没有 createdb/createrole/bypassrls、库属主是该角色。失败时向 stderr 写消息并 `os.Exit(1)`（与该 TestMain 现有的失败路径一致），消息含 `governance integration test disposable identity mismatch`。

**为什么重复实现一份**：`cmd/server` 是 `package main`，其测试辅助函数无法被 governance 导入；`internal/testutil` 是上游维护的 fixture 包，往里加本仓独有的规则会扩大与上游的冲突面。governance 自己的 `execution_control_migration_test.go` 本来就持有一份相近的检查。两份规则靠各自的拒绝测试对齐，差异在评审时核对。

同时修正 `crsync_test.go` 里指向旧 `run.mjs` 的陈旧注释。

**拒绝测试**：新增 `TestMainRejectsWrongDisposableNonceBeforeSetup`（governance 包）：父进程取当前 fixture workspace 的 `updated_at`，用错误 nonce 重新执行测试二进制（`-test.run=^$`），子进程必须在 15 秒内以非零退出并输出该消息；父进程再读 `updated_at`，必须不变。"不变"比 cmd/server 的"仍存在"更强：fixture 的写入是带 `ON CONFLICT DO UPDATE` 的 upsert，被执行就会改动该值。TC-DTI-007 的证据使用 `selections.identity.json` 的两个单测试选择，分别执行该拒绝测试和 `TestVerifyDisposableTestDatabaseRejectsMismatch`，零匹配即失败；完整 `selections.json` 的 13 个选择另作 C2 回归，需调用方导出 `AIFI45_TOOLS_ROOT`，结果单独记录于 test-report，不属冻结证据。

### 6. 测试包装脚本拒绝含 `:` 的 TMPDIR

**方案**：`go-test-with-agent-cli-guard.sh` 在 `mktemp` 和改写 `PATH` 之前，取 `TMP_ROOT=${TMPDIR:-/tmp}`，含 `:` 就向 stderr 写明原因并 `exit 2`。`test-go.test.sh` 在自己的 `mktemp` 之前做同样的检查。`TMPDIR` 为空或未设时回退 `/tmp` 的行为不变。

**为什么拒绝而不是转义**：POSIX 的 `PATH` 用 `:` 分隔，没有可移植的转义；拒绝并给出明确提示，是最小且不改变既有行为的处理。

**复现与验证方式**：guard 的测试在 `test-go.test.sh` 的私有临时目录里造一个含 `:` 的子目录当 TMPDIR，传入一个绝对路径假命令，假命令写标记文件；修复前假命令被执行、标记存在（RED），修复后 guard 非零退出、标记不存在。`test-go.test.sh` 自身的拒绝只在**修复后**验证，且用一个不存在的含 `:` 的 TMPDIR：修复前 `mktemp` 会先失败，不会走到改写 PATH、解析到真实 `go`，所以不需要运行修复前的行为。

## Architecture

```text
run-selection.mjs
  ├─ parse args (--admin-url → 退出 1)
  ├─ startInstance ──► podman run -d (buildRunArgs) ──► ID
  │                    podman port → 127.0.0.1:<port>；SELECT 1 有界重试
  ├─ for each selection:  provision(adminUrl) → go test → drop   （既有逻辑，不改）
  └─ finally releaseInstance(ID): 回读名称+标签 → rm -f -v → 按 ID 与标签读回为 0

强杀入口 → 无 finally → 容器由 --rm --timeout 到期自毁
```

## 变更落点

| 文件 | 改动 |
|---|---|
| `scripts/aifi45-disposable/instance.mjs`（新） | 信封、启动、释放 |
| `scripts/aifi45-disposable/instance.test.mjs`（新） | 信封与释放的单元测试（假 `run`） |
| `scripts/aifi45-disposable/instance.real.mjs`（新） | 真实 podman 的生命周期与 TTL 测试；文件名不含 `.test.`，默认通配不执行，只显式运行；清理只释放测试自己拿到的实例 ID，不扫描；拿不到 ID 时由实例自身 `--timeout` 兜底 |
| `scripts/aifi45-disposable/run-selection.mjs` | 用 `instance.mjs` 取代 `--admin-url`/`AIFI45_ADMIN_URL`；`finally` 释放 |
| `scripts/aifi45-disposable/run-selection.test.mjs`（新） | `--admin-url` 被拒 |
| `scripts/aifi45-disposable/selections.json` | 增加 `governance-identity`，用于 C2 回归 |
| `scripts/aifi45-disposable/selections.identity.json` | TC-DTI-007 使用的两个单测试选择 |
| `server/internal/governance/crsync_test.go` | TestMain 身份核验、拒绝测试、注释修正 |
| `scripts/go-test-with-agent-cli-guard.sh`、`scripts/test-go.test.sh` | 拒绝含 `:` 的 TMPDIR |
| `CUSTOM.md` | 按其结构登记本 change 的定制 |

## Risks / Trade-offs

| 风险 | 缓解 |
|---|---|
| `--rm` 加 `--timeout` 在 podman machine 远程模式下的行为只见文档与 `--help` | build 阶段先做一次真实强杀验证（TC-DTI-005，显式运行真实测试文件）；通不过回头改方案，不用补丁绕过 |
| 释放时回读的标签格式因 podman 版本而异 | 用 `--format '{{.ID}}|{{.Names}}|{{.Labels}}'`，按 `,` 切分后精确匹配键值，不做子串匹配；单元测试覆盖带多个标签的情形 |
| 入口异常早于取得容器 ID（`podman run` 自身超时/断连） | 此时没有 ID，无法按 ID 释放；容器若已创建由 TTL 兜底。不另加按名称/标签的"补救删除" |
| governance 与 cmd/server 的两份身份检查口径漂移 | 两个包各有拒绝测试；差异评审时核对。接受"两份"的代价，换取不碰上游包 |
| 真实 podman 测试在无 podman 的环境不可运行 | 不显式运行真实测试文件，单元测试不依赖 podman；真实路径的证据须在具备条件时执行并记在 test-report |
| TTL 3600 秒内一次入口运行不完（选择变多） | 到期容器被销毁，后续选择因连接失败而失败，不会静默通过；改上限需要走本 change 的设计调整 |

## 不在本设计内

journal、lost-ack、进程树证明、清扫器、库级回滚、`scripts/aifi45-db/` 草稿接线、CI 改动、网络隔离、重开 AIFI-45/M005 验收。
