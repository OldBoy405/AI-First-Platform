# AIFI-45 Runner pipeline 冲突修复 — 限定审阅与独立运行记录

> 范围：仅 `findActiveRunTx` 的 pipelineID 绑定修复，以及独立 AST 测试包 `runnerquery_test`。
> **本记录不构成 RUN-007 验收。** 真实 SQL、唯一索引冲突语义、并发行为均未证明。

## 1. 会话与环境

| 项 | 值 |
|---|---|
| pi session id | `01a1854b-2985-7020-aecc-d2152ef81546` |
| session file | `C:\Users\GOBAO\.pi\agent\sessions\--C--Users-GOBAO-Downloads-AI-AI First Platform--\2026-10-29T01-34-17-990Z_01a1854b-2985-7020-aecc-d2152ef81546.jsonl` |
| model | `GBClaude / claude-opus-5-5` |
| Go | `go1.27.1 windows/amd64` |
| 运行时间 | 2026-10-29 约 09:35 (+08:00) |
| multica 工作树 | `C:/Users/GOBAO/Downloads/AI/multica`（main，`81e5293ad`，含未提交修改；`runner.go` 为工作树修改态） |

## 2. 对象 raw SHA-256

| 文件 | SHA-256 |
|---|---|
| 修复后 `multica/server/internal/governance/runner.go`（工作树） | `faf7085c115e11fbe45da8685a15b37d76b88e6de2bc37d2dc206e1b0c877ed1` |
| 修复前 `validation/runner-pipeline-conflict-20261028/source-before/runner.go` | `7dfcbb3c0b2dc5bfb568cb0368c0ab5572d034739f6116e4adc0bdefa35c6854` |
| 测试 `multica/server/internal/governance/runnerquery_test/active_query_test.go` | `f535341a576aee2dae1dc0f2be8cd2acccb1e14918590e9476be485cb978afd8` |

两个工作树文件（runner.go、active_query_test.go）在独立运行**前后**各取一次 SHA，结果均与上表一致，未变化。

## 3. 第一轮：静态审阅（静态推断，未执行）

### 3.1 差异

`diff source-before/runner.go runner.go` 仅一行（第 1171 行，`findActiveRunTx` 内）：

```diff
-		ORDER BY created_at DESC LIMIT 1`, workspaceID, crID, PipelineIDs.ArchitectureDesign).
+		ORDER BY created_at DESC LIMIT 1`, workspaceID, crID, pipelineID).
```

`git diff --stat`：`runner.go | 2 +-`（1 insertion, 1 deletion）。

### 3.2 真实调用链（读源码所得）

- `upsertRunTx(…, pipelineID, …)`（runner.go:1113）：`INSERT … ON CONFLICT DO NOTHING RETURNING id`；`ErrNoRows` 时调用 `findActiveRunTx(ctx, tx, workspaceID, crID, pipelineID)`（runner.go:1125），然后 `UPDATE … WHERE id=$1 AND COALESCE(execution_context->>'runner','')=''`。
- 调用方：
  - runner.go:623、685、1146 —— 均传 `PipelineIDs.ArchitectureDesign`，修复前后行为不变。
  - runner_code.go:308 `ensureWritebackRun` —— 传 `PipelineIDs.FeatureWriteback`，是唯一受影响路径（由 runner_code.go:448 在 code 流程 approve 通过后调用）。

### 3.3 具体影响（静态推断）

修复前，writeback 插入冲突后回查被硬编码为 ArchitectureDesign：

- 无 active 架构 run → `ErrNoRows`，`ensureWritebackRun` 报错，writeback handoff 失败；或
- 命中同 CR 的 active ArchitectureDesign run → 若其 `execution_context.runner` 为空，会被写入 writeback 的 inputs/execution_context（跨 pipeline 污染）。

修复后回查限定为同 pipeline（FeatureWriteback）。

### 3.4 修复不足（静态推断，均未经 DB 验证）

1. **冲突目标不明**：`ON CONFLICT DO NOTHING` 未指定 conflict target。若触发冲突的唯一索引是"每 CR 跨 pipeline 唯一 active run"，冲突行并非 writeback run，按 FeatureWriteback 回查仍为 `ErrNoRows` → 报错。需核对真实 schema/唯一索引定义。
2. **竞态**：INSERT 冲突与随后的 SELECT 之间，冲突行可能已转为终态（不再 `running`/`waiting_approval`），回查得 `ErrNoRows`，无重试。
3. **静默复用**：UPDATE 仅在 `runner` 为空时生效；已有 runner 但 inputs/上下文不一致的 active run 会被直接复用，不报不一致。
4. **非原子 check-then-act**：`ensureWritebackRun` 为 find（池）→ 独立 tx upsert → 再 find（池），三步之间无锁，并发幂等性未证明。
5. `findActiveRun`（非 Tx 版本）仍硬编码 ArchitectureDesign；其调用方均为架构路径，判定可接受，但未逐一动态验证。

### 3.5 AST 测试审阅（active_query_test.go）

测试只用标准库 `go/parser` 解析 `../runner.go`，无 DB、无 TestMain。断言：

- 有且仅有一个带接收者的 `findActiveRunTx`；
- 函数体内恰一个 `tx.QueryRow`，参数 5 个；
- 参数 0/2/3/4 为标识符 `ctx`/`workspaceID`/`crID`/`pipelineID`；
- 参数 1 为字符串字面量，且匹配 `(?i)\bpipeline_id\s*=\s*\$3\b`（`$30` 不会误匹配）。

对修复前源码：参数 4 是 `SelectorExpr`（`PipelineIDs.ArchitectureDesign`）而非 Ident，**推断**应失败。注意：**未执行针对修复前源码的变异/反向运行**，此为静态推断。

**假绿风险（保留）：**

1. 只比对标识符名，不校验其绑定到函数形参：函数体内 `pipelineID := PipelineIDs.ArchitectureDesign` 遮蔽仍会通过。
2. 不检查函数签名是否含 `pipelineID string` 形参。
3. 不检查 `upsertRunTx` 是否把自身 `pipelineID` 透传给 `findActiveRunTx`（writeback 路径的关键链路），也不检查 runner_code.go:308 的实参。
4. SQL 仅正则检查：`pipeline_id=$3 OR true`、SQL 注释内出现 `pipeline_id=$3` 等都会通过；未检查 `workspace_id=$1`、`cr_id=$2`、`status IN (…)` 过滤。
5. 仅单函数源码级检查，不能证明数据库语义或并发语义（测试文件注释亦如此声明）。

## 4. 第二轮：独立动态执行（实际运行）

### 4.1 命令

工作目录：`C:/Users/GOBAO/Downloads/AI/multica/server`

```bash
unset DATABASE_URL $(env | grep -o '^PG[A-Z_]*')
env | grep -E '^(DATABASE_URL|PG)'      # 输出为空，确认已清除
GOPROXY=off GOWORK=off GOFLAGS= go test -count=1 -json ./internal/governance/runnerquery_test \
  > /tmp/rq.json 2>/tmp/rq.err
echo "EXIT=$?"
```

### 4.2 结果

| 项 | 值 |
|---|---|
| `TestFindActiveRunTxBindsRequestedPipeline` | **pass**（0.00s） |
| 统计 | **1 pass / 0 fail / 0 skip** |
| 包结果 | pass，0.352s |
| `go test` 退出码 | **0** |
| stderr | 空 |

### 4.3 临时输出文件（如实说明）

- 使用固定路径 `/tmp/rq.json`（stdout JSON）与 `/tmp/rq.err`（stderr），Git Bash 下对应 `C:\Users\GOBAO\AppData\Local\Temp`。
- 运行后：`/tmp/rq.json` 1736 字节，SHA-256 `8741489a3ee935eff3c91e7c60a08c3e9821d5efc5658d6d1da7c03cca3c650f`；`/tmp/rq.err` 0 字节，SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`。
- 两文件**未删除**。路径固定且非随机，**不声称**运行前该路径不存在或为本次独占；上述内容 SHA 仅代表记录时刻状态。

### 4.4 未执行项

- 未运行 governance 包（含其 DB TestMain）及任何其他测试包；
- 未连接/启动任何数据库或 PG，未使用容器，未操作真实 CR；
- 未对修复前源码做反向/变异运行；
- 除本报告外未修改任何文件。

## 5. 结论

- **静态绑定：通过。** `findActiveRunTx` 的 `$3` 已绑定调用方传入的 `pipelineID`；独立 AST 测试 1 pass / 0 fail / 0 skip，退出码 0，运行前后源码与测试 SHA 不变。
- **未证明：** 真实 SQL 执行与唯一索引冲突语义、writeback 跨 pipeline 冲突场景、竞态/并发幂等性、AST 测试的假绿缺口（遮蔽、透传链、SQL 宽松匹配）。
- **本记录不是 RUN-007 验收。**
