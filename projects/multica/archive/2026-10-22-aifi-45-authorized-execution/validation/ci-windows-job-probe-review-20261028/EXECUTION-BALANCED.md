# Windows Job 探针独立复跑（balanced）

## 环境与范围

- 节点：Windows 10 build 19045（MINGW64）；Node.js `v24.15.0`；Go `go1.27.1 windows/amd64`。
- 探针文件：`C:/Users/GOBAO/Downloads/AI/multica/server/internal/governance/supervisorjob_test/job_windows_test.go`。
- 仅从 `C:/Users/GOBAO/Downloads/AI/multica/server` 执行下列命令一次，外层限时 75 秒：

```text
go test -v -count=1 -run '^TestWindowsJobCapability$' ./internal/governance/supervisorjob_test
```

- 启动环境清除了 `DATABASE_URL`、所有 `PG*` 和 `MULTICA_TEST_WINDOWS_JOB_PROBE_ROLE`，并设置 `GOPROXY=off`、`MULTICA_TEST_WINDOWS_JOB_PROBE=1`。
- 执行操作未使用 DB、容器、引擎或 taskkill，也未按名称或 PID 清理其他进程；没有审计 Go 依赖及环境的所有潜在副作用。探针代码仅管理自己创建的测试子进程。
- 探针文件未修改；运行前后 SHA-256 均为 `27bb70f91c0f05cf20ac01e472e12bb65b5ac2b2474a7d9478bf4e38aa941c3a`。

## 结果

依据下方实际原始输出，目标顶层测试 `TestWindowsJobCapability`：**PASS 1 / FAIL 0 / SKIP 0**。Go 测试退出码为 0；外层耗时 0.96 秒。

```text
SHA256_BEFORE=27bb70f91c0f05cf20ac01e472e12bb65b5ac2b2474a7d9478bf4e38aa941c3a
ENV: DATABASE_URL, PG*, MULTICA_TEST_WINDOWS_JOB_PROBE_ROLE cleared; GOPROXY=off; MULTICA_TEST_WINDOWS_JOB_PROBE=1
COMMAND: go test -v -count=1 -run '^TestWindowsJobCapability$' ./internal/governance/supervisorjob_test
=== RUN   TestWindowsJobCapability
--- PASS: TestWindowsJobCapability (0.12s)
PASS
ok  	github.com/multica-ai/multica/server/internal/governance/supervisorjob_test	0.488s
GO_TEST_EXIT=0
ELAPSED_SECONDS=0.96
SHA256_AFTER=27bb70f91c0f05cf20ac01e472e12bb65b5ac2b2474a7d9478bf4e38aa941c3a
```

## 证明边界

本次结果仅证明探针中的匿名 Job 创建、自身加入、测试子进程继承，以及子进程自然退出后的进程列表检查。不证明 kill-on-close 实际触发、不证明 OS 对抗逃逸防护、清理能力或 CI 安全。
