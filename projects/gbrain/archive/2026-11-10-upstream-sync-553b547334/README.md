# 上游同步档案：2026-11-10-upstream-sync-553b547334

> 窗口：`2568d32ac8..553b547334` | 版本：`0.60.461.0 → 0.60.636.0`
> 同步分支：`sync/upstream-2026-11-10-553b547334` | 合并提交：`d0a0515036`
> 回滚锚点：`pre-sync/2026-11-10`（`a752cc41a4`）

## 本档案与 STDD CLI 的边界（重要）

本轮沿用 2026-10-26 档案的 **`upstream-sync` 四 Gate 变体**，但**没有通过 STDD CLI 创建 change**。
因此本档案**不含** `.stdd.yaml`、`canonical/`、CLI 生成的 `design.md` / `test-plan.md` /
`spec.md` Human View——这些是 CLI 状态文件，按 `AI_OPERATING_MANUAL.md`
「禁止手动改 `.stdd.yaml`、Gate/Phase 必须通过 CLI 推进」的规定，不手工伪造。

本轮的 Gate 确认证据以对话记录为准：

| Gate | 时点 | 确认证据 | 状态 |
|------|------|----------|------|
| Gate 1 | §0 台账新鲜度 BLOCK → 修复 → PASS 后 | 用户选项「确认继续（推荐）」 | PASS（用户确认） |
| Gate 2 | 冻结窗口 + 19 冲突裁决矩阵成表后 | 无独立用户交互；以 Gate 1 的「继续」涵盖执行 | 执行依据 = `gate2-decision-matrix.md` |
| Gate 3 | 95 项 verify 逐条定性 + 2 处真实回归修复复跑后 | 首次仅完成验证、未放行；**同日用户另行明确授权**（「合入 master，提交，推送，部署，跑 gbrain apply-migrations；bun install；处理存量欠债」） | ✅ 已交付，见 `delivery-log.md` |

> 后台任务完成通知是系统事件，不构成授权；Gate 3 的放行依据是用户后续那条明确指令，不是通知。

**结论**：合并本体与后续交付均已完成。`origin/master` = `18ba403289`（最终；`06a600043f` 为首次落地），本机 CLI = `0.60.636.0`，
brain schema = 298，250 个尾换行欠债已闭环。执行明细与推送踩坑见 `delivery-log.md`。

## 文件清单

| 文件 | 内容 |
|------|------|
| `proposal.md` | Gate 1 提案：Why / What Changes / Success Criteria |
| `gate1-detail.md` | §0 台账新鲜度四维首判、BLOCK 项、修复提交与复跑证据 |
| `gate2-decision-matrix.md` | 19 个真实冲突逐文件裁决 + 干净合并挂钩核对 + 生成物重跑顺序 + 迁移改号执行单 |
| `test-report.md` | Gate 3：成功标准逐条结果、95 项 verify 的 21 个失败逐条定性、定向回归与探针 |
| `design-adjustments.md` | 实施中相对 Gate 2 设计的偏离与补充（D1–D9） |
| `spec-delta.md` | 主规范 `specs/upstream-sync-merge/spec.md` 中因本轮而过时的具体值（**不直接改 CLI Human View**） |
| `delivery-log.md` | 同日用户授权后的交付记录：合入、推送（含 HTTP 408 与分批续传）、部署、安装迁移、欠债闭环、推送后复核 |
| `upstream-window.txt` | 冻结窗口的机器可读统计 |
| `conflict-surface.txt` | 19 个真实冲突路径 |
| `both-changed.txt` | 51 个两边都改的路径 |
| `merge-tree.txt` | `git merge-tree --write-tree --name-only` 预测原始输出 |
| `verify-rerun-results.tsv` | 95 项检查的 rc 与耗时 |

## 唯一事实源

冲突裁决以 `CUSTOM.md`《合并守则》及各《明细合并注意项》为准；本档案是执行记录，
不替代台账。台账本轮《阶段记录》（2026-11-10）在仓库 `CUSTOM.md:207`。
