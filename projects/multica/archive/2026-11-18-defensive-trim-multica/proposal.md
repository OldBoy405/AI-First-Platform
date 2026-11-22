# Multica 防御性编程精简：授权一次准备、敏感动作锁一次、状态读一次、实跑取材只认固定提交

<!-- source_hash: bc510d344d53753f -->
<!-- generated_at: 2026-11-18T15:24:32.003249 -->
<!-- canonical: canonical/proposals/2026-11-18-defensive-trim-multica.yaml -->

## Why

2026-11-18 对 Multica 二开代码（仅带 AIFIRST 标记或在 CUSTOM-LEDGER.md 登记的 fork 代码）的只读审查，逐条对 HEAD `0c47c67e7` 核实，发现四处防御性编程问题：
(1) 授权签发与读取：请求先在 HTTP 入口补默认合同值，`BuildExecutionAuthorization` 内又补一次（`execution_authorization_http.go` 与 `execution_authorization.go`），
    身份、仓库与协调器选择还分别重扫请求；授权头读取端对已冻结原文重跑新请求解析器 `decodeExecutionRawRequest`、`parseExecutionScopeBody` 及仓库/协调器绑定校验，
    使“收紧申请填写规则”会连带作废历史批准；`validateExecutionContractFields` 只被测试调用，测试用它代替生产验证。
(2) 敏感动作结算：`ApplySensitiveActionTx` 在已持 CR 锁的事务内再发一次 `FOR UPDATE` 并重查决定，`decision == "reject"` 才返回的 `no_effect` 在持锁条件下不可达。
(3) 状态读取：GET 先读一次 `pipeline_run.status`，`progressOf` 又独立读一次，两次结果拼进同一响应，可能出现 `status: running` 与 `progress.state: completed`；
    存在但不是对象的 runner 详情被兜底为空 map，运行中分支报 `idle`，失败分支静默丢失错误码；`progressOf` 的 `default` 返回 `idle`；
    `MountPipelineRunProgressRoute` 只供测试调用。
(4) 实跑取材：`stack.mjs` 读 pin 后只做 `trim`，未复用 `parsePin`；`crctl-stage` 的 ref 接受 `HEAD`，使无效 pin 写成 `HEAD` 时静默走工作树 overlay；
    固定提交模式下 `assertPureAddition(headCrctl, headCrctl)` 自己比自己，`crctl` 还被写两次。


## What Changes

- 授权签发一次准备：入口一次产出补全后的确切字节与已解析字段，重放比较与首次签发共用该结果；`BuildExecutionAuthorization` 不再补第二次，
不再为身份、仓库、协调器选择分别重扫请求。首次签发仍从数据库确认工作区、项目、CR 和真实资源绑定；重放不重读当前仓库资源绑定，
但保留锁内由 CR 解析项目并与已签 payload 比对的作用域核对。合法输入的冻结及签名字节兼容性不变。

- 授权头读取不重审旧申请：当前授权头按存储协议核验签名、冻结原文摘要、头指针及作用域、适用合同与撤销关系，一次返回摘要及已验证 payload，
供激活、绑定、消费和敏感动作直接使用；冻结原文不再进入新请求解析器，也不由读取端逐字段重做签发。
无需重签或回写历史记录。删除只供测试调用的 `validateExecutionContractFields`，历史读取测试改走生产授权头入口。

- 敏感动作锁住一次：事务按现有顺序锁住 CR 及其指向的授权记录，在锁内核验当前授权，再完成动作/目标/环境匹配、操作查重、额度判断和回执写入，锁保留到提交；
额度结算依赖这笔事务已核验的授权，不再重取 CR 锁、重查决定；由授权入口拒绝撤销头，删除之后不可达的 `no_effect` 分支。

- 状态读取：已作工作区核对的那一行 `pipeline_run.status` 同时填 `status` 并选择 `progress` 分支（start/resume 尚无该状态时仍读一次），保留成员鉴权、跨工作区 404 和既有启动/恢复 POST 路由；
无持久化 runner 详情是正常情况，存在但不是对象的详情改为报错（覆盖运行中与失败两个分支）；`progressOf` 的 `default` 由返回 `idle` 改为报错；
错误交给现有进度错误出口（GET 返回读取失败；已提交的 start/resume 保留 `run_id`、`changed`、记录错误并省略 `progress`）。
生产继续使用叶子 GET，移除只供测试调用的 `MountPipelineRunProgressRoute`，测试改走 `NewRouterWithOptions`。

- 实跑取材：默认合同实跑读取 pin 时复用 `parsePin`，无效值（含 `HEAD`）在 pin 解析处直接报错，不得降级到可读工作树的模式；
固定提交模式按提交树物化文件一次，去掉自比的纯追加检查和第二次写入；只有明确选择现有工作树 overlay 模式时才读工作树并做纯追加检查。
保留现有实际 commit 与摘要输出，不另建 pin 格式、开关或取材框架。

- 契约与台账同步：只同步受影响的现行契约与验收（历史授权不再按新申请规则重审；其余保持现有契约不变）；按 `CUSTOM.md` 结构在 `CUSTOM-LEDGER.md` 登记每处 fork 代码改动，追溯真实流程的变更和任务标识，格式不接受该标识时停止并确认，不编造 CR 身份。


### Modified Capabilities

- **authorized-runner**：授权签发一次准备；历史授权读取只核验已签记录、不重审旧申请；敏感动作结算同事务锁一次，撤销与结算有确定顺序、同一操作重试不多扣。字面 null 拒绝已由在途 change 落实，不再重复。
- **execution-wait-visibility**：status 与 progress 对同一运行状态作答，损坏的等待详情不报 idle，读取失败走既有错误出口。
- **ci-backend-environment**：aifi45 实跑取材作为单一 tools pin 的消费者：声称验证固定提交时，实际使用的 Tools 文件只来自该提交；overlay 模式须明确选择。Phase 2 核实归属后可调整。

## Success Criteria

- [ ] 走真实签发 HTTP 入口：缺字段或 `""` 正常补齐，同一请求重放仍使用已冻结记录；格式合法但合同不同仍返回 `409 EXECUTION_CONTRACT_MISMATCH`；合法输入的冻结与签名字节与改动前一致。
- [ ] 构造签发后再收紧新请求规则的情形：历史批准仍可经授权头读取；已签记录的原文摘要不符被拒；作用域、验签、撤销既有回归保持通过。
- [ ] `BuildExecutionAuthorization` 内无第二次默认值补全；`validateExecutionContractFields` 已删除且无任何测试依赖它。
- [ ] 撤销先取得锁，后来的动作不扣额；动作先取得锁，结算后撤销才生效；有效授权下同一操作重试不多扣；授权未列出的动作不扣；`ApplySensitiveActionTx` 内无第二次 CR 锁与决定重查，无不可达 `no_effect` 分支。
- [ ] 同一 GET 响应不出现 `status: running` 与 `progress.state: completed`；无持久化详情的运行仍正常返回；存在非对象的 runner 详情时 GET 返回读取失败，start/resume 成功回执保留 run_id 与 changed 并省略 progress，二者都不呈现 idle；`progressOf` 的 default 不再返回 `idle`。
- [ ] 经 `NewRouterWithOptions` 的集成测试（请求越过鉴权）：Runner 关闭时不注册 GET；开启时成员 GET 可达且原有 POST 不被遮蔽；`MountPipelineRunProgressRoute` 已移除。
- [ ] 在临时 git 仓库调用真实 `stageCrctl`：pin 合法时，即使工作树 `crctl` 有改动，取材仍与固定提交一致；pin 写成 `HEAD` 或其他无效值时直接失败，不进入 overlay；明确选择的 overlay 模式沿用现有正例与非追加拒绝用例。
- [ ] 每处 fork 代码改动已按 `CUSTOM.md` 结构登记于 `CUSTOM-LEDGER.md`，使用真实的追溯标识；既有受影响测试按新语义更新后通过，被改写用例对应的保证各至少保留一个，未新增删除即无法解释的跳过。
