# AIFI-45 SC-AUTH-010 跨语言 execution-binding 互通限定静态评审

## 明确结论

**成立——仅就“服务端真实 binding HTTP 响应中的签名 envelope 能被实际 T 的 requestExecutionBinding 接受，并满足其 20 字段比较”这一正向互通命题而言。测试不是 Go 自证，也没有只调用低层验签再在 Go 复制 T 的 expected。** 所读、与当前测试文件匹配的作者执行记录有正例 PASS，非 Skip；本评审没有独立运行它。

**抗篡改负例的因果证明仅为部分，确证一项 P2 测试缺陷 I1**：第二个 Node 的新 challenge/PID 与回送的首个进程旧 payload 本来就不匹配，因此即便移除签名验证，该负例也可继续 PASS。不能用这一个负例宣称“保留签名、改 payload 的拒绝分支已经被有效回归保护”。这不推翻正向互通，也不表示当前 T 没有验签。

这是接口格式/密码学互通的一次 fixture 场景，不是生产 daemon 私有 relay、真实 OS child 归属、人类来源、完整安装链、消费或准入证明。若把 SC-AUTH-010 扩大为包含独立、可辨识的负签名回归或完整生产链，本报告不签扩大后的结论；还须补 I1 所列负例与相应运行证据。

## 范围、源码身份与方法

- M 根：`C:/Users/GOBAO/Downloads/AI/multica`；主要文件 `server/internal/governance/execution_binding_issue_test.go`。
- T 根：`C:/Users/GOBAO/Downloads/AI/tools`；直接读取 `skills/shared/crctl/scripts/lib/{execution-binding,execution-authorization,workspace-transactions}.mjs` 的必要实现，以及直接本地依赖的 import/错误类型片段。
- 仅静态检查新增顶层测试、fixture 改动及所需直接 helper。**未访问 DB，未运行测试、Node、Go、vet、编译或生成器，未修改源码/测试，未使用子代理。** DB 单权未被触碰。
- 当前测试文件：35,393 bytes，raw SHA-256 `35d90ef0fe1e9106518df82b12d8d1709eb71d37743dcc6c8d2e60e8ae8f85da`，匹配 `interop-20261025T083500Z-red1-source-manifest.json`（`2026-10-25T08:30:34.183Z`）。该 manifest 只列此 M 测试文件，不冒充 T/所有服务端源码已被运行时固定。
- 模型背景沿用 configured strong `OpenAIPersonal/gpt-6.1-sol/high`，actual backend unknown；没有重新发现 backend。
- 报告 wx 独占创建，发布前重新核测试 raw pin，并回读验证；不覆盖既有报告。

## 1. 是否真的执行 T 的 requestExecutionBinding？——是

`execution_binding_issue_test.go:812–816` 从 `os.Getenv("AIFI45_TOOLS_ROOT")` 取根；仅空值时 t.Skip。Node 内联脚本 `:849–859`：

1. 从子进程 env 读取同一 root；
2. 用 `path.join(root,'skills/shared/crctl/scripts/lib/execution-binding.mjs')` + `pathToFileURL(...).href` 动态 import；Windows 盘符路径不是裸当 module specifier；
3. 同样 import T 的 execution-authorization.mjs；
4. 调 `authorization.readExecutionGrant(workspace,grantName,crID)`；
5. **await `binding.requestExecutionBinding(workspace,grant,'implement-code')`**；成功后才输出 keys count。

`:861–870` 真正 `exec.Command("node","--input-type=module","-e",script)`，把 toolsRoot/workspace/CR/grantName 放入子进程 env，cwd 为临时 workspace。未见 mock module、替换 export、Go 复制 T 的 binding verifier 或执行同名 Go 函数。

T `execution-binding.mjs:51–124` 是本机真实模块的高层函数：检查本地根/coordinator、创建随机 challenge，等待 stdin，调 `verifyExecutionEnvelope`，然后比较完整 expected、身份形状和 exact key set。脚本不是只 import 一个名字而不调用。

**执行身份边界**：AIFI45_TOOLS_ROOT 必须指向受信的真实 T checkout；源码未拒绝相对路径或核验 checkout/hash。指向任意替代目录理论上可以导入替代模块，正如其他外部测试依赖需可信；本轮所读 T 就是上面明确路径。现有运行 metadata 没有保存该 env 的值/Node 版本/T 文件 hash，不能独立追溯运行当时 T 的全部身份。建议把实际 root、关键模块 hash/版本和 Node 版本记入证据；这不是把本轮发布时哈希当成历史执行 pin。

## 2. challenge 与 envelope 的实际数据流——真实闭环，无另签

### 子进程生成 challenge，父进程读 stdout

T `execution-binding.mjs:75–84` 使用 crypto.randomBytes、process.pid/ppid、本地 realpath、grant digest、toolsRuntimeDigest 创建 challenge，再向 stdout 写 `JSON.stringify({binding_challenge:challenge}) + '\n'`。

Go `execution_binding_issue_test.go:875–918` 从 **cmd.StdoutPipe** 读首个换行行，JSON 解到 BindingChallenge，并拒绝空对象；将它传给 proof callback。5 秒内读不到行或非预期 JSON 是 Fatal/FAIL，不是 Skip。Go 没有在此调用 f.challenge() 生成替代 nonce/PID。

解成 map 再 marshal 会重排 challenge 的运输键序，但字段值来自该子进程；本次 PID 等整数在正常 OS 范围，JSON float64 中转并不改变它们。这里没有要求 challenge 原 JSON bytes 本身被签，服务端签的是其另建 payload bytes。

### 父进程通过真实路由拿 response envelope

正例 `:927–949` 把 child challenge 放入四键 body（task/runtime/代次由本次 DB fixture 提供），调用 `f.post(t,raw,f.h.token)`，要求 HTTP 200，解析 response 的 `Envelope json.RawMessage`，并 **return resp.Envelope**。

`f.post` 在 `:249–260` 使用 httptest.NewRequest/ResponseRecorder、Bearer MDT fixture token，并调用已挂 middleware/handler 的 `f.routes.ServeHTTP`。fixture `:139–151` 注册真实 DaemonAuth 与 governance daemon routes，DB 是真实 fixture。它不是 stub JSON responder；但也**不是经过 socket 的远程 HTTP 传输测试**。本报告的“真实 HTTP”指公开路由/中间件/handler/DB seam，不冒充 TCP/反向代理/部署入口验证。

Go `:914–923` 把 callback 返回的 envelope 写入 child stdin，关闭 stdin（让 T readProof 读到 EOF），再 Wait。没有在正例 callback 中再次 ed25519.Sign、自己构造 binding payload 或使用先前 f.assertEnvelope 的 Go 字段断言替代 T。

fixture 里的服务私钥用于真实服务签名；初始授权也由服务授权 HTTP 路由取得并保存在 f.grant（`:150–179`）。测试本来需要 fixture signer/key，不等于把 binding 另行在 Go 测试中自签。公钥安装在临时根，是测试信任锚，不是生产公钥来源证明。

## 3. exit 0 与 20 字段断言——正向足够，不是只数键

Go 正例 `:950–956` 要求 cmd.Wait 无 error，即正常 exit 0，并要求 child stderr 包含 `"keys":20`。Node 脚本该行在 await requestExecutionBinding 成功之后（`:858–859`），并非在调用前无条件打印。

关键不是这个 substring 单独多强，而是 T 内部真实校验：

- `execution-authorization.mjs:286–309` 限定 envelope exact 三键、规范 base64、Ed25519 key/signature，验证 `execution-binding/v1\0 || raw_payload_bytes`，不是重序列化后再验；
- `execution-binding.mjs:99–124` 在验签之后比较 schema/key/W/P/CR/resource/daemon、nonce、两 root、PID/PPID、operation、head/revision、policy/template/tools digest，核 runtime/task canonical UUID，并拒未知/缺失/额外字段；
- 因 fixture 是 local_directory，daemon_id 也进入 expected，相应 fields 共 20 个。返回 verified 说明经过这些检查，而不是只通过 crypto.verify。

因此没有把 T 的字段期望抄回 Go 来形成循环自证。readExecutionGrant 内部先验的是 initial authorization；requestExecutionBinding 内部验的是 binding 域，两者不是用 grant 验签来冒充 binding 验签。

可接受的测试健壮性建议：stderr count 用 substring 会匹配类似 `"keys":200` 的前缀，最好解析独立 JSON 结果并等于 20；但当前实际 T 的 exact fields 检查已在成功返回前排除 200 键，故不单独定为新 P2。不能由这一个 fixture 宣称所有字段负例/值域/平台组合均覆盖。

## 4. I1 — P2（测试证明缺陷）：负例同时是过期 challenge/进程回包，不能单独回归签名拒绝

**位置**：`execution_binding_issue_test.go:926–948,959–983`；T `execution-binding.mjs:75–84,104–124`。

### 真实做到了什么

负例把 positiveEnvelope 解成 envelope，解 payload，改 `payload["task_id"] = uuid.NewString()`，重新编码 PayloadB64，保留原 key_id 和 Signature（`:959–981`）。它没有重新签名；map 重编码还可能改变 payload 键序，所以不仅语义上的 task_id 改了，原 signed bytes 也变了。随后把 tamperedEnvelope 送给 T，断言 child error 非 nil（`:982–983`）。在当前 T 里真实 crypto.verify 位于逐字段校验之前，确实应该先拒绝坏签名。

### 为什么断言不足

它调用 runChild **新起第二个 Node**，而 proof closure **忽略该进程输出的新 challenge**，回送第一个进程的旧 payload。新进程有新的 random nonce/自己的 PID，所以 payload 在新进程的 expected 中本来就不匹配，至少 nonce 不同。

即使 T 回归到“跳过 crypto.verify 但保留字段比较”，这个负例仍会因 C_old≠C_new（通常 PID 也不同）而失败，Go 仍认为负例 PASS。只检查任何非零退出也未断言 `EXECUTION_GRANT_SIGNATURE_INVALID` 的 cause；当前运行记录没有保存该 negative child stderr 作为可辨识原因。

**分类与影响**：确证一项 P2 测试/验收证明缺陷，不是发现 T 当前验签缺失或生产认证突破。它不使正向 PASS 变成 Go 自证，也不否认 payload 确实被改而 signature 未变；只是负例不能证明“仅签名失效”这条安全机制受回归保护。

**最小补法（本轮未改）**：在负例自己的 runChild callback 中，用该 child 的真实 challenge 再走一次 HTTP，拿同进程的合法 envelope，然后只改其中 canonical task_id/runtime_id 等 T 不会另与预期固定值比较的身份字段、保留原签名，再回填。这样移除验签就会被 T 接受，负例才会失败并检测到回归。让 Node catch 输出结构化 error/cause_code，并精确断言签名错误，不接受任意非零退出。不能另签新 payload，也不能把高层 request 换成测试侧复制 expected。

## 5. fixture、安装根和布局——满足当前 T 的默认安装语义，不靠跳过通过

`execution_binding_issue_test.go:817–845` 使用 EvalSymlinks(t.TempDir())，把 workspace 作为 coordinator.local_path 传给 `newBindingIssueFixtureAt`，再创建：

```text
<workspace>/.crctl/keys/<key_id>.pub
<workspace>/.crctl/grants/<scopeHash>-<grant_id>.execution-grant.json
```

这里 Go 变量 `installDir` 已等于 `<workspace>/.crctl`，不能再在它下面额外加一层 `.crctl`。题述若以 installDir 指“安装 workspace 根”则含义不同，须按上面的实际完整路径理解。

T 语义逐项对应：

- `workspace-transactions.mjs:47–54` 的 deriveInstallRoot 对普通非 git 临时目录回退 opWs；若 git 可用且命中 linked checkout，则取 common-dir 父目录。本测试通常是独立系统临时目录，所用分支真实支持这种 fixture，不是测试自写 resolver。
- `execution-authorization.mjs:84–86` 没传 options.trustRoot 时取 deriveInstallRoot(workspace)/.crctl；`readExecutionGrant(:263–282)` 实际从 grants 读文件，验 initial grant，验证文件名中的 scope hash/grant UUID/CR。
- 文件名 Go `ExecutionScopeHash` 来自真实 shared-domain helper（`execution_authorization.go:409–417`）；T `execution-authorization.mjs:256–280` 独立按相同 domain/W/P/CR 重算并比对。错路径或错文件名会抛错，不会悄悄接受另一个文件。
- `installedFile(:105–118)` 检查实际路径 containment 与 size，`verifyExecutionEnvelope(:297–304)` 实读 keys 公钥；不存在缺文件自动跳过验签。
- T `execution-binding.mjs:57–73` 的 localCoordinator 分支核 local_path 是 native absolute、与 installRoot 词法相等（Windows 忽略大小写），并 stat 实际目录 dev/ino。fixture 的 descriptor 的确是 local_directory，路径指同一个 canonical temp workspace，不是改为非 local 类型绕过此分支。
- `newBindingIssueFixtureAt(:78–99)` 用 json.Marshal 生成 localRef，Windows 反斜杠/引号能正确作为 JSON 字符串转义；避免旧字符串拼接产生无效 JSON。绑定 descriptor/初始 grant 都使用这一 localRef，不是只给 Node 另塞一个方便的 root。

布局不对通常在 readExecutionGrant 或根检查阶段就没有 stdout challenge，Go 会 Fatal；Node 端没有 t.Skip，也未见失败后自动采用其他 grant/公钥。因此没有“布局错但恰好被跳过”的路径。

**范围上限**：这是默认 legacy .crctl 安装布局；没有使用声明在 workspace 外部的 trustRoot 模式，也没有测试生产 daemon installer、key 的远程来源或同 UID 隔离。没有 source sidecar 是因为 readExecutionGrant 不调用 readExecutionSource；不能以此宣称已测试完整人类来源核验。Git 环境变量若把 common-dir 指向别处可能使测试失败，而不是构成默默跳过。

## 6. CI、依赖、网络与路径写入

| 环境条件 | 当前代码行为 / 证据范围 |
|---|---|
| AIFI45_TOOLS_ROOT 未设置或空 | `:814–815` 直接 Skip；不算 SC-AUTH-010 执行证明，CI 不能只看 package exit0。 |
| env 已设但 node 不在 PATH | `:862,881–882` cmd.Start Fatal，**不是 Skip**。 |
| env 已设但 tools 路径/模块/所需文件不存在 | import 或 toolsRuntimeDigest 失败，challenge 读取错误或超时使测试 FAIL；**不是 Skip**。 |
| 无专用 DATABASE_URL/DB schema | 需要真实 DB fixture；直接 helper `execution_task_claim_project_test.go:51–60` 缺 DATABASE_URL 即 Fatal，不是无需数据库的纯 Node 单测。这里只读代码，没有执行。 |
| Node/T 依赖 | 需要支持当前 ESM/import.meta.dirname/recursive readdir 等功能的 Node，以及完整实际 T checkout；toolsRuntimeDigest 会读 libraries、templates、agents、skills、规则文件（T binding `:12–32`）。所读直接/transitive import 是 Node 标准库与本地 .mjs，无新增 npm/npx/远端模块安装步骤。 |
| Git | deriveInstallRoot 做本地只读 git rev-parse；缺 git/非 git 失败时回退 workspace，不因缺 git 单独 Skip。不是 remote fetch。 |
| 网络 | Node 交互是 stdin/stdout，不向平台发网络请求；Go HTTP 是进程内 httptest。真实 DB 连接仍可能用本机 TCP/其他 DATABASE_URL 连接；不应宣称整个测试“零网络/零外部服务”。未见这一互通路径需要互联网/API key。 |

文件写入在 t.TempDir 下的 keys/grants；localRef 与签名 payload 中有临时绝对路径，会进入 fixture DB/临时 grant，也可能出现在失败日志。未见写 M/T 产品仓源码、将宿主绝对 toolsRoot 硬编码进仓库或把 .crctl 写进实际 T checkout。Node 所读 T 指纹路径仅用于读/哈希。0700/0600 不构成跨平台隔离证明。

健壮性建议（非新增 P2）：runChild 没有统一 defer/t.Cleanup 去 kill/reap；如果 proof callback 中 t.Fatal，则可能没有关闭 stdin/Wait，子进程需等 T 的 15 秒 readProof 超时。cmd.Wait 也没有独立 context deadline。建议 child 统一 cleanup/超时，并结构化解析输出；这是测试资源管理，不是互通成立的替代证据。

## 7. 提供运行记录、未验证项与最终边界

只读 `interop-20261025T083500Z-red1.meta.json` 和 stdout.jsonl：**3 RUN / 3 PASS / 0 FAIL / 0 SKIP，2 leaf**，含正向 accept 与 tampered reject；测试源 raw hash 匹配当前文件。名字虽然带 red1，这份记录实际是 PASS，**不能编造已经观察到 RED→GREEN**。元数据记载原库 unchanged/released、临时资源 cleaned，但本评审未访问 DB 验证。

它支持“按所提供作者记录，这次不是 Skip、且真实交互测试的正例执行通过”。运行日志未导出 Node 成功结果 JSON/完整错误 cause，也未记录实际 AIFI45_TOOLS_ROOT/T hash/Node 版本；发布时对 T 文件的哈希不等于运行时 pin。没有独立重跑、没有覆盖所有跨平台/linked-worktree/trust-root 模式，没有完成生产私有 relay/消费链。

**新增确证问题：I1/P2（负例不能隔离签名验证）；无新增确证产品 P0/P1。正向 SC-AUTH-010 签名/20 字段互通成立，负签名回归证明仍部分；不签消费、准入、activation、隔离域、完整进程身份或全局 C1/Gate3。旧 claim 锁序 INCOMPLETE；业务 TC 0/49；5 major 未关闭；消费 closed/off。**

## 附：发布前读取身份核对

时间：`2026-10-25T08:37:13.435759+00:00`。M 测试再次匹配 red1 raw pin；T 下列三模块再次匹配本轮读取时采样，**不代表历史执行已固定这些 T 文件**。

- M `server/internal/governance/execution_binding_issue_test.go` — 35393 bytes，raw SHA-256 `35d90ef0fe1e9106518df82b12d8d1709eb71d37743dcc6c8d2e60e8ae8f85da`。
- T `skills/shared/crctl/scripts/lib/execution-binding.mjs` — 7262 bytes，raw SHA-256 `8fe71e0f5fc48a524763a63641a43052fff78fc25868017669516297b03ba95d`。
- T `skills/shared/crctl/scripts/lib/execution-authorization.mjs` — 22367 bytes，raw SHA-256 `71437e20ddfdf33b74d3490c7129359562443555d1abc0a44886b27f32c34abc`。
- T `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` — 323236 bytes，raw SHA-256 `7f559c808eb63484f388a429594b017b7e58b46d1e655cf2f3eb458aef2350bf`。
