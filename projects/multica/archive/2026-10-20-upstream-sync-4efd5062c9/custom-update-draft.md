# CUSTOM.md 第九次同步更新草稿

> 已应用：CUSTOM.md `1dc9ffeb7`（记录）与 `f6e90ab80`（push 状态修正）；origin/main 已推送。
> 本文件保留为变更记录；CUSTOM.md 是唯一事实源。

## 1. 《当前状态》更新

- `multica main`：`d5f58a70`（2026-10-20，AIFI-45 tools pin + governance fix）。
- `sync/upstream-2026-10-20-4efd5062c9`：`a3af2341f` = **第九次同步**（`upstream/main` @ `4efd5062c9`，101 提交），Gate 3 pending。
- 迁移水位：上游 565–584；fork 已顺延 **+20 → 585–641**（57 对迁移）。
- 库账本：dev 库仍需按 +20 重命名后再 `migrate up`；属会打断服务的动作，未代跑。
- 验证：挂钩四数 442/1400/541/278 前后逐位相同；两父路径缺失 0；go build/vet、pnpm typecheck、views 505/505、Go 定向测试绿；desktop `scripts/package.test.mjs` 为已知基线。
- 未完成：空库 `migrate up`、Go 全量 A/B、push。

## 2. 迁移顺延映射（2026-10-21，+20）

| 段 | fork 原号 → 新号 |
|---|---|
| 治理投影（CR-2026-011） | 565→585 |
| Discussion 容器 origin（CR-2026-009/012） | 566→586 |
| Team Agent 队列/单写者（CR-2026-004/007/010） | 567→587、568→588、569→589 |
| Runner 唯一索引（CR-2026-045） | 570→590、571→591 |
| origin 恢复 + 成熟度（CR-2026-045/047） | 572→592、573→593、574→594、575→595、576→596、577→597、578→598 |
| Skill Market（CR-2026-048） | 579→599、580→600、581→601、582→602、583→603 |
| drift_finding（CR-2026-049） | 584→604、585→605、586→606、587→607、588→608 |
| cr_sync_event 工作区隔离（CR-2026-049） | 589→609、590→610、591→611、592→612、593→613、594→614 |
| approval 幂等索引（CR-2026-049） | 595→615、596→616 |
| 审批续跑（CR-2026-052） | 597→617、598→618、599→619 |
| 会话级配置（CR-2026-056） | 600→620、601→621、602→622、603→623、604→624、605→625、606→626、607→627、608→628 |
| Discussion 共享会话（CR-2026-059） | 609→629、610→630、611→631、612→632、613→633、614→634、615→635、616→636、617→637、618→638 |
| Discussion 显式升级（CR-2026-061） | 619→639、620→640、621→641 |

## 3. 《合并官方记录》追加行（草稿）

| 日期 | 对齐 | 冲突要点 |
|---|---|---|
| 2026-10-21 | `upstream/main` @ `4efd5062c9`（第九次同步，101 提交）→ merge `a3af2341f`；fork 57 对迁移 +20（565–621 → 585–641） | 119 个两边都改文件，24 个文本冲突：9 个 db 生成物重跑 sqlc；5 个 locale 并集；1 个 SQL 真源并集；9 个前后端手解（router #1 重新摘除、pi #102 自持管道、daemon #58 退役、taskEvent + reaction target、runtime local skill 发布门、search/inbox 并集等）。挂钩四数 442/1400/541/278 前后逐位相同；两父路径缺失 0；go build/vet、pnpm typecheck、views 505/505、Go 定向测试绿；desktop `scripts/package.test.mjs` 为已知基线。Gate 3 pending；未 push。 |

## 4. 基线行

无需新增：2026-10-20 行 442/1400/541/278 与第九次同步前后实测逐位相同。可在合并记录行中注明“四数不变”。

## 5. Windows 测试处置与已知基线补记（待 Gate 3）

- 测试隔离/CRLF 修复：`f5a1f4f35` daemon env、`0e08bb7f4` execenv worktree、`6bfb33381` service embedded SKILL.md。
- wecom quoted streaming 子测试：`874ea9621` 在 Windows skip（上游新增测试；`decryptToFile` 打开时 unlink，Windows 回退 buffered；Linux CI 覆盖 streaming）。
- 原 38 个新增失败已清零；最终 B3（`-count=1`）失败测试 165 个，A2 baseline 252 个。
- 剩余 2 个上游新增 timing 测试在全量并行下偶发失败，单跑通过：
  - `server/internal/service`：`TestCancelChatTranscriptReadIsBounded`
  - `server/internal/handler`：`TestClaimTasksByRuntime_HTTPFollowupDoesNotWaitForRecovery`
- 建议按“已知并行 flake”记入本表，或降低 CI 并行度；不把这两个测试算作 merge 回归。
