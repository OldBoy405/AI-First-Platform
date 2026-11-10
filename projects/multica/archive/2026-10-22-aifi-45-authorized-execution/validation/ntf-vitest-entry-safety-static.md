# AIFI-45：NTF-005/007 已列前端命令安全前置静态核查

**结论：两条命令仍 BLOCK，未运行。** 本次只读源码和依赖实现，没有检查或读取任何 `.env` 文件、进程环境或凭据，也没有启动 Vite/Vitest、访问网络/DB/容器，或清理缓存。

## 两项独立阻断

1. `packages/core/package.json` 的 test 脚本为 `vitest run`；当前 `realtime/use-realtime-sync-inbox.test.tsx` 的测试名称和父套件没有 `NTF-005` 或 `NTF-007`。`-t` 是测试完整名称筛选，不是读取 test-plan TC 标签，因此现有两条命令不能选中目标。`vitest.config.ts` 还配置 `passWithNoTests: true`，退出成功本身不是选中与执行证据；收集测试之前仍会初始化配置和模块。
2. 当前 `vitest.config.ts` 未禁用 env 文件加载。所读 Vite 依赖的 `resolveConfig` 默认按项目根调用 `loadEnv`；`loadEnv` 依次检查 `.env`、`.env.local`、`.env.<mode>`、`.env.<mode>.local`，存在且为文件时先读取解析，再按前缀选取暴露变量。**未检查文件是否存在或含秘密**；仅按源码已不能证明原命令满足“不读取既有环境/凭据”边界，不能以“只暴露 VITE_”作反证。

## 其他需处理的副作用

- 默认配置加载可能写入 `.vite-temp`，Vitest 有结果缓存、OS 临时目录与子进程；正常清理源码不证明异常退出后的清理成功，且不能清理未知归属的共享缓存。
- 通知测试用假 websocket、桌面 API、部分预填内存 query；但传递导入会创建持久化 store，jsdom localStorage 的初始化并未完全 mock。局部 mock 和 jsdom 不等于整个依赖链无网络、文件或其他副作用。
- 各测试的清理对正常路径有覆盖，但部分挂载发生在 `try` 之前，singleton API 和异步工作等异常清理还须复核；以上是静态风险，不是本轮观察到真实外部调用。

## 客户端测试静态覆盖映射

对 `use-realtime-sync-inbox.test.tsx` 的 14 个现有 `it` 逐项阅读断言（行号为当前工作树，未运行）：

| 测试起始行 | 静态断言范围；仅限客户端组件 |
|---|---|
| 38 | legacy Inbox 缓存刷新；无重投提醒去重断言。 |
| 209、362 | 手工 key fixture 的同 ID 顺序及重叠重投，分别断言 confirmed 桥只发送一次；209 另断言新 Inbox ID 可发送。 |
| 242、522 | 无 key legacy：242 对同一行重投断言 void 桥调用两次；522 单次投递保持 legacy 路由。 |
| 259、289、317 | 假桌面拒绝、Promise 拒绝、假浏览器 banner 报错后，重投可再次调用；不证明真实 OS 失败或成功后仍去重。 |
| 396、540 | 相同 ID 分别在两个 workspace 发送；540 的“无 workspace”是查询列表无对应项，不是 item 缺 `workspace_id`。 |
| 429、586、639 | focus 或 mute 在异步偏好读取期间变化时不发送；条件解除后可重投。639 是 mock rejection，不是真实请求取消。 |
| 476 | 有 key 但仅有 legacy void 桥时不发送；出现 confirmed 桥后重投可发送。 |

14 个测试中 3 个使用 legacy 无 key 形状，其他 11 个手工提供 key；不存在缺失 item workspace 的覆盖。测试不证明服务器会生成 key 或恢复重投，也未覆盖 GC、重启、跨 CR、真实 WS/OS/第三方与 NTF-007 的 DB 故障恢复。上述是静态断言分类，不是任何测试结果。

## 下一步

- 在测试设计中分别标明客户端组件与服务端事务/生产接线/恢复的覆盖范围；不可通过重命名或添加标签就把组件测试当成完整 TC。
- 另行设计并审议受控测试入口，明确禁读环境文件、源码/依赖快照、网络边界、缓存和临时资源归属、清理及精确非零选中；任何新增入口、参数或命令须先列明并获授权。不能执行原命令、自动安装依赖、探查秘密，或用 fake 替代真实端到端。

## 依据

独立只读审查 session `01a18d05-f77d-7468-8217-4a6786a3fb54`（含同会话续查 14 例断言），请求 `OpenAIPersonal/gpt-6.1-sol:high`，actual backend 无回执记 unknown。协调者复核了 `packages/core/package.json`、`packages/core/vitest.config.ts` 和本地 Vite `node.js` 中的 `resolveConfig/loadEnv`；依赖与工作树并未锁定成最终验收快照。
