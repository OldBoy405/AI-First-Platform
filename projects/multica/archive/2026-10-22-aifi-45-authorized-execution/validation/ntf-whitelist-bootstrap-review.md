# AIFI-45 multica：NTF-005/007 白名单命令启动链复核

## 结论与本轮执行事实

**两条命令继续 BLOCK；没有启动 pnpm/Vitest，没有真实 RED，也没有修改测试或生产行为。** 本轮完成的是命令安全前置和组件断言的只读复核，不是 TC 验收。该结论补充而不覆盖[此前静态核查](ntf-vitest-entry-safety-static.md)及[载荷/缓存核查](ntf-replay-payload-cache-static-20261030.md)。

授权依据为当前用户委派和已确认的[限定授权](aifi45-long-range-auth-confirmation-20261030.md)。唯一可考虑运行的测试命令仍为从 multica 根执行：

```text
pnpm -C packages/core test realtime/use-realtime-sync-inbox.test.tsx -t NTF-005
pnpm -C packages/core test realtime/use-realtime-sync-inbox.test.tsx -t NTF-007
```

没有增加参数、替换 executable、调用 Vitest API、另跑脚本/测试或安装依赖。没有读取 `.env*`、项目/用户 `.npmrc`、`auth.ini` 或任何凭据内容，也没有枚举进程环境；目录列表曾显示项目根 `.env`、`.npmrc` 名称，未打开文件。没有访问真实 CR、网络、DB、容器或历史 HOLD 资源，没有删除或清理任何缓存/临时资源。

## 1. 新确认的前置阻断：pnpm 本身先于 Vitest 读取配置

只读 `command -v pnpm` 定位本机 shell shim，再读取它指向的安装源码及 `package.json`，**没有执行 `pnpm --version`**。当前 shim 指向安装的 **pnpm 11.22.0**，而 multica 根 `package.json` 声明 **pnpm@10.28.2**。以下行号是此次所读本机安装 `pnpm/dist/pnpm.mjs` 的位置，不是仓库锁定/提交的源码证据；安装变动后须重核。

| 位置 | 已读行为 | 对本任务的影响 |
| --- | --- | --- |
| 安装入口 `bin/pnpm.mjs` | 启用可用的 Node compile cache，随后动态 import `dist/pnpm.mjs` | 配置/测试内的守卫不能约束 Node 启动、入口缓存与此前继承环境。未检查实际环境或缓存位置。 |
| `dist/pnpm.mjs:322367–322432`，`main4` | 先 `getConfig2`，再按 package-manager 条件切换版本，再 `installConfigDepsAndLoadHooks`，随后才进入命令处理 | 测试的 `vi.mock`、setup 或 Vite 配置都晚于该阶段。 |
| `:168561–168576` | 读取用户配置目录中的全局 YAML，再调用 `loadNpmrcConfig` | 不能把只调整 Vitest 配置当作完整的凭据隔离。未读取该全局 YAML。 |
| `:167643–167670`，`loadNpmrcConfig` | 读取 workspace `.npmrc`、user `.npmrc`、配置目录 `auth.ini`，并处理配置环境及 CA 文件 | **禁读凭据前置未满足**；`userconfig` 的重定向本身不会跳过 workspace `.npmrc` 或 `auth.ini`。 |
| `:167824–167834`，`:167476–167477` | `readAndFilterNpmrc` 先调用 `readIniFileSync`，后者直接 `fs.readFileSync`，之后才过滤键 | 忽略不支持的键、限制暴露字段或最终不发请求，均不能证明没有读取文件内容。 |
| `:168965–168970`，`:322145–322284` | package manager 缺省 `onFail=download`；符合切换条件时会解析版本、创建 store controller、安装目标 pnpm，再以继承环境启动它 | 当前 launcher 和项目 pin 不同；存在联网/下载/写 store 的条件路径，不能“先跑一次看看”。是否被用户设置覆盖、目标是否已有缓存，本轮未查，不断言实际一定下载。 |
| `:321887–321933` | 若存在 config dependencies 可解析安装；未禁用时可加载本地/全局 pnpmfile hooks | 未证明这两条原命令的有效配置关闭了该路径，不能仅凭 test script 是 `vitest run` 放行。 |
| `:168549`，`:273311–273354`，`:274176–274178` | `verify-deps-before-run` 默认 `install`；run 处理器先检查依赖状态，不同步时该模式可调用 `pnpm install` | 已有 `node_modules` 不等于禁止自动安装。未执行依赖检查，也未以探测安装来验证。 |

这些是**安装源码中的默认/条件路径**，不是已经发生的读密钥、下载或网络事件。为避免触发它们，本轮没有运行 launcher。更新通知检查的所读调用条件限于 `install/add`，没有把“pnpm 可能有 update notifier”泛化成这两条 test 命令必联网。

**原地测试文件/业务代码的修改不能封闭该前置边界。** 本轮不改安装在仓库外的 pnpm，不借重命名/移动现有 `.npmrc` 隐藏未知内容，不改项目 package-manager pin，不加 shell wrapper/预加载脚本/新参数，不通过另一个目录的替身项目声称执行了原工作树命令。

## 2. Vitest/Vite 前置仍未闭合

读取路径与事实：

- `packages/core/package.json`：`test` 仍为 `vitest run`，没有 pretest/posttest 脚本；这只说明项目脚本，不约束上面的 launcher。
- `packages/core/vitest.config.ts:1–9`：仅 `globals`、`include`、`passWithNoTests: true`；未配置禁读 env、隔离缓存/临时资源或网络拒绝策略。
- 已安装 `packages/core/node_modules/vitest/package.json` 为 4.1.0；所读 `node_modules/vite/package.json` 为 8.0.1。这是本地文件版本，不是本轮运行版本回执。
- 所读 Vite `dist/node/chunks/node.js:4944–4977,34107–34109`：默认 envDir 为项目 root；先读取、解析存在的 `.env*` 文件，再按前缀暴露。`envFile: false` 可使这一层不选 env 文件，但**不约束 pnpm 或继承进程环境**。未通过检查 `.env*` 内容来试图证明安全。
- 同文件 `:34355,34531–34548`：配置默认 bundle loader 在导入配置前写 `.vite-temp` 临时模块，正常路径尝试删除。修改配置中的 `cacheDir` 或 `test.cache` 不能倒推保护此前的配置打包写入；未动既有共享缓存。
- 测试 fake WS/桌面桥及预填 query 不等于全启动链隔离。`use-realtime-sync.ts → ../chat/index.ts → recent-context-store.ts` 会导入模块级 persist store，其 adapter 为 `platform/storage.ts` 的浏览器存储接口；测试未 mock 这条 storage 入口。jsdom 存储不应冒称已访问真实浏览器凭据，但传递初始化、所有 I/O 与异常清理尚未完成安全证明。

已经存在一个更早、不能用测试内代码封闭的阻断，因此本轮未穷举所有传递依赖，也不宣称整个导入图已审计或已实现系统级网络/文件隔离。

## 3. 精确选中与真实目标边界

只读逐项查看 `packages/core/realtime/use-realtime-sync-inbox.test.tsx` 的 **14 个顶层 `it`**；没有父 `describe`、`NTF-005`/`NTF-007` 名称、`.skip`、`.todo` 或 `.only`。因此两条 `-t` 对当前文件的**静态预期均为零个匹配目标**。这不是运行后报告的选中数；未运行，也不能以 `passWithNoTests` 或 exit 0 计通过。

现有断言可作为将来标记/扩充**客户端组件子集**的基础，但本轮没有只加标签制造验收：

| 当前测试行 | 实际断言层次（静态阅读，不是 PASS） |
| --- | --- |
| 209、362 | 手工带 key 的 Inbox fixture，同 ID 顺序/重叠重投仅调用一次假 confirmed 桥；209 还区分新 Inbox ID。只断言桥调用，不是 OS 可见提醒。 |
| 396、540 | 相同 Inbox ID 在不同 workspace 可分别调用桥；540 的“slug 失败”不是 item 缺 workspace 的覆盖。不是不同 CR 的服务端去重测试。 |
| 259、289、317、476 | 假桌面拒绝/rejection、假浏览器 onerror、缺 confirmed 能力后重投可重试。不是提交后崩溃、pending 扫描或 DB 恢复。 |
| 429、586、639 | 异步期间 focus/mute 变化；639 使用 mock rejection，不是真实取消网络请求。 |
| 38、242、522 | legacy 缓存刷新/旧 void bridge 路由；242 明确同一 legacy 行可两次发送。 |

共 11 个测试手工提供 `details.execution_notification_key`，3 个没有 key；这不证明服务端实际提供该字段。

### 代码契约与未验证差距

- `packages/core/inbox/ws-updaters.ts:39–70` 依赖 key 才启用新策略，以 workspace + Inbox ID 在 QueryClient claim/release；`use-realtime-sync.ts:566–709` 负责 focus/mute 与 bridge/web 分流。结果最多证明该入口在特定 fixture 下的客户端行为。
- 当前工作树 `server/internal/governance/execution_notice.go` 的 Inbox INSERT 不写 `details`；`LoadInboxItem` SELECT/返回 map 也不带 `details`。当前同文件已有他人未提交改动，本轮只读且没有覆盖。不能把手造 key fixture 当作真实 `DeliverNotice → LoadInboxItem → BusBroadcaster` 链路已经成立。
- `packages/core/query-client.ts` 默认 `gcTime=10min`；claim helper 没有另定生命周期。GC 后、重启、多窗口/设备的保证仍无本轮运行证据。**未获得 fake-clock RED**，不改 gcTime、不增永久全局集合、不自行收窄批准的幂等要求。
- 本轮未验证服务端事务/并发身份、不同 CR、pending/delivered 恢复、业务不重签/不扣额/不派 writer、mobile、真实 WS/桌面主进程/OS/第三方或生产接线。NTF-005/007 完整 TC、tasks 3.2 和 Gate3 不得据此标记通过。

## 4. 本轮产物、保全及后续准入

本轮只新增本报告；没有修改 multica 的源码、测试、配置、`CUSTOM.md`，也没有改任务/授权/状态账本。此前 multica 的 `CUSTOM.md`、backend、DB 脚本等未提交更改保留原样。对上列 core 源码/测试/配置的定向 `git diff` 无输出，定向 `git diff --check` 无错误；这是 diff 卫生检查，不是测试通过证据。`tasks.md` 已有他人未提交修改，未编辑或覆盖。

继续该受阻路径所需的最小输入不是允许读真实密钥，而是**可验证的外层启动隔离能力/方案**：在 Node/pnpm 启动前封闭继承凭据与配置读取、禁下载/禁网络、限定文件可见性及临时写入归属，并绑定正确现有 launcher/依赖和当前源码。必须再核原命令、目标来源及异常退出边界；涉及新增入口/脚本/参数或不同执行目录的方案不能自行当作现有白名单。

满足外层前置后，才适合在授权内修改必要测试/配置：为有业务意义的组件目标加准确标签及非零计数断言，保留同 ID/新 ID/跨 workspace、失败释放与 legacy 对照；必要行为修复先获得真实 RED，再以**完全相同两条白名单命令**验证 GREEN。既不能让无关测试扩入选择，也不能用空选、skip、只改名字、手工缺 key 的预期结果或配置启动错误充当业务 RED。涉及 server details/持久化形态、重启保证等重大设计差距继续独立审议，不在本轮臆定修复。
