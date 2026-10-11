# FR-14 实际取用版本记录（SDD §8 变更集合 → 实际取用版本 → origin）

判据口径（SDD-CLOSE-08 / SDD §4.13）：交付完成 = 「安装后新 run 的目标行为证据 + 实际取用版本记录」；
源码合入／构建成功／镜像更新**不单独**算实际交付完成。本记录由 `cmd-14` 真实执行产出，
比较口径 = `multica skill get --with-content` 线上内容 vs tools CR worktree 目标文件（`\r\n → \n` 归一、尾空行归一）。

- 证据命令：`cmd-14`（`node --test skills/shared/crctl/scripts/test/publish-effectiveness.test.mjs`，exit=0）→ `test-evidence/cmd-14.log`
- 集成入口：`cmd-11`（suite-gate 全仓集合核对，本文件与 `gate-registry.json#manifest.files`／`manifest.cases` 同批落盘）
- 比较目标集合唯一来源：SDD §8 表；`controlled-shell` 的 §8 行标注「无改动」，不列入（AC 5：不声称覆盖未在 §8 声明变更的 Skill）

## 1. 实际取用版本（Skill，13 项，逐字一致）

| # | Skill | origin repo／ref／path | sha256（仓库目标 = 线上实际取用） | equal |
|---|---|---|---|---|
| 1 | `approve-dev-start` | `AI-First-tools`／`main`／`skills/develop/approve-dev-start` | `4c285c4cc8d1709bc2ad007516291be14e2f1aa96c2a52fb2288c0ddc7660ec6` | true |
| 2 | `write-dev-tasks` | `AI-First-tools`／`main`／`skills/develop/write-dev-tasks` | `726db600408c34bf3a3bdb5b616937436871050a13fed21b11b28e56e2210858` | true |
| 3 | `implement-code` | `AI-First-tools`／`main`／`skills/develop/implement-code` | `d80b00269899b67971af9e7a3e2314d21fc3e9b6d6fb24a83dcbde65ec775a2d` | true |
| 4 | `workspace-freshness` | `AI-First-tools`／`main`／`skills/sync/workspace-freshness` | `8e385a4e36b22fec58435a22a00ea790e68d131734a912700d8f7ee4006d9d23` | true |
| 5 | `review-code` | `AI-First-tools`／`main`／`skills/develop/review-code` | `2aa82a4993e46f9d9e5cde9ee8f8d8c0b8b6fe4b7bd2768347f55af85f73799f` | true |
| 6 | `review-dev-plan` | `AI-First-tools`／`main`／`skills/develop/review-dev-plan` | `385f72de55da58b969cfc4858887366b212eca34dd5675d7224c71b9f3efc1c7` | true |
| 7 | `write-test-report` | `AI-First-tools`／`main`／`skills/develop/write-test-report` | `3ce02a1920adbac8761958e88e7b4c0e8a2013a394d0611427d99be17efb4906` | true |
| 8 | `crctl` | `AI-First-tools`／`main`／`skills/shared/crctl` | `4bf63565efdb8573cfe6633518eb6971b23c05563020715acce5fc959e75b0ab` | true |
| 9 | `requirement-register` | `AI-First-tools`／`main`／`skills/requirement/requirement-register` | `c9f3805b1ec76e3cb4e4e6bc5a97c69448d2422b543b24302f72e6a7d90948ff` | true |
| 10 | `handover-cr` | `AI-First-tools`／`main`／`skills/sync/handover-cr` | `72b4ce1290de83ecde6732428bc168188da3b393a9a718d26eedfb21c86fe29f` | true |
| 11 | `push-progress` | `AI-First-tools`／`main`／`skills/sync/push-progress` | `7ad5ec4c599414d3a0dd96ccf1e81dcf51bc2d71d010efce2cf11490d7c5b8ea` | true |
| 12 | `cr-review-record` | `AI-First-tools`／`main`／`skills/cr/cr-review-record` | `e5b5c9c055d74b9142bf47969c1d9df9f55567aacfc66faa72a63d8c4143284a` | true |
| 13 | `inbox-emit` | `AI-First-tools`／`main`／`skills/cr/inbox-emit` | `6bd783f61a7cbd9065c395af6ba287a380083cafe7376674d098ff669e583087` | true |

## 2. 三份 CR Agent instructions（记录型观测，无相等断言）

plan §5.4 说明③：其平台部署副本通道 `multica/cr-prompts-revised/*.md` 不在 SDD §1.5 变更面内，
故只记录线上版本 sha256，**不**据以声称指令同步完成，也**不**做相等断言。

| instruction | sha256（线上实际取用） |
|---|---|
| `dev-agent` | `c116f0ebe273c1c92b7c22ad67e91b7af7466c4023c75697aafe868d4b76c73b` |
| `quality-reviewer-agent` | `daf87cb1b9046e3b1b576187d131ba5b1f120c650a6616cd76b4037a6a19b15c` |
| `requirement-writer` | `dd88b8fd39ee4c6deea348d81e0a625106fd4239f84c5e5ae5eb9be55b0e7ada` |

## 3. 窗口时序事实（plan §5.4：M7、TASK-17 执行窗口内、早于代码审批）

- 平台 Skill 侧同步时刻（`multica skill list` 的 `updated_at`，13 项取值集合原样）：`2026-10-10T23:56:09Z`、`2026-10-10T23:56:42Z`、`2026-10-10T23:56:43Z`
- 已安装入口：`multica --version` → `v0.6.1-429-ge5f0fc089`（`commit e5f0fc089`，`built 2026-10-10T23:58:07Z`）；`multica daemon status` 的 `cli_version` 同值（见 `cmd-15.log`、`fr14-launch-receipt.md`）
- 代码审批未发生：`approval.yml` 仅含 `requirement`／`tech-design`／`development-start` 三段，**无 `code` 段**；`cr.md` 的 `status: developing`（非 `code-approved`）
- 对照：multica CR worktree HEAD `e5f0fc089` 与上述入口 `commit` 同值（版本断言见 `cmd-15.log`）

## 4. 回退清单（人类 owner 按同一目标文本回退）

平台侧消费者切换由人类 owner 按第 1 节同一 origin 目标文本（`repo=AI-First-tools`／`ref=main`／`path` 逐行）回退；
本 TASK 的证据与同步清单同批 revert（plan §4 风险表）；回退不使用 feature flag。

## 5. 不声称的范围

- 不声称覆盖未在 SDD §8 声明变更的 Skill（含本 CR worktree 内存在差异但 §8 未声明的项）。
- 不声称被启动 run 的业务结果正确性——该事实由行为证据原样文本（`fr14-run-behavior.md`）承载，由人工与评审消费。
- `cmd-14` 只做「线上内容 ≡ 仓库目标文件」的字节比较，不做 Skill 语义正确性结论。
