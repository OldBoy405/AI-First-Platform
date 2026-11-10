# AIFI-45 WP4-2 / WP4-3 — static BLOCK record

## Disposition

**BLOCK; no product implementation.** The user has selected the original immutable reservation as the attempt identity and requires attempt-bound trusted evidence, semantic replay/conflict, unknown retention, and both trusted `no_effect` and exclusion of late execution before a new attempt. Those decisions are not being put back to the user for selection. The same instruction requires stopping if the existing contract must change. The following archived rules conflict with the requested complete behavior; a direction decision alone does not make an archived contract amendment effective:

- `projects/tools/archive/2026-10-27-trusted-verdict-channel/canonical/specs/code/trusted-merge-gate.yaml:126-133` (`SC-MG-015`): `unknown` + remote containing expected requires successful settlement, whereas the requested behavior does not attribute success to that observation alone.
- Same file `:134-139` (`SC-MG-016`): `intent` + remote prev, or `settled_no_effect` + `unknown` + remote prev, requires `not_attempted` then attempt+1 reserve. Requiring separately trusted evidence that the old attempt had no effect and cannot arrive late adds a precondition.
- `projects/multica/archive/2026-10-27-trusted-verdict-channel/canonical/specs/code/verdict-channel.yaml:317-324` (`SC-VC-035`) and `SC-MG-020`: distinguish returning the existing mapping from granting a new publishable attempt. Their relationship to SC-MG-016, and immutable settled_no_effect combined with unknown + remote expected, needs paired contract resolution; do not assume a specific priority.

The existing paired draft `remote-recovery-paired-amendment-draft-20261103.md` records these differences and is explicitly unapproved. No canonical file, code, test, or existing customization ledger entry was modified for this investigation. No claim is made that either archived behavior or the requested behavior is wired into production.

## Static inventory (current worktrees, line numbers at inspection)

Paths prefixed `multica/` and `tools/` refer to sibling repositories under `C:/Users/GOBAO/Downloads/AI/`. Both contain pre-existing uncommitted changes; preserve them.

| Path | Actual source of facts / risk |
|---|---|
| `multica/server/internal/governance/execution_merge_effect.go:109-143` | Reserve takes `cr FOR SHARE`, then reads the current authorization head/decision and hashes `MergeEffectInput` from the caller before looking up an old reservation. A changed head can block an old replay before the original identity is read. `FOR SHARE` serializes against CR updates, not concurrent reserves taking the same shared lock. |
| `execution_merge_effect.go:145-168,185-190` | Derives lineage from current request workspace+CR; finds a reservation by that lineage and caller-derived digest. Replay returns the current **count** of reservations as attempt, not the stored attempt. New attempt is also count+1, even when another digest has an unsettled reservation. No original attempt read. |
| `execution_merge_effect.go:172-182` | Stores caller-derived digest source as `candidate_bytes`, plus selection, scope, lineage and proposed task. It does not store the attempt, separate target/ref, lease, or the accepted `HeadRecordID`; the digest source covers trunk, base, candidate head, selection kind, approved source/revision, authorization head and grant digest, not necessarily an authenticated execution target or lease. |
| `multica/server/migrations/648_cr_execution_control.up.sql:54-65,170-185,549-567` | Reservation and settlement are mutation-protected; reservation is unique on `(lineage_id,candidate_digest)`. Its schema has no attempt column; same-digest new attempt cannot simply create another reservation. Settlement allows only `effect` and `no_effect`, not a separate `not_attempted` kind. Exact migration/representation requirements remain a design question, not an assertion that a new table is necessary. |
| `execution_merge_effect.go:202-229` | Merge report writes the settlement using reservation digest but caller-provided `kind`, attempt, head UUID and remote SHA; `no_effect` is accepted without an attempt-bound proof or late-writer exclusion. It uses `ON CONFLICT DO NOTHING` without checking row count or semantic equality; it does not lock the reservation. Zero matching reservations and conflicting replay can both return nil. No separate merge settlement writer was found in `server/` production Go search. |
| `multica/server/internal/governance/execution_control_reservation.go:70-133` | Separate cold-start control reservation writer: re-reads strict selection; persists provided candidate bytes/digest and proposed task. It is not shown to be the merge attempt writer. |
| `multica/server/internal/governance/execution_control_settlement.go:71-151` and `execution_channel_reader.go:41-65` | Separate control-command settlement: checks existing row before command lock and returns it without comparing the new meaning; reader skips candidate checking for an existing settlement. Current authorization decision can convert caller effect to no_effect at `execution_control_settlement.go:107-119`; this is not evidence that an already in-flight remote push had no effect. Do not conflate this command contract with merge reservation. |
| `execution_channel_admission.go:179-224` | Separate dispatch settlement INSERT and conflict readback; compares verdict/kind/effect/digest/head/ref. |
| `execution_control_policy.go:222,304,373` | Separate sensitive-action, repair-extension, resume settlement INSERTs. They have different semantics and locks; sharing a table alone does not prove they are merge writers. |
| `tools/skills/shared/crctl/scripts/lib/merge-effects.mjs:59-75,86-123,137-153,177-229` | `classifyRemote` consumes injected remote SHA/ancestor predicate; `planRecovery` consumes local journal and server input, including intent+prev → PUSH and unknown+contains expected → SETTLE_SUCCESS, and settled_no_effect+unknown+prev → reserve next. `resolveAttempt` derives last/next from journal history and caller digest. `runMergeEffect` writes unknown before injected push and reports injected result. Local static searches found definitions/tests and same-file finalize wrapper, not a production caller; dynamic/other-repo/deployed use remains unknown. |
| `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs:2036-2055,2078-2109,2149-2237` | Distinct `mergeCr` journal flow, not proven connected to the M merge reserve/report or the T helper. It uses current workspace/repository config and approval, and, during recovery, fetches current base before observing the original candidate; changed base may rebuild and overwrite the journal's `mergeSha`. The publish loop also rebuilds against current remote and uses current `repo.trunk` as target/lease ref. Receipt gating uses remote containing recorded merge SHA as `remotePublished`; this is a target-state observation, not attempt attribution. These are current-state re-derivation points for separate assessment, not proof of the same contract's production applicability. |

Original `no_effect` evidence and old-writer fencing are not established by these entry points. Append-only storage alone does not create a trusted observation, prevent a late remote writer, or prove an unknown slot is held. DB-backed concurrency and actual remote execution are not verified.

## Checks actually run

From `multica/server`, with `GOPROXY=off GOSUMDB=off GOFLAGS=-mod=readonly GOTOOLCHAIN=local`; both commands ran independently:

```
$ go version && go build ./...
go version go1.27.1 windows/amd64
go build exit=0

$ go version && go vet ./...
go version go1.27.1 windows/amd64
go vet exit=0
```

No tests were run; build/vet are not test results. No DB or network access was performed. Offline behavior, DB lock/CAS/replay concurrency, cross-end identity/attestation, actual remote/late execution and deployment compatibility remain unverified. ## strong 独立复核（2026-11-04；`Gobao/kimi-k3.1-pro:high`）

结论：**PASS，阻断成立**——不是把可变实现误当合同冲突，而是 `SC-MG-015/016` 明确要求了与已采纳方向相反的结果（`trusted-merge-gate.yaml:126-133` 要求「远端含 expected 即结算成功」；`:134-139` 要求「先 `not_attempted` 再 `attempt+1`」）。`SC-VC-035` 只是衔接待定，未夸大为直接冲突。

复核补出的 4 个漏判（原记录未点名）：

| 漏判 | 位置 | 说明 |
|---|---|---|
| `intent + contains_expected` 也冒认成功 | `tools/.../lib/merge-effects.mjs:95-100` | 不止 `unknown` 分支；同样把目标状态当本 attempt 成果 |
| 任何已终结历史都 `attempt+1` | 同文件 `:142-152` | 只看有无 unfinalized；`settled_success` 也能推到下一 attempt，未检查可信 `no_effect` 与旧 writer fencing |
| merge 的「已 settled 重放」不返回原结果 | `multica/.../execution_merge_effect.go:149-158` | 只用 `EXISTS` 判 settled，随后返回当前 `count` 与 `Replayed`，没读回 settlement kind/mapping，注释所称「返原结果」不成立 |
| command 索引不能证明 merge 已占 slot | `648_...up.sql:106-110` 只覆盖 `cr_execution_control_command`；`execution_merge_effect.go:174-182` 只插 reservation | 不能用该唯一索引推断 unknown 已占住 |

**可立即做的切片（不依赖 `SC-MG-015/016` 新恢复语义，不改变任何已批准结果）：**

1. 只读原 mapping 查询：按持久 reservation 读原字节/digest/selection/settlement，不据当前 HEAD 重新授权，不授予发布权。
2. 结算冲突拒绝：修 `execution_merge_effect.go:216-224` 的 `ON CONFLICT DO NOTHING` 零行成功与异义静默成功（与 `SC-VC-021/035` 一致）。
3. 锁后重读 + 同义重放：修 `execution_control_settlement.go:76-100,121-151` 锁前查无、等待后未重读。
4. 未知保留占用：只要存在未终结 reservation 就拒绝新开 attempt（`SC-MG-017`/`SC-VC-035` 支持）。
5. `execution_channel_reader.go:42-64` 重复查询收敛为单一入口一次字节比较。

**必须配对修订后才能做的切片**：`unknown|intent + 远端含 expected` 的归属判定、`intent + prev` 的重试、`no_effect` 复准入、`attempt+1` 任一形态。

完整 WP4-2/4-3 仍为 BLOCK；上述 1–5 也不得宣称 WP4 完成。
