# NTF 隔离原型：独立只读复核与暂停

> **状态更正（2026-11-01，务必先读）**：两次合成探针各自记录 exit 0，但运行前独立评审绑定的源码与实际运行版本不一致，故未满足 E1；第一次的 19 项主要是存在性检查，不证明完整对象归属。第 6 轮独立复核对运行真实 NTF 目标结论为 **BLOCKING**；目标未运行，也不能将探针结果外推为隔离机制安全。见 [首次记录](PROBE-RUN-20261101.md) 和 [第二次记录](PROBE-RUN2-20261101.md)。
> 下文各轮评审对应各自当时的源码，不可按版本名一概折算，也不得将旧 runner 证据倒签为当前代码通过。

本记录不推断已读取凭据或访问旧资源，也不把缺乏证据当作未发生。是否存在由继承句柄或可访问 ACL 引出的其他资源接触，目前 unknown。

## 发现

独立只读复核针对初版 `runner.go`、`probe.go`、`isolation-probe.json`、`old-red.json`、`new-green.json` 及原测试源码，未执行命令：

1. **目标自身令牌未实测**：每个 `runPhase` 创建不同 profile/SID；探针检查不能替代目标 SID 的检查。目标记录的 capability 数量是启动器声明而非从目标 token 回读。
2. **句柄继承未约束**：`CreateProcessW` 开启 `bInheritHandles`，未设置仅标准句柄的 `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`；其他可继承句柄可能绕过文件 ACL。此前是否存在或实际使用此类句柄 unknown。
3. **外部文件和网络覆盖有限**：专门设置 DACL 的自有哨兵拒绝访问，不证明所有宿主文件 ACL 都拒绝 AppContainer。回环连接失败不证明外网出站全部受阻。零 capability 的实测仅针对探针，非目标。
4. **证据链缺口**：目标原始 stdout/stderr 已随临时目录清理；失败原因主要依据测试名与正控模式复核，不能回放原断言文本。原 runner/probe 二进制与源码构建身份未完整记录，旧二进制完整 SHA 仍须与预检清单核对。
5. 还需审查沙箱可写目录的 reparse-point 安全清理、哨兵排他创建、目标校验到执行的替换窗口及异常退出残留。不能以随机名称或事后清理声称这些边界已证明。

## 已观察的测试结果及限制

`old-red.json` 记录精确选择器 exit 1、139 个父子 run 标记、74 pass、65 fail、0 skip；`new-green.json` 记录 exit 0、139/139、0 skip；新版完整包 674/674、0 skip。独立复核按源码测试树核对这些计数及失败测试名，未见编译失败或零选中冒充 RED 的迹象；缺少原始断言输出。父子标记不等于叶子用例数。**这些是已发生的测试观察，不证明事前或事后的隔离合规，也不证明 DB、广播、真实生产者或完整 TC。**

## 恢复前条件

先对修改后的 runner 做独立只读审查，至少验证：挂起目标的实际 AppContainer SID、capabilities 和完整性等级后才 resume；将句柄继承限制为明确的标准句柄；排他创建自有哨兵；不跟随 reparse point 清理；校验目标源码/二进制与执行之间的绑定；原始输出和构建身份可审计，且不得泄露凭据。环境键和值及网络/文件隔离边界要分别证明，不能把单一探针推广为所有 ACL 或 WFP 策略。任何证明不足均 fail-closed，不运行目标。

## preserve-all 版本的只读复核

初版执行后，runner 已改成仅供合成 probe 的 preserve-all 草案，不自动删除 profile、随机目录或哨兵；尚未构建、执行或动态验证。独立静态复核确认仍有阻断：`--probe` 可指向任意 exe 且未强制绑定已审探针哈希；资源建立后才排他创建证据文件，写失败或崩溃时可能丢失身份；证据缺 parent 绝对路径。哨兵创建与设 ACL 间有竞态，按路径设置 ACL 存在对象被替换的风险。创建 AppContainer profile 还会在授权路径之外产生 HKCU 注册表项及用户 Packages 目录，preserve-all 会留下这些资源；不能把用户对隔离环境的授权直接当成对特定残留及其影响的确认。执行者随后提交了针对哈希、预写证据、parent/文件身份及哨兵原子创建的静态修订，仍未构建或运行。独立复核又发现五项阻断：Windows `BY_HANDLE_FILE_INFORMATION` Go 布局不匹配导致身份错误；写句柄尚未关闭即创建只读 guard 会触发共享冲突；中途 owned 状态日志始终为 false；`\\\\?\\` 路径用作工作目录尚未验证；操作者可将任意目标二进制及其哈希作为 probe 传入。父目录替换竞态、probe 环境值和网络范围仍未解决。修订并独立复核前，不运行合成 probe，更不运行真实目标。

复核同时指出环境值、实际 HANDLE_LIST、外网/DNS、broker 后代和所有宿主 ACL 均未证实，Job 清空只证明 Job 内计数。现有各轮 JSON 仍是旧 runner 的历史结果，不能用新版代码倒签旧执行。旧报告曾计算仓库文本文件的原始 bytes SHA，未先规范化 CRLF，违反工作区哈希纪律；该值仅如实保留当时记录，不得当作规范化源码快照证明。可执行二进制的原始字节绑定与文本规范化摘要是不同口径。若此方案需要保留授权目录外的系统资源，应先向用户明确说明并取得决定；也可先研究不产生这类持久资源的替代方案。主会话只检查了 `C:\Windows\System32\WindowsSandbox.exe` 和 `WindowsSandboxClient.exe` 两个固定路径，均不存在；这不是全盘扫描，也不足以证明本机没有其他沙箱能力。

执行者和独立审阅者 requested 模型与实际 backend 回执未在本记录核实，actual 记 `unknown`。不自行清理未知残留，也不查询其他进程、旧 DB、容器或卷来弥补证据缺口。

## 修订后状态（2026-10-31，自评，未经独立复核）

五项阻断的处置，**只做静态修订与构建验证，未运行任何探针或目标**：

| 阻断 | 处置 | 可验证内容 |
|---|---|---|
| B1 FILETIME ABI | 删除自建 `byHandleFileInformation`（把 FILETIME 建成 `uint64` 会错位后续字段），改调 `syscall.GetFileInformationByHandle` + `syscall.ByHandleFileInformation`，不再有自建结构体与 unsafe 读 | `go build`/`go vet` 通过 |
| B2 写句柄未关 + 路径替换 | `copyExclusive` 先 `output.Close()` 再建只读 guard（guard 只 share read，故其存在期间他人 open-for-write/delete 必失败），随后用文件身份比对 output↔guard；不相等即 fail-closed | 同上 |
| B3 owned 恒 false | 在每次 `*-state` 事件**之前**把当前 `ProfileOwned`/`RootOwned`/`SentinelOwned` 写入 `phase.Resources`，中间日志不再恒 false | 同上 |
| B4 `\?\` 作工作目录 | 新增 `dosPath()` 还原 DOS 形式；启动前分别对 work 目录与探针镜像用**扩展路径与 DOS 路径各开一次句柄并比对文件身份**，不相等即 fail-closed；`CreateProcessW` 的 `lpApplicationName`/`lpCurrentDirectory` 均传 DOS 形式，证据里记录 `workIdentity`/`launchWorkDir` | 同上 |
| B5 `--probe` 任意二进制 | 删除调用方自报的 `--probe-sha256`；改为编译期常量 `reviewedProbeSourceSHA256`（probe.go 归一化哈希）与 `reviewedProbeBinarySHA256`（`-trimpath` 构建产物字节哈希），`runPhase` 用后者作为 expectedSHA，两者任一不符即拒绝 | 两个钉值由本轮实际构建算出：源码 `d4d83af0…`、二进制 `7f4ae679…`（4,922,368 bytes），证据里另记 `probeBinaryBinding=SOURCE_AND_BINARY_PINNED_IN_RUNNER; REPRODUCIBILITY_UNPROVEN` |

改动后 `runner.go`、`probe.go` 分别 `go build`（单文件，二者同目录且都是 `package main`，不能整包构建）、`go vet`、`gofmt -l` 全部干净。

**仍然阻断、本轮未解决**：

1. `CreateAppContainerProfile` 会在授权路径之外产生 HKCU 注册表项与用户 `Packages` 目录，preserve-all 会留下它们——**须人类先就「允许在授权目录外留下这些持久资源」作出决定**，否则不得运行。
2. 父目录替换竞态、探针环境值、外网/DNS 与 WFP 覆盖、broker 后代、全部宿主 ACL 均未证实；Job 清空只证明 Job 内计数。
3. 探针二进制↔源码的可复现构建未证明（记录为 `REPRODUCIBILITY_UNPROVEN`）；换工具链或构建参数后两个钉值必须同时重算。
4. 本记录与 `runner.go` 的修订**未经独立只读复核**，也未运行；此前各轮 JSON 仍是旧 runner 的历史结果，不能用新代码倒签。
5. requested model 与实际 backend 回执仍为 `unknown`。

### 构建与钉值证据补档（2026-10-31，回应 economy 档 finding F1–F3）

此前「go build / go vet / gofmt 干净」只有会话内输出，没有留存工件。现已归档 [BUILD-VERIFICATION.txt](BUILD-VERIFICATION.txt)，内容可复核：

- toolchain `go version go1.27.1 windows/amd64`；
- `go build -trimpath -o <tmp> runner.go` exit 0、`go vet runner.go` exit 0、`gofmt -l runner.go` 无输出（runner 二进制 5,384,192 bytes / sha256 `38cfce66…`）；
- `go build -trimpath -o <tmp> probe.go` exit 0、`go vet probe.go` exit 0、`gofmt -l probe.go` 无输出（probe 二进制 4,922,368 bytes / sha256 `7f4ae679a617695f82b019029df3b25c987b04ee597e3c414e991978052a9ace`）；
- 两个编译期钉值被**独立重算复现**：`probe.go` 的 LF 规范化 sha256 = `d4d83af0…`（与 `reviewedProbeSourceSHA256` 相同），`-trimpath` 构建的 probe 二进制字节 sha256 = `7f4ae679…`（与 `reviewedProbeBinarySHA256` 相同）。同一工具链下两次构建得到同一二进制哈希，说明构建在该环境可复现；换工具链或构建参数会使二进制钉值失配并 fail-closed（这是设计意图，不是缺陷）。

同目录 `REPORT.md`（v3 版本）已在开头加状态横幅，标明其中的 `--probe-sha256`、自动清理与既有 JSON 属于修订前版本，不得用当前代码倒签。

### 第二&三轮 strong 档复核 findings 处置（2026-10-31）

runner.go 被 strong 档（requested `GBClaude/claude-opus-5-5` / `high`，actual `unknown`）判 **BLOCKING**，两条为真阻断，已修：

| # | finding | 处置 |
|---|---|---|
| B2 残留（阻断） | 只比对文件身份不足以证明字节未变：同 UID 可在「关闭写句柄 → 重开 guard」之间**就地覆写**内容，文件 ID 完全不变，身份比对照样通过，于是 `CreateProcessW` 会执行被替换过的镜像 | **已修**：guard 建立后立刻用 `hashOpenFile(guard)` 重新哈希并与 `expectedSHA` 比对，不等即 `probe image bytes changed before the read-only guard was established` 失败退出。原注释也同步更正 |
| ACL 路径传播（阻断/高） | 子目录原用 `os.Mkdir` + 事后 `setACL`；`SetNamedSecurityInfoW` 按**路径**操作并用继承 ACE 传播到已存在子树，目录内若有 junction 可能改到沙箱外对象；`bin` 的 0700 与 root 的受保护 DACL 也不一致 | **已修**：删除 `setACL` 及两个不再使用的 proc；六个子目录一律改用 `createDirectoryWithACL` 的**原子创建 + 受保护 DACL**（`bin` 给 AppContainer `GRGX`，`work/home/tmp/cache/gopath` 给 `GRGWGXDE`；不再有「先建后改」窗口） |
| dosPath 兜底过宽 | 原实现在无前缀时只查 `filepath.IsAbs`，`\GLOBALROOT\...`、`\??\C:\...` 去掉前缀后会变成相对路径却仍被当作「已转成 DOS 形式」 | **已修**：只接受 `X:\`（字母盘符）或 `\server\share`，其余直接报错 |
| `go.mod` 与两个 `package main` | `go build .` / `go vet ./...` 必然重复声明失败 | 本轮按单文件 `go build runner.go` / `go build probe.go` 验证，并在 [BUILD-VERIFICATION.txt](BUILD-VERIFICATION.txt) 写明；未拆分包（拆分需新建目录，属结构变更，留待人类决定） |
| `GoToolchain` 恒空 | 字段声明未赋值 | **已修**：写入 `runner-built-with <runtime.Version()>; probe-toolchain unverified`，明确它指 runner 而非探针 |
| 失败路径未写 `phase-evidence` / `process` 事件 | 中途 `return phase, err` 只落 start+final，Job 清空/后代终止缺少中间产物 | **未修**，如实记为缺口 |
| HANDLE_LIST 只证明「列了三个句柄」 | 无法由探针证明「没有别的句柄被继承」 | **未解决**，与既有 `ISOLATION-REVIEW.md` 的披露一致，不得宣称已证明 |

修订后 `runner.go`、`probe.go` 各自 `go build`/`go vet` exit 0、`gofmt -l` 无输出；probe 二进制与源码两个钉值**重新独立复现**（`7f4ae679…` / `d4d83af0…`），见 [BUILD-VERIFICATION.txt](BUILD-VERIFICATION.txt) 第二段。

### 第 4 轮 strong 档复核：SDDL 权限串写错（已修，并有动态解析证据）

第 4 轮复核判 BLOCKING，唯一「必须先修才能运行」项为真且在运行时才会暴露：作者把标准删除权写成 `DE`，而 SDDL 里是 `SD`。`GRGWGXDE` 既非合法权限串，`ConvertStringSecurityDescriptorToSecurityDescriptorW` 会直接失败——而它发生在 `createProfile`/root/sentinel/`bin` **都已建好之后**，即「先污染再失败」，且 `go build`/`go vet` 抓不到。

| 项 | 处置 |
|---|---|
| `GRGWGXDE` → `GRGWGXSD` | **已修**：六个子目录的 scratch 权限串改为 `GRGWGXSD` |
| 先污染再失败 | **已修**：新增 `validateDirectoryAclTemplates()`，只用占位 SID 解析 `GRGX`/`GRGWGXSD` 两个模板并立即 `LocalFree`，在 `main` 里**先于任何持久资源创建**调用；解析失败即退出 |
| 注释过度声称 | **已改**：guard 重哈希处的注释明确写出「重哈希不证明 launch 那一刻的字节」 |

**动态证据（只解析、零资源）**：[SDDL-PARSE-CHECK.txt](SDDL-PARSE-CHECK.txt) —— 一个仅调用 `ConvertStringSecurityDescriptorToSecurityDescriptorW` 的临时程序（自建 `os.tmpdir()` 目录，运行后删除），输出：

```text
rights=GRGX       RESULT=ACCEPTED
rights=GRGWGXDE   RESULT=REJECTED err=... The access control list (ACL) structure is invalid.
rights=GRGWGXSD   RESULT=ACCEPTED
```

这就是该项的 RED→GREEN：旧串真被拒、新串真被接受，且全过程不创建目录、文件、profile 或注册表项。

### 人类决定（2026-10-31）

人类**已同意**允许在授权路径外留下 `CreateAppContainerProfile` 产生的 HKCU 注册表项与用户 `Packages` 目录。因此该项不再是阻断；但同意「可以留下」不等于免除记录义务：运行前须按 [RUN-PLAN-20261031.md](RUN-PLAN-20261031.md) 登记预期对象，运行后逐条核对，对不上号的一律不删。

### 仍未运行

截至本记录，**未运行任何探针**。`RUN-PLAN-20261031.md` 的执行前置要求第 4 轮之后的再次复核放行；本轮 SDDL 修复**尚未经第 5 轮独立复核**。

### 第 5 轮复核结论与 F1/F2 修订

第 5 轮 strong 档复核结论 **INCOMPLETE — 有条件允许运行所复核版本的合成探针**，要求 E1（把 runner 绑定到被复核版本的 SHA）、E2（补齐预期对象清单）、E3（改掉超出实测的措辞）。其后 F1/F2 修改了源码，运行前未见同版本独立复核；E1 未满足，见 [RUN-PLAN-20261031.md](RUN-PLAN-20261031.md)。

顺带修掉两条低危项（不阻断运行，但属于"改一处忘另一处"型隐患）：

| finding | 处置 |
|---|---|
| F1 哨兵 SDDL 未预验 | `D:P(A;;FA;;;<user>)` 已并入 `validateDirectoryAclTemplates()`，与两个目录模板一起在任何持久资源创建前解析 |
| F2 模板格式串写了两份 | 抽成常量 `directorySddlTemplate` / `sentinelSddlTemplate`，生产与预验共用同一份；`go vet` 现已能捕获参数个数不匹配（修订过程中它确实报出 `format %s reads arg #3, but call has 2 args`，即 F2 的活证据） |

修订后 `runner.go` 各自 `go build` / `go vet` exit 0、`gofmt -l` 无输出；probe 两个钉值仍被独立复现（`7f4ae679…` / `d4d83af0…`）；`runner.go` 的 LF SHA 变为 `9100192d3cf12dfd22c9e9a17a6c49721182fb617a93529d4c020f61fe2b34cb`，`BUILD-VERIFICATION.txt` 末段已记录。仅将 E1 门控改指向该值不等于修订后获得运行前独立复核。

**仍未运行探针**；本轮修订尚未经第 6 轮独立复核。
