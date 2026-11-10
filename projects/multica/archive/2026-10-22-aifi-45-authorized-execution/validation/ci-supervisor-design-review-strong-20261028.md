# AIFI-45 CI 隔离 supervisor：STDD strong 只读设计复核（含纠正）

**性质：** 只读设计复核与技术建议。未修改任何代码；未运行 DB、容器、真实引擎；本轮复核与纠正**未执行任何测试或复现**（纠正部分为静态读码 + 引用既有复审报告的已执行证据）。
**不解除现有 BLOCK，不构成任何真实操作授权。**

## 0. 所依据的输入（原始 SHA-256，sha256sum 计算，未归一化）

| 文件 | 原始 SHA-256 |
|---|---|
| `multica/scripts/aifi45-db/instance-lifecycle.mjs`（当前磁盘） | `8bf026671ffe6b57825848dafc397bdd36cf5df61892fcad0cdad6cbb0e67a88` |
| `multica/scripts/aifi45-db/instance-lifecycle.test.mjs`（当前磁盘） | `9a628afcde61bdd1b0a2c47ad0ab8f2c9656db04943c196c1c8cc6b614f5b5f4` |

计划文件：`validation/ci-isolated-supervisor-plan-20261028.md`。
纠正参考：`validation/ci-instance-lifecycle-review-20261028/REVIEW-BOUNDARY-RECHECK.md`（其实测快照为 lifecycle `9c7bbb23…`，**不是**当前 `8bf02667…`；其证据对当前版本仅作为同类模式的参照，见 §2）。

---

## 1. 原设计复核报告（存档原文，§2 对其中一处断言作出撤回）

> 以下为首轮回复的内容存档（中文整理），未改动结论；被撤回的断言以【已撤回，见 §2】标出。

**结论：可以开始，但仅限下述"不接真实引擎"的切片；不得把其首次运行当作进程树为空的证据。** 计划未规定进程树机制的实现位置/语言，这是阻塞决策（B1）。

### 1.1 仓库事实
- `runOwnedInstance` 全程同步；probe 仅在 `runProbe` 返回 `{exited:true, code:0..255}` 且不是 Promise/thenable 时被接受，否则保留实例、不清理；非零退出码可以清理，但原失败保留。
- 缺口 1：`exited:true` 是调用方的声明值，没有任何对进程树为空的核验，也没有对输出做限额/分帧。
- 缺口 2：~~Promise 处理会消费拒绝，因此不会使进程崩溃~~【已撤回，见 §2】；失败原因被丢弃（此半句成立）；controller 内部仍不存在 async 与 secret 的隔离。
- Go 侧已有 Job Object 代码：`server/internal/daemon/processtree/controller_windows.go`、`execenv/isolation_windows.go`、`pkg/agent/proc_windows.go`；Unix 侧使用 `Setpgid`。
- **未核实：** 上述代码中 `AssignProcessToJobObject(c.job, process)` 很可能在 `cmd.Start()` 之后执行；若属实，间隙中启动的孙进程可逃出 job。核实前不得把它复用为证明。进程组（`Setpgid`）可被 `setsid` 脱离，同样不能证明任何事情。
- 环境事实：Node v24.15.0；Go 1.27.1；`server/go.mod` 为 `go 1.26.9`、`golang.org/x/sys v0.48.0`。

### 1.2 最小实现切片（TDD，仅虚构子进程）
1. **纯状态机**（`supervisor-state.mjs`）：输入为已解析、带序号的帧；输出为枚举 verdict：
   - `PASS`：仅当退出帧 code 0、`treeEmpty` 已确认、两条流均未超限、无解析错误、序号连续并以 EOF 结束；
   - `FAIL_KEEP`：任何未知；
   - `FAIL_CLEANABLE`：仅当非零退出、树已确认为空、帧完整。
2. **有界帧解析器**：固定头（版本、seq、类型枚举、len ≤ N），总量 ≤ M 字节。超长、截断、乱序、未知类型、重复退出帧、退出后仍有数据均判失败。原始 stderr 仅计数并丢弃；只保留白名单字段与枚举错误。达到上限后继续排空但不再缓存；stdout/stderr 并发读取。
3. **async 边界**：controller 只接受 supervisor 包装层自身构造、已 settle 并冻结的普通对象 `{exitCode, treeEmpty, overflow, frames}`，绝不接收子进程侧的 Promise。不读取 rejection reason，仅保留枚举。secret 不进入 supervisor argv，仅经 stdin 或 env 传给子进程；测试 canary 字符串不出现在 journal、错误消息或帧字段中。
4. **能力门禁**：`create` 之前要求 `capability.treeContainment === 'verified'`；默认实现返回 `unsupported`，即在 create 前拒绝。
5. **测试替身**：虚构子进程为 Node 脚本，分别做洪泛输出、提前关闭 stdout 但继续运行、写半帧、exit 0 但留下孙进程、抛空异常、把假 secret 写入 stderr。"孙进程仍存活"绝不能成为 PASS。本切片中树证据由 fake attestor 注入。

### 1.3 平台设计（技术建议，**全部未经实测**，见 §3）
- **Windows（首选）**：一个可信 Go helper，在完成以下步骤之前不启动任何子进程：
  1. `CreateJobObject`，限制为 `KILL_ON_JOB_CLOSE`，且**不设** `BREAKAWAY_OK` / `SILENT_BREAKAWAY_OK`；
  2. 把**自身**加入该 job；
  3. 然后才启动子进程。所有子孙自动继承 job，不存在"子进程已运行但尚未 assign"的窗口。

  备选：`CreateProcess` + `PROC_THREAD_ATTRIBUTE_JOB_LIST`，或 `CREATE_SUSPENDED` → assign → `ResumeThread`（未核实 x/sys 是否暴露该常量，或 Go `os/exec` 能否取得主线程句柄）。
  "树为空" = `JobObjectBasicProcessIdList` 只含 helper 自身且 `ActiveProcesses==1`；job 句柄不命名、不可继承。
  局限：同权限代码仍可对 helper 进程 `DuplicateHandle` 拿到 job 句柄（计划已排除）；若 CI runner 已将进程放入禁止嵌套的 job 则失败（未核实）。技术假设（未核实）：libuv 自身的 job 允许静默 breakaway 且 JS 无法访问；无论如何，Node `kill` / `taskkill /T` 都不能证明子孙已退出。
- **Linux**：有可委派、可写的 cgroup v2 时，helper 在 fork 前迁入新 cgroup（或用 `UseCgroupFD`）；终止用 `cgroup.kill`，之后要求 `cgroup.procs` 为空。
  备选：`PR_SET_CHILD_SUBREAPER` + wait 直至 `ECHILD`，可证明无残留子孙，但不能可靠杀死持续 fork 的进程；超时 → `FAIL_KEEP`。
  CI runner 是否有委派 cgroup 或非特权 userns：未核实。两者都没有时，在 create 前拒绝。

### 1.4 决策点（原文为"需用户决定"，现更正为技术建议，见 §4）
- B1：supervisor 放在哪里——仓库内 Go helper（需构建/哈希固定和固定路径）或 Node 原生 addon。建议 Go helper。
- B2："树已确认为空"是否为非零退出可清理的前提。建议是；否则为保留并失败。
- B3：帧/总量上限和超时取值。
- B4：现有 `runProbe` 调用方是否必须返回新回执。建议是；旧格式判失败。

### 1.5 未核实项与剩余风险
- 既有 Go Windows 代码是在子进程启动前还是后 assign job；
- x/sys v0.48 是否有 `PROC_THREAD_ATTRIBUTE_JOB_LIST`；
- CI runner 是否允许嵌套 job、委派 cgroup 或 userns；
- Windows 下 journal 目录的 `fsync`。
- 即便完成该切片，也不能防恶意同权限代码、断电或所有 secret 泄露通道；不解除当前 BLOCK。

---

## 2. 纠正：撤回"Promise 处理会消费拒绝，因此不会使进程崩溃"

**撤回该断言。** 它过度概括了当前 lifecycle 的行为。正确的限定是：

> 当前 lifecycle 仅对**普通原生 rejected Promise**（probe 路径）和**行为规范的普通 Promise/thenable**（record ack 路径）安装了拒绝处理；对其它形态的返回值，拒绝可能未被处理。Node v24 默认 `--unhandled-rejections=throw`，未处理拒绝会把 reason（可含 secret）写入 stderr 并以退出码 1 终止进程。同步抛出的错误与 journal 中保持固定文本，并不意味着整个进程的输出是受控的。

### 2.1 依据（当前 `8bf02667…` 的静态读码；未执行）
- **record ack，`instance-lifecycle.mjs:18`**：`if (acknowledged && typeof acknowledged.then === 'function') Promise.resolve(acknowledged).catch(() => {})`
  - 读取 `.then` 的 getter 抛错 → 在安装 handler 前就抛出，原 rejection 未被消费；
  - rejected Promise 自有 `then` 不是函数（如 `null`）→ 不进入消费分支；
  - 原生 Promise 的 `constructor` getter 抛错 / 子类 `Symbol.species` 抛错 → `Promise.resolve` 或 assimilation 失败；
  - thenable 的 `then` 自身返回一个额外的 rejected Promise → 标准 assimilation 不消费该返回值。
- **probe，`:61–62`**：`types.isPromise(result)` + `Promise.prototype.then.call(result, undefined, () => {})`
  - `then.call` 会经由 `constructor` / `Symbol.species` 构造派生 Promise：getter 抛错时 handler 未装上；自定义 species 可产生被忽略的派生 rejected Promise；
  - Promise **Proxy** 不具备内部品牌，`isPromise` 为 false，随后因 `then` 可调用被拒收，但背后的 rejection 无人消费。
- **engine 返回值，`create`（`:39–42`）及 `start/stop/remove`（`!== true` 判定）**：返回 rejected Promise 时，当前代码会判失败（`start/stop/remove` 不再出现旧快照中"先返回 cleaned=true"的现象——这一点来自读码与现有测试名称，本轮未执行），但该 Promise **从未被消费**，仍为未处理拒绝。
- **adapter 直接写 stderr**：lifecycle 无从控制。

### 2.2 与既有已执行证据的关系
`REVIEW-BOUNDARY-RECHECK.md` F1–F4、F6 已在隔离 Node 子进程（`--unhandled-rejections=strict`）中对 **`9c7bbb23…` 快照**实测：同步错误和 journal 均无假标记，但 stderr 出现标记、退出码 1。当前 `8bf02667…` 中相关代码行（`:18`、`:61–62`、engine 调用点）模式与之相同，因此**推定**同类缺口仍存在；但**本轮未对当前版本执行任何复现**，不作已实测声明。F5（端口基准）在当前代码中似已改为在 created inspect 后保存 `requestedPort`，属读码观察，未审查、未验证。

### 2.3 对设计的影响（加强 §1.2 第 3 点）
- 不能依赖"给任意 Promise 安装 handler"来证明安全（计划第 7 段已明确禁止此类声称）。正确方向仍是：**controller 不接触任何来自 adapter/子进程的 Promise 或 thenable**；supervisor 进程边界之外只传输有界帧字节，由 supervisor 自身构造回执。
- engine adapter 必须遵守可验证的同步契约（或同样经由进程边界返回帧），非同步返回值视为失败**且**不得被当作已安全消化。
- secret 的 stderr 泄露需要进程级控制：真实运行时 controller 自身的 stderr 应走同一有界、白名单通道，或由外层 runner 接管；在此之前不得声称"错误/journal 不含 secret"即等于"进程输出不含 secret"。
- 新增 TDD 用例（仅 fake）：上述每种 Promise 形态 × {record, probe, create, start, stop, remove}，在隔离 Node 子进程 `--unhandled-rejections=strict` 下断言 **退出码、stderr 无 canary、无 cleaned 成功、无 stop/remove**；预期在当前 lifecycle 上为红。

---

## 3. 平台方案状态（明确标注）

**§1.3 中所有 Windows（Job Object 自加入、`PROC_THREAD_ATTRIBUTE_JOB_LIST`、`CREATE_SUSPENDED`）与 Linux（cgroup v2 / `cgroup.kill` / `UseCgroupFD` / subreaper）方案均未经实测**：未在本机或任何 CI runner 上编译、运行或验证；libuv 行为、x/sys 常量、嵌套 job、cgroup 委派、userns 可用性全部为技术假设或未核实项。缺少能力时的正确处理是在 create 前拒绝，而不是降级。

## 4. 决策性质

§1.4 中的 B1–B4 属于**技术建议，无需用户批准**，可由实现者按建议值直接采用并在 TDD 中固化；若后续实测推翻某项假设，应回到本文件更新。此说明不扩大任何操作授权：运行 DB/容器/真实引擎、CI 接线、提交、推送仍受现有 gate 与 BLOCK 约束。

---

*本文件仅为文档写入；未修改 multica 源码或测试；未运行 DB、容器、真实引擎或测试。*
