# AIFI-45 final-tiered independent test — 2026-10-24T12:32:49Z

## Verdict

**PASS** for the requested current-head/P2 + fixture-cleanup slice. All three sequential Go commands exited 0 with zero fail and zero skip. No production/source/business-config change was made; only this validation folder was written.

No full suite, race run, crash-kill, deployment, Gate, commit, push, shared-DB use, or external network access was performed. Complete business TC coverage remains outside this slice.

## Identity and preconditions

- Source HEAD: `f6e90ab8090c8a712c7fe2a324e977f10a39499c` (checked by wrapper before spawning).
- Container: `666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823`, label `stdd.change=2026-10-22-aifi-45-authorized-execution`, running.
- Port binding read from `.HostConfig.PortBindings['5432/tcp'][0]`: `127.0.0.1:55432`.
- DB/user: `stdd_aifi45_20261022` / `stdd`.
- Unmodified dedicated runner logic was reproduced inline: same ID/label/port/DB/user/Running checks, `GOPROXY=off`, deletion of `KNOWLEDGE_BASE_*`/`GITHUB_TOKEN`/`GH_TOKEN`, and memory-only URL construction. No password, URL, or secret was printed or saved.
- Static selection check before running: `TestExecutionAuthorizationCreatedRecordCleanupAtSubtestEnd` exists at `server/internal/governance/execution_fixture_ownership_test.go:141`; router and daemon names exist; no zero-match regex.

## Actual sequential runs (single context-mode call)

| Artifact prefix | Selected scope | Top RUN/PASS/FAIL/SKIP | Sub RUN/PASS/FAIL/SKIP | All | Exit | Wall | Go pkg |
|---|---|---:|---:|---:|---:|---:|---:|
| `governance-combo` | governance regex below, shuffle/on | 31/31/0/0 | 143/143/0/0 | 174/174/0/0 | 0 | 7.243s | 5.004s |
| `cmd-server-router` | `^TestExecutionAuthorizationHeadRouter` | 2/2/0/0 | 3/3/0/0 | 5/5/0/0 | 0 | 4.504s | 1.912s |
| `daemon-consumption` | two named daemon tests | 2/2/0/0 | 0/0/0/0 | 2/2/0/0 | 0 | 4.064s | 1.713s |

Exact argv (also saved in each `.meta.json`):

```text
go test ./internal/governance -run '^(TestExecutionAuthoriz|TestExecutionGrantCheckAgainstRealCrctlCLI|TestDaemonAuthenticatedDeliveryRunsCrctl|TestDaemonFetchesAndInstallsExecutionAuthorization)' -count=1 -json -shuffle=on
go test ./cmd/server -run '^TestExecutionAuthorizationHeadRouter' -count=1 -json
go test ./internal/daemon -run '^(TestExecutionVerifierRequiresExplicitNegativeFacts|TestClaimedExecutionTaskCannotStartOnRootAttributionAlone)$' -count=1 -json
```

Governance shuffle seed: `1792845190300760800`. The selected top-level set includes all expected names, including `TestExecutionAuthorizationCreatedRecordCleanupAtSubtestEnd`, `TestExecutionGrantCheckAgainstRealCrctlCLI`, `TestDaemonAuthenticatedDeliveryRunsCrctl`, `TestDaemonFetchesAndInstallsExecutionAuthorization`, and `TestExecutionAuthorizePersistsAndReplaysSource`. Router run selected both `...RouterConfigured` and `...RouterDefaultOff`. All three stderr files are 0 bytes.

## Protected baseline and residue

- Pre-run `approval_record` total observed: 83.
- Baseline query (read-only): `id`, `cr_id`, `md5(grant_json::text)` for `CR-9050%` plus `CR-906%`; 42 rows = 2 `CR-9050` + 2 `CR-9060` + 38 `CR-9061`.
- Before and after PSV SHA256 both `25a91fe323a424b30af7c74dda56f9acb6305dfcf094e63cb252851ed2d18599`; `cmp` identical. IDs exactly match the prior review-3 42-row baseline.
- Post-run `approval_record` total: 83. Non-baseline rows created at/after cutoff: **0**. New `cr`, `project`, `issue`, `project_resource`, `workspace`, `agent_task_queue`, `daemon_token`: **0** each.
- Note: `db-after-counts.psv` uses a broad cutoff and reports `new_approval_record|1`; that single row is protected baseline row `a2c894b3-9544-4605-9243-a54d3fa297dc` with a pre-existing future `created_at` (2026-10-25 11:54:51Z). It is present in the 42-row before/after baseline. `new-residue-after.psv` excludes the 42 protected IDs and shows `new_approval_record_nonbaseline|0`.
- No broad delete or cleanup SQL was run.

## DB release state

- Before: advisory locks 0, other sessions 0.
- After: advisory locks 0, other sessions 0.
- Migrations 671, latest `642_cr_execution_authorization_head`.

## Artifacts

All under `validation/final-tiered-20261024T123249Z/`:

| File | SHA256 |
|---|---|
| `governance-combo.go.jsonl` | `cc86cbfd271bbe0f8e711dfe0cf469c7a9d0ea047f4d8de2090350cbcc4ffcd6` |
| `governance-combo.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `governance-combo.meta.json` | `dd29af52e47f51b45cc35900ae07e363c360710476b1441deec168ed29121532` |
| `cmd-server-router.go.jsonl` | `46899ab4e7f1ec17d96b256af9d935f7a938f9a79a805dcc0b1b38711e2f86f2` |
| `cmd-server-router.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `cmd-server-router.meta.json` | `c1a874d3d01469054af62fd27c0bfbc2971d0e8d7ce2fd5a98dde96c3fafbdc5` |
| `daemon-consumption.go.jsonl` | `4a575cf267245107ef6d9552d0a6d2d2968cb5b5bb861dee23b68341b93c8c12` |
| `daemon-consumption.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `daemon-consumption.meta.json` | `dddf7f8bfaa3b0745a9282d76fe518fa33dca9458f1e1653ca2cd7dfcb5b3ee8` |
| `baseline42-before.psv` | `25a91fe323a424b30af7c74dda56f9acb6305dfcf094e63cb252851ed2d18599` |
| `baseline42-after.psv` | `25a91fe323a424b30af7c74dda56f9acb6305dfcf094e63cb252851ed2d18599` |
| `locks-before.txt` | `2ce220d8d046f85fd648a70bc8e4b330562a745e56a371ee36e2596a39f56a37` |
| `locks-after.psv` | `7c8ff1bceef887f493eed8789b4025916d8898c9e81cabf2ae3ba9bc87314d49` |
| `new-residue-after.psv` | `767882c58c518074ffb0274621ee686199ce2b1327665dad10e9bbb83ed872f1` |
| `db-after-counts.psv` | `e8e3080bc45cb7343f727a8aea4cfc11118ddddd8f3719ac4bdfed5e2083e73b` |

## Boundaries

- Scope limited to this initial current-head/P2 + fixture-cleanup slice; not a review of all 49 business TCs.
- No source, business config, runner, existing evidence, or shared library was modified.
- Harness metadata only: `PI_PROVIDER=Gobao`, `PI_MODEL=deepseek-flash`, `PI_REASONING_LEVEL=max`; actual backend identity remains unknown.
