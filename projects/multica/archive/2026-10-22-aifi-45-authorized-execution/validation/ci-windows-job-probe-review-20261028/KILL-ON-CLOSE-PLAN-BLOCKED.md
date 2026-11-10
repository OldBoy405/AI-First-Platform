# Kill-on-close 实验：安全方案未闭合

balanced 会话 `01a18302-0ba6-7020-aecc-d1e5df2d81a0` 被要求只设计自有测试进程、且无法证明异常清理安全时不写可执行探针。它报告尚无法同时证明 child 创建与跨进程 handle 交付之间的失败清理及身份安全，因此**没有写入或运行 kill-on-close 测试**。

候选设计是在受试 Job 之外再设一个仅由主测试持有、禁止 breakaway 的自有安全 Job；helper 完成安全 Job 归属握手后才允许派生 child，再将其持有的 child 进程 handle 复制给主测试。成功路径仅结束自有 helper，并在该 handle 上有界等待 child；失败路径只清理经证明属于本次测试的安全 Job。这只是尚未审阅的设想。

必须先证明：helper 在创建 child 与交付 handle 间崩溃时不依赖正在测试的 `KILL_ON_JOB_CLOSE` 做唯一清理；主测试异常退出和清理 API 失败时不遗留子进程；受控句柄不会指向已复用 PID 或任何非本次进程。新设计及其源码须单独经过 strong 安全审查；不能把成员继承探针的 PASS 升级成 kill-on-close、进程树退出或真实容器 cleanup 的证据。
