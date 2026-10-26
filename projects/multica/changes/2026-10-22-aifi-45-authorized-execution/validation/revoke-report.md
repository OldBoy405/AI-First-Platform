# AIFI-45 M revoke — stopped writer handoff

## Status and stop boundary

Source root: `C:/Users/GOBAO/Downloads/AI/multica`.

Stopped new development and test expansion on the user's corrected authoring-ownership instruction. All previously started Go test processes had already returned normally; their `t.Cleanup` callbacks completed. No process was killed, no source reset/restoration was performed, and no additional tests, vet, or generator runs were started after the stop. Closeout only read DB state/Git/source and wrote this writer's validation artifacts.

No T source/protocol, CUSTOM, main-thread records, Gate, commit, push, shared DB, production deployment, or real CR was changed. Full business completion remains **0/49**, **5 major unresolved**. No freshness, claim, isolation, budget, receipt, execution admission, extension, migration, or resume was enabled. The production daemon installer remains initial-only.

## Implemented M narrow slice

- Real authenticated workspace `POST /execution-authorization/revoke`, using existing Auth, membership, owner/admin and human-actor rules; real task-token and locally verified cloud machine credentials are rejected despite forged headers.
- Exact five-key body and separate exact 21-key `ExecutionRevokePayload`, without making initial fields optional. Existing record/source schemas and original signature byte domain are retained.
- Reason is preserved, not trimmed: Unicode White_Space emptiness, UTF-8 byte bound 4096, TAB/CR/LF allowed, other C0/C1 rejected. A small raw JSON-string surrogate check precedes reliance on decoded values; legal JSON `\/`, paired surrogate and BOM-only cases are accepted. Existing strict JSON scanner is reused.
- CR-row-locked current initial verification, terminal revoke history (`stage=execution,decision=reject`), append then old independent record-ID CAS in the same transaction. Exact committed actor/raw replay precedes current-head checking and never repairs a missing pointer. Different raw/owner conflicts. Existing revoke history prevents a second revoke even if a damaged pointer is rolled back to initial; duplicate committed revoke histories fail closed.
- `/head` uses a repeatable-read, read-only transaction to validate purpose-specific revoke and the referenced initial signature/source/scope/lineage/digest/revision/contract in one snapshot. It returns `purpose=revoke`, not active permission. Initial history GET and initial historical replay retain their semantics; replay cannot overwrite/rebuild the head.
- No new migration. Existing installed **sqlc v1.31.1** generated queries offline once, exit 0. A repeat generation/determinism check was not run before stopping.

Owned semantic source/test changes are listed with exact current hashes in `revoke-source-manifest.json`: **13 files** (7 changed from the old 23-file union, 6 new); the other **16/23** old files are unchanged. The three final run source snapshots match current source. Production additions/changes:

- `server/internal/governance/execution_authorization_revoke.go`
- `server/internal/governance/execution_authorization_head.go`
- `server/internal/governance/execution_authorization_routes.go`
- `server/pkg/db/queries/approval.sql`
- `server/pkg/db/generated/approval.sql.go`

Tests: five new `execution_authorization_revoke*_test.go` files; existing head/router tests and `execution_fixture_ownership_test.go`. The shared ownership helper now derives approve/reject from the created purpose, then tracks/deletes only exact record ID + workspace + CR + stage. New revoke fixtures never sweep history by CR scope. The configured router fixture also changed to exact owned history IDs.

**Generated EOL rewrites left for the main thread:** the one sqlc invocation additionally rewrote 12 initially clean generated files. `revoke-generated-rewrites.json` proves all 12 are CRLF→LF-normalized identical to HEAD and records raw/current/head hashes. They were deliberately not restored after the stop instruction. Do not reset the other pre-existing generated changes when handling these files.

## Actual RED → GREEN and retained failures

1. `revoke-http-red-20261024T124956Z.*`: RUN 1 / PASS 0 / FAIL 1 / SKIP 0, exit 1. Initial issuance succeeded; actual failure was **authenticated revoke POST=404, want 201**. Not a compiler failure or zero selection.
2. `revoke-http-green-20261024T125225Z.*`: 1/1, exit 0. Same first test reached real revoke 201 and DaemonAuth head 200/revoke, with original-byte signature/source checks.
3. `revoke-terminal-history-red-20261024T130053Z.*`: RUN 3 / FAIL 3, exit 1 (parent plus two leaves). Duplicate exact committed history incorrectly returned 200; a pointer rolled back to initial incorrectly allowed a second 201. Minimal history uniqueness/terminal guards made `revoke-terminal-history-green-20261024T130123Z.*` 3/3, exit 0.

All intermediate failures remain separate, not overwritten or called product RED/GREEN:

- `revoke-request-boundaries-*`: empty RawMessage fixture mistakenly failed marshaling the missing-key case; fixed to delete the key. Final 45/45.
- `revoke-history-chain-*`: DB-actor corruption fixture initially used a nonexistent user and hit an existing FK; replaced with an owned real human fixture. Final 23/23.
- `revoke-head-regression-*`: the old initial-with-reject-decision case expected query-filtered 404; the expanded query now reads reject records and strict purpose validation returns 409. The assertion now explicitly expects invalid-head 409, never success. This does not change historical initial GET.
- `revoke-real-router-*`: reusing a Go response struct merged initial's source map into revoke's map; the test now clears the record before decoding. Final router 7/7.
- `revoke-http-node-interop-*`: successful check/source-check for both purposes preceded a test parser failure because noncheck errors are JSON on stderr, not stdout. The harness now parses the appropriate stream. Final 3/3.

## Executed component coverage

Progressive groups passed: request/raw boundaries **45/45**, real actors **9/9**, history/chain **23/23**, predecessor/concurrency/transaction/lost-response **16/16**, exact CAS miss rollback **1/1**. These are overlapping component events, not independent business TCs.

The concurrency test observes both HTTP transactions waiting on the real CR row lock before releasing it. Same actor/raw returns 201+200 with the same packet; different raw/owner returns 201+409. Fixture CHECK failures cover history INSERT and head UPDATE rollback. A fixture trigger moves the pointer between INSERT and CAS: CAS misses, and both inserted history and the induced pointer move roll back. All fixture DDL is removed. Lost response uses a response writer returning `io.ErrClosedPipe` after commit; it is not TCP disconnect or crash-kill evidence.

Final runs, before the stop instruction:

| Evidence stem | Scope | RUN/PASS/FAIL/SKIP | Top RUN | Exit |
| --- | --- | --- | --- | --- |
| `revoke-governance-final-20261024T131116Z` | authorization/head/revoke/source/real crctl/delivery; shuffle, count2 | 550/550/0/0 | 90 | 0 |
| `revoke-router-final-20261024T131156Z` | configured + default-off actual server router; shuffle, count2 | 14/14/0/0 | 4 | 0 |
| `revoke-consumption-final-20261024T131206Z` | daemon consumption-refusal pair | 2/2/0/0 | 2 | 0 |

Each stem has original `.go.jsonl`, `.stderr.log`, `.meta.json` with exact argv, actual exit, elapsed time, counts and source hashes. `revoke-evidence-index.json` indexes raw runs without normalization; `revoke-closeout-index.json` additionally covers this report and the generated-rewrite addendum. No full suite, race, crash-kill, independent review, final vet/diff-check, or deployment validation was run.

## HTTP → temporary trust root → real Node snapshot evidence

`TestExecutionAuthorizationRevokeHTTPToRealNodeCLI` reads real authenticated HTTP records/public keys, directly installs only test wrappers into a temporary trust root, and calls real T CLI. Initial raw request contains literal `repair_limit:-0`; revoke contains emoji, TAB and CRLF. Both --check and --check --check-source yield the expected purpose, digest and negative bound/current-head facts. Noncheck revoke with --binding-stdio rejects before a challenge. Workspace/trust file inventories remain unchanged.

This passed only against the T snapshots logged by the test, including core hashes:

- crctl.mjs LF SHA256 `0b8faa403504a0abbabd42495dfefdee908adcab111f9f20a9a807ef64fccf2c`
- execution-authorization.mjs LF SHA256 `fce9c8bb85f0ce625e52a4c49a24425794b85db3bdb2f87586a946fefc021ee8`

**The subsequently reported T numeric precision P2 remains for the main thread. These snapshot results are not a full-chain PASS or post-P2 validation.**

Reusable public test fixtures (no private key/credentials):

- `revoke-http-fixtures/initial-9c3d0286-69ac-4a29-ac45-08ca66acc1d3/`
- `revoke-http-fixtures/revoke-e5e541a0-af63-443e-93ea-614067e79ca8/`

Each includes HTTP JSON, `execution-authorization-record/v1` record, envelope, `structured-human-request/v1` source, original `source-raw.bin`, and public PEM. Their actual source/payload bytes are not line-ending-normalized. This is not a production daemon revoke-install test or trusted claim proof.

## DB ownership and release

Exclusive dedicated container `666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823`, matching change label, loopback 55432, `stdd_aifi45_20261022/stdd`. Secrets stayed in memory; runner unchanged, GOPROXY=off.

At acquisition the current full approval history was **83**, not just the older protected 42. Preserved all 83 exact IDs/content hashes:

- before: `revoke-before-1792846143009.json`
- after first GREEN: `revoke-after-first-green-1792846374762.json`
- released: `revoke-released-1792847645625.json`

Final comparison: **83→83, identical=true**, no added/removed/changed approval history. All new revoke-fixture history was removed by exact owned cleanup; the original head regression fixtures retain their existing cleanup implementation. At **2026-10-24T13:14:05.624Z**, read-only final proof shows **0 advisory locks, 0 other client sessions**, migrations **671/latest642** unchanged. That connection ended normally; no later DB access by this writer. **DB released to the main thread.**

## Concrete continuation for the main thread

1. Review/finish the reported T numeric precision P2, capture the new T hashes, then reacquire the dedicated DB exclusively before rerunning `^TestExecutionAuthorizationRevokeHTTPToRealNodeCLI$` and the relevant selected regressions. Do not reuse this old-snapshot result as post-fix proof.
2. Review this M narrow implementation and the explicit 404→409 invalid initial-head assertion change. Run the pending static checks (`go vet ./internal/governance ./cmd/server`, owned `git diff --check`, offline sqlc repeat/determinism), and handle only the 12 proven EOL-only generated rewrites if desired. The prepared temporary static script was **not executed**.
3. Independent review remains outstanding. Keep claim/budget/receipt/credential isolation and execution admission fail-closed; no major or business TC closure from these component tests.

Harness only: `PI_PROVIDER=OpenAIPersonal`, `PI_MODEL=gpt-6.1-sol`, `PI_REASONING_LEVEL=high`. Actual backend identity **unknown**.
