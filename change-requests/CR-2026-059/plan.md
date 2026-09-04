---
id: CR-2026-059-plan
type: PLAN
cr-ref: CR-2026-059
sdd-ref: "change-requests/CR-2026-059/sdd.md"
target-version: "0.32"
status: draft
created: 2026-09-04T16:35:00+08:00
updated: 2026-09-04T16:35:00+08:00
---

# 开发计划：Discussion 无 Issue 共享会话（CR-2026-059）

> 输入：`change-requests/CR-2026-059/prd.md`（已审批）+ `change-requests/CR-2026-059/sdd.md`（cycle 3 复评 PASS，2026-09-04 人工 `approve --stage tech-design` 已落盘）。
> 实施仓：multica（`../multica`，CR worktree 分支 `requirement/CR-2026-059`，证据基线 HEAD `be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d`）。KB 仓承载本计划与 TASK 卡。`../tools/` 零改动。
> 前置已核：三仓 `workspace inspect` 全部 `healthy / dirty=false`；status=`tech-design-reviewed`，`crctl next`=`write-dev-plan`。

## 1. 交付里程碑

| 阶段 | 内容 | 主责 TASK | 工时估算 |
|---|---|---|---|
| M0 迁移与数据层 | 481–490 迁移（含 down 全集、钩子登记）、sqlc 查询收窄与新增、CUSTOM.md 登记 | TASK-01 | 16h（2 人天） |
| M1 服务层 | Discussion ensure/发送/协办/投影/幂等/转投与 merge-forward 渲染 | TASK-02 | 24h（3 人天） |
| M2 处理层与实时 | handler kind 分流、错误码矩阵、幂等头、事件 kind 标注、跨节点断连、附件门禁 | TASK-03 | 20h（2.5 人天） |
| M3 前端 | schemas 硬降级、DiscussionPane session 身份化、作者展示、四语文案 | TASK-04 | 12h（1.5 人天） |
| M4 验证与评审 | `crctl test` 证据闭环（cmd-01..06）、review-dev-plan / review-code 评审环、人工审批 | 非交付 TASK（审计事实承载） | 8h（1 人天） |

交付 TASK 总工时 = **72h（9 人天）**（TASK-01 16h + TASK-02 24h + TASK-03 20h + TASK-04 12h，与 `tasks/_index.yml` 的 `totalEstimateHours` 一致）；M4 为流程性投入，不建交付 TASK（完成边界须在 `developing` 内，见 write-dev-tasks FR-10 纪律）。

## 2. 任务依赖图

```text
TASK-01 迁移与数据层
   └──▶ TASK-02 服务层（依赖 01 的迁移与 sqlc 查询）
          └──▶ TASK-03 处理层与实时（依赖 02 的服务函数 + 01 的查询/迁移）
                 └──▶ TASK-04 前端（依赖 03 定稿的 HTTP 契约与响应 schema）
```

- TASK-03 `depends-on: [CR-2026-059-TASK-01, CR-2026-059-TASK-02]`；TASK-04 `depends-on: [CR-2026-059-TASK-02, CR-2026-059-TASK-03]`（前端契约以 TASK-03 定稿的响应/错误码为准，作者字段契约产自 TASK-02 消费的 M486 列）。
- 无环；顺序符合产出/消费方向。

## 3. 资源与分工

- 开发 owner：Ray（`cr.md owners.development`）；测试 owner：Ray（`owners.test`）。评审由独立 `quality-reviewer-agent` 执行，作者不自评。
- 预计工时分配（交付 TASK 总 72h / 9 人天）：TASK-01 16h、TASK-02 24h、TASK-03 20h、TASK-04 12h。
- 关键纪律：multica 代码注释一律英文（其 CLAUDE.md 硬规则）；所有新迁移/新文件/挂钩点按当时结构登记 `CUSTOM.md`（编号顺延，TASK-01 负责）；`make sqlc` 生成文件不手改；状态推进只经 crctl，账本零手改。

## 4. 风险与回滚策略

| 风险 | 等级 | 缓解 | 回滚 |
|---|---|---|---|
| 迁移窗口破坏在线服务（481–490 十连迁移） | 高 | 每索引 `CONCURRENTLY`、一文件一条语句；483 先建新名再删旧（无无约束窗口）；487 建表不内联 PK；代码在 490 之后上线、kind 分流在 482 之后生效 | down 全集 490→481 逆序回滚（§4.9 表）；回滚窗口契约：代码先于 485/482.down 回滚；有损 down（482/486/487）注释写明损失，不静默吞错 |
| 幂等表并发收敛缺陷（FR-24） | 中 | PK 唯一索引 + `ON CONFLICT ON CONSTRAINT chat_idempotency_pkey DO NOTHING`；赢家回滚→输家可见（无死锁残留）；指纹稳定排序 | revert TASK-01/TASK-02 commit + 487–490 down |
| 跨节点断连控制不可达（AC-29） | 中 | user-scope 控制帧复用既有订阅拓扑（持有用户连接的节点必然消费 user 流）；deliverEnvelope 唯一新增分支；XADD 失败重试一次 + 请求级门禁兜底 | revert TASK-03 commit（Broadcaster 纯新增方法，既有四方法零 diff） |
| L2 配置校验最坏 30s LiveLoad 阻塞 PATCH | 低 | cache 快速路径优先；单次 PATCH 至多 1 次 LiveLoad round；owner/admin 低频 | 无需回滚；调参数即可 |
| 前端响应 schema 漂移白屏（NFR-8） | 低 | 独立 zod schema + 硬降级只读；`legacy_issue_id` 永不作可写身份 | revert TASK-04 commit |
| 移出竞态 TOCTOU（B-AUTH-2 关闭面） | 中 | `LockSubscriberWrites` 首锁 + 事务内成员复核；锁序固定 | revert TASK-02/TASK-03 commit（零数据面回滚） |

## 5. 验收与发布策略

- **发布前 checklist**：① 三仓 worktree healthy/clean；② `crctl test` 全绿且 `test-evidence/cmd-01..06.log` 与 §7 证据命令表全等；③ review-dev-plan PASS（canonical 落盘）；④ 人工 `approve --stage dev-start`；⑤ review-code PASS + test-report status=pass；⑥ 人工 `approve --stage code`；⑦ `CUSTOM.md` 已登记。
- **发布顺序**：迁移先行（481→490，`cmd/migrate up`），服务端代码在 490 之后上线；旧前端在服务端上线窗口内继续读 legacy Issue 只读流（`legacy_issue_id`），新前端与旧服务端并存时 schema 硬降级只读——kind 列天然隔离（482 落地但代码未上线期间不存在 `project_shared` 行）。
- **feature-flag**：不引入独立 flag；`chat_session.kind` 即开关，`project_shared` 行由新代码唯一创建。
- **估算总工时（交付 TASK）**：72h（9 人天），与 §3 及 `tasks/_index.yml` `totalEstimateHours` 一致。
- 证据命令执行经 `crctl test --plan`（cr-test-plan/v1），机器区 `commands` 顺序与 §7 证据命令表 1:1 对应，日志落 `test-evidence/cmd-NN.log`（cmd-05/06 前置 `pnpm install` 属实施期准备，不在证据命令内）。

## 6. 交付覆盖表（稳定表 1/2）与证据命令表（稳定表 2/2）

### 6.1 交付覆盖表

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 | §3.1 GET 重写 + §4.1 `EnsureProjectDiscussionSession`；`EnsureProjectDiscussionIssue` 解除调用；无其它 `origin_type='project_discussion'` 写入路径 | TASK-02（关联 TASK-03） | cmd-02 | revert TASK-02/TASK-03 commit |
| FR-2 | §2.2 M482 `kind` 列 + CHECK 枚举 + 存量默认 `private` | TASK-01 | cmd-01 | 482.down（有损注记） |
| FR-3 | §2.4 M485 部分唯一索引 + §4.1 advisory 收敛 | TASK-02（关联 TASK-01） | cmd-02 | 485.down（代码先回滚） |
| FR-4 | §3.1/§4.2 门禁一律成员资格；`creator_id` 仅审计列 | TASK-03（关联 TASK-02） | cmd-02 | revert TASK-03 commit |
| FR-5 | §2.3 M483/M484 谓词收窄 + `GetProjectChatSessionForCreator` 加 `kind='private'`（三调用点语义保持） | TASK-01（关联 TASK-03） | cmd-02 | 484.down→483.down 逆序 |
| FR-6 | §2.3 M483/M484（先建新名再删旧）+ §2.4 M485 | TASK-01 | cmd-01 | 484.down→483.down 逆序 |
| FR-7 | §2.1 M481 `agent_id` 可空 + FK `ON DELETE SET NULL`；NULL 贯穿查询盘点 | TASK-01 | cmd-01 | 481.down（先清 NULL 行） |
| FR-8 | §3.1 `base_*` 快照规则 + §4.4 L2 workspace ready-runtime 并集 authority | TASK-02（关联 TASK-03） | cmd-03 | revert TASK-02 commit |
| FR-9 | §3.2 kind 分流；复用 `ResolveChatConfig`/`ValidateResolvedChatConfig`/`LoadChatCatalogForConfig`；无 Coordinator 校验 = §4.4 L2 | TASK-03（关联 TASK-02） | cmd-03 | revert TASK-03 commit |
| FR-10 | §4.2 普通消息只写 `chat_message`（无 task/Issue/comment） | TASK-02 | cmd-02 | revert TASK-02 commit |
| FR-11 | §4.2/§4.3 触发判定 + `CreateChatTask(issue_id=NULL)` + 快照 + 两个 409 + invocation 403 复用 | TASK-02 | cmd-02 | revert TASK-02 commit |
| FR-12 | §4.2 `writeChatCompletionOutcome` 按 `task.ChatSessionID` 写回 + 作者列 | TASK-02 | cmd-02 | revert TASK-02 commit |
| FR-13 | §3.5 `message_ids` 路径 + `RouteDiscussionToTeamAgent` 触发源适配（内核 zero_diff） | TASK-02（关联 TASK-03） | cmd-02 | revert TASK-02/TASK-03 commit |
| FR-14 | 复用 CR-2026-056 草稿契约（五空上传、上传者门、168h sweeper 谓词不改） | TASK-03（关联 TASK-02） | cmd-02 | 复用既有，无新增回滚面 |
| FR-15 | §4.2 同事务绑定 `BindDraftAttachmentsToChatMessage` + 失败零残留 + 草稿保留重试 | TASK-02（关联 TASK-01） | cmd-02 | revert TASK-02 commit |
| FR-16 | §3.1 `legacy_issue_id` 只读查询；不双写、不删除、不补建 | TASK-02（关联 TASK-03） | cmd-02 | revert TASK-02 commit |
| FR-17 | §3.2/§3.4/§3.6 固定状态映射（404/409/200 只读）+ `LockChatSessionInWorkspace` 锁内复验 | TASK-03 | cmd-02 | revert TASK-03 commit |
| FR-18 | §3.1–§3.5 全部 error-code 落点 + `writeErrorCode`/`writeProjectChatSendError` 复用；legacy code 不动 | TASK-03 | cmd-02 | revert TASK-03 commit |
| FR-19 | 前端 schema 硬降级（session_id 缺失/空/非 UUID → 只读）+ discussion-pane session 身份 + `legacy_issue_id` 只读流 + 配置控件走 PATCH config + 四语 | TASK-04 | cmd-05；cmd-06 | revert TASK-04 commit |
| FR-20 | §3.7 `Event.ChatSessionKind` + §4.7 路由与移出退订 | TASK-03 | cmd-04 | revert TASK-03 commit |
| FR-21 | §2.1 M481 SQL（与 PRD 逐字一致）+ §4.9 编号/CONCURRENTLY/钩子登记/CUSTOM.md/英文注释 | TASK-01 | cmd-01 | 481–490 down 逆序 |
| FR-22 | §3.1–§3.4 八项闭合（精确状态 + code + 权限 + 幂等 + 副作用 + 观察点） | TASK-03（关联 TASK-02） | cmd-02 | revert TASK-03 commit |
| FR-23 | §3.5 修改契约闭合（互斥/空/重复/顺序/跨 session/权限/幂等） | TASK-03（关联 TASK-02） | cmd-02 | revert TASK-03 commit |
| FR-24 | §2.6 M487–490（建表/唯一索引/挂 PK/辅助索引）+ §4.6 收敛算法 + §3.4/§3.5 缺头/冲突错误 | TASK-02（关联 TASK-01/TASK-03） | cmd-02 | 487–490 down 逆序 + revert |
| FR-25 | §3.1/§3.2/§3.4 成员门禁 + §4.7 实时拒绝/退订 + §4.8 附件 404 + 草稿仅上传者 | TASK-03（关联 TASK-02） | cmd-02 | revert TASK-03 commit |
| FR-26 | §4.5 写权威/投影/读规则/竞态/归档/hard-delete 全表 | TASK-02（关联 TASK-03） | cmd-02 | revert TASK-02 commit |

### 6.2 证据命令表

> 与 `crctl test --plan`（cr-test-plan/v1）机器区 `commands` 1-based 下标全等，日志落 `test-evidence/cmd-NN.log`。`executable` 均直接 spawn（shell:false），无内建/管道。

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | multica | server | go | ["test", "./cmd/migrate/", "-count=1"] | 900 |
| cmd-02 | multica | server | go | ["test", "./internal/handler/", "./internal/service/", "-count=1"] | 1800 |
| cmd-03 | multica | server | go | ["test", "./internal/handler/", "./pkg/agent/", "-count=1"] | 1800 |
| cmd-04 | multica | server | go | ["test", "./internal/realtime/", "-count=1"] | 900 |
| cmd-05 | multica | packages/core | node | ["node_modules/vitest/vitest.mjs", "run", "api/schemas.test.ts"] | 1200 |
| cmd-06 | multica | packages/views | node | ["node_modules/vitest/vitest.mjs", "run", "locales/parity.test.ts"] | 1200 |

覆盖口径：cmd-01 = 迁移 up/down 往返与钩子登记完整性（AC-19，`TestEveryConcurrentUpBuildHasCleanup` 守护）；cmd-02 = Discussion/Private Ask/merge-forward 主路径、错误码矩阵、幂等、成员门禁与移出竞态（AC-1..8、11..16、20、22..28）；cmd-03 = 配置 authority 阶梯 PATCH/入队臂（AC-9/10/21）；cmd-04 = 实时路由、控制帧与跨节点断连（AC-29）；cmd-05 = 前端 schema 硬降级向量（AC-17）；cmd-06 = 四语文案 parity（AC-18/NFR-2）。

## 7. AC/业务闭环覆盖矩阵

> 关键 AC（影响主路径验收可达性）每行唯一 TASK owner，验收证据为稳定 `cmd-NN`。

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 打开不建 Issue | §3.1/§4.1 | TASK-02 | cmd-02 |
| AC-2 四类操作零工作 Issue | §4.2/§4.5 | TASK-02 | cmd-02 |
| AC-3 普通消息零 task | §4.2 | TASK-02 | cmd-02 |
| AC-4 协办 task 参数 | §4.2/§4.3 | TASK-02 | cmd-02 |
| AC-5 回复写回同 session | §4.2 | TASK-02 | cmd-02 |
| AC-6 成员互见 + Private Ask 隔离 + 作者气泡 | §4.2/§3.6/§3.2/§2.5/§3.3 | TASK-03 | cmd-02 |
| AC-7 旧 Issue 只读回放 | §3.1 | TASK-02 | cmd-02 |
| AC-8 并发收敛 + Private 并存 | §2.3/§2.4/§4.1 | TASK-02 | cmd-02 |
| AC-9 非 owner 403 + 不调 UpdateAgent | §3.2/§4.4 | TASK-03 | cmd-03 |
| AC-10 非法配置 PATCH/入队 400 | §4.4/§4.2 | TASK-03 | cmd-03 |
| AC-11 未绑定 Coordinator 409 | §4.3/§4.2 | TASK-02 | cmd-02 |
| AC-12 草稿仅上传者可见 | §4.8 | TASK-03 | cmd-02 |
| AC-13 发送成功原子绑定 | §4.2 | TASK-02 | cmd-02 |
| AC-14 无 Coordinator GET/发送 + 解绑回空 | §2.1/§4.1/§4.5 | TASK-02 | cmd-02 |
| AC-15 merge-forward 仅 message_ids 201 | §3.5 | TASK-03 | cmd-02 |
| AC-16 转投内核 zero_diff | §3.5 | TASK-02 | cmd-02 |
| AC-17 前端 schema 硬降级 | 前端 schema（schemas.test.ts） | TASK-04 | cmd-05 |
| AC-18 pane 不依赖可写 issue_id + 四语 | discussion-pane + locales | TASK-04 | cmd-06 |
| AC-19 迁移 up/down 往返 + CONCURRENTLY + 钩子 | §2.1–§2.6/§4.9 | TASK-01 | cmd-01 |
| AC-20 归档/错 kind/非成员状态映射 | §3.2/§3.4/§3.3 | TASK-03 | cmd-02 |
| AC-21 配置校验单一实现 | §3.2/§4.2/§4.4 | TASK-02 | cmd-03 |
| AC-22 Team Agent/Private Ask 零回归 | §3.6 + NFR-6/7 | TASK-03 | cmd-02 |
| AC-23 shared 消息列表分页对象 | §3.3 | TASK-03 | cmd-02 |
| AC-24 POST 输入校验 400/201 | §3.4 | TASK-03 | cmd-02 |
| AC-25 merge-forward 互斥/跨源/去重 | §3.5 | TASK-03 | cmd-02 |
| AC-26 幂等重放/冲突/并发单提交 | §2.6/§4.6 | TASK-02 | cmd-02 |
| AC-27 message_ids 幂等 + legacy 无头 201 | §3.5 | TASK-03 | cmd-02 |
| AC-28 非成员/移出即时失效 + 竞态零残留 | §3.1/§3.2/§3.4/§4.8/§4.2 | TASK-03 | cmd-02 |
| AC-29 移出退订 + 双节点断连 | §4.7 | TASK-03 | cmd-04 |
| AC-30 首绑/替换/解绑投影 | §4.5 | TASK-02 | cmd-02 |
| AC-31 归档后 409 unavailable | §4.5/§4.3 | TASK-02 | cmd-02 |
| AC-32 hard-delete 保留 + 回放 + 409 | §2.1/§4.5/§4.3 | TASK-02 | cmd-02 |
