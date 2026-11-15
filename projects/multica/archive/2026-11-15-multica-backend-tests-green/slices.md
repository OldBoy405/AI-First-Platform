# 2026-11-15-multica-backend-tests-green 切片执行计划

## Dependency Graph Summary
```
C1 bigm(pg_stats)+selection ──┐
                              ├─> S1 (TC-BTO-001)
ownership 4 条 ───────────────┴─> S2 (TC-BTO-002/003)
                                   │
admin 对账函数 + 6 用例 + ci.yml ──┘─> S3 (TC-CAO-001/002)  ← 依赖 S2 的 3 条 ci-admin 登记
withRunLock + 2 用例 + 池 4 + 2 selection ─> S4 (TC-RRL-001/002/003)  ← 独立于 S1–S3
claim 定性 ─> S5 (TC-BTO-004)  ← 依赖 S1–S4 落地
CUSTOM.md ─> S6 (TC-BTO-006)   ← 依赖 S1–S4 的最终触点
真实 CI ─> 推送后 (TC-BTO-005)
```
**并行化说明**：
- S1、S2、S4 之间无代码依赖，可并行；S3 依赖 S2 的归属表（ci-admin 条目是它要求「必须出现」的输入）。
- 实际执行按 design 顺序串行，减少同一文件反复编辑：S1 → S2 → S3 → S4 → S5 → S6。

## Slice Execution Plan
| # | 优先级 | 风险 | 预估工时 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|--------|------|---------|--------|---------|---------|------|
| 1 | P0 | 🟢 Low | S | 组1 | TC-BTO-001 | `statisticsRowCount` 改读 `pg_stats`；`selections.json` + `bigm-restricted-role` | 无 |
| 2 | P0 | 🟡 Med | S | 组1 | TC-BTO-002, TC-BTO-003 | `test-ownership.json` + 3×ci-admin + 1×independent | 无 |
| 3 | P0 | 🟡 Med | M | — | TC-CAO-001, TC-CAO-002 | `reconcileAdminStream` + CLI 模式 + 6 个 node 用例 + ci.yml step | 2 |
| 4 | P0 | 🔴 High | M | 组1 | TC-RRL-001, TC-RRL-002, TC-RRL-003 | `withRunLock` + 三处调用点 + 池 4 + 2 个 selection + 2 个 Go 用例 | 无 |
| 5 | P1 | 🟡 Med | S | — | TC-BTO-004 | claim 用例重复运行定性记录 | 1–4 |
| 6 | P1 | 🟢 Low | S | — | TC-BTO-006 | `CUSTOM.md` 台账行 + CRLF 核对 | 1–4 |
| 7 | P0 | 🔴 High | M | — | TC-BTO-005 + C1–C7 | 全量质量验证、三路评审、test-report、Gate 3、真实 CI | 1–6 + 推送授权 |

## Rationale
### Slice 1: bigm 改读 `pg_stats`（P0）
- **依赖关系**：无。先加 selection 作为 RED 证据（现有 selection 都跑不到这条），再改查询。
- **风险分析**：经验库无匹配模式；改动是单条 SQL 视图替换，语义由「表达式索引统计以索引名出现在 `pg_stats.tablename`」保证，已在取证中实测。难度 S。
- **工作量估算**：2 文件一个小改。

### Slice 2: 归属表 4 条（P0）
- **依赖关系**：无代码依赖；S3 的 ci.yml step 用它决定「必须出现的 3 个名字」。
- **风险分析**：`test-ownership.mjs check` 会校验条目指向真实 `func TestX(`，写错名字立刻红；`skip-regex` 的输出决定共享 run 的排除集合，改动会让 `ci-evidence` 规则 3 覆盖到新条目。难度 S。
- **工作量估算**：1 JSON 文件 + 2 条验证命令。

### Slice 3: 管理员流对账（P0）
- **依赖关系**：需要 S2 的 3 条 ci-admin 登记（对账对象），但 6 个 node 用例自带表输入，RED 可先行。
- **风险分析**：与经验 EXP-2026-0008 同族——只测一种失败条件会漏；本切片的 5 类坏样本各自独立断言「点名具体包与测试」，并额外覆盖「恰好一条 pass」。ci.yml 只做接线，真实效果由 TC-CAO-002/005 给出。难度 M。
- **工作量估算**：3 文件（mjs + test + yml）。

### Slice 4: `withRunLock` 与池固定（P0）
- **依赖关系**：无。生产路径改动，风险最高。
- **风险分析**：经验库暂无匹配条目；关键是等待期间释放连接、取消返回 `ctx.Err()`、释放用 `context.Background()`；EXP-2026-0008 提醒「互斥」断言必须是并发进入计数，而不是「都返回」。既有 `TestMTick003` @池 4 是现成红样本，替换后必须绿。难度 M。
- **工作量估算**：5 文件（runner*.go + 新测试 + crsync_test + selections）。

### Slice 5: claim 定性（P1）
- **依赖关系**：在 C1–C4 落地后跑，避免把权限/锁/共库干扰算进该用例。
- **风险分析**：2026-11-15 改前基线显示单跑 20/20 通过；CI 失败疑为跨包共库干扰（`GetAgentTask` 行消失）。结论只按实际重复结果写，不预设修。
- **工作量估算**：容器内重复运行，执行交 balanced 子代理。

### Slice 6: CUSTOM.md（P1）
- **依赖关系**：最终触点确定后登记。
- **风险分析**：CRLF 与行模板是硬要求；只追加行，不改既有行。
- **工作量估算**：S。

### Slice 7: 质量验证与交付（P0）
- **依赖关系**：全部切片完成；真实 CI 需推送授权。
- **风险分析**：C4 失败模板块须逐项执行；Gate 3 必须用户确认，AI 不代签。
- **工作量估算**：M。
