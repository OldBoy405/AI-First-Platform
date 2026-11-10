# AIFI-45 NTF Windows 一次性 AppContainer 隔离原型与 RED/GREEN 证据

> **状态更新（2026-10-31，务必先读）**：本文件描述的 runner/CLI 与执行结果属于**修订前（v3）**版本，已被同目录 `ISOLATION-REVIEW.md` 末尾「修订后状态」与 `runner.go` 当前的 v4-synthetic-preserve-all 取代。
> - 本文件里的 `--probe-sha256`、自动清理、哨兵创建方式、B1–B5 阻断等描述**对当前代码已不成立**（例如调用方自报 SHA 已被编译期钉值取代）。
> - 本文件中的 JSON（`old-red.json`、`new-green.json`、`probe-evidence-*.json`）仍是**旧 runner 的历史执行结果**，不得用当前代码倒签，也不构成隔离证明。
> - 当前仍未运行任何探针；`CreateAppContainerProfile` 会在授权路径外留下 HKCU 注册表项与用户 `Packages` 目录，须人类先决定是否允许。

## 结论：隔离放行撤回，等待修正后的独立审查

**独立审查发现既往隔离论证有阻断缺陷。本报告撤回“目标运行已由 OS 严格隔离证明”的结论；既往 JSON 中的 `ISOLATION_VERIFIED_*` 只是当时 runner 自报状态，不再是可接受的安全结论。当前不得重跑任何旧/新目标二进制。**

阻断点：

1. `probe/selected/full` 分别使用不同 AppContainer SID。既往只核验了探针自身 token，没有在目标 resume 前由启动器读取目标 token，因此探针结果不能证明目标有效 token。
2. `CreateProcessW(bInheritHandles=TRUE)` 未设置 `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`，不能证明目标只继承三个 stdio 句柄。没有证据表明实际发生了额外句柄利用，但也无法证明未泄露。
3. 既往哨兵创建未使用 `O_EXCL`，随机名碰撞时可能截断或随后删除非本轮文件；本轮未观察到碰撞，但实现不满足归属证明。
4. 既往根目录使用 `os.RemoveAll`，未完成 Windows junction/reparse point 不跟随的明确论证。

既往功能观察仍保留为未独立复跑的历史记录：旧二进制选择器出现测试失败，新二进制选择器及完整包出现通过标记；但原始 stdout/stderr 已删除，旧 RED 的逐条失败原因目前不可独立复核。它们不替代重新执行，也不替代真实 DB、producer/recipient、恢复、广播、消费者、完整 TC 或 Gate3。

当前 runner 只做静态修正供第二次独立只读审查，**尚未构建、执行或通过新的安全验证**。本轮没有运行任何程序或探针，没有修改产品代码或账本，没有删除或屏蔽既有证据及脏改。

本轮进一步收敛为 **仅供合成 probe 的显式 `--synthetic-probe-preserve-all` 模式**：未指定该模式、传入 target 参数或请求 selected/full 均拒绝。成功或失败都不自动删除 profile、根目录或哨兵；原按路径 `ReadDir/Remove/RemoveAll` 清理代码已移除，不再把 reparse TOCTOU 留在清理路径中。每阶段证据记录相对 parent 的 `rootRelativePath`、`sentinelRelativePath`、精确 `profileName`、各项 owned 标志及 AppContainer SID。

### A1–A4 静态修正状态（均未动态验证）

- **A1 / 生命周期**：属性列表 buffer、`securityCapabilities`、三句柄数组由同一个 defer 在 `DeleteProcThreadAttributeList` 后 `runtime.KeepAlive`；目标 AppContainer SID 与 integrity SID 的 token 缓冲在 SID 转换后 `KeepAlive`。profile 字符串、CreateProcess 参数和 ACL 输入也补充了相应生命周期保护。
- **A2 / profile 归属**：只有 `CreateAppContainerProfile` 成功才返回 `profileOwned=true`。创建失败不标记拥有；创建成功但 SID 转换失败仍报告精确所有权。preserve-all 下只报告、不自动删除。
- **A3 / Assign 失败**：`AssignProcessToJobObject` 失败后，直接对自有 suspended process handle 调用 `TerminateProcess` 并 `WaitForSingleObject` 确认退出，不再把终止空 Job 当作该进程已退出。
- **A4 / 终止与现场**：token 验证、resume、超时、wait、exit code 和 Job 查询失败统一进入 `TerminateJobObject` + 有界 `ActiveProcesses==0` 确认。无法确认时记录 `JobHandleDisposition=OS_RECLAIM_ON_RUNNER_EXIT` 和 `DescendantTermination=UNKNOWN`；handle 会随 runner 退出由 OS 回收，但后代是否终止仍 unknown。无论清空是否确认，preserve-all 都保留 profile、根目录和哨兵。

### 第三次审查 F1–F3 静态修正（未构建、未执行，待另一 reviewer）

- **F1 / probe 哈希与替换竞态**：新增必需的 `--probe-sha256`，只接受协调者审过的完整 64 位十六进制值。源句柄在复制前计算 SHA，复制后核对副本 SHA；参数值本身不被视为授权或安全证明。副本以 Windows `CREATE_NEW` 创建，源和副本句柄均拒绝 write/delete sharing；写句柄关闭前先开启 read-only guard，并比较两句柄的卷序列号/文件索引。guard 保持到 `CreateProcessW` 之后及 launch 返回。该设计尚未动态验证，不能声称哈希比较本身消除竞态，也不能声称 Windows 执行映射兼容性已实测。
- **F2 / 早期证据**：canonical parent、root/sentinel/profile 待创建名先排定，再以 `O_EXCL` 创建直接位于 parent 下的 JSONL 证据句柄并 `Sync` 写入 plan。每次 owned 状态变化在下一项资源创建前追加并同步；写失败即停止后续资源创建。强杀仍可能丢失末尾事件或造成状态不确定，不声称已消除。
- **F3 / canonical 与文件身份**：parent 由目录句柄 `GetFinalPathNameByHandleW` 取得完整 canonical 路径，并记录 `GetFileInformationByHandle` 的卷序列号和文件索引；证据、根、哨兵和 probe image 也记录可用身份。读取身份失败即阻断，不用路径或名称猜测。文件索引证明力依赖实际文件系统，未宣称跨所有卷/重解析点的绝对身份。
- **哨兵**：改为用户专有 SDDL + Windows `CREATE_NEW` 原子创建，启动器持有句柄且不放入 HANDLE_LIST；不再有先开放后按路径改 ACL 的步骤。
- **profile 副作用边界**：`CreateAppContainerProfile` 仍可能在授权 parent 之外创建 `HKCU/Packages` 等用户资源。preserve-all 只是不替代、不清除这些资源，必须由人类另行决定后续处理；当前不执行、不枚举、不清理。

## 原型范围与机制

- [runner.go](runner.go)：仅使用 Go 标准库和公开 Windows API。
  - 以 128 位随机名在本 change 证据目录下排他创建每轮根目录；不接受“待删除目录”参数。根通过 `CreateDirectoryW + D:P` SDDL 安全描述符原子设置受保护 DACL，不再先继承后改 ACL。
  - `CreateAppContainerProfile` 创建随机一次性 profile，capability 指针为 nil、数量为 0；`CreateProcessW` 使用 `PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES`。profile 名称和 SID 均进入保留证据。
  - 对本轮根目录设置受保护 DACL：当前用户完全控制、AppContainer 仅读/执行；`work/home/tmp/cache/gopath` 单独授予本轮写权限。二进制位于只读/可执行 `bin`。
  - 本轮外部哨兵使用受保护 DACL，只授权当前用户；不授予 AppContainer。
  - 既往实现将子进程 suspended 加入自有 Job 后 resume，但未直接核验目标 token，且未限制继承句柄列表；这是当前阻断，不再描述为充分隔离。
  - 目标从明确指定的预检路径复制到本轮随机 `bin`；复制前后计算 SHA-256，并再次强制匹配命令行绑定的完整预检 SHA。
  - 当前版本不自动清理 profile、根目录或哨兵，成功也保留。证据文件以 `O_EXCL` 新建；后续仅能由证明资源归属的程序或人工处理，不建议枚举或自动清理。
- [probe.go](probe.go)：在沙箱内检查有效 token，而非检查名称。
  - `TokenAppContainerSid` 必须等于启动器 SID；`TokenCapabilities` 必须为空。
  - 探针只自报环境键集合匹配，未由独立启动器逐项核验环境值；本轮一个文件读写必须成功。
  - 外部哨兵读、追加写都必须返回 permission denied。
  - 对启动器本轮创建的 `127.0.0.1` 监听器发起连接，必须立即拒绝而非连接成功或超时。
- 启动器构造 21 键环境块，设计值包括 `GOTOOLCHAIN=local`、`GOPROXY=off`、`GOSUMDB=off`、`GOENV=off`、`GOWORK=off`、`GOFLAGS=-mod=readonly`、`GOTELEMETRY=off`、`CGO_ENABLED=0`；不继承宿主环境块。既往没有独立逐项实测目标实际看到的环境值。
- 构建原型也只使用固定本机 Go、标准库、随机独占构建目录和同类无凭据白名单环境；没有下载。两个构建目录均已删除并验证不存在。

## 既往探针观察（不构成目标隔离证明）

下表只描述独立探针进程及启动器观察到的事实。由于 probe/selected/full 的 SID 不同，它不能外推为目标 token、句柄或完整运行隔离证明：

| 检查 | 实际结果 |
|---|---|
| 探针有效 AppContainer SID | 与探针本轮 profile 匹配；目标未由启动器直接核验 |
| 探针有效 token capabilities | 0；目标 capabilities 未由启动器直接核验 |
| 环境 | 探针自报键集合匹配；环境值未由独立启动器逐项核验 |
| 本轮文件 | 探针在本轮一个文件中写入、读回成功，不证明所有文件隔离 |
| 外部哨兵 | 本轮一个哨兵读写被拒绝、内容未变，不证明所有历史资源不可达 |
| 网络 | 本轮一个回环连接被拒绝，不证明所有网络路径/协议均被隔离 |
| 探针进程 | exit 0 |
| Job 残留 | `ActiveProcesses=0` |
| 自有清理 | profile deleted、root removed、sentinel removed 均为 true |

早期失败探针 1–7 均阻断目标，并保留了对应 JSON。修正包括 64 位 token 信息对齐、改用 `TokenAppContainerSid/TokenCapabilities`、移除非必要且在本机持续超时的嵌套孙进程试验。最终“子进程退出”由启动器直接等待实际沙箱进程、读取退出码并要求 Job 残留为 0 来证明；没有将嵌套试验记作通过。

## 目标二进制绑定

只在探针成功后读取用户明确指定的两个精确文件，没有枚举其父目录或其他用户资源。

| 版本 | 实测完整二进制 SHA-256 | 预检声明的 LF 源哈希 |
|---|---|---|
| 旧 | `a2a5917680942c4b96c39a61ac5302a1b7b1fcbd9fb011a5b1530533cf0f4ef8` | `9be512…` |
| 新 | `2121e80bb9864176648eec7d4d6c5cafb156e897d8aa3b7c56550455971f2427` | `955740…` |

LF 源哈希和“除 `execution_notice.go` 外内容一致”是预检交接事实，本轮没有重新读取源码或把 1813 项依赖清单当作原子快照。此前将探针结果当作安全放行依据是不充分的；修正后必须直接验证目标 token 并通过独立审查。

## 既往 RED/GREEN 标记与完整包观察（待原始输出复核）

直接运行 `go test -c` 产物，参数为 `-test.v -test.count=1 -test.timeout=60s`，精确选择器为 `^TestNoticeRejectsTabbedExistingCommands$`，完整包为 `-test.run=.`。只解析 verbose 标记并保存计数；原始 stdout/stderr 随本轮根目录删除，没有输出或另存测试日志。

下表的 run/pass/fail/skip 是包含父测试与子测试的 **verbose 标记数**，不是独立叶子用例数：

| 二进制 | 范围 | exit | run | pass | fail | skip | 解释 |
|---|---|---:|---:|---:|---:|---:|---|
| 旧 | 精确选择器 | 1 | 139 | 74 | 65 | 0 | `selectedRun=1`、package fail，历史 RED 观察 |
| 旧 | 完整包 | 1 | 674 | 609 | 65 | 0 | 同一批失败，其他标记通过 |
| 新 | 精确选择器 | 0 | 139 | 139 | 0 | 0 | `selectedRun=1`、package pass，真实 GREEN |
| 新 | 完整包 | 0 | 674 | 674 | 0 | 0 | 同包完整回归通过 |

旧版失败名称列表包含五种命令的 TAB 组合及相关父测试/边界分组；当时进程 exit 1、非零选中且 skip 0。由于原始断言输出未保留，逐条失败原因仍待重新执行复核。目标 Job 残留为 0 和路径已清理只是既往观察，不消除 token、HANDLE_LIST、哨兵归属及 reparse 安全缺口。

另有一次旧目标调用误用了已编译二进制不支持的 `-test.json`：exit 2、stdout 0、零 RUN，不计 RED；详见 [old-target-evidence.json](old-target-evidence.json)。改为 `-test.v` 后重新执行才产生上表结果。

## 修正设计与新的放行条件

当前静态修正必须经独立代码审查和安全验证后才可执行：

1. **目标 token 直接核验（静态实现，未实测）**：目标保持 suspended，加入仅属本轮的 Job 后、首次 resume 前，由启动器通过目标 process handle `OpenProcessToken`，读取 `TokenIsAppContainer`、`TokenAppContainerSid`、`TokenCapabilities`、`TokenIntegrityLevel`。要求 isAppContainer 非零、SID 精确等于本阶段 profile、capabilities 数量为 0、integrity 为 Low (`S-1-16-4096`)。失败路径进入 A4 终止/清空确认。
2. **句柄白名单（静态实现，未实测）**：attribute list 同时设置 `SECURITY_CAPABILITIES` 与 `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`，列表仅含本轮 stdin/stdout/stderr 三个句柄。没有据此声称额外句柄泄露已被实测排除。
3. **归属、ACL 与 reparse（静态实现，未实测）**：哨兵使用 `O_CREATE|O_EXCL`，只有创建成功才标记 owned。根在创建时即带受保护 DACL，消除继承窗口。当前没有 ReadDir/删除路径，因此不依赖 reparse 检查或 PID/名称推断安全；所有资源无条件保留并记录精确身份。
4. **TODO — 原始 stdout/stderr 保存尚未实现**：当前仅提出 1 MiB/流上限、秘密模式检查和 `O_EXCL` 新文件归档设计，尚无新的 raw 输出证据，也未执行合成保存测试。命中秘密、超限、解析/隔离/Job/清理失败时不得宣称通过；不能保存环境变量值。
5. **TODO — 异常路径资源/句柄 leak 风险**：无法确认清空时，证据明确记录 Job handle 将在 runner 退出时由 OS 回收，后代是否终止为 `UNKNOWN`；`KILL_ON_JOB_CLOSE` 的实际结果不作保证。自有 profile、根和哨兵也会保留，后续只能由证明归属的程序或人工处理，不建议枚举或自动清理。
6. **复核顺序**：现在只等待第二次独立只读审查。任何后续合成验证都需另行批准方案；本 change 不提供或建议业务二进制测试入口。探针通过不构成目标放行条件。

其他边界不变：这不是对任意恶意程序、内核漏洞、提权、所有系统 broker/注册表对象或所有主机 ACL 的形式化证明；没有外部报文测试或独立 WFP/内核审计；预检源清单不是原子快照，JSON 未签名。当前没有实测证明所有网络/文件隔离、三句柄继承、环境值或异常清理安全。

### 如后续另行批准，可供审查的合成验证方案（只报告，不执行）

- 以可注入 Windows API 失败的自有 fake 验证 profile 创建失败不删除、SID 转换失败仍清理已拥有 profile。
- 验证 Assign 失败只终止并等待自有 suspended 主进程；模拟 Terminate/Wait 失败时必须保留现场。
- 对 token 查询、Resume、超时、GetExitCode、Job 查询及 TerminateJobObject 分别注入失败，检查先终止、清空确认和保留现场分支。
- 用额外可继承哨兵句柄验证 HANDLE_LIST，仅三个 stdio 可用；用直接读取目标 token 的合成目标核验 SID/capability/integrity 门。
- 用自有哨兵碰撞、根 ACL 和保留资源身份 fixture 验证不误删、不继承放宽、身份报告完整；这些测试不得指向任何既有资源，也不包含自动清理。
- stdout 保存实现后，再用正常、超限、模拟秘密和 O_EXCL 碰撞合成输出验证归档与失败门。当前不建议、不授权执行 noticeguard 或其他业务二进制。

## 既往已执行版本文件原始 bytes SHA-256（不绑定当前未审查修正版）

| 文件 | SHA-256 |
|---|---|
| `runner.go` | `b9a702d39b528a18dc8147d2a7c645f8fda60f3e440e49ac16b6ba2d4e454004` |
| `probe.go` | `d4d83af0ebb78dc564e8ecafbfe611dff9c1155c2b1496a06960d3792efda022` |
| `isolation-probe.json` | `0e5de112ab3a6c8c5d348f9aa19787df6a3dd6b8dd57b8a0967d2045766d918f` |
| `old-red.json` | `ea2dc5313ced2e6df20004ca7f3113cc0b1789409542d69eb0959281e2d7056c` |
| `new-green.json` | `af6ff9037833feae4e33bcbdb0faa686500f67e9f6d5cef7e6fc06ff5431fcd4` |

## 运行状态（暂停，等待第二次独立只读审查）

当前不得构建或执行。代码仅保留显式 synthetic preserve-all 的静态入口，拒绝 target 和非 preserve-all 调用；没有业务测试、自动清理或历史复跑建议。既往命令和状态名只用于解释旧证据，不构成新的放行依据。
