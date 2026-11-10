# Windows Job：自有 helper 子进程能力探针

在 strong 对 `27bb70f91c0f05cf20ac01e472e12bb65b5ac2b2474a7d9478bf4e38aa941c3a` 版本给出 **PASS-for-safe-first-run** 后，协调会话在 Windows 上单独执行本探针。该安全结论不等同能力验收。

- 入口：源仓 `multica/server/internal/governance/supervisorjob_test/job_windows_test.go`；运行前后原始 SHA 均为上值。
- 清除 `DATABASE_URL`、`PG*` 和既有 probe 环境，设置 `GOPROXY=off`；`go test -c` 编译到本次新建临时目录，exit 0；编译生成的测试二进制 SHA-256 `a9c689a85ff3a2350e43a9a3a0281db65237a04d62bcb38ed41e4b63d133e618`。
- 显式设置 `MULTICA_TEST_WINDOWS_JOB_PROBE=1`，运行上述二进制 `-test.v -test.count=1 -test.run=^TestWindowsJobCapability$ -test.timeout=60s`；目标顶层 **1 PASS、0 FAIL、0 SKIP**，进程 exit 0。二进制位于该次专有临时目录，运行后已清理。
- helper 创建匿名 Job 并仅加入自身，随后启动自己的测试子进程；断言配置、测试进程成员集合、自然退出后的活动成员数。无 DB、容器、真实引擎或真实秘密。此为作者运行；随后 balanced 独立执行同一源码目标测试亦 **1 PASS、0 FAIL、0 SKIP**，详见 `EXECUTION-BALANCED.md`。

**边界**：不证明 KILL_ON_JOB_CLOSE 实际终止效果、整个进程树的对抗性退出、宿主/EDR 句柄行为、可信 journal、流式输出保护或 CI 清理安全；不授权创建或删除真实容器。默认跳过的运行不是能力证据。
