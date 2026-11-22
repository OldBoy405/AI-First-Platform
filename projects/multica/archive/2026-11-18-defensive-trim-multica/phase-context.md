# Phase Context — 2026-11-18-defensive-trim-multica

> 阶段交接摘要；冲突时以正式产出物为准。

## Phase 1: UNDERSTAND（2026-11-18T15:38:04 完成）

### 关键决策与用户关注点
- 范围为源方案中的授权准备与历史读取、敏感动作、运行进展和固定提交取材；已交付的字面 null 拒绝不重复开发。
- 模式为 thorough（初步复杂度 14）。用户要求精简过度防御及过度设计，仅修改已登记的 fork 代码。

### 产出物与完整上下文
- `canonical/proposals/2026-11-18-defensive-trim-multica.yaml`、`proposal.md`：Gate 1 已确认，需求和约束以其为准。
- `docs/analysis/Multica与Tools防御性编程精简方案.md`：源方案，路径相对记录根。

## Phase 2: SPEC（2026-11-18T17:21:00 完成）

### 关键技术决策
- 一次准备授权请求，签发与重放复用；历史读取核验存储协议与当前事实，不按新申请规则重审；消费者使用已验证结果。
- 敏感动作与撤销在现有 CR 排他锁内确定顺序；进展 GET 使用同一 run 状态，读取失败走现有错误出口。
- 默认合同实跑使用 `parsePin` 和固定提交；仅显式选择时使用工作树 overlay。
- 合并数据库检查点；选择及实际测试包依 `design.md` 和 `test-plan.md` 落实。

### 经验与注意事项
- 测试夹具区分缺省和显式传值；真实凭证的路由测试须抵达 handler；锁序测试须在交错时探测；跨包核对签名改动的调用者。
- 现有工作树有无关未提交改动，实施前与提交前核对并隔离；fork 台账使用真实 change/任务标识。

### 待 Phase 3 验证
- 授权字节、事务交错、生产路由与固定提交取材尚未实跑。DB 测试仅授权使用 `run-selection.mjs` 为本 change 按需自建和回收的一次性实例；实施前仍须核对工作树隔离。

### 产出物与完整上下文
- `design.md`：技术决策、范围、选择包和验收清单；Gate 2 已确认。
- `canonical/specs/code/` 与 `specs/`：3 个 capability、13 个 Scenario；`canonical/specs/agent/`：6 个检查点。
- `test-plan.md`：6 个 TC 及同次执行证据计划；首 task dry-run 通过。

## Phase 2 后的长程授权与暂停（历史）

### 长程授权与暂停
- 用户原话（2026-11-18）：“确认上述长程授权；先不实施。”已确认上轮列明的长程授权，包括本 change 的一次性数据库测试，但本轮不得进入 BUILD 或实施。
- 不连接或清理现网数据库、daemon 或容器；先核对并隔离无关改动，不覆盖、stash、reset 或提交这些内容。不新增依赖或访问外部网络；需要时暂停询问。
- 受审承诺变更须暂停并走 revision；Git 提交、推送、部署和 Gate 3 另行确认。

## Phase 3: BUILD（2026-11-18 启动）

- 用户要求启动本 change 的 BUILD，并避免重复校验和无意义兜底。仅启动 Multica change；前述数据库、外网及 Git 操作边界保持不变。
- 经 `stdd phase set 2026-11-18-defensive-trim-multica build` 进入 `in_progress`；计划见 `slices.md` 和 `tasks.md`。
- 实施目录为业务仓的独立 worktree `../multica-defensive-trim-build`（基线 `0c47c67e7`），其 STDD binding 指向原记录根；不复制 `.env`，不改主工作树的 Pi/Chat 改动。
- **S2 完成**：`scripts/aifi45-real-run/{stack,crctl-stage}.mjs` 复用 `parsePin`、固定树一次物化、显式 HEAD 走 overlay；两个对应测试文件覆盖 TC-CBE-101，fork 台账 #348。RED：缺少显式 ref 的拒绝、坏 pin 的拒绝均失败；GREEN：三文件 50 pass / 0 fail / 1 个既有 Windows skip；相关脚本回归 368 pass / 0 fail / 3 skip（另两例未配置 `AIFI45_TOOLS_ROOT`）。
- 全脚本套件 737 pass / 16 fail / 3 skip，与独立未修改基线同名、同计数；不把全脚本报告为全绿。用于 Windows 验证的 `stub-pi.mjs` 只在独立 worktree 恢复 Git blob 的 LF，和 HEAD 无内容差异。
- S1（签发与重放）继续按长程模式执行。按用户要求，Multica 测试的 `AIFI45_TOOLS_ROOT` 指向独立检出 `../tools-pin-multica-defensive-trim`，`CRCTL_MJS` 指向该目录内的 `skills/shared/crctl/scripts/crctl.mjs`；两者同为 `.github/aifirst-tools-pin` 指定的 `7a0a2ab57f3f5e2c583c3523bc69d67e7be115c1`，不读正在修改的 `../tools`。DB 仍只用 runner 自建实例。
- S1 部分进展：HTTP 增加显式空串，重放核对原信封、冻结字节及头不变；selection 加入真实 `crctl` 互操作。固定检出下 `run-default-contract-issue` 24 pass / 0 fail / 0 skip，自建实例回收 `remaining=0`；fork 台账 #349。尚未改生产签发或重放代码、未登记 S1 完成。
- 宿主 Guard 在冻结字节基线测试编辑时返回 `HASH_NOT_AUTHORIZED`（`evt_453cc7f5-e22a-4daa-baf9-553af9e95ca7`），未执行被拒修改。随后用户以 `change hash=allow` 要求长程继续 S1；只将现有协议的冻结源 SHA-256 收拢到两路径的公共准备，未另加测试哈希，未变更签名协议。
- **S1 完成**（TC-RUN-201，1/1，新增 5 个通过的叶子，无新增文件；fork 台账 #349–#350）：CR 排他锁内一次解码、补值及计算冻结源摘要；精确重放返原记录且不查资源、不验当前头、不写入，首发锁内核对身份和资源后同事务写记录与初始头。已迁移 Go 签发调用和跨包夹具。现场保留两次拒绝时序：原文/补全后的上限各在原边界拒绝，显式空身份与资源冲突并存时先返回资源冲突。
- RED/基线：固定测试密钥及 `synctest` 时间，用未修改的 `0c47c67e7` 签出两份样本；先用空期望签名观测失败，再固定签名，并以基线原 payload 对照。GREEN：CRLF/`-0` 和补值样本的冻结原文、原 payload 及签名逐字节一致。固定 Tools 下 `run-default-contract-issue` 对账 30 pass（27 叶）/ 0 fail / 0 skip，含真实 `crctl`；`run-authz-boundary` 4 pass / 0 fail / 0 skip。
- 固定同一 Tools 提交和一次性 runner 的包级对照：`internal/governance` 基线 1416 / 79 / 1，实施 1403 / 79 / 1（pass / fail / skip，已移除旧导出 builder 无生产调用的输入检查测试）；`cmd/server` 皆 920 / 13 / 0；失败与跳过的测试名集合相同，不把两包报为全绿。各实例 `remaining=0`，未触碰现网。`stdd state ... --complete-slice S1 --tc-coverage 1/1 --new-tests 5` 已成功。该轮仅推进 S1，未开始后续切片。
- 用户随后要求长程继续本 change。**S3 完成**（TC-RUN-202，1/1，新增 1 个叶子，无新增文件，fork #351）：同一读取与验签结果返回已验 payload；授权 GET 仍返回原 head/record/key。既有回执、claim、协调器及 daemon 事实校验留在各消费入口；撤销使用已签前驱与 revision 验唯一初始根，精确重放不修复指针。将签发原文映射断言移到签发 HTTP，移除测试专用比较器。
- RED：同一历史形态夹具在未修改 `0c47c67e7` GET 409；GREEN：`run-authorization-head` 20 pass（19 叶）/ 0 fail / 0 skip，覆盖历史可读、原文被篡改拒绝、撤销成功与坏链。迁移入口定向回归 128/0/0；移除重复比较器后 `run-default-contract-issue` 29/0/0。继续固定 Tools 与一次性 runner，回收 `remaining=0`。
- **S4 完成**（TC-RUN-203，1/1，新增 2 个叶子，无新增文件，fork #352）：在取 CR 排他锁时读指针，核对并共享锁定指针记录，验头与敏感结算在同事务。删掉重复锁/decision 查询及不可达的 `no_effect` 出口，保留其余结算路径。新生产路由交错测试改前即通过（保持已有行为），改后 `run-sensitive-action` 8/0/0（7 叶），策略与撤销回归 18/0/0；撤销先行用结算表锁验证不查重、且零 effect；同 operation_id 校验原回执及只扣一次。实例回收 `remaining=0`。
- **S5 完成**（TC-EWV-101/102，2/2，新增 7 个叶子、原路由用例迁移，fork #353）：GET 用 scope 首读 status 派生进展；非法 frontier 对象、未知状态错误，缺 runner 键仍可读；两个 POST 按提交后单独读 status，进展出错保留原回执。改前 RED 捕捉首读 `running` 混出 `completed`、坏详情误报、两 POST 成功时错误附带进展。改后 `ewv-progress` 41 PASS/36 叶、`ewv-route` 10 PASS/9 叶（生产 router，真实成员 JWT/任务令牌，两 POST 各断言业务码）；`ewv-receipt` 9、`run-requirement-shape` 1、`run-routes` 18 均通过，0 fail/skip，runner 自建库。无生产测试钩子、无路由或认证机制变更。
- **C1 三路已返回**：代码、测试/配置、文档/Skills；配置及工具请求分别为 `OpenAIPersonal/gpt-6.2-sol:high`、`GB-JP/qwen4-max:xhigh`、`Gobao/deepseek-flash:high`，未获取到独立的 actual 模型运行凭据，不把请求等同生效。代码三条已复现并在原边界修复：S2 固定 Git 对象读取忽略 replacement refs、S1 在首发检查冻结 UTF-8 以保留重放冲突、S5 jsonb 对象数字不受 float64 限制。改前见固定 pin 读到替换字节、重放误返 400、合法对象误报；改后 CBE 50/0/1、签发 selection 29/0/0、authz 4/0/0、进展 41/0/0，DB 三次均报告 `remaining=0`。已同步台账 M34/#348/#350/#353 和 S1 的历史/当前计数，未改既有签名协议、进展状态或生产路由。
- **暂停在 C1 后的修订点，未进入 Gate 3**：`pending-adjustments.md` PA-001 记录 24 个冻结输入预览遗漏的实际 selection/代码/夹具/runner/pin，以及尚待补测的原场景；不把既有单次定向结果当最终证据。`make test` 不走获授权的一次性 runner，且 worktree 未装 pnpm 工作区依赖；未运行项目级组合检查、未联网/安装或使用现网。等待 Gate 2 修订授权与合规质量验证口径；当时未编辑已确认的 proposal/design/test-plan/spec，未写最终 run/test-report 或批准 Gate 3。
- **PA-001 Gate 2 修订**：用户授权修订，不是批准修订结果。同步 `test-plan.md`（冻结输入 24 → 35、原 6 个 TC/CP 不变）、`design.md`（实际调用点、回归及验证状态）、CBE agent spec（分文件计数；执行命令及断言不变）。`stdd canon verify` 和 `stdd agent verify authorized-runner --change 2026-11-18-defensive-trim-multica --dry-run` 通过；新增的 11 项均已由 Git 跟踪，覆盖本轮遗漏的实际输入。Gate 1 确认仍有效、旧 Gate 2 stale、Gate 3 pending。未改业务代码、未执行补测或最终同次 run。项目级检查仍未获替代口径。
- **PA-001 Gate 2 重审完成**：按用户确认原文「确认 PA-001 修订后的 Gate 2」执行 `stdd gate approve --gate 2 --reapprove --confirmed-by dialog`；CLI 核实修订版 Gate 2 有效，Gate 1 不变，Gate 3 仍 pending。该轮只登记重审，未执行补测或取证。
- **重审后长程续作**：补齐 SC-EWV-101 的 4 个缺失叶子，并让 RUN-201 同次执行 3 个既有生产 HTTP 拒绝回归，未改生产逻辑。`a9eb2552-7233-419a-b476-b9daf95053a6` 冻结 35 个已跟踪输入；五个 Go selection 为 32/20/8/45/10 pass，均 0 fail/skip，runner 均 `remaining=0`；CBE 50 pass、0 fail，原 Windows skip 保留。两个 Tools 变量同指 pin `7a0a2ab57f3f5e2c583c3523bc69d67e7be115c1`。6/6 CP；同 run 的 CLI 失败模式检查 9/9。已完成 C3–C7 记录、`EXP-2026-0012`、`design-adjustments.md`、`test-report.md`，PA-001 已解决。
- **项目级质量仍阻塞**：`pnpm test:scripts` 739/16/1；离线 `pnpm lint`、`pnpm typecheck` 均缺工作区依赖未能启动；`make test` 和 `scripts/check.sh` 不满足已授权的一次性数据库边界，未执行。未提交 Gate 3 确认，未改质量配置、接入现网、安装、提交、推送或部署。
- **项目级对照已执行**：按用户授权，离线同条件复跑脚本基线，和变更版 739/16/1 且失败、跳过名称一致；再按原五包清单，以 runner 各跑干净基线与当前 BUILD，两个实例均 `remaining=0`，临时 worktree 已清理。五包终结事件齐全，失败/跳过路径逐项一致，无新增红项，但两次均 exit 1。结果和本机证据目录见 `test-report.md`，不替代 6 CP 同次证据。原配置未覆盖项仍保留，Gate 3 待决定。
- **项目级隔离补验**：用户授权锁文件安装、项目 CI 一次性数据库及本机/Podman/WSL。D 盘 BUILD 副本冻结安装和 `pnpm typecheck` 通过；`pnpm lint` 在未改的 `@multica/views` 失败。用新建 Podman PostgreSQL/Redis、CI up/down 和原归属表跑 Windows 常规/agent `-race`，皆 exit 1，管理员库 3/3；临时库、角色及容器已清理。因 Go `1.27.4` 下载 TLS 超时，使用 Windows Go `1.27.1`，不能视为 Ubuntu CI；无同条件宽测基线。E2E `critical_only` 未列路径，未执行。记录见 `test-report.md`，C2 未完成，Gate 3 未发起；原 BUILD 补丁、锁文件和项目质量配置未变。
- **race 红项基线复核**：用户采纳「只对 Go race 失败项同环境复核，先列 E2E 候选」。Windows 干净 `0c47c67e7` 同工具、参数及 CI DB 复核 16 个常规红包 + `pkg/agent`，未重跑变更版或其余包。16 个红包、agent 红包均复现；常规 281 个失败路径事件相同，6 基线独有、18 变更版独有全在未改 `repocache`，两边均出现 Windows Job Object attach 被拒；117 skip 相同。两边同一 execenv panic 导致 324 个已开始用例无终结。agent 2185/382/190 和路径相同，两边 exit 1，无 race detector 警告。证据 `D:/multica-trim-quality.o41bVk/race-baseline.SEwxqW/`，临时 DB/Redis/checkout 已清理。E2E 无直接命中这次 API 的现成浏览器用例；报告列两个冒烟候选，当轮未跑。Gate 3 未发起。
- **运行历史 E2E 冒烟**：按用户授权只跑 `e2e/issue-task-history.spec.ts`。前两次临时 runner 自定义标识不符合夹具要求，止于登录和创建工作区；去掉覆盖后，未改变用例或业务代码，Playwright Chromium 1 pass/0 fail/0 skip、exit 0。CI 新建 DB/角色、Podman PG/后端和回环 Next.js 均清理，日志 `D:/multica-trim-quality.o41bVk/e2e-run-history.OUITtu/`。未跑评论路由、未跑 `scripts/check.sh` 或全套 E2E；不替代本次 API 同次证据。lint、race 仍红，Gate 3 不动。
- **剩余差异顺序复核**：隔离 Debian 12 Podman `Go 1.27.4` 上 `repocache -race` 基线和实际补丁均 149/0/0、路径一致，不覆盖 Windows 专属用例或全套 Ubuntu CI。Windows 干净基线冻结安装后 `pnpm lint` 逐条复现变更版 `@multica/views` 的 21 errors/21 warnings（路径、行列、诊断文本相同）。日志 `D:/multica-trim-quality.o41bVk/linux-quality.0oCecC/`，清理容器/基线 worktree。复核不消除原配置红项；不扩大本变更修复前端，不重跑定向 CP 或冒烟，Gate 3 pending。
- **Linux CI 后端全量对照**：用户要求长程连续完成，按项目 CI 命令在同 Debian 12、Go1.27.4、Node22.23.5 容器执行变更版及干净基线，专用 PG/Redis 内网并使用 CI up/down。两侧 106 包均结束、83 pass/11 fail/12 skip；测试事件基线 24248/278/35、变更 24241/282/35，277 失败事件相同、1 基线独有、5 变更独有，35 skip 一致。agent 均 3103/15/1 且路径一致；admin 3/3、对账通过；regular 与 regular-evidence 均 exit1。无 data race 报文；独有失败未经等价归因，原配置 quality.test/lint 仍未通过。两侧专用库、容器与内部网络已清理，日志分别 `D:/multica-trim-quality.o41bVk/linux-ci-baseline.14fSNs/` 和 `linux-ci.6qBBEV/`。未改业务/质量配置、未跑评论路由或全套 E2E；Gate3 pending。
