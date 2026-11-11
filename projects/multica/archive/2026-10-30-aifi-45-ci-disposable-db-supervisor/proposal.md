# AIFI-45 一次性库实例生命周期与测试守卫边界

<!-- source_hash: 6726ba499f4f28ec -->
<!-- generated_at: 2026-11-11T00:09:29.339272 -->
<!-- canonical: canonical/proposals/2026-10-30-aifi-45-ci-disposable-db-supervisor.yaml -->

## Why

AIFI-45 与 M005 的真实库回归已经在一次性库上取得证据（数据库级隔离与标记校验已有测试和真实运行支撑），本 change 不再重做。仍然缺的是实例这一层：
1. 容器由各会话手工创建和删除，没有版本化入口。一个标签属于 `2026-10-22-aifi-45-authorized-execution` 的容器（`aifi45-disposable`，127.0.0.1:55432）在该 change 归档后仍运行约两小时，M005 会话因归属未核实而未动，直到本次凭标签、代码里的固定 ID 和创建时间核对后才释放。
2. `run-selection` 接受任意 admin URL，入口本身不能保证测试只触及自己创建的实例。
3. governance 的 TestMain 只要求 `DATABASE_URL` 非空，不像 cmd/server 那样核验一次性库身份，普通 `go test` 带着误指的 DATABASE_URL 就会向该库写 fixture。
4. test-go 的 CLI guard 及其测试把 `${TMPDIR:-/tmp}` 下的目录直接拼进以 `:` 分隔的 PATH；TMPDIR 含冒号时 PATH 被拆分，sentinel 或假 go 找不到。静态推导成立，未实测。


## What Changes

- 新增一次性库实例生命周期（`scripts/aifi45-disposable/` 下一个小模块），并让 `run-selection` 只使用它创建的实例：
入口自行创建容器，按完整容器 ID 取回环端口并派生连接地址（有界重试等待就绪，无回退），子进程沿用现有的 DATABASE_URL 与 nonce 覆盖；`--admin-url` 参数被拒绝，环境变量 `AIFI45_ADMIN_URL` 不再读取；在自己控制的退出路径（成功、失败）上按完整容器 ID 释放，释放前回读名称与标签确认归属，释放后回读为零并输出；强杀或崩溃由实例生命周期上限兜底。
资源信封即下列固定内容，写在代码中，改动任一项即扩大信封、须重新审批：本机已有镜像 `docker.io/pgvector/pgvector:pg17`（`--pull=never`）；仅 `127.0.0.1` 随机宿主端口；数据目录 tmpfs、无 bind mount 和 volume；容器名 `aifi45-disposable-<nonce>` 与标签 `aifi45.disposable=<nonce>`；每次随机密码、不落盘不入日志；`--rm` 加 `--timeout`（上限值在设计阶段定，不超过 1 小时）。
数据库级逻辑（`provision.mjs` 的 nonce 库、角色、标记、drop 前回读）保持不动。

- governance 的 TestMain 在写任何 fixture 之前核验一次性库身份，口径与 cmd/server 的 `verifyDisposableTestDatabase` 一致，不匹配即以非零退出；同时修正其注释中指向旧 `run.mjs` 的陈旧说明。
- test-go 的 CLI guard 与 `test-go.test.sh` 在创建临时目录和改写 PATH 之前，拒绝含 `:` 的临时根并给出明确报错；`${TMPDIR:-/tmp}` 的空值回退和既有正常路径行为不变。

### New Capabilities

- **disposable-test-instance**：AIFI-45 真实库测试只运行在入口自己创建、可证明归属、有生命周期上限的一次性实例上，并在受控退出路径上被释放；Go 集成测试拒绝非一次性库。
- **test-wrapper-path-guard**：测试包装器不把含 `:` 的临时根拼进 PATH，避免 sentinel 与假工具因 PATH 被拆分而失效。

## Success Criteria

- [ ] 一次真实运行（至少一个选择真实通过、一个选择失败）后，入口输出实例的容器 ID 与标签读回均为 0，且运行前后其他容器与卷的集合不变；传入 `--admin-url` 被入口拒绝。创建参数（`--pull=never`、仅回环随机端口、tmpfs 且无 bind/volume、`--rm`、`--timeout`、固定名称与标签）由单元测试断言；释放逻辑在名称或标签不匹配时不发出删除命令（单元测试）。
- [ ] 用短上限创建 detached 实例后强杀持有它的入口进程且不执行释放，按完整容器 ID 在上限加宽限时间内读回为零（真实 podman 一次）。
- [ ] governance 测试在缺失或错误 nonce 的库上于写 fixture 前以非零退出（与 cmd/server 同类测试）。
- [ ] `go-test-with-agent-cli-guard.sh` 与 `test-go.test.sh` 均在 mktemp 和 PATH 改写之前拒绝含 `:` 的 TMPDIR。guard 的修复前后对照用私有目录内以绝对路径调用的假命令加标记文件：修复前标记出现（用例失败）、修复后标记不出现；`test-go.test.sh` 只验证修复后的拒绝，不运行其修复前行为（该行为可能解析到真实 go）。空 TMPDIR 仍回退 `/tmp`，既有 `test-go.test.sh` 用例保持通过。
