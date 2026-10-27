# 证据索引（M003）

> 本文件是 `gate3-readiness.md` §1 的**生成视图**，不独立维护：两处不一致时以 §1 为准。
> 复核方式：`node scripts/aifi45-verify/channel-evidence.mjs verify <label> <prefix> --expectations <change>/validation/channel-test-expectations.json --side <go|node> [--platform linux]`。
> 跑次前缀是相对本目录的目录名；同名前缀下还有 `.meta.json`、`.stdout.jsonl`/`.tap`、`.source.json`（源文件摘要）。

## 1. 权威证据（42 条）

| # | label | 侧 | leaves | 跑次前缀 |
|---|---|---|---|---|
| 1 | `foundation-selection` | go | 5 | `r-foundation-selection-20261027T111158Z` |
| 2 | `foundation-reservation` | go | 5 | `r-foundation-reservation-20261027T111158Z` |
| 3 | `store-guards` | go | 9 | `r-store-guards-20261027T111158Z` |
| 4 | `migration-up` | go | 14 | `r-migration-up-20261027T111158Z` |
| 5 | `migration-down` | go | 14 | `r-migration-down-20261027T111322Z` |
| 6 | `migration-reapply` | go | 14 | `r-migration-reapply-20261027T111322Z` |
| 7 | `migration-protected` | go | 2 | `r-migration-protected-20261027T111322Z` |
| 8 | `task-tx` | go | 2 | `r-task-tx-20261027T111322Z` |
| 9 | `store-state` | go | 7 | `sx-20261027T110226Z` |
| 10 | `settlement` | go | 4 | `st2-20261027T142417Z` |
| 11 | `revoked-permit` | go | 2 | `rr-20261027T112634Z` |
| 12 | `policy-facts` | go | 5 | `pj-20261027T115443Z` |
| 13 | `policy-resume` | go | 5 | `pj-20261027T115443Z` |
| 14 | `reader` | go | 11 | `rg2-20261027T143755Z` |
| 15 | `binding` | go | 6 | `bi4-20261027T144831Z` |
| 16 | `worker` | go | 7 | `wo-20261027T125625Z` |
| 17 | `client` | go | 1 | `cm-20261027T124626Z` |
| 18 | `composition` | go | 2 | `cs-20261027T124942Z` |
| 19 | `d8-recovery` | go | 2 | `dg-20261027T125558Z` |
| 20 | `readiness-protocol` | go | 3 | `rq-20261027T131611Z` |
| 21 | `readiness-activation` | go | 4 | `s3-20261027T135434Z` |
| 22 | `readiness-retirement` | go | 3 | `s4-20261027T135458Z` |
| 23 | `readiness-access` | go | 3 | `s5-20261027T135518Z` |
| 24 | `readiness-component` | go | 2 | `cc-20261027T135756Z` |
| 25 | `deployment-observer` | go | 4 | `od-20261027T140233Z` |
| 26 | `deployment-launch` | go | 1 | `lu-20261027T140438Z` |
| 27 | `readiness-composition` | go | 1 | `rd-20261027T140645Z` |
| 28 | `readiness-fresh-work` | go | 1 | `g0-20261027T141710Z` |
| 29 | `foundation-fresh-work` | go | 4 | `fz-20261027T141650Z` |
| 30 | `policy` | node | 23 | `n3-policy-20261027T142326Z` |
| 31 | `readiness` | node | 2 | `n3-readiness-20261027T142327Z` |
| 32 | `recovery` | node | 2 | `n3-recovery-20261027T142327Z` |
| 33 | `protocol` | go | 3 | `pg2-20261027T142437Z` |
| 34 | `merge-facts` | go | 6 | `mk-20261027T104452Z` |
| 35 | `merge-effects` | go | 4 | `mz-20261027T105320Z` |
| 36 | `isolation` | linux | 5 | `iso-20261027T101534Z` |
| 37 | `worker` | node | 1 | `nw-20261027T145425Z` |
| 38 | `isolation` | node / linux | 3 | `ni-20261027T145815Z` |
| 39 | `protocol` | node | 2 | `np2-20261027T142510Z` |
| 40 | `store` | node | 2 | `n-store-20261027T111459Z` |
| 41 | `merge-facts` | node | 11 | `mf2-20261027T142500Z` |
| 42 | `merge-effects` | node | 16 | `me-20261027T104637Z` |

## 2. 不属于 label 的证据

| 内容 | 位置 |
|---|---|
| Windows 目录同步（Gate 3 §4 #5） | `winsync-20261027T150008Z.log`（windows/amd64 原生 `go test`） |
| 变异归档（112 patch，107 可重放） | `mutations/`，口径见 `mutations/README.md` |
| P0 隔离与 execve 审计替代 | `p0-isolation-evidence.md`、`p0-run-20261027/` |
| Gate 3 声称/不声称口径 | `gate3-readiness.md` §7；确认记录 §8 |
| AIFI-45 六条 RUN TC 重跑前置 | `aifi45-run-tc-rerun-prerequisites.md` |

## 3. 历史前缀（不可认证当前树）

`r-foundation-*`、`migration-*`、`ac-proto-*`、`z-combined-*`、`v-tasktx-*`、`q-down-*`、`p-final-*`、`n-green-*`、`y-combined-*`
产生于 648/selection/reservation 重写或 ADJ-11 改源码之前，源码摘要已失效；保留仅作历史，**审阅时不得引用为当前通过依据**。
