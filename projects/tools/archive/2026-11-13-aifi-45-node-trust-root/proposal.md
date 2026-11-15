# 授权节点内 crctl 可定位 daemon 信任根，提供 workspace 的 authority 事实，并让 crctl 自己的 git 调用不经 agent 的 git shim（tools 侧，与 multica 2026-11-13-aifi-45-real-execution-closure 成对）

<!-- source_hash: d0d5c0e7090305dc -->
<!-- generated_at: 2026-11-14T23:03:28.452981 -->
<!-- canonical: canonical/proposals/2026-11-13-aifi-45-node-trust-root.yaml -->

## Why

授权执行（authorized-execution/v1）的 execution-grant 与公钥由 multica daemon 安装在 daemon 自有的信任根
（~/.multica/execution-trust/<ws>/），原因是 CR 工作区内的 .crctl 对受管 agent 可写（ADJ-AIFI45-003）。
目前 crctl 只有命令行 --trust-root 一种方式选择这个信任根；tools 的所有节点 skill 里的 crctl advance
命令都不带它，也没有环境变量或默认路径。因此授权节点内 agent 运行的 crctl advance 读取的是旧位置
<安装根>/.crctl/grants，找不到 execution-grant，以 EXECUTION_CONSUMPTION_REQUIRED 拒绝，节点无法完成
门控推进，也就无法在 run 内产生执行回执。该结论来自静态读码（crctl.mjs:1474-1480、
execution-authorization.mjs:111-145、各 SKILL.md、multica daemon.go 的 env 注入），没有真实运行验证。
multica 的 real-execution-closure 需要这个问题被解决后才能进行真实运行（切片 4–6）。

2026-11-14 并入第二处接缝：multica 的无模型替身运行（A0，真实 podman 整栈、替身 pi，零模型费用）显示，
daemon 在启动每个 pipeline 节点任务前会执行 crctl workspace inspect <CR> --workspace <root> --detail，
要求输出含 targetSpecId（或 kebab 名）与有效的 targetVersion，缺失即以 TARGET_SPEC_AUTHORITY_DRIFT 或
WRITEBACK_VERSION_UNASSIGNED/INVALID 拒绝启动。tools HEAD 的该命令输出键只有 op、cr、mode、txId、
resources、changed、operationalWorkspace、operationalWorkspaceError、freshness，git log -S 证明历史上
从未输出过这两个键；daemon 单测用手写 JSON，所以一直没被发现。不补这两个字段，授权节点在 writer 节点启动前
就会被 daemon 拒绝，信任根变量也没有机会被验证。该结论来自读码与宿主机复跑 crctl，尚未端到端观察。

2026-11-14 再并入第三处接缝：A0 再往下走时发现，daemon 在每个任务 agent 的 PATH 前置一个 git shim
（{envRoot}/bin/git，内容是 multica gitguard-exec <真实 git> <调用者> "$@" 的包装），其后端读取
MULTICA_CONTROLLED_SHELL_RULES；agent 环境里没有该变量（multica 的 agent 环境构造丢弃全部继承来的
MULTICA_* 变量，daemon 也不重新发布），shim 因此对每一次 git 失败关闭。crctl 自己的 git 调用共 10 处
（crctl.mjs 2、lib/change-scope.mjs 4、lib/workspace-transactions.mjs 4）都是经 PATH 解析的
spawnSync('git')，在 agent 环境里同样命中该 shim；deriveInstallRoot 在 git 失败时回落到传入路径，
所以此前没暴露。A0 三组对照（真实 podman 整栈、替身 writer、零模型费用；不是任何 TC 的证据）：
①现状：crctl 的 git 被 shim 拒绝，两个候选 --workspace 都在 next 或 inspect 失败，advance 一次也没能执行；
②仅让 shim 看到规则变量：拒绝变为白名单拒绝，crctl 内部的 rev-parse --git-common-dir
（deriveInstallRoot 的输入）与 advance 里的 show HEAD:<CR>/execution-contract.yml 被拒，安装根被回落成
CR worktree，第一次 advance 以 EXECUTION_BINDING_INVALID 失败，没走到平台；③仅让 crctl 子进程的 PATH
去掉 shim 目录、不发布规则变量：next、inspect、两次 advance 全部成功，没有任何白名单拒绝，
basis.grant_head 等于授权 head，平台侧 consumption=1、effects=1/1/1；agent 自己直接调用的 git 仍失败关闭。
因此授权节点里的 crctl advance 在现状下无法工作，信任根变量也没有机会被验证。


## What Changes

- crctl 增加信任根定位环境变量 CRCTL_EXECUTION_TRUST_ROOT，语义等同于同值的命令行 --trust-root
- 合并集中在一处（main 的 flag 解析边界），仅对当前实际消费 trustRoot 的八个命令生效：advance、authorization-bind、authorization-scope、sensitive-action、repair-admit、repair-resume、register、archive；其他命令（含 kb/workspace/business/writeback-apply/git、repair-assess/repair-outcome）完全不受影响
- 变量与 --trust-root 并存：值相同通过，不同以 EXECUTION_TRUST_ROOT_INVALID 拒绝；变量被实际选作信任根而值不合法时拒绝，不回退到旧的 .crctl 位置；未设置时行为与现状完全一致
- multica 侧（daemon 对授权节点注入该变量）在 multica 成对 change 内实现，不在本 change 内
- （2026-11-14 并入）crctl workspace inspect --detail 的成功输出新增 targetSpecId 与 targetVersion 两个键（字符串或 null），取值只复用既有读取器（resolveTargetSpecMode、readCrMdTargetVersion）；既有键、类型与值不变，默认（非 detail）输出不变；daemon 读这两个键的方式不变
- （2026-11-14 并入）同步 crctl-detail 金样本 workspace-inspect.json 的字段路径集合，并新增测试断言新字段的取值与既有输出不变
- （2026-11-14 并入）crctl 在 main 入口最先的位置，从自己进程的 PATH 移除放有 controlled-shell git shim 的目录（目录内的 git 或 git.cmd 是小于 4096 字节的文件且内容含 gitguard-exec），使 crctl 自己 spawn 的 git 到达真实 git；没有 shim 时 PATH 逐字不变；agent 直接调用的 git、shim 与 rules.json 白名单、crctl 自己的 controlledGit 白名单与调用者名均不变

### Modified Capabilities

- **crctl-execution-trust-root**：crctl 对执行授权信任根的选择方式：除 --trust-root 外，接受 daemon 注入的环境变量，规则一致、失败即拒绝；并为 workspace inspect --detail 补充 daemon 核对 authority 所需的两个事实键，并让 crctl 自己 spawn 的 git 不经 agent 的 git shim（2026-11-14 并入）

## Success Criteria

- [ ] 设置合法的信任根环境变量时，八个生效命令与传同一值的 --trust-root 行为一致（可比的只读输出逐字节一致，其余稳定结果一致）。
- [ ] 变量被实际选作信任根而不是绝对路径、不存在、不是目录、位于或包含安装根时，crctl 以 EXECUTION_TRUST_ROOT_INVALID 拒绝，不回退到 .crctl；legacy 或不消费信任根的分支与同值 flag 一样忽略该值。
- [ ] 变量与 --trust-root 不一致时拒绝；一致时通过。
- [ ] 未设置变量时，crctl 现有测试全部不变地通过（legacy 与 --trust-root 用法无差异）；对八命令之外的命令设置任意变量，结果与未设置一致。
- [ ] 同一自备信任根及材料经环境变量与 --trust-root 选择时，本地准入结果一致，环境变量不比 flag 更宽松或更严格；缺 key、签名无效或 binding 不匹配仍按现有规则拒绝；本地准入成功不构成平台授权证明（取代原“伪造 grant 或公钥不能准入”一条，该条与现有代码不符）。
- [ ] multica 成对 change 的 daemon 注入后，授权节点里 crctl advance 的授权读取成功（该条在 multica 的真实运行验证，本 change 只负责 crctl 侧）。
- [ ] crctl workspace inspect <CR> --detail 在 cr.md 与 _backlog.yml 的 target-spec-id 一致且有效、cr.md 有 target-version 时，输出非空的 targetSpecId 与 targetVersion，值等于既有读取器的结果；legacy（两侧都无）、单侧缺失或不一致时 targetSpecId 为 null，cr.md 无 target-version 时 targetVersion 为 null；unassigned 等原值逐字透传，不在 inspect 里判断有效性；退出码与既有错误码不变。
- [ ] 除新增两键外，workspace inspect 的既有输出键、类型、值与默认（summary）面不变，crctl-summary.test.mjs 对金样本的三层比对继续通过。
- [ ] multica 的 daemon 在真实 crctl 上通过 inspectPipelineAuthority（在 multica 的无模型替身运行与真实运行中观察，本 change 只负责 crctl 侧）。
- [ ] crctl 进程启动后其 PATH 不含放有 controlled-shell git shim 的目录（识别：目录内 git 或 git.cmd 为小于 4096 字节的文件且内容含 gitguard-exec），其余目录及相对顺序不变，没有 shim 时 PATH 逐字不变；crctl 的 controlledGit 白名单、调用者名与命令面不变，agent 直接调用的 git 不受影响。
- [ ] multica 的无模型替身运行与真实运行中，授权节点里经 git shim 环境（shim 在 PATH 上、无规则变量）的 crctl next、workspace inspect 与两次 advance 成功（在 multica 观察，本 change 只负责 crctl 侧）。
