---
id: CR-2026-033-prd
type: PRD
cr-ref: CR-2026-033
title: tools Checkpoint 收敛：单一深原语 + latest-checkpoint + 多仓恢复（TCA-011）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-13T06:52:05+08:00
updated: 2026-08-13T06:52:05+08:00
---

# 1. 概述

当前 checkpoint 由 `push-progress` Skill 手写完整逐仓 Git 算法（worktree 遍历、`add -A`、diff、commit、push、`rev-parse`、逐仓失败处理），同一算法还被四个 Pipeline prompt 复制；`crctl checkpoint-add` 每次只 CAS 一次并追加单个 repo，没有 batch-id、manifest、journal 或 commit——第 N 仓写失败会留下同一轮的半记录，resume 无法区分"完整 checkpoint"与"半记录"；旧 `checkpoints[]` 无限追加，消费者取首条/末条结论不一；knowledge-base checkpoint 元数据天然"晚一轮"（先 push 分支再改 backlog，本轮元数据不进入刚推送的 remote HEAD），换机恢复只能看到上一轮记录；多仓 push 没有持久化恢复状态，通用"已发布"分类不足以证明 checkpoint freshness。这是 TCA-011 的未解决核心。

本 CR 按《tools-archive-checkpoint-test-traceability-optimization-plan.md》§12 交付分组 B（T03~T05）落地，覆盖 §4.2 CKP-01~07：

- **单一深原语**：新增幂等 `crctl checkpoint`（不新增 `checkpoint status`），`checkpointCr()` 独占全仓 Git、账本与恢复算法；成功/失败输出固定结构化字段（§5.1）。
- **单一当前快照**：`_backlog.yml` 中每 CR 只保留一个整块可原子替换的 `latest-checkpoint`，batch-id 内容寻址（排除 message/actor/时间）；首次成功时同批删除旧 `checkpoints[]` 与顶层 `remote-ref/last-push-*`。
- **敏感文件预检**：`add -A` 前按固定路径规则 + 私钥头内容规则拦截，命中整批零 commit/零 push。
- **多仓可恢复 saga 与 exact-head freshness**：durable journal 增加 `op=checkpoint` 逐仓记录；生成 metadata 前按 remote 与 source SHA 的精确关系分类；KB 用"本轮恢复 HEAD + metadata commit"解决晚一轮，`source-sha` 固定为 metadata commit 的直接父提交。
- **迁移与删除**：push-progress 收缩为一次调用；四条 Pipeline 的 checkpoint 节点只保留输入/跳过/输出/onFail；list-remote-checkpoints 与 resume reader 改读 `latest-checkpoint` 与 exact-head drift；删除 `checkpoint-add`。

**依赖与顺序**：复用 CR-2026-031 交付的 durable-tx/workspace-transactions 基础设施；按总路线图 A→B 顺序，需 CR-2026-032（Archive 小修）先行完成；本 CR 内部按 T03 → T04 → T05 顺序实施，T01（schema/错误码/fault point 红测）先行，每个 TASK 一个可回滚提交。本 CR 实施期自身在 T04 完成前仍使用旧 checkpoint 流程保存进度（与 CR-2026-031 自用旧流程同理），T04 起切换新入口。

# 2. 用户故事

- **US-01 换机/协作接续者**：希望在任意一台机器恢复 CR 时，看到与远端完全一致的最新进度（含本轮元数据），不再"晚一轮"。
- **US-02 同步意图发起者**：希望保存进度只有一条命令、一个语义，中断后重跑同一条命令自动续跑补齐，不重复提交、不留半 repo 投影。
- **US-03 Skill/Pipeline 作者**：希望只声明"调用一次 `crctl checkpoint`"，不再复制逐仓 Git 算法与恢复分类。
- **US-04 安全负责人**：希望 `.env`、私钥等敏感文件在任何 `add/commit/push` 之前被整批拦截，且没有绕过开关。
- **US-05 远端只读查询者**：希望远端列表如实标记任一仓的 drift（超前/分叉），不把"仍是祖先"当作 synced。

# 3. 功能需求

## FR-01 单一 checkpoint 深原语与输出契约

`crctl checkpoint <cr_id> [--message <text>] --workspace <ws>` 是唯一 checkpoint 写入入口；正常执行、中断续跑与幂等重放均调用同一命令。输入只含 CR 与人类可读 message；repo/branch/worktree/trunk/remote/batch-id/actor/时间全部内部派生。状态合法性守卫沿用 crctl 现有非终态语义，status 只读 `cr.md`。成功输出固定字段：`op/cr/txId/batchId/phase=complete/repositories[{repo,sourceSha,remoteRef,confirmed}]/metadataCommit/changed/recoverCommand`；失败输出 `txId/phase/sideEffects/recoverCommand`（零副作用错误可省 sideEffects）。不新增 `checkpoint status` 子命令，durable journal 不成为公共查询模型，只读查询继续由 `list-remote-checkpoints` 承担。checkpoint 只在 resolver 确认的当前 CR worktree 与 `requirement/{cr_id}` 分支运行，保留"保存全部未忽略变化"语义：每仓 commit 前纳入 tracked/untracked 的全部未忽略变化；不提供 `--files`、include/exclude glob、staged-only 或 checkpoint ignore 配置。

## FR-02 敏感文件与私钥预检（零副作用）

在 `add -A` 前，crctl 从 Git 状态取得本轮新增/修改的普通文件路径，先按 workspace-relative POSIX 路径执行固定规则，再只对命中文件检查私钥头；命中则在尚未修改 index 时返回 `CHECKPOINT_SENSITIVE_PATH`，整个 checkpoint 零 commit/零 push。固定路径规则：basename `.env`、`.env.*`（明确放行 `.env.example`、`.env.sample`、`.env.template`），basename `id_rsa|id_dsa|id_ecdsa|id_ed25519`，以及任意层级后缀 `.aws/credentials`、`.config/gcloud/application_default_credentials.json`、`.netrc`、`.pypirc`；路径比较按 Git 路径大小写精确语义，不做平台相关模糊匹配。内容规则仅匹配 `-----BEGIN ... PRIVATE KEY-----`。不拦截所有 `*.pem/*.key`，不识别通用 TOKEN/PASSWORD，不做熵扫描，不引入 gitleaks/trufflehog，不提供 `--allow-sensitive` 或例外配置。`.gitignore` 仍是项目特定临时文件与本地配置的第一道边界。

## FR-03 latest-checkpoint 单一当前快照与内容寻址 batch-id

`_backlog.yml` 每 CR 条目只保留一个可原子整块替换的当前快照：

```yaml
latest-checkpoint:
  batch-id: <sha256(cr-id + repository-graph-digest + 按 repo id 排序的 repo/source-sha/remote-ref) 前 16 位>
  repositories:
    - repo: <id>
      source-sha: <本轮内容 commit>
      remote-ref: refs/heads/requirement/<cr>
```

batch-id 是内容寻址标识，只由 cr-id、事务启动时的 repository graph digest、按 repo id 排序后的 `repo/source-sha/remote-ref` 组成，明确排除 message、actor、时间、本地路径与 journal txId；不持久化 `pushed-at/by/summary`（可从 metadata commit 推导）。每次整块替换、不追加，reader 只消费该映射；历史查询走 Git log，事务中间态只读 journal。首次成功执行新命令时，以本轮真实 repo source SHA 生成该映射，并在同一 metadata commit 删除旧 `checkpoints[]`、顶层 `remote-ref`、`last-push-at`、`last-push-by`；不迁移、不归组旧数据，不永久双读、不维护兼容投影，无 `CHECKPOINT_LEGACY_AMBIGUOUS` 迁移分支。

## FR-04 幂等 no-op 快速确认与 KB metadata commit

1. 创建任何 journal/source/metadata commit 前先执行 no-op 快速确认：读取现有 `latest-checkpoint`，fetch 全部参与仓，核对 graph digest、远端 freshness 与本地未忽略变化；全部未变时直接返回现有 checkpoint、`changed=false`，不创建 journal、不更新时间、不 push。
2. 相同 graph 与 source facts 重跑必须 `changed=false`，即使 message 不同也不得产生新 metadata commit；任一 repo source SHA 或参与仓图变化时才形成新 batch-id。
3. 有真实变化时：各 repo 先形成并确认本轮恢复 HEAD，有业务变化的仓创建 source commit、clean 仓沿用当前 HEAD；非 knowledge-base repo 先发布并精确确认 remote HEAD；knowledge-base 在自己的本轮恢复 HEAD 之上生成**只含 checkpoint 账本**的 metadata commit；最后发布 KB metadata commit。
4. `latest-checkpoint.repositories` 中 KB `source-sha` 固定为 metadata commit 的**直接父提交**，表示"本轮 metadata 创建前已确认的 KB 恢复 HEAD"，不要求一定是纯业务内容 commit；避免 commit 内容引用自身 SHA，也避免把上一轮 metadata HEAD 误当作新业务变化导致 `M1 → M2 → M3` 空转。

## FR-05 exact-head freshness 与可恢复 saga

durable journal 增加 `op=checkpoint`，逐仓记录 `prepared → committed-local → pushed → confirmed`，最后记录 `metadata-committed → metadata-pushed → complete`；重跑按 journal 补齐副作用，不做补偿 revert、不改写历史。不修改共享 `classifyRemoteCommit()` 对其他事务的既有语义；checkpoint 在生成 metadata 前使用 exact-head freshness 分类：

- remote == source SHA → confirmed；
- remote 是 source SHA 的祖先 → 本地 source 按当前 remote SHA 做 lease fast-forward publish，push 后必须再确认精确相等；
- source SHA 是 remote 的祖先且不相等 → `CHECKPOINT_REMOTE_ADVANCED`，不写 metadata，提示先走 `pull-progress` 后重新 checkpoint；
- 双方分叉 → `CHECKPOINT_REMOTE_DIVERGED`，不自动 merge、不 force；
- journal 已记录发布但 remote 不再包含 source → `CHECKPOINT_REMOTE_HISTORY_REWRITTEN`。

完整 checkpoint 的可见性点为 KB metadata commit 被 origin confirmed；在此之前其他 repo 的 source commit 只是"已发布资源"，不是完整批次。最终条件：非 KB repo 的 remote HEAD 精确等于 source SHA；KB 的 remote HEAD 精确等于 metadata commit，且记录的 source SHA 为其直接父提交——不得把"任意祖先"解释为当前完整状态。

## FR-06 Pipeline checkpoint 节点收敛

`requirement-authoring.pipeline.json` checkpoint 节点、`architecture-design.pipeline.json` checkpoint 节点、`code-implementation.pipeline.json` 的任务/代码/审批三个 checkpoint 节点、`resume-cr.pipeline.json` 远端比对节点，每个节点只保留输入、是否跳过、输出字段与 onFail：执行 push-progress（`cr_id`、message=阶段摘要），消费输出 `batchId/repositories/phase`，非 complete 按 Skill 失败语义中止。具体 Git 命令、账本字段和恢复分类只存在于 crctl/Skill，Pipeline prompt 不得出现。

## FR-07 push-progress 收缩与 list/resume reader 迁移

- `push-progress` Skill 收缩为一次 `crctl checkpoint {cr_id} [--message ...]` 调用与结果分类；删除手写的 worktree 遍历、`add -A`、diff、commit、push、`rev-parse` 与逐仓失败处理。
- `list-remote-checkpoints` Skill：状态只读 `cr.md`（删除"缺 status 时回退 backlog"的兼容承诺）；checkpoint 只读单个 `latest-checkpoint`；非 KB repo 要求 remote HEAD 与 source SHA 精确相等，KB 要求 remote HEAD 等于 metadata commit 且记录的 source SHA 是其直接父提交；任一仓远端超前或分叉均标记 drift，不把"仍是祖先"当作 synced。
- `resume-from-remote` 只消费 metadata-confirmed 的 `latest-checkpoint` 恢复，不读取旧 `checkpoints[]`。
- README 的 checkpoint 说明更新为"一次保存全部 active repo"的阶段说明与失败语义概览，不复制深原语算法。

## FR-08 旧入口删除与一次性切换

删除 `checkpoint-add` 的 dispatch、help、测试与文案（T05 完成后 `crctl` 不再暴露该命令）。reader 随命令切换一次性改读新字段，不永久双读；如存在过渡兼容代码，必须带删除条件与测试，不允许"先留着以后再说"。旧 checkpoint 历史仍可从 Git 查询。

## FR-09 测试先行与交付结构

- 冻结 `latest-checkpoint` schema、错误码与 fault point 后先写旧实现下失败的测试（T01 红测）；现有 253 个 crctl tests 与 10 个 writeback tests 绿基线不得靠放宽断言"假绿"。
- 实施顺序 T03（checkpoint journal 与 `latest-checkpoint` 整块编辑纯函数，durable-tx/workspace-transactions）→ T04（checkpoint 多仓 publish/recover，crctl 与 checkpoint tests）→ T05（Skill/Pipeline/README 迁移并删 checkpoint-add）；每个 TASK 一个可回滚提交，先测试、再实现、再删旧入口。
- 三 bare remote 测试矩阵覆盖：CR worktree/branch 不匹配与敏感路径命中在任何 `add/commit/push` 前零副作用失败；同一 `latest-checkpoint` 且 graph/remote/local 全未变的重跑在创建 journal 前 `changed=false`；全成功（含 clean repo）；第二仓 push 后 kill/restart；push 响应丢失；remote fast-forward lease publish 并最终精确相等；remote advanced；remote diverged；KB metadata commit/push 失败；同批重放零新 commit；CRLF backlog 与 Windows path。

# 4. 非功能需求

- **可靠性**：任一 rename/commit/push fault 后，要么零 authority 写入，要么返回 txId + 可执行 recoverCommand；重跑自动续跑，不静默当作成功。
- **原子性**：`latest-checkpoint` 整块替换走 recoverable write-set（读入 LF 规范化解析、before hash 按磁盘原字节、任一 schema/第三值/CAS 冲突零写）；敏感命中与 preflight 失败零 commit/零 push。
- **幂等性**：相同 graph 与 source facts 重跑 `changed=false`、零新 commit、零新 journal。
- **安全性**：固定敏感路径与私钥头预检在任何 index 修改前执行；不新增 secret scanner 依赖与绕过开关。
- **可审计性**：KB metadata commit 只含 checkpoint 账本；journal 记录全部副作用；commit trailer 支持 journal 丢失后的恢复判定。
- **兼容性**：关键 fault vectors 覆盖 Windows 与 Ubuntu；CRLF 规范化（解析用 `split(/\r?\n/)`、跨行解析失败硬失败）保证 Windows autocrlf 检出内容可稳定解析。
- **复杂度边界**：不新增 npm 依赖；不建通用 saga/phase runner、checkpoint 历史账本、status API、文件选择器；只有至少三个真实处理器出现同一非平凡重复或同一恢复缺陷需三处修复时，才允许从调用点向既有 `durable-tx.mjs` 提炼最小公共函数。

# 5. 验收标准

- **AC-01（FR-01）**：`crctl checkpoint` 成功输出包含 `op/cr/txId/batchId/phase=complete/repositories[].confirmed=true/metadataCommit/changed/recoverCommand` 全部固定字段；help 无 `checkpoint status` 入口。
- **AC-02（FR-02）**：预置 `.env` / `id_rsa` / 含 `-----BEGIN ... PRIVATE KEY-----` 头的文件后运行 checkpoint，返回 `CHECKPOINT_SENSITIVE_PATH`，三仓 index/commit/push 全部为零；`.env.example` 正常放行。
- **AC-03（FR-03）**：首次新 checkpoint 成功后，`_backlog.yml` 条目不含 `checkpoints[]`/`remote-ref`/`last-push-*`，`latest-checkpoint.batch-id` 等于规定内容寻址值；相同 facts 重跑 batch-id 不变，仅 message 不同也不变。
- **AC-04（FR-04）**：全仓未变的重跑在创建 journal 前返回 `changed=false`，journal 无新条目；有真实变化时 KB `source-sha` 等于 metadata commit 的直接父提交。
- **AC-05（FR-05）**：fault matrix 覆盖第二仓 push 后 kill/restart（重跑补齐且同批零新 commit）、push 响应丢失、`CHECKPOINT_REMOTE_ADVANCED`（零 metadata 写入）、`CHECKPOINT_REMOTE_DIVERGED`（不 merge/force）、`CHECKPOINT_REMOTE_HISTORY_REWRITTEN`（硬阻断）。
- **AC-06（FR-05）**：lease fast-forward 场景 push 后 remote HEAD 精确等于 source SHA；KB 场景 remote HEAD 等于 metadata commit 且 source SHA 为其直接父提交。
- **AC-07（FR-06）**：静态 contract/lint 检查证明四个 Pipeline 的 checkpoint 节点 prompt 不含任何 Git 命令与账本字段描述。
- **AC-08（FR-07）**：`list-remote-checkpoints` 对超前/分叉仓输出 drift；`cr.md` 缺 status 时不再回退 backlog；resume 只消费 `latest-checkpoint`。
- **AC-09（FR-08）**：T05 完成后 crctl/Skill/Pipeline/README 无 `checkpoint-add` 残留。
- **AC-10（FR-09）**：新增红测在旧实现下按预期红、现有 253+10 绿基线仍绿；Ubuntu/Windows CI 全绿；T03/T04/T05 各为可回滚提交。

# 6. 成功指标

- 任意时刻只有 metadata-confirmed 的单个 `latest-checkpoint` 被 resume/list 消费；不存在半 repo 投影、"元数据晚一轮"或账本内历史批次数组。
- active Pipeline/Skill 中逐仓 Git 算法复制为零；`crctl.mjs` 因删除 checkpoint-add 与旧兼容代码净缩短。
- 重跑成功率以真实 fault-injection matrix 衡量：所有承诺的零副作用、roll-forward、hard-block 场景均有可执行测试。
- 换机恢复端到端演示：一台机器 checkpoint 后，另一台机器 resume 得到与远端精确一致的最新进度。

# 7. 范围排除

- 不实施总路线图 T06~T16（test 原子记录、traceability/feedback、静态治理收尾属后续交付 CR C/D/E）。
- 不新增 `checkpoint status` 子命令、checkpoint 历史账本数组、文件选择器、include/exclude 配置与 `--allow-sensitive`。
- 不迁移、不归组旧 `checkpoints[]`；不建兼容投影、不永久双读。
- 失败不自动 merge、不 force push、不补偿 revert。
- 不引入数据库、消息队列、分布式锁、2PC、secret scanner 或任何新 npm 依赖；不建通用 saga/phase engine、provider、registry、plugin。
- 不把 durable journal 开放为公共查询模型。
