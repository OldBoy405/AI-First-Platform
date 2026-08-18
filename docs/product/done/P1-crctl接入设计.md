# P1 设计 — crctl 接入：同步协议 · 签名审批 · controlled-shell 下沉

> 前置：[《P0-数据模型映射表.md》](P0-数据模型映射表.md)已定权威域（git 权威 / PG 投影）与五张新表。
> 代码锚点均已核对：Multica `server/internal/daemon/`、`cmd/server/router.go` 的 `/api/daemon/*` 端点族、
> tools `skills/shared/crctl/scripts/crctl.mjs`（TTY 检查 :652，`via` 校验 :453/:783）、`gates.json#approvalStages`。
> 日期：2026-07-28。修订：2026-07-29 —— 增补 §C.5 AI 行为审计与交付项 D6（理念对比改进 S5）。
> 修订：2026-08-07 —— 对照已落地代码核实，追认三处落地形态：§A.5 embedded 补全用 `pending:` 占位符（非空 SHA 延迟处理）；§B 真人校验现状为局部守卫，将统一到 `RequireHumanActor` 中间件；§C.3/C.4 两处防御层降级声明（Layer 1 暂缓、callers 仅审计）。

---

## A. 同步 worker 协议：CR 事件从 git 到投影表

### A.1 设计原则

- **crctl 保持零依赖、可离线**：不让 crctl 直连服务器 HTTP。crctl 只写本地文件，网络交给 daemon。
- **结构化优先，commit 解析兜底**：crctl 自己最清楚发生了什么（from/to/trigger 都在手上），让它直接产出结构化事件；解析 `[cr] ` commit message 只做兜底通道（覆盖"没装新版 crctl / 人工 git 操作 / 平台模式编排器直接 commit"三种旁路）。
- **at-least-once + 幂等**：投影表靠 `UNIQUE(cr_id, commit_sha, event_kind)` 去重，事件可重放。
- **三层防漏**：outbox（主）→ commit 扫描（兜底）→ reconcile 对账（安全网）。

### A.2 通道一（主）：crctl outbox

crctl 新增行为（改动集中在 `casWrite` 收尾处，约 60 行）：`advance`、`approve`（含 §B 的 grant 模式）、`git push` 成功后，向 workspace 根的 **`.crctl/outbox/`** 原子写入一个事件文件（先写临时名再 rename，防半写）：

```
.crctl/outbox/{utc-ts}-{cr_id}-{event_kind}-{short_sha}.json
```

```json
{
  "v": 1,
  "event_kind": "status",              // status | owners | checkpoint | merge | archive | inbox
  "cr_id": "CR-2026-001",
  "from_status": "requirement-reviewing",
  "to_status": "requirement-approved",
  "trigger": "approve-requirement",
  "commit_sha": "a1b2c3d…",            // 携带该变更的 knowledge-base commit（--embedded 时为空，见 A.5）
  "actor": "alice",                     // crctl --caller 自报，仅记录不作信任依据
  "evidence": {                         // review/approve 类事件附带，供 §B 与投影 review_summary
    "review-annotations/requirement.yml": "sha256:…",
    "test-report.md": "sha256:…"
  },
  "payload": { "…": "事件特有字段：checkpoints[] / merge-commits[] / notify-log 条目等" },
  "occurred_at": "2026-07-28T15:04:05+08:00"
}
```

`.crctl/` 已有 `audit.log` 且自动生成 `.gitignore`——outbox 同样不入 git。

### A.3 daemon 的采集与上报

Multica daemon 新增一个 **CR 事件收集器**（`internal/daemon/crevents.go`，挂进现有 daemon 主循环，与 heartbeat 同周期驱动）：

1. **outbox 扫描**：对每个已知 CR worktree（daemon 本来就管理 `.rayai-worktrees/`）与主 workspace，扫 `.crctl/outbox/*.json`，按文件名排序读取。
2. **commit 扫描（兜底）**：对 knowledge-base worktree 维护游标 `.crctl/.scan-cursor`（上次扫描到的 SHA），`git log {cursor}..HEAD --format=%H%x00%s` 增量拉取，正则匹配四类前缀并还原为事件：
   - `^\[cr\] status (CR-\S+) (\S+) -> (\S+)$` → `status` 事件（该格式已被 tools 的 CI workflow 正则依赖，是稳定契约）
   - `^\[cr\] merge metadata (CR-\S+)` → `merge` 事件（payload 从该 commit 的 `_backlog.yml` diff 读 merge-commits）
   - `^\[cr\] archive (CR-\S+)` → `archive` 事件
   - `^\[cr\] inbox-emit (CR-\S+) event=(\S+)` → `inbox` 事件
   与 outbox 事件按 `(cr_id, commit_sha, event_kind)` 合并去重——两条通道产出同一事件是常态，不是错误。
3. **批量上报**：`POST /api/daemon/cr-events`（新端点，挂在既有 DaemonAuth 组，`mdt_` 令牌）：

```
POST /api/daemon/cr-events
{ "workspace_root_hash": "…", "events": [ …最多 100 条… ] }
→ 200 { "accepted": ["<文件名>", …], "rejected": [{"file": "…", "code": "BAD_EVENT"}] }
```

4. **确认删除**：仅对 `accepted` 的 outbox 文件执行删除；`rejected` 保留并告警（不无限重试坏事件：三次后移入 `.crctl/outbox/dead/`）。网络失败整批保留，指数退避重试——**离线可积压，上线即补传**。

### A.4 服务端 worker 的消费

`internal/service/crsync.go`（新）：

1. 入库 `cr_sync_event`（幂等键冲突 = 已处理，静默跳过）。
2. **有序化处理**：按 `cr_id` 分组串行消费（Go 侧 per-CR 互斥即可，无需分布式锁——单服务节点起步；多节点时用 PG advisory lock `hashtext(cr_id)`）。
3. 应用规则：`to_status` 相对当前投影是**合法转移**（对照 `dir-graph.yaml#state_machine` 的 23 条转移表，服务端持有一份只读副本）→ 更新 `cr` 行 + `issue.metadata.cr_status_bucket` + 按 §4.1 映射更新壳 Issue 的 7 态；**非法转移**（乱序到达/漏事件）→ 该 CR 标记 `needs_reconcile`，不强行应用。
4. 广播：复用 Multica 的 `events.Bus` → WS Hub，作用域 `workspace:{id}`（看板刷新）+ `issue:{id}`（详情页）。
5. `inbox` 事件 → 建 `inbox_item`（P0 已定：不回写 git 的 `handled` 位，P2 再议）。

### A.5 两个边界情况

- **`--embedded` 模式无独立 commit**：`merge-feature-branch` / `cr-archive` 用 `commit_mode=embedded` 把状态与业务变更同 commit 发布。落地形态（2026-08-07 核实，CR-2026-003 FR-1）：此时 outbox 事件的 `commit_sha` 写 **`pending:` 占位符**（而非空串，避免幂等键冲突），服务端将其降级为空指针不投影，由后续 `crctl git push` 的 checkpoint 事件（`rev-parse HEAD` 已在手上）追上补全；**非**设计初稿的「空 SHA + 延迟 60s」方案。
- **reconcile 对账**：定时任务（复用 `sys_cron_executions` DB 调度器）对每个非终态 CR 比较 `cr.projected_commit` 与 origin HEAD。**前提是服务端有 knowledge-base origin 的只读凭据**（企业内网 GitLab/Gitea，合理假设）；若无法配置，降级为 daemon 侧全量快照上报（daemon 定时跑 `crctl status --json` 全量上传）——两种模式二选一，部署时定，`REMOTE_RECONCILE_MODE=server|daemon`。

---

## B. 签名审批：替代 TTY，强度不降级

### B.1 端到端流程

```
① review 节点完成
   crctl outbox 事件携带 evidence sha256 → 投影表 review_summary + evidence digests
② 审批人在 Web/桌面端打开审批卡片
   服务端渲染证据摘要（verdict/blockers/test-report.status + digest 指纹）
③ 点击 批准/驳回
   服务端校验：RequireHumanActor（mat_ 任务令牌 403）
            + evidence_digest == 该 CR 最新事件的 digest（证据未漂移）
            + 审批人 ∈ cr.owners 对应角色 或 具备审批角色（策略可配）
   → 写 approval_record + Ed25519 签名 → 生成 grant 文件
   （2026-08-07 落地形态注：真人校验当前为 approval.go 内局部守卫，仅拒 mat_；
   已定案统一到 handler.RequireHumanActor 中间件（兼拒 mcn_ cloud_pat），
   局部守卫保留其独有的 X-User-ID 非空检查）
④ grant 下发
   pipeline runner 把 grant 作为任务上下文交给 daemon（或 daemon 轮询
   GET /api/daemon/approvals/pending?workspace=…）落盘到 CR worktree：
   .crctl/grants/{cr_id}-{stage}.grant.json
⑤ daemon 调 crctl approve --grant .crctl/grants/….grant.json（非 TTY 放行）
   crctl 验签 + 本地重算 evidence digest 比对 → 写 approval.yml → 级联 advance
⑥ advance 产生 [cr] status commit → 回到 §A 通道 → 投影更新 → UI 关闭审批卡片
```

驳回路径：不写 `approval.yml`；grant 的 `decision: reject` 让 runner 走状态机**既有的显式回退转移**（如 `approve-code:reject -> implement-code`），并把 `reject_reason` 作为 `review_feedback` 注入修复节点。

### B.2 grant 文件与签名格式

```json
{
  "v": 1,
  "cr_id": "CR-2026-001",
  "stage": "code",                          // gates.json#approvalStages 的四个键
  "decision": "approve",
  "approver": "alice@corp",
  "approved_at": "2026-07-28T16:00:00+08:00",
  "evidence_digest": "sha256:9f2c…",         // 对 approvalStages[stage].evidence 全部文件的
                                             // sha256 按路径字典序拼接后再 sha256（canonical digest）
  "key_id": "approval-2026a",
  "signature": "base64(ed25519.sign(canonical))"
}
// canonical = "v1|{cr_id}|{stage}|{decision}|{approver}|{approved_at}|{evidence_digest}"
```

- **Ed25519**：Node ≥18 的 `crypto.verify('ed25519', …)` 原生支持，crctl 保持零依赖。
- **公钥分发**：`{workspace}/.crctl/keys/{key_id}.pub` **提交进 knowledge-base 仓库**（公钥可公开；进 git 意味着换钥有审计痕迹）。轮换 = 加新文件 + 服务端换 `key_id`，旧 grant 仍可验。
- **防重放**：签名绑定 `cr_id + stage + evidence_digest`——同一 grant 重复使用只会幂等重写同一审批段；挪到别的 CR/阶段/证据版本一律验签失败。
- **摘要算法两轨统一**：`evidence_digest` 的计算方式（对 `approvalStages[stage].evidence` 声明的全部文件、按路径字典序逐个 sha256 后拼接再 sha256）是**唯一实现**，TTY 审批路径（§B.3）复用同一份代码，不得各自维护一套哈希逻辑——这是下面"两轨漂移检测统一"的前提。

### B.3 crctl 侧改造点（含 TTY 路径的 EVIDENCE_DRIFT 补齐）

现状里有一个此前未标注的缺口：`cmdApprove`（:664–673, 707）在有 `passCondition` 时会算一次证据哈希（`sha256(单个 $default 文件).slice(0,16)`）写进 `evidence-sha256-16`，但**没有任何代码再读它**——审批之后改动证据文件，`crctl status`/`validate` 不会发现。这不是"设计未做"，是"当年就没设计"，需要一并补上，而不是只给新的 `server-approve` 路径加检测、放着 TTY 路径不管（两条路径此后长期并存，TTY 仍是默认路径，只给新路径加检测覆盖率没有实质提升）。

| 位置 | 现状 | 改为 |
|---|---|---|
| `cmdApprove`（:647–652，TTY 分支） | 无条件 `!isTTY → APPROVAL_REQUIRES_HUMAN`；有 `passCondition` 时算单文件 16 位短哈希存 `evidence-sha256-16`，此后无人读取 | 改用 §B.2 的**规范摘要算法**（对 `stageCfg.evidence` 全部文件，非仅 `$default`），存入统一字段 `evidence-digest`（废弃 `evidence-sha256-16`，历史 approval.yml 中的旧字段名视为"无摘要"而非报错，向后兼容）。`--grant` 分支不变：验签失败或 digest 不符 → `EVIDENCE_DRIFT` |
| gate 校验（:447–454） | `section.via === 'crctl-approve'` 才承认，不比对任何哈希 | 不论 `via` 是 `crctl-approve` 还是 `server-approve`，**只要 `section['evidence-digest']` 存在就重算 `stageCfg.evidence` 当前摘要并比对**，不符 → `EVIDENCE_DRIFT`（不阻塞已通过的 CR 继续走，但记为治理事件，见下）。签名重验证（`验签通过`）仍只对 `server-approve` 生效——两件事分开判断：**摘要漂移**（两轨都测）与**签名有效性**（仅新轨） |
| `validate`（:783） | 同上单一 via 检查 | 同步扩展：两轨统一摘要比对 + server-approve 额外验签；CI 模板 `cr-guard.template.yml` 自动获得远端复核能力 |

`gates.json` 无需改动——`approvalStages[stage].evidence` 已声明证据文件清单，digest 计算直接复用该声明。

### B.4 EVIDENCE_DRIFT 留证（P3 看板的前置依赖）

检测到漂移只在 CLI 输出里报一次错误码，P3 §1.2 的治理板块无法据此计数——"检测"和"看板能看见"是两回事，中间缺一次持久化。补法沿用 §C.5 的模式（零新增探针，复用既有回调通道）：gate/validate 检测到 `EVIDENCE_DRIFT` 时，daemon 侧记录一条 `{cr_id, stage, expected_digest, actual_digest, detected_at}`（**不含证据文件内容**），随任务回调族上报，落 Multica 现成的 `activity_log` 表（新增一个 action 枚举值）。P3 治理板块的"EVIDENCE_DRIFT"计数直接查这张表——**这一步不上线，P3 那格指标永远是 0，且看起来像"从未漂移过"而不是"从未测过"，二者必须能区分，指标上线前必须先接这条留证链路**。

### B.5 私钥存储与保护（服务端）

Ed25519 私钥是整条签名链路的信任锚，公钥进 git 已有方案，私钥这侧此前缺设计，补齐如下。

**存储位置：** 私钥**不得以明文存入 `config.yaml` 或环境变量文件**。两种可接受方案按部署规模选一：

| 方案 | 适用场景 | 实现 |
|---|---|---|
| **A. 文件系统 + 0400 权限**（轻量，内网自托管首选） | 单机或小团队，无密钥管理基础设施 | 私钥文件放 `{server_data_dir}/keys/{key_id}.priv`，权限 0400，属主=server 进程 uid；server 启动时读入内存，之后不再读磁盘；`server_data_dir` 本身权限 0700，不进 git，不进 backup 明文目录 |
| **B. 环境变量注入（base64）**（容器化部署） | Docker / Kubernetes | 私钥 base64 后以 `APPROVAL_SIGNING_KEY` 传入，由 orchestrator（K8s Secret / Docker Secret）管理，server 启动时解码、内存驻留；**禁止打印到日志**（启动时只 log `key_id`，不 log 密钥内容） |

**访问收口：** 签名操作**只在一处发生**——`server/internal/handler`（或独立 `service/approval.go`）中响应"批准"HTTP 请求的那条路径。私钥变量不跨包传递；签名函数接受 `canonical string → []byte`，不暴露私钥对象本身。

**轮换流程：**
1. 生成新密钥对：`openssl genpkey -algorithm ed25519 -out new.priv`
2. 公钥推进 knowledge-base 仓库（新文件名 `key_id` 递增，如 `approval-2026b.pub`）
3. 服务端切换到新私钥（重启或热加载），同时更新 `key_id` 配置
4. 旧 grant（带旧 `key_id`）仍可验——crctl 按 `key_id` 找对应 `.pub`，多版本公钥共存天然支持平滑过渡
5. 旧私钥文件立即销毁（`shred` 或等效操作）

**最小化泄露半径：**
- 私钥仅对 server 进程可读（`chown server:server` + `chmod 0400`）
- server 进程以最小权限 uid 运行（非 root）
- 如有密钥管理服务（Vault / AWS Secrets Manager）则优先使用，私钥不落磁盘
- 启动时校验私钥与对应公钥能互相验签（`crypto.sign` + `crypto.verify` 一次 smoke test），不匹配立即拒绝启动而非运行时报错

**与 TTY 路径的风险对比（诚实说明）：**

| 维度 | TTY 审批（现状） | grant 签名审批（本设计） |
|---|---|---|
| 伪造审批的前提 | 物理/SSH 访问审批人终端 | 绕过 server 人类身份校验 **或** 获取签名私钥 |
| AI 自批风险 | 结构性不可能（无 TTY） | 由 server 侧 `RequireHumanActor`（拒绝 `mat_` 令牌）阻断 |
| 私钥泄露影响 | 不适用 | 攻击者可签发任意 grant，直到轮换 |
| 证据漂移检测 | 无（只在批准时记一次哈希） | gate 每次校验时重算（比 TTY 版更强） |

私钥泄露是该机制新引入的唯一结构性风险，上述措施是对应的控制层。**实施前检查清单：** ① 私钥存储方案选型落地；② `service/approval.go` 审批路径单元测试（含 mat_ 令牌 403、证据漂移 409、验签失败 403 三个拒绝路径）；③ crctl 补测试（`--grant` 验签通过/失败/evidence_digest 不符三用例）——这三项与 D4 验收并列，缺任一项不得上线。

### B.6 诚实边界（继承并明示）

签名解决"**是不是真人、批的是不是这版证据**"；不解决"人是否认真看了"。与 tools 原设计的边界声明保持一致，产品文案不得夸大。

---

## C. controlled-shell 白名单下沉 daemon execenv

### C.1 威胁模型先说清楚

daemon 以用户身份跑在用户机器上——**机器主人本来就能做任何事，防的不是用户，是模型**（漂移、误操作、prompt 注入后的越权）。因此目标是"模型拿不到裸 git/裸 shell 的默认路径"，而非内核级沙箱。这与 tools 的诚实边界一脉相承（hooks 是尽力而为的拦截）。但下沉到 execenv 后有一个实质提升：**拦截从"IDE 善意配合"变成"执行环境的默认形态"**，Agent 进程是 daemon 的子进程，PATH/配置/hooks 全部由 execenv 铸造。

### C.2 规则单一事实源：`controlled-shell.rules.json`

现状问题：白名单以文字表格写在 `controlled-shell/SKILL.md`，crctl.mjs 里硬编码了一份三元组（:327–347），两处已经漂移（SKILL.md 自称 15 条，实际 19 条）。P1 把规则抽成数据文件，放 `skills/shared/controlled-shell/rules.json`：

```json
{
  "v": 1,
  "git": [
    { "sub": "worktree", "shapes": ["^add -b \\S+ (--track )?\\S+", "^remove ", "^list$"], "callers": ["*"] },
    { "sub": "commit",   "shapes": ["^-m (wip: |\\[cr\\] |merge\\()"],                    "callers": ["*"] },
    { "sub": "push",     "shapes": ["^-u origin \\S+$", "^origin \\S+$", "^origin --delete \\S+$"], "callers": ["*"] }
    // …其余 16 条从 crctl.mjs 现有表机械迁移
  ],
  "forbiddenFlags": ["-c", "-C", "--exec", "--upload-pack", "--receive-pack", "--config-env"],
  "protectedPaths": {
    "deny": ["change-requests/_backlog.yml", "change-requests/_history.yml",
             "change-requests/*/cr.md", "change-requests/*/approval.yml",
             "change-requests/*/review-loop.yml", "change-requests/*/review-annotations/*"],
    "ask":  ["specs/**", "delivery/**", "change-requests/*/test-report.md"]
  }
}
```

三个消费方读同一份文件：**crctl.mjs**（删掉硬编码表，改为加载 rules.json）、**Go `pkg/gitguard`**（见下）、**Claude Code hooks**（pretooluse-guard 改读此文件）。SKILL.md 降级为对该文件的解说。

### C.3 Go 侧实现：`pkg/gitguard` + execenv 三处改造

**新包 `server/pkg/gitguard`**（crctl 三元白名单的 Go 移植，~300 行）：`Check(sub string, args []string, caller string) error` + `Run(...)` 用 `exec.Command`（Go 天然不经 shell，与 crctl 的 `spawnSync(shell:false)` 等价）。错误码沿用 `FORBIDDEN_SUBCOMMAND / FORBIDDEN_FLAG / SHELL_UNAVAILABLE`。

**execenv 改造点**（对照现有文件）：

| 文件 | 改动 |
|---|---|
| `execenv/execenv.go` | 每任务工作目录铸造时：① 创建 `{workdir}/.bin/git` **shim**（脚本一行：`exec {daemon自带的gitguard二进制} git "$@" --caller={agent_id}`）；② Agent 子进程 env 的 `PATH` 前插 `{workdir}/.bin`；③ 传入 `CRCTL_WORKSPACE` 指向 workspace 根 |
| `execenv/git.go` | daemon 自身的 worktree 操作（`setupGitWorktree`/`removeGitWorktree` 等 10 个函数）改走 `gitguard.Run`——daemon 自己也守白名单，caller=`system-orchestrator`（与 matrix 中 21 个基础 Skill 收归 orchestrator 的设计对齐） |
| `execenv/runtime_config_sections.go` | 生成 Agent 上下文时追加一节：「git 一律用 `git`（已是受控网关）或 `crctl git`；商店在 `protectedPaths` 的文件禁止直改」——把行为约束写进模型能看到的地方 |
| `execenv/crguard_config.go`（新，仿 `openclaw_config.go` 模式） | 对 **Claude Code** 后端：向 per-task 的 `.claude/settings.json` 物化 tools 现成的 PreToolUse hooks（`pretooluse-guard.mjs` + `inject-cr-status.mjs`，路径指向 tools 包安装位置）——原来要人工装的适配器变成 execenv 自动铸造；对 **Codex/Cursor** 等无 hook 后端：仅靠 PATH shim + 上下文注入 |
| `pkg/agent` 各后端 | `permission.bash: deny` 的 Agent（tools 九个全是）：Claude 后端追加 `--disallowedTools Bash` 类旗标（`ExecOptions.ExtraArgs` 通道已存在，claude/codex 后端已消费该字段）；不支持工具禁用的后端退化为 shim + hooks。**（2026-08-07 落地形态：本行暂缓未接线）** 原因是执行时拿不到「该 Agent 是否 permission.bash: deny」的可信数据源。解铃路径已明确：`aifirst/agent-import.mjs` 导入时已解析 frontmatter 的 `permission.bash`，将该字段落进 agent 表（或 metadata）后 execenv 铸造时即有判定依据 |

### C.4 防御层次总结（改造后）

| 层 | 机制 | 强度 |
|---|---|---|
| 1. 工具禁用 | `--disallowedTools Bash`（支持的后端） | 模型无法发起 shell 调用。**落地形态（2026-08-07）：暂缓未接线**（无可信数据源，解铃路径见 §C.3）；本层缺席期间由 2–5 层兜底 |
| 2. PATH shim | `{workdir}/.bin/git` → gitguard | 拦默认路径；绝对路径 `/usr/bin/git` 可绕过（诚实声明）。**落地形态（2026-08-07）：rules.json 的 callers 三元维度仅审计不校验**，实际为二元白名单（sub + shapes）；拦截收益低、误伤面高，除非治理板块显示跨 Agent 越权调用，否则不开 |
| 3. IDE hooks | Claude Code PreToolUse（execenv 自动铸造） | 拦 Write/Edit 直改受控文件 + 裸 git |
| 4. crctl CAS + gate | 权威文件唯一合法写入路径 | 绕过前三层也改不动权威状态（改了 CAS 冲突/gate 拒绝） |
| 5. CI 远端复核 | cr-guard workflow（required check） | 本地怎么漂都进不了 trunk |

第 2 层的绕过可能性明写进文档——与其假装是沙箱，不如让第 4/5 层兜底的事实清晰可见。

### C.5 AI 行为审计（2026-07-29 增补，S5）

五类质量门（文档/设计/代码/追溯/**AI 行为**）中，前四类已由 gate + traceability 覆盖；AI 行为门此前只有"拦截"（gitguard 拒绝、hooks deny）没有"留证"。补两条零新增探针的审计通道：

1. **越权尝试计数**：gitguard 的 `FORBIDDEN_SUBCOMMAND / FORBIDDEN_FLAG` 拒绝事件，当前只拒不记。改为 daemon 侧记录（caller、子命令、时间，**不含命令参数正文**——参数可能含敏感路径），随既有任务回调族上报，服务端落 `activity_log`（Multica 现成表，加一个 action 枚举值）。P3 治理板块据此增加"**越权尝试次数**"观测项——拦截率高不是坏事，说明护栏在工作；持续增长才需要看是哪个 Agent/Skill 在漂移。
2. **工具调用摘要持久化**：`pkg/agent` 六类 Message 流中的 tool-use / tool-result 已在 `task_message` 流经服务端，但仅供实时渲染。任务完成回调附带**摘要序列**（工具名、目标路径、结果码，不含输入输出正文），与 P3 §3.4 的 `skills_used[]` 同一回调通道持久化。用途：作为"Agent 是否按 Skill 声明的方式执行"的行为证据——`review-annotations` 证明产物被审过，工具调用摘要证明过程没越界，两者合起来才是完整的 AI 行为证据链。

诚实边界（延续 §B.6 风格）：摘要证明"调了什么工具、动了哪些路径"，不证明"动机正确"；行为审计是观测面，不是新的强制门——强制仍由 gate 与 gitguard 承担。

---

## D. 交付切分与验收

| 序 | 交付物 | 验收 |
|---|---|---|
| D1 | crctl outbox（`advance/approve/git push` 三挂点） | 断网执行 advance → outbox 出现事件文件；联网后 daemon 补传成功且文件被删 |
| D2 | daemon `crevents.go` + `POST /api/daemon/cr-events` + worker | 双通道（outbox+commit 扫描）同一事件只入库一行；乱序到达 → `needs_reconcile` 而非错误投影 |
| D3 | reconcile（server / daemon 两模式） | 手工篡改投影行 → 下个对账周期自愈 |
| D4 | approval_record + grant 签发 API + `crctl approve --grant` + gate/validate 验签 + **私钥存储方案落地**（§B.5） | ① 无 TTY 环境 grant 审批走通全链 ② 批后篡改 review-annotations → **TTY 与 grant 两轨审批** gate 均报 `EVIDENCE_DRIFT`（非仅 grant 轨） ③ grant 挪用到别的 CR → 验签失败 ④ mat_ 令牌调审批 API → 403 ⑤ server 启动时私钥与公钥 smoke test 通过（不匹配则拒绝启动）⑥ `service/approval.go` 三个拒绝路径单测通过 ⑦ crctl `--grant` 的验签通过/失败/digest 不符三用例通过 |
| D5 | rules.json 抽取 + crctl/hook 改读 + `pkg/gitguard` + execenv 四处改造 | ① Agent 任务内 `git push --force` → `FORBIDDEN_SUBCOMMAND` ② `git -c core.editor=… ` → `FORBIDDEN_FLAG` ③ Write 直改 `_backlog.yml` → hook deny ④ daemon 自身 worktree 操作日志显示 caller=system-orchestrator |
| D6 | AI 行为审计（§C.5）：gitguard 拒绝事件上报 + 工具调用摘要持久化 | ① 任务内触发一次 FORBIDDEN_* → `activity_log` 出现对应行（不含参数正文）② 任务详情可查工具调用摘要序列（工具名/路径/结果码）③ 摘要与 `skills_used[]` 同回调到达，无独立探针 |
| D7 | EVIDENCE_DRIFT 留证（§B.4）：TTY 路径统一摘要字段 `evidence-digest` + daemon 侧漂移事件上报 `activity_log` | ① TTY 审批（无 `--grant`）也写 `evidence-digest`（非旧的 `evidence-sha256-16`）② 旧 approval.yml 含历史 `evidence-sha256-16` 字段时按"无摘要"处理，不报错 ③ TTY 路径批后篡改证据文件 → `crctl status`/`validate` 检出漂移且 `activity_log` 出现对应行 ④ P3 治理板块的 EVIDENCE_DRIFT 计数与 `activity_log` 该 action 的行数一致 |

依赖顺序：D1→D2→D3 一条线；D4 依赖 D2（evidence digest 从事件来）；D5 独立可并行；D6 依赖 D5（gitguard 先存在才有拒绝事件）；D7 依赖 D4（摘要算法统一在 §B.2/§B.3 先落地），工作量约 2–3 天，且**必须先于 P3 治理板块上线 EVIDENCE_DRIFT 指标交付**。

**上游回馈建议**：D1（outbox）、rules.json 抽取、`EVIDENCE_DRIFT`/`server-approve` 扩展对 tools 上游是通用增强，建议按 `CUSTOM.md` 的 fork 治理流程整理成 PR 回馈，减少长期分叉成本；gitguard 与 execenv 改造属于本平台特有，留在 fork。
