# AIFI-45 非作者独立复验第2轮 — T full + current-T M interop + DB release

Executed 2026-10-24 by balanced `Gobao/deepseek-flash/max`; `actual=unknown`.
Only new validation evidence/report was written. No source/config/CUSTOM/task-status change.
DB was used only for the M stages below and is released at the end; no later DB access.

## 1. Model configuration (native, both roots)

Command in each source root:
`D:/Program Files (x86)/Python/Python313/python.exe -B C:/Users/GOBAO/Downloads/AI/stdd/bin/stdd config models --format json`

Both exit 0, `schema_version=1`, `kind=configured`, `user_defaults_present=true`.
`balanced=Gobao/deepseek-flash`, `effort=max` in both.
Raw evidence: `revoke-independent2-{tools,multica}-models.json`.

## 2. T full independent rerun (not hash-only)

Exact argv, cwd `C:/Users/GOBAO/Downloads/AI/tools`, timeout 600s (not hit):

```text
node --test --test-reporter=tap
 skills/shared/crctl/scripts/test/execution-authorization.test.mjs
 skills/shared/crctl/scripts/test/execution-transaction.test.mjs
 skills/shared/crctl/scripts/test/durable-tx.test.mjs
```

Result: exit 0, wall 59143ms. TAP: **218 tests / 217 pass / 0 fail / 1 skip / 0 todo**.
Skip: `EXEC-12 受控文件自身为 symlink：拒绝写入 # SKIP 当前环境无法创建 symlink: EPERM`.
**Skip is not counted as pass; this is not 218/218 all-pass.** No zero-selection.
stdout/stderr are separate: `revoke-independent2-tools-20261024T132700Z.{stdout.tap,stderr.log}`;
stderr empty. Meta: `...meta.json`.

Five T files, raw and LF SHA256, identical before/after:

| file | raw SHA256 | LF SHA256 |
|---|---|---|
| `crctl.mjs` | `d064100f…ca1557` | `0b8faa40…fccf2c` |
| `lib/execution-authorization.mjs` | `71437e20…c34abc` | `71437e20…c34abc` |
| `execution-authorization.test.mjs` | `909c8759…1db1c9d` | same |
| `execution-transaction.test.mjs` | `c82c8814…a43e7cd2` | same |
| `durable-tx.test.mjs` | `7e1d82c3…8b0fef8` | `774a5db7…69dce44` |

The current P2 snapshot used by M interop is therefore `execution-authorization.mjs` LF `71437e20ddfdf33b74d3490c7129359562443555d1abc0a44886b27f32c34abc`.
The author's old `fce9c8bb…` snapshot is not reused.

Four protected files (raw bytes, unchanged before/after):

- `AI First Platform/projects/tools/config.d/quality.yaml` `25380eed…6a6fcf2`
- `tools/.stdd/binding.yaml` `31546e1a…f0cf7b`
- `AI First Platform/projects/multica/config.d/quality.yaml` `05a0e3eb…0909af`
- `multica/.stdd/binding.yaml` `ae676b9a…57186d89`

## 3. Dedicated DB acquisition and baseline

Container name `stdd-aifi45-20261022-pg`; full ID:
`666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823`.
Label `2026-10-22-aifi-45-authorized-execution`; running; port `127.0.0.1:55432`;
DB/user `stdd_aifi45_20261022/stdd`. Runner `/Temp/aifi45-gotest.cjs`, LF SHA256
`b876a383…ad4b6`; it enforces the same ID/password/env checks, sets `GOPROXY=off`,
removes `KNOWLEDGE_BASE_*`/`GITHUB_TOKEN`/`GH_TOKEN`; no dependency install.

Read-only baseline at 13:25:12Z: **83 approval rows**, 83 unique IDs, 0 advisory locks,
0 other client sessions, migrations 671/latest 642. Compared to released baseline:
`identical=true`. Evidence `revoke-independent2-before-1792848312113.json`.

## 4. M final-equivalent combinations (events, not business TCs)

All commands are exact argv from the author's meta/report, run through the strict runner;
raw JSONL/stderr/meta retained under unique names.

| stage | argv tail | exit | events RUN/PASS/FAIL/SKIP |
|---|---|---|---|
| governance | `./internal/governance -run '^(TestExecutionAuthoriz\|TestExecutionGrantCheckAgainstRealCrctlCLI\|TestDaemonAuthenticatedDeliveryRunsCrctl\|TestDaemonFetchesAndInstallsExecutionAuthorization)' -count=1 -json -shuffle=on -count=2` | 0 | 550/550/0/0 (90 top) |
| real router | `./cmd/server -run '^TestExecutionAuthorizationHeadRouter' -count=1 -json -shuffle=on -count=2` | 0 | 14/14/0/0 (4 top) |
| daemon refusal | `./internal/daemon -run '^(TestExecutionVerifierRequiresExplicitNegativeFacts\|TestClaimedExecutionTaskCannotStartOnRootAttributionAlone)$' -count=1 -json` | 0 | 2/2/0/0 |
| revoke HTTP→real Node | `./internal/governance -run '^TestExecutionAuthorizationRevokeHTTPToRealNodeCLI$' -count=1 -json` | 0 | 3/3/0/0 (1 top) |

The 550 are repeated/overlapping component events (`-count=2`); they are **not 550 business TCs**.
No failure, skip, or zero selection in these four runs. Evidence stems:
`revoke-independent2-{governance-…132658Z,router-…132725Z,consumption-…132738Z,interop-…132751Z}`.

Interop log confirms current T bytes after P2:
`crctl.mjs` LF `0b8faa40…fcf2c`, `execution-authorization.mjs` LF `71437e20…c34abc`.
It exercised current-T `--check` and `--check --check-source` for initial and revoke; revoke
`--binding-stdio` was rejected before a challenge with `EXECUTION_AUTHORIZATION_REVOKED`.
This is component interop, not production daemon revoke installation, claim, or admission.

## 5. Source/state preservation

M 29-file set from `revoke-source-manifest.json` (`e0403783…1f600d`) was hashed raw+LF before
the T run and after every M stage/final: all 29 still match the manifest; no source mutation.
T 5 files also matched every stage. Snapshots:
`revoke-independent2-snapshot-{before-tools,after-tools,after-governance,after-router,after-consumption,after-interop,after-final}.json`.

Git after completion:
- T: `main`, HEAD `9e41ad74ce631459bc007a29c3d0cdaaa1e49e75`, staged 0, status only pre-existing author changes.
- M: `main`, HEAD `f6e90ab8090c8a712c7fe2a324e977f10a39499c`, staged 0; the 29 owned files hash-match.

## 6. DB final state and release

Read-only final proof at 13:28:09Z:
- **83→83**, 83 unique IDs, missing `[]`, added `[]`, changed `0`, literal rows `identical=true`;
- no baseline deletion; no new fixture/row;
- 0 advisory locks, 0 other client sessions; migrations 671/latest 642 unchanged;
- full ID/label/DB/user/port rechecked.

Evidence `revoke-independent2-after-1792848489114.json`.
**DB is released here; no further DB access after this report. Main thread may acquire.**

## 7. Remaining boundaries

T skip is not pass. No full M suite, race, crash-kill, production deployment, Gate3, commit/push,
or business TC closure is claimed. Static vet/sqlc remain for the main thread; this run did not
run `go test -list` or any session SQL deletion. Full 49-TC completion remains **0/49**.

Index: `revoke-independent2-index.json` (contains hashes/paths of all runs and snapshots).
