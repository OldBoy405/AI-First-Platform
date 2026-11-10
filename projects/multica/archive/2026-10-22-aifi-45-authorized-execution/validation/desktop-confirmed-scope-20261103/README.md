# Desktop confirmed 通知：workspace 身份边界组件切片

**范围：** confirmed 请求缺少 `workspaceId` 时，在 gate 及 native factory 之前返回 `invalid-payload`；legacy 无 workspace 的同步行为不变。这是现有桌面 IPC 边界的输入校验，不证明正常调用方曾发送坏数据，也不是 WP6/TC-NTF-005/007 的完整验收。正常 caller 已传 workspace；本修复不认证该 workspace 的成员资格，也不修改 sender/session 权限顺序。

## 实施与证据

- 本轮委派前两仓 STDD 配置已刷新为 configured；后续续审没有逐次重新刷新。strong 审查 `01a1a17c-fa1f-7374-9f4d-45fb3c7fdc62`、balanced 测试预审 `01a1a189-3d9e-7374-9f4d-45fc4e1e0c79`，requested 分别为 `OpenAIPersonal/gpt-6.1-sol:high`、`OpenAIPersonal/gpt-6.1-terra:high`；无后端回执，actual unknown。均只读预审，非独立动态复跑。
- `red.stdout.tap`：同一 memory fixture 加载旧产品源码，exit 1，6 项中 4 pass、2 fail、0 skip/cancel/todo。缺 scope 的 confirmed 实际创建并显示模拟通知、无作用域 gate 被调用并留 attempt，与预期 invalid/零调用不同；unsupported 组合实际返回 `unsupported` 而非预期 `invalid-payload`。这两项是行为断言失败，不是编译、加载或权限失败。RED 中首条断言之后的同 gate 有效 scoped 分支和第三个测试（第二个失败测试）的 focused 循环分支未执行。
- `green.stdout.tap`：仅在产品解析失败出口加入 confirmed 缺 workspace guard，随后同一 fixture、同形命令运行，exit 0，6/6 pass，0 skip/cancel/todo。覆盖缺 scope 拒绝及同 gate 合法正例、legacy 同步、unsupported/focus 优先级、两种模式对非法 workspace 的已有拒绝、focused 行为、不同 workspace 同 item 不互吞与同 scope 去重。
- `red.meta.json`、`green.meta.json` 记录 argv、cwd、Node `v24.15.0`、退出状态、超时、环境键及两份输入前后 raw SHA-256；`red.stderr`/`green.stderr` 保留实验特性警告。测试 fixture 两轮 raw SHA 为 `2aaa893bc4c5e50494278a7ef8998866ae3a2af6eaece3c9bd4ea9ba6e9c36fa`；产品由 `0a28ee5a120fb9a0f7f1aec1dda2881ca8f123fb91c0ea69539201a15fdb7801` 变为 `0d9db959c83fb63a7be41f7cda39049fdd51201e7198ee1f354877b712372965`。RED 无单独源码快照；在内存中按原行尾将当前 guard 精确还原为原单行后，计算出的 raw SHA 与 RED meta 匹配，当前源码 raw SHA 与 GREEN meta 匹配。这支持两快照的唯一差异，但不证明执行历史；每轮自身前后摘要相同也不能排除运行中短暂替换后恢复。meta 只保存环境键名，不单独证明变量值或句柄隔离。
- 新增常规 `apps/desktop/src/main/notification-gate.test.ts` 回归；**未运行 Vitest**。源码和测试在 multica `CUSTOM.md` #290 登记。无新的生产链开关。

## 执行边界与未验证项

子进程只获两个明确文件的 Node 只读权限，无 fs 写或子进程权限，PATH 为空、TZ 为 UTC；父进程用独占创建保存原始输出。测试直接执行 `memory.test.mjs`，以 Node 内置 `stripTypeScriptTypes` 转换指定产品源码并在 VM 执行；拦截模块与动态导入，使用真实 `NotificationGate`（首项包装计数）、假 native handle 和真实宿主计时器。**VM 和 Node permission 不是 OS 沙箱，也不阻断网络**；此次只对审查过的固定源码/夹具作组件观察，不将其外推为对恶意代码的隔离。目录静态检查和摘要不证明并发替换防护。

未验证真实 Electron IPC sender/session、OS 通知显示、系统超时与迟到事件、生产 producer/Inbox、移动端、服务端持久投递、跨进程/重启去重、完整 Vitest 或生产部署；不声称用户已收到或去重永远成立。资源 HOLD 和 Gate3 **NO-GO** 保持。
