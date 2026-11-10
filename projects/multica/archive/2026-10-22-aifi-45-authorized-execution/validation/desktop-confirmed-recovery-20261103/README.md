# Desktop confirmed：失败及重试的内存组件观察

**范围：**对当前 `notification-gate.ts` 的 confirmed 分支进行独立组件观察，未改产品源码；不关闭 WP6、NTF-005/007 或业务 TC。本目录是新夹具，未改先前 `desktop-confirmed-scope-20261103/memory.test.mjs` 及其历史 RED/GREEN。

## 本轮执行

- 命令由本会话的 `spawnSync` 以绝对运行时路径 `D:/Program Files (x86)/nodejs/node.EXE` 执行；实际 argv 依次为 `--permission`、两条分别指向本目录 `memory.test.mjs` 和 `C:/Users/GOBAO/Downloads/AI/multica/apps/desktop/src/main/notification-gate.ts` 的 `--allow-fs-read=`、`--experimental-vm-modules`、`--test-reporter=tap`、夹具绝对路径和源码绝对路径。cwd 为工作区根；子进程环境键仅 `SystemRoot`、空 `PATH`、`TZ=UTC`；外层超时 30 秒。没有给子进程 fs 写或子进程权限。本轮未单独查询运行时版本，不能仅凭同一路径推断它与历史版本相同。
- 退出码 **0**，signal/error 均 null；TAP 为 `tests 5 / pass 5 / fail 0 / cancelled 0 / skipped 0 / todo 0`。其中 **1 项是受控时钟自检，4 项是产品组件测试**。stderr 仅有 `stripTypeScriptTypes`、`VM Modules` 两条实验特性警告。
- 执行前后夹具 raw SHA-256 均为 `43ea51b26b80ec020284dace64e89a99803faf11fc7286c6d1c756a0c2fe22e5`；产品 raw SHA-256 均为 `0d9db959c83fb63a7be41f7cda39049fdd51201e7198ee1f354877b712372965`。端点哈希不能排除期间被替换后恢复。上面的结果转录自 `spawnSync` 的 UTF-8 解码输出，**未单独保存原始 stdout/stderr 字节文件**，不声称是可重放的原始字节证据。

## 覆盖与边界

1. ws-a `failed` 后释放 a、保留同时 pending 的 ws-b，并使 a 的 confirmed 重试成功；同 scope duplicate 不创建新通知。
2. 手动推进时钟：14ms 尚 pending、15ms 超时为 `unconfirmed` 并释放；新 attempt pending 时旧 attempt 先后收到 `failed`、`show`，不能释放新 token。
3. 人工通过公开 `gate.release` 构造旧 attempt 尚未 settled、同 key 新 attempt 已存在；旧 `failed` 不释放新 token。这是 token 防护的组件构造，不等同真实 OS 竞态。
4. factory 和 `show()` 同步抛错分别被命中一次、释放 claim，并允许有效重试；断言同步/Promise 返回形态。

假通知仅手动触发事件，`emit` 会断言产品此前调用过 `show()` 一次；假时钟自检取消与到期，afterEach 检查残留 timer。它不证明真实定时器、`unref` 或系统调度；也不覆盖 `on`/`once` 注册失败、旧 attempt 超时防护、所有相反事件顺序、B 完成后的迟到事件或本轮 RED。测试没有真实 Electron IPC、OS 展示、producer/Inbox、跨进程重启或用户送达。

Node permission 和 VM **不是 OS 沙箱，也不阻断网络**；VM 宿主回调有跨边界风险，本结果只针对经静态审阅的固定源码和夹具。没有执行真实 Git/CLI/DB、完整 Vitest、网络或事故资源检查；资源 HOLD 与 Gate3 **NO-GO** 不变。

## 审阅

本轮模型配置已刷新；balanced `01a1a1c1-848c-7374-9f4d-46149073f8bd` 独立只读预审并续审夹具，requested `OpenAIPersonal/gpt-6.1-terra:high`，actual unknown，未独立动态复跑。其指出假通知必须断言实际 `show()`、明确返回类型、检查清理残留；这些已在执行前补入。没有将该审阅或本结果当作生产验收。
