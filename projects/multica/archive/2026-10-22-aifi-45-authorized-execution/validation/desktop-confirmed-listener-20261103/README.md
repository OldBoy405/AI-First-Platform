# Desktop confirmed 通知：监听注册失败处理

**范围：**confirmed 通知注册 `show` 或 `failed` 监听时同步抛错，原代码返回 rejected Promise，且在超时前保留 gate claim；修复将两次注册纳入已有错误处理，清除 timer、按 attempt token 释放并返回 `{ shown: false, reason: "error" }`，允许重试。legacy 路径未修改。这是客户端组件防御性错误路径，不表示真实 Electron 已出现此故障，不关闭 WP6 或 TC-NTF-005/007。

## 实施与验证

- 产品源码 `../multica/apps/desktop/src/main/notification-gate.ts`；常规回归 `../multica/apps/desktop/src/main/notification-gate.test.ts`；`../multica/CUSTOM.md` #291 登记。
- 新增 [`memory.test.mjs`](memory.test.mjs)，两个用例分别注入 `show` / `failed` 注册失败，检查调用次数、未调用 native `show`、返回 error、claim 释放、timer 清理及同 scope 重试成功。测试在 VM 中加载真实产品源码和 gate，timer/native handle 是受控替身。
- 旧源码 [`red.stdout.tap`](red.stdout.tap)：退出 1，2 tests / 0 pass / 2 fail / 0 skip / 0 cancel。两项均因实际 Promise rejected 而未得到预期 error 结果；旧行为下 claim/timer 值有捕获但位于首个失败断言之后，**不能声称该 RED 已分别断言其值**。
- 修改后 [`green.stdout.tap`](green.stdout.tap)：退出 0，2/2 pass；原失败/重试夹具 [`recovery.stdout.tap`](recovery.stdout.tap) 5/5、原 workspace 夹具 [`scope.stdout.tap`](scope.stdout.tap) 6/6，均 0 fail / skip / cancel。recovery 的 5 项中 1 项为假时钟自检，4 项为产品组件测试。各轮原始 stdout/stderr 以独占创建方式保存在本目录；原两个夹具没有修改。
- 每轮执行的 Node argv 为 `--permission`、分别限定当前夹具与产品源码两条 `--allow-fs-read=`、`--experimental-vm-modules --test-reporter=tap`、夹具绝对路径和源码绝对路径；无 fs 写/子进程授权，cwd 为工作区根，环境仅 `SystemRoot`、空 `PATH`、`TZ=UTC`，外层超时 30 秒。GREEN 时单独查询到该路径 Node 为 `v24.15.0`；RED 时未单独查询版本。VM 和 Node permission 不是 OS 沙箱，也不阻断网络。
- 初次夹具运行前后 raw SHA-256 均为 `58a9c2f99298ed8227de77d25db5b3373ab8a25f2bc66ea0e2254ff99674722e`；初次 RED 产品 raw SHA 为 `0d9db959c83fb63a7be41f7cda39049fdd51201e7198ee1f354877b712372965`，GREEN 和两次复跑为 `7a33a3f876c29b643afa8a99e981f7fa3016122bf72502542a63ebe6eb596a23`，每次执行前后相同。初次执行信息来自本会话工具输出，未另存机器可读元数据。哈希不能排除执行期间替换后恢复。
- 依独立测试审阅补充 [`verified-memory.test.mjs`](verified-memory.test.mjs)：先校验真实当前源码 SHA，在**内存中**精确还原移动前的同一代码块，校验重建结果 SHA 与初次执行旧源码一致；不修改活体源码。`old` 模式 [`verified-red.stdout.tap`](verified-red.stdout.tap) 为 2 项行为失败（显示注入的 rejection），`current` 模式 [`verified-green.stdout.tap`](verified-green.stdout.tap) 2/2 通过；均无 skip/cancel。对应 [`verified-red.meta.json`](verified-red.meta.json) / [`verified-green.meta.json`](verified-green.meta.json) 保存两次 argv、运行时版本、输入前后 hash、退出码及原始 TAP/stderr hash。两次 fixture SHA 为 `78bbdfe6a1df0ec12bcfafa0e83c246391331302b497351f91756a956c48f81a`，真实输入产品 SHA 均为当前 `7a33...`；旧 SHA 是夹具内存重建值，不是新一轮独立旧源码文件。
- 补充用例实际统计 timer 的创建与取消，并在 `failed` 监听注册失败、重试已占有新 token 时触发旧 `show` 回调，验证不会释放新 claim，且 duplicate 不再创建通知。RED 仍在结果断言后短路，不能用它声称旧 claim/timer 断言通过或失败；GREEN 验证完整路径。

## 边界

产品源码及新增的常规测试文件均用 Node `stripTypeScriptTypes` 单独做语法转换（exit 0，受限读取两个文件，未执行 imports），**不是类型检查或 Vitest 运行**。常规 Vitest 新增回归未运行；无真实 Electron/IPC/OS 显示、系统定时器、producer/Inbox、跨进程或最终用户送达证据。未运行真实 Git/CLI/suite 或数据库测试；未改变 CR/Gate 状态，Gate3 仍 NO-GO。

## 独立审阅

委派前两仓 STDD 配置刷新均为 configured：代码 strong `OpenAIPersonal/gpt-6.1-sol:high`、测试 balanced `OpenAIPersonal/gpt-6.1-terra:high`；无后端回执，actual 均 unknown。strong 会话 `01a1a406-f0cf-7374-9f4d-4645d846541d` 未发现本次移动导致的可触发问题；balanced `01a1a406-f0e0-7374-9f4d-46478d822f8d` 指出初次 TAP 缺独立可核 hash/命令回执、未验证 timer 曾创建及迟到回调，已按上述补充夹具和元数据。balanced 续审确认新增覆盖，并指出未在旧回调后、重试 show 前单独断言重试 Promise 仍 pending 与 retry timer 仍在；原始旧源码独立来源与独立动态复跑也未证明。两路审阅均仅静态，未独立动态复跑。
