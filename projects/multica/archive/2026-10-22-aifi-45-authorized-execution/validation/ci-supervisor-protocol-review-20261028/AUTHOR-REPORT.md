# Supervisor 完整缓冲帧解析草稿

新增 `multica/scripts/aifi45-db/supervisor-protocol.mjs` 和 `supervisor-protocol.test.mjs`，只解码由固定可信 wrapper 提供的完整非共享 Buffer。总量、单帧大小、帧数、顺序、类型、终帧和尾部均受限；输出为冻结的 null 原型对象，仅给出解码状态和 wrapper 报告的枚举，不返回 stdout/stderr 内容。`decoded` 表示协议格式可解码，**不是进程树退出、调用成功或清理许可**。

作者最终四项相关原有 Node 测试加该解析器测试为 **186/186、fail 0、skip 0**。当前源码 raw SHA `bed82664f2f17918b47302a94255e3061cbce9f516f578a074a997671b75452c`；测试 raw SHA `360c6c4d31dd05d4691b5be1fa92ffe6fb603badcd1334cb8f46df1750fe5b96`。作者对首版及后续边界做过定向变异；balanced 独立复跑最新测试 **24/24、skip 0**，只确认报告中列出的有限断言。

此前 balanced 复跑和 strong 复核按各自快照保留，strong 发现返回值语义与 Buffer 属性测试缺口；作者后续修订与增加测试不自动改变原报告结论。详见本目录报告。该模块假定同进程内建对象未被篡改，不提供传输认证、采集端流式限额、输出背压或实际进程树证明。它尚未接入 lifecycle、runner、真实引擎，不授权创建/删除容器或 cleanup；既有 lifecycle 异步边界问题与 CI BLOCK 不变。
