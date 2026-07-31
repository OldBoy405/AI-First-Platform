---
id: CR-2026-002-TASK-04
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: migrations（cr / cr_sync_event / approval_record）+ transitions_gen.go 入库
status: done
estimate: 8h
depends-on: []
assignee: ""
created: "2026-07-31T09:30:00+08:00"
spec-id: ai-first-platform
version: "0.11"
---

## 任务描述
FR-2 数据前置：三张新表迁移（DDL 见 SDD §2.1，注意 approval_record 用部分唯一索引 `WHERE decision='approve'`）+ activity_log 两个 action 枚举常量 + 状态机 23 条转移表生成入库。仓库：multica。

## 涉及文件
- 新增 `server/migrations/{next}_aifirst_cr_projection.sql`（三表 + 索引）
- 新增 `server/internal/governance/transitions_gen.go`（生成产物，头注释记 tools commit SHA）+ 生成脚本 `server/internal/governance/gen/`（读 tools dir-graph.yaml）
- 新增 CI 步骤：重新生成 == 已入库（漂移即红，SDD-SUG-003）
- activity_log action 常量：`aifirst.gitguard_denied`、`aifirst.evidence_drift`（放 governance 包，不动上游枚举定义处）

## 实现要点
- 迁移风格对齐 multica 既有 396 个迁移的命名与工具链。
- transitions_gen.go 含 `IsLegalTransition(from, to, trigger) bool`；数据来源 tools dir-graph.yaml 的 16 态/23 条转移。
- CUSTOM.md 记账：新迁移文件属自研，rebase 时保序。

## 验收条件
1. `make selfhost-build COMPOSE=docker-compose.exe` 起栈后三表存在、索引正确（\d 检查部分唯一索引）。
2. 同 (cr_id,stage,digest) 先 reject 再 approve 两次插入均成功；approve 重复插入被幂等拒绝。
3. transitions 单测：23 条合法转移全 true、抽样非法转移 false。
4. CI 一致性校验步骤红绿验证（手改 gen 文件 → 红）。

## 完成标志
构建通过 + 迁移可重放（down/up 或重建卷）+ 单测绿 + 完成记录回填。

## 完成记录（2026-07-31）

- **提交**：multica worktree b78434bd2（requirement/CR-2026-002，已推 origin fork——multica 侧首个 CR 分支推送）。
- **迁移 158**：三表 DDL 落地。**实测验证**（临时库 aifirst_t04，001 基表 + 158，生产 multica 库未动）：① 同证据 reject×2 + approve×1 = 3 行共存；② approve 重复插入 → 撞 `approval_record_approve_uniq`（SDD-SUG-001 部分唯一索引双向验证）；③ cr_sync_event `ON CONFLICT DO NOTHING` 幂等 → 1 行；④ down 迁移三表干净回滚。
- **governance 包**：`transitions_gen.go`（45 条展开转移 = 21 直接 + 2 wildcard×12，来源 tools@63f5f0c）+ `IsLegalTransition`（空 trigger 只按 from/to 匹配，为 commit 兜底扫描留口）+ `actions.go` 两个 `aifirst.` 常量（activity_log 免迁移）。Go 测试 3 项全绿，gofmt/vet/全仓 build 通过。
- **gen --check 红绿验证**：篡改 gen 文件 → exit 1；恢复 → exit 0。比对忽略"来源 SHA"行——tools 提交推进但状态机没变不算漂移。CI 挂接留待 fork CI 就位（记 CUSTOM.md #4 备注），当前由本地 --check 承担。
- **过程发现两个真 bug（都被当场修掉）**：① 生成器的跨行正则被 CRLF 检出静默失配，wildcard 两条转移（rejected/withdrawn 入口）差点丢失——加行尾规范化 + 解析失败即 exit 2 硬失败；② 状态数断言：具名状态实为 15，"16 态"的口径含 (new)。
- **两个如实记录**：① SDD §5 曾写"multica 无 internal/service 包"——**事实错误**（该包存在）；governance 新包的决策依据（规则一冲突面隔离）不受影响，但 SDD 的论据行需在评审时知悉；② multica CLAUDE.md 规定代码注释必须英文，初稿中文注释已全部重写（迁移 SQL/Go/生成器及其产物）。
- **CUSTOM.md**：新增台账 #3（迁移）#4（governance 包，含状态机变更流程：改 tools → 重跑 gen → 提交两仓）。
