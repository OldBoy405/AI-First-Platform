# 上游同步提案：e0f84dda4..4efd5062c9

> 变更 ID：`2026-10-20-upstream-sync-4efd5062c9`
> 阶段：Gate 1/2/3 已确认（Gate 3 2026-10-21T11:30:10）；merge `a3af2341f` + 测试修复至 `874ea9621`；CUSTOM 台账 `1dc9ffeb7`/`f6e90ab80`；origin/main 已推送
> 模板：[gate1-template-v2.md](gate1-template-v2.md)
> 本变更只做上游合并；CUSTOM.md 仍是唯一事实源，不另写 capability spec。

## 0. 台账新鲜度检查（硬前置）

| 维度 | 判定 | 证据 |
|---|---|---|
| 条目新鲜 | PASS | 最后一条 CUSTOM 提交 = `54d5d5bbf`，之后 0 个代码提交；AIFI-45 的 5 个测试文件已在补登记说明中覆盖，其余标记文件按相对路径覆盖 |
| 基线新鲜 | PASS | 现场 442 / 1400 / 541 / 278；CUSTOM 2026-10-20 行同为 442 / 1400 / 541 / 278 |
| 状态新鲜 | PASS | 《当前状态》已更新为 2026-10-20；CR-2026-076 标为已合并 `c47381ae7`；AIFI-45 标为已提交 `0d6b4e9f9` |
| 格式可解析 | PASS | 2026-10-20 基线行已归位到《核对基线》；《合并官方记录》表恢复 3 列 |

### 0.5 Gate 1 准入结论

**PASS**

台账修复提交：`54d5d5bbf`（`docs(CUSTOM): 同步前台账修复（基线/状态/CR索引）`）。Gate 1 仍待用户确认。

## 1. 窗口与策略

| 项 | 值 |
|---|---|
| 仓库 | multica fork |
| fork 分支 | main @ `0d6b4e9f9`（2026-10-20） |
| 上游分支 | upstream/main @ `4efd5062c9`（2026-10-20） |
| 上次同步点 | `e0f84dda4`（第八次同步，merge `7680aa700`，2026-10-08） |
| 本次窗口 | `e0f84dda4`..`4efd5062c9` |
| 提交数 | 101（0 个 merge commit） |
| 日期跨度 | 2026-10-07..2026-10-20（作者日期口径） |
| 触发原因 | 例行同步；距第八次同步 12 天 |
| 合并策略 | merge（推荐）/ rebase（待拍板） |
| 同步分支 | `sync/upstream-2026-10-20-4efd5062c9`（尚未创建） |
| 执行模式 | thorough |
| 模式理由 | 119 个两边都改的文件；迁移号撞进 fork 565–621；9 个 db 生成物；daemon/handler/agent 冲突面大 |
| 上游 tip 冻结 | 以 `4efd5062c9` 为准；窗口外新提交不纳入 |
| 小增量检查 | 101 提交 / 119 潜在冲突，明显大于第八次同步的 15 提交 / 24 文件；是否先拆分窗口需 Gate 1 决策 |

## 2. 前置检查

- [x] upstream 历史已补全：`git rev-parse --is-shallow-repository` = false
- [x] `git fetch upstream --unshallow --tags` 完成
- [x] 工作区干净（`git status --short` 无输出）
- [x] §0 台账新鲜度已修复并通过（`54d5d5bbf`）
- [x] 同步分支已创建：`sync/upstream-2026-10-20-4efd5062c9`
- [x] 基线标签 `pre-sync/2026-10-20` 已打
- [ ] 停写窗口确认：其他 agent/PR 不再向 main 合入
- [ ] 本次不 push、不部署、不改生产库
- [ ] 库账本修复与 `migrate up` 另按授权执行

## 3. 基线快照

### 3.1 挂钩四数

按 CUSTOM《核对基线》同一口径，HEAD `0d6b4e9f9` 实测：

| 指标 | 本次基线 | CUSTOM 2026-10-20 行 | 差异 |
|---|---|---|---|
| 文件数 | 442 | 442 | 0 |
| 命中行 | 1400 | 1400 | 0 |
| AIFIRST | 541 | 541 | 0 |
| packages/ | 278 | 278 | 0 |

CUSTOM 2026-10-20 行已按 HEAD 重取；HEAD^ 为 430 / 1320 / 519 / 278，仅作历史参考。

### 3.2 迁移水位

| 项 | 值 |
|---|---|
| 上游窗口新增号 | 565–579、581–584（565–584 区间，580 缺号） |
| fork 占用区间 | 565–621（57 个 up 迁移） |
| 是否重叠 | 是，565–584 全面重叠 |
| 建议处理 | fork 57 个迁移整体顺延 **+20 → 585–641**；同步更新 cleanup map、migrate 测试、号引用测试 |
| 验证 | 空库 `migrate up`，末位应为 641 |

### 3.3 测试基线

| 检查 | 合并前结果 | 备注 |
|---|---|---|
| `go build ./...` | 绿 | 2026-10-20 基线 |
| `go vet ./...` | 绿 | 2026-10-20 基线 |
| `pnpm typecheck` | 绿 | 10/10，1m12s |
| `pnpm test` | 既有基线 1 文件失败 | core 175/175、web 35/35、docs 3/3、ui-lab 8/8、views 491/491（6160 tests）；desktop 58/59，`scripts/package.test.mjs` SyntaxError 为 CUSTOM 已知基线 |
| 定向测试（按模块） | 未取 | merge 后按 test-plan 执行 |
| 空库 `migrate up` | 未取 | 迁移 +20 顺延后执行，末位期望 641 |

### 3.4 路径与生成物基线

| 项 | 值 |
|---|---|
| 上游改动文件 | 978 |
| fork 改动文件 | 687 |
| 两边都改文件 | 119（见 [conflict-surface.txt](conflict-surface.txt)） |
| 上游 db 生成物改动 | 9 个 `server/pkg/db/generated/*.go` |
| 上游 governance 生成物 | 本窗口未发现 `governance/*gen*` / registry 改动 |
| apps/* 路径审计 | 合并后必须做「两父均有而在落树缺失 = 0」 |

## 4. 预测冲突面

### 4.1 上游提交概览

完整 101 条见 [upstream-window.txt](upstream-window.txt)；上游改动文件见 [upstream-changed-files.txt](upstream-changed-files.txt)。

### 4.2 两边都改的文件分组

| 区域 | 数量 | 高风险点 |
|---|---|---|
| `server/` | 64 | db generated 9、daemon 14、handler 14、agent 6、protocol、service、migrations 号段 |
| `packages/` | 53 | core realtime、chat、inbox、issue-detail、locales、editor |
| `.github/` | 1 | CI workflow |
| `scripts/` | 1 | ci-scope 测试 |
| **合计** | **119** | |

完整清单见 [conflict-surface.txt](conflict-surface.txt)。

### 4.3 高风险清单

- [x] 迁移号 565–584 与 fork 565–621 重叠，需顺延 +20
- [ ] 9 个 db 生成物冲突：丢弃冲突块，重跑 `make sqlc`
- [ ] daemon / handler / agent 的 AIFIRST 挂钩逐条贴回
- [ ] `packages/core/realtime/use-realtime-sync.ts` 等前端无标记定制按清单核对
- [ ] CUSTOM 三条口径盲区逐文件核对
- [ ] 合并后挂钩四数不低于 442 / 1400 / 541 / 278，差异逐项归因

## 5. 在途状态

| 项 | 状态 | 处理 |
|---|---|---|
| CR-2026-076 | 已 merge 到 main（`c47381ae7`，2026-10-12） | CUSTOM 索引已刷新为已合并 |
| AIFI-45 | 已提交 `0d6b4e9f9` | CUSTOM 行已刷新为已提交；Gate 3 状态另行核对 |
| 其他在途 CR | 未确认 | 修台账时逐行核对 CR 索引 |
| 模板 change | 独立 change，Gate 1/2/3 已确认（模板范围） | 不参与本合并，也不替代本 change 的 Gate |

## 6. 范围外

- 不处理与本次上游窗口无关的 fork 技术债
- 不修改 CUSTOM.md 历史行（只做事实性修正和追加）
- 不在 Gate 3 前 push 到 origin/main
- 不自动部署、不自动重启服务
- 不把模板 change 的 Gate 确认当作本合并的 Gate

## 7. 风险与回滚

| 项 | 内容 |
|---|---|
| 主要风险 | 迁移号第五次撞号；119 个潜在冲突；db 生成物；daemon/handler 挂钩静默失效 |
| 回滚方式 | `git merge --abort` / 删除同步分支 / 回到 `pre-sync/2026-10-20` |
| 升级复核条件 | 台账修复后 §0 仍非 PASS；迁移号无法顺延；关键行为测试无法解释 |

## 8. Gate 1 确认项（已确认）

§0 已通过（`54d5d5bbf`）。Gate 1 已确认（2026-10-20T22:58:15，dialog，user）；已进入 Phase 2（SPEC），Gate 2 待准备。

1. §0 结论（PASS / PASS-WITH-FIX）
2. 窗口 `e0f84dda4..4efd5062c9`、101 提交
3. merge vs rebase
4. 迁移顺延 +20 → 585–641
5. 挂钩四数 442 / 1400 / 541 / 278 与测试基线
6. 119 个潜在冲突面与 thorough 模式
7. 是否接受一次性合并，还是先拆分窗口

| 项 | 值 |
|---|---|
| 确认人 | user |
| 确认时间 | 2026-10-20T22:58:15 |
| 确认方式 | dialog |
| 确认原文 | 确认 Gate 1 |

## 9. Gate 2 材料（已确认）

- 矩阵：[gate2-decision-matrix.md](gate2-decision-matrix.md)
- CSV：[gate2-decision-matrix.csv](gate2-decision-matrix.csv)
- 汇总：取并集 58、贴回挂钩 38、按内容核对 12、生成物重跑 9、重新摘除 1、分半 1；合计 119。
- Gate 2 已确认：user / 2026-10-21T08:44:25 / dialog / 确认 Gate 2。
- merge 执行中。

## 10. Merge 执行记录

- merge commit：`a3af2341f`（第一父 `d5f58a70`，第二父 `4efd5062c9`）
- 测试/Windows 后修：`599114cb1` … `874ea9621`（详见 test-report）
- CUSTOM 台账提交：`1dc9ffeb7`；push 状态修正 `f6e90ab80`
- origin/main：`f6e90ab80`（已推送）
- 记录仓提交：`c3705744`（同步 change）、`955dac88`（template-only）
- upstream issue：https://github.com/multica-ai/multica/issues/9379
- 临时测试库与 baseline worktree：已清理
- Gate 3 confirmed 2026-10-21T11:30:10
