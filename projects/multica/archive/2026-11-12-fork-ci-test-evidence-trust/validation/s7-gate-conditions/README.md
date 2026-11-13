# S7 验证证据 — nonce 门禁逐条件覆盖（TC-CBE-002，按 R2）

切片 7 只补测试，不改门禁。两份 `verifyDisposableTestDatabase`（`server/cmd/server/integration_test.go`
与 `server/internal/governance/crsync_test.go`）把 11 条拒绝折叠进同一个 `if`，原有测试只证明
"某个错身份会被拒"，无法说明哪一条仍然有牙。本切片为两份各补一份表驱动测试，逐条单独退化。

## 1. 产出物

| 文件 | 性质 |
|---|---|
| `server/cmd/server/disposable_identity_conditions_test.go` | 新增（自研，214 行） |
| `server/internal/governance/disposable_identity_conditions_test.go` | 新增（自研，214 行，与上者仅 `package` 子句不同） |
| `scripts/aifi45-disposable/selections.json` | 追加 `ci-gate-identity`、`ci-gate-identity-server` |
| `scripts/aifi45-disposable/selections.identity.json` | 同上 |

两份测试文件的手段：从**这个库真实报出的身份**读一行（`current_database()`、`current_user`、
`session_user`、`datdba = r.oid`、两个 `shobj_description` marker、四个权限位），再经门禁自己的
`pgx.Row` 接口回放。11 条里只有库 marker 能在真库上真实改写（既有测试
`TestVerifyDisposableTestDatabaseRejectsMismatch` 就在事务里 `COMMENT ON DATABASE` 改过它）。
其余 10 条受 nonce 角色权限所限——非 superuser、无 CREATEROLE，不能改自己正连着的库名/角色名，
也不能给自己加权限位——所以回放是覆盖它们的唯一手段，不是偷懒。

## 2. 真实执行（一次性 podman 实例，非 CI）

命令（两次独立调用，各自自建并释放实例）：

```
node scripts/aifi45-disposable/run-selection.mjs \
  --selections scripts/aifi45-disposable/selections.identity.json \
  --only ci-gate-identity        --evidence-dir <本目录>/events
node scripts/aifi45-disposable/run-selection.mjs \
  --selections scripts/aifi45-disposable/selections.identity.json \
  --only ci-gate-identity-server --evidence-dir <本目录>/events
```

| selection | package | pass | fail | skip | runner 退出码 | 实例 |
|---|---|---|---|---|---|---|
| `ci-gate-identity` | `./internal/governance` | 16 | 0 | 0 | 0 | `4f3f92bc42d2` released remaining=0 |
| `ci-gate-identity-server` | `./cmd/server` | 16 | 0 | 0 | 0 | `2ad8a85e936d` released remaining=0 |

16 = 1 个顶层 + 11 个条件子测试 + 3 个 nonce 变体 + 1 个"身份读不出来"测试（`go test -json`
的 pass 事件含中间父测试）。两个包的流里都出现全部 11 个条件名：
`bypassrls createdb createrole database-marker database-name database-owner nonce-format
role-marker role-name session-user superuser`。

证据：`green-ci-gate-identity.txt`、`green-ci-gate-identity-server.txt`（含 16 条 PASS 事件名），
原始流 `events/*.ndjson` 与 runner 结论 `events/*.json`。

## 3. 变异验证：11 条拒绝各自有牙（两份门禁同时变异）

对每条拒绝，从**两份**门禁里各删掉它对应的一个项（nonce 格式守卫整条置 `if false`），
在一次性库上真跑两个包，要求"该条件子测试在两个包里都变红"，随后恢复原字节并核对 sha256。

结果：**11/11 DETECTED**，两份门禁逐字节恢复。

```
sha256 cmd/server   before=899f8ddf7d6ef3328bc11a144295b44635bbc0e79c5e6eb838ae7e2adf83eb21 after=同值
sha256 governance   before=04221be49c5c236605ecc17e4521573ea8856bfdd6622224d4c141c6ab4497eb after=同值
```

证据：`mutation-gate-conditions.txt`（逐条件判定、变红的子测试全名、实例释放行）、
`mutation-fail-events.txt`（22 条流的 pass/fail/skip 与真实失败报文）。
每条变异都新建并释放了自己的一次性实例（11 个实例，全部 `remaining=0`）。

### 3.1 探针抓到的真实缺口（已修，不是探针 bug）

第一轮探针 `role-name: NOT DETECTED (runner exit=0)`。根因：门禁里有 `sessionRole != role`，
只改 `Role` 时这条比较先兜住它，`role != "aifi45_role_"+nonce` 那一项删掉也照样红——
也就是说"角色名"这一项当时**没有被单独钉住**。

修法：`role-name` 条件同时把 `Role` 与 `SessionRole` 移到同一个错值，使"角色名"成为唯一
被违反的条件；表字段由 `column string` 改为 `columns []string`，并用
`slices.Sort`/`slices.Equal` 断言"实际变化的列集合 == 声明的列集合"。修后 `role-name`
与 `session-user` 两条都 DETECTED。记为 ADJ-011。

## 4. 门禁未改（任务 7.3）

- `git status --porcelain -- server/cmd/server/integration_test.go server/internal/governance/crsync_test.go`
  输出为空。
- 两份门禁 sha256 与切片开始时一致（见上）。
- 未放宽任何拒绝条件，未改错误串（R2：条件名由 `t.Run` 子测试承载）。

## 5. 容器边界

`containers-before.txt` 与 `containers-after.txt` 按排序后集合比对无差异（`containers-compare.txt`；
before 捕获时未排序，after 已排序），只有两个既有旧容器且均为 Exited：

```
multica-backend localhost/multica-backend:81e5293adc Exited (0) 292 years ago
multica-postgres docker.io/pgvector/pgvector:pg17 Exited (0) 292 years ago
```

全程未连接 `localhost:5432`，未操作 `multica-postgres`。所有数据库均由 `run-selection.mjs`
自建的一次性 podman 实例提供，用后释放。

## 6. 未覆盖 / 如实标注

- **这不是 CI 执行**：CI 的 nonce 库由 `ci-provision.mjs` 提供（S6 已单测，真实 up/down 属 S13 + TC-CBE-005，尚未执行）。
- 本切片未在 ubuntu-latest 上跑过这两个 selection。
- 10 条条件用回放而非真库退化，理由见 §1；真库能造的库 marker 由既有测试
  `TestVerifyDisposableTestDatabaseRejectsMismatch` 在事务里真实改写过，本切片不重复。
## 7. 整包回归（受影响包 + node 目录）

| 命令 | pass | fail | skip | 与 S4 基线对比 |
|---|---|---|---|---|
| `node --test "scripts/aifi45-disposable/*.test.mjs"` | 154 | 0 | 0 | 与 S6 相同（`regression-directory.tap`） |
| `run-selection --only baseline-cmd-server` | 675 | 0 | 0 | 659 + 16 新增，失败集合为空 |
| `run-selection --only baseline-governance`（注入 tools 变量） | 1344 | 48 | 1 | 1328 + 16 新增，**失败集合逐名完全相同** |

证据：`regression-go/`、`regression-go-env-present/`。

**一次环境差异的如实记录**：第一次跑 `baseline-governance` 得到 1312 pass / 59 fail，
比基线多 11 个失败。逐名比对后确认**全部**是 `CRCTL_MJS` / `AIFI45_TOOLS_ROOT` 缺失触发的
Fatal（S3 守卫按设计生效），当前 shell 没有这两个变量，而 S4 基线运行时它们存在
（`s4-baseline-ownership/README.md:98`）。注入同一环境重跑后失败集合与基线**逐名相同**，
新增 16 个通过事件即本切片的新测试。**不是 S7 引入的回归**；两次流都留档以便复核。
