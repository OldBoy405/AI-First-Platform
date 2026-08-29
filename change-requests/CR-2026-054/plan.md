---
id: CR-2026-054-plan
type: PLAN
cr-ref: CR-2026-054
sdd-ref: "change-requests/CR-2026-054/sdd.md"
target-version: tbd
status: draft
created: 2026-08-29T18:08:00+08:00
updated: 2026-08-29T18:23:53+08:00
---

# 1. 交付里程碑

| 里程碑 | 交付内容 | 预计工时 | 退出条件 |
|---|---|---:|---|
| M0 基线与实现准备 | 再次确认三仓 workspace health、读取 SDD/PRD、核对目标文件现状和测试入口 | 0.5 人天 | 三个资源均为 healthy；实现分支和验证命令明确 |
| M1 archive 安全轨 | 严格 YAML 可选模式、四候选校验、hash 前接入及 tools 测试 | 3.0 人天 | 正常 archive、首次失败、rebuild 失败和零 Git 副作用测试通过 |
| M2 Agent 执行边界轨 | 更新 Agent、implement-code、review-code 和 README 的职责及失败语义 | 0.75 人天 | 文档 diff 仅覆盖 PRD/SDD 约定的文件；负向契约检查通过 |
| M3 daemon 终态补投轨 | terminal report 内存集合、单 worker、统一错误包装、daemon 挂钩和 CUSTOM.md 登记 | 2.75 人天 | complete/fail、fallback、去重、重放、关闭及脱敏测试通过 |
| M4 集成验证与证据 | 三域测试、真实 workspace 只读账本验证、test-report 和 traceability 映射 | 1.25 人天 | `write-test-report` 为 pass；AC-1 至 AC-7 均有可追溯证据 |
| M5 评审与发布 | checkpoint、独立 code review、人工 code approval、合并、writeback 和 archive | 1.0 人天 | code review pass、人工审批通过、现有归档门禁通过 |

预计总工时：9.25 人天。TASK 实现估算合计 62 小时（7.75 人天）；M0 基线检查和 M5 评审发布另计 1.5 人天。M1、M2 可并行；M3 依赖 M0 和 SDD 稳定；M4 依赖 M1~M3；M5 依赖 M4。

# 2. 任务依赖图

```text
M0 baseline inspect
  |\
  | +--> M1 tools archive 安全轨 -->+
  |                                 |
  +----> M2 Agent 执行边界轨 -----> M4 集成验证与证据 --> M5 评审与发布
  |                                 |
  +----> M3 multica 终态补投轨 ----+
```

实现资源必须使用 M0 `crctl workspace inspect` 返回的路径：

- `ai-first-platform-docs`：当前 CR knowledge-base worktree，承载 `plan.md`、测试报告及 CR 账本。
- `multica`：`.rayai-worktrees/multica/requirement/CR-2026-054`，承载 daemon 代码、测试和 `CUSTOM.md`。
- `tools`：`.rayai-worktrees/tools/requirement/CR-2026-054`，承载 YAML、archive、Agent/Skill/README 改动。

不得在实施期重新拼接资源路径；若 workspace freshness 报告 HEAD 漂移或资源异常，先按既有流程暂停并重新确认权威 worktree。

# 3. 任务分组与依赖

## 3.1 tools / archive 安全轨

1. 扩展现有 `yaml-subset.mjs` 的可选 strict 模式，保留默认解析兼容；覆盖 CRLF、重复键、未消费行、缩进、容器切换和合法空值。
2. 在 `workspace-transactions.mjs` 的 `buildEntries()` 中实现文件私有 `validateArchiveCandidates`，覆盖四候选根形状、目标 CR 不变量、history 全局唯一和 archive 终态集合。
3. 确认校验位于 write-set hash、stage、commit、push 之前，并由首次构建和 rebuild 共用。
4. 更新 `yaml-subset.test.mjs` 和 `archive-tx.test.mjs`，验证既有生成错误码保持不变及无副作用失败。

依赖：1 -> 2 -> 3；4 与 2、3 同步完成后执行。

## 3.2 tools / Agent 执行边界轨

1. 按 SDD 更新 `agents/dev-agent.md`，明确路由、职责判断、Skill 委派和技术中止后的结束语义；技术中止时必须报告所需平台/人工动作并结束，不等待或轮询下游任务。
2. 按 SDD 更新 `skills/develop/implement-code/SKILL.md`，明确一次环境检查、最多一次重跑、任务边界、遵守测试计划 timeout、使用既有测试入口和禁止遗留后台进程；超出权限时返回 `ENVIRONMENT_MISMATCH`。
3. 更新 `skills/develop/review-code/SKILL.md`，明确共享实例输出不可归因时不采信，环境不匹配不生成代码 blocker。
4. 仅在人读范围内更新 README，并保留可执行细节的唯一事实源在对应 Skill、Pipeline 和 crctl。

依赖：M0；四项可并行，完成后执行文档越界检查。

## 3.3 multica / daemon 终态补投轨

1. 在 `server/internal/daemon/terminal_report_retry.go` 定义零值可用的私有 pending map、mutex、once、不可变值复制和 first-wins 语义。
2. 抽出 `deliverTerminalTaskReport`，复用既有 CompleteTask/FailTask、有限重试和幂等契约；保持 complete 瞬时错误不 fallback、永久错误才 fallback。
3. 实现 `terminalReportFailure` 的 `Unwrap`、错误分类和 `slog.LogValuer` 脱敏字段；新增错误值只暴露 `task_id`、`terminal_kind`、`error_class`。
4. 在 `daemon.go` 仅增加 SDD 约定的零值字段和统一 `reportTerminalTask` 两个小型挂钩；不修改共享 logger 和既有 complete/fail caller。
5. 实现 30 秒单 worker、snapshot、成功/永久删除、瞬时错误保留并结束本轮、root context 取消停止。
6. 新增 `terminal_report_retry_test.go`，覆盖初次投递、fallback、去重、冲突、payload 保真、关闭和 `slog` 脱敏；完成后按当时实际结构登记 `CUSTOM.md`。

依赖：1 -> 2、3；2 与 3 -> 4、5；4、5 -> 6。Go 注释保持英文。

## 3.4 集成验证

M4 的实现与证据工作由 TASK-08 承接，包含以下交付：

1. 在各目标 worktree 使用现有测试入口执行 tools、multica 和文档契约验证。
2. 对真实 workspace 的 backlog、history、index 执行一次只读严格解析验证，不新增常驻脚本或 CLI。
3. 检查三域 diff、`CUSTOM.md`、测试报告和 AC 映射，确保没有 Pipeline、状态机、账本、权限矩阵或共享服务管理越界。
4. 通过既有 `write-test-report` 生成测试证据，失败按既有 reviewLoop 回修，不手工修改测试账本。

TASK-08 的前置检查还包含 M0：重新执行 `crctl workspace inspect`，确认 operational workspace 非空且全部 resources 为 healthy。M0 先于实现；TASK-08 在 TASK-03、TASK-04、TASK-07 完成后执行。

# 4. 资源与分工

| 角色 | 工作内容 | 预计工时 |
|---|---|---:|
| workspace/CR 协调负责人 | M0 workspace inspect、基线确认和路径消费 | 0.5 人天 |
| tools 实现负责人 | YAML strict、archive 候选验证、tools 测试 | 3.0 人天 |
| 平台文档负责人 | Agent/Skill/README 职责边界和契约文档 | 0.75 人天 |
| multica 实现负责人 | daemon 补投、错误值、Go 测试、CUSTOM.md | 2.75 人天 |
| 测试与证据负责人 | 三域验证、真实账本只读检查、test-report | 1.25 人天 |
| 独立 reviewer / CR owner | code review、审批、合并及归档 | 1.0 人天 |
| 合计 |  | 9.25 人天 |

实际执行中以各资源 worktree 的 owner 和现有 Pipeline 上下文为准；本计划不新增服务账号、共享实例或基础设施管理职责。

# 5. 风险与回滚策略

| 风险 | 预防与检测 | 回滚策略 |
|---|---|---|
| strict 模式误拒合法账本 | 默认模式保持不变；覆盖引号键、空值、CRLF 和真实账本只读验证 | 移除 archive strict 调用和对应私有校验，保留默认解析器行为；不回滚无关改动 |
| rebuild 绕过候选校验 | 校验固定在共用 `buildEntries()` 且位于 write-set 前；测试首次和 rebuild | 回退 `validateArchiveCandidates` 接入及测试，恢复原 archive 事务路径 |
| Agent 误把环境问题当代码 blocker | 以 `ENVIRONMENT_MISMATCH` 作为 Skill 输出，Pipeline 继续使用既有 abort | 回退对应 Skill/Agent/README 文档提交，不改 Pipeline 或状态机 |
| daemon 补投递归入队或重复 worker | 重放只调用 `deliverTerminalTaskReport`；`sync.Once`；单轮 helper 测试 | 回退 daemon 挂钩和新增文件；服务端既有一次性终态交付和 orphan recovery 保持可用 |
| 日志泄露原始 cause 或 payload | 捕获 `slog.Handler` 验证 LogValue 字段；检查初次、fallback、重放和冲突 | 回退终态补投轨；不修改共享 logger，不以删除日志替代代码修复 |
| multica rebase 冲突扩大改动面 | `daemon.go` 仅两个小挂钩；新增逻辑独立文件；CUSTOM.md 登记 | 以目标分支为基线重做独立文件和两个挂钩；不逐个改造 caller |
| 某业务域证据不足 | M4 逐域检查 AC-1~AC-7 和 test-report；code review 缺证据即 block | 保留 CR 在既有 reviewLoop 回修态，补齐实现/测试证据后重新评审 |

# 6. 验收与发布策略

## 开发完成 checklist

- [ ] M0 `workspace inspect` 返回全部 resources `healthy`，并消费 operational workspace。
- [ ] tools archive 校验在 write-set hash 前生效，首次构建和 rebuild 均有测试。
- [ ] Agent、Skill、README 改动没有复制 Pipeline、状态机、账本或权限矩阵规则。
- [ ] multica 仅有独立终态补投文件、测试文件、`daemon.go` 两个挂钩和 `CUSTOM.md` 台账登记。
- [ ] complete 瞬时错误不调用 FailTask fallback；complete 永久错误才调用 fallback；payload 保持一致。
- [ ] 新增终态错误日志不包含原始 cause、errorMessage、output、session/workdir 或完整 report；既有非敏感 caller 上下文保持兼容。
- [ ] 三域测试和真实 workspace 只读验证完成；`write-test-report` 为 pass。
- [ ] 独立 quality reviewer 完成 code review，所有 blocker 清零。
- [ ] 通过 `crctl approve --stage code` 后再合并、writeback 和 archive。

## 发布策略

本 CR 不引入 feature flag、配置项、迁移或新发布开关。发布按既有代码合并和归档流程执行：先在各自 CR worktree 完成实现与测试，再通过统一 checkpoint 发布代码和证据；代码审批、合并、writeback、archive 继续由既有 crctl 门禁控制。

daemon 补投为进程内能力：升级后新进程启用，进程退出时未完成的内存条目仍由既有 orphan recovery 处理；不承诺跨重启保存。若发布后发现行为回归，按 repository commit 回退并重新运行既有测试与 CR 门禁，不保留半启用状态。
