# Design Adjustments — 2026-11-24-upstream-sync-58352363d0

## Scope adjustment

- Original plan included a Graph visibility/degree repair (Slice 6, TC-FCB-004).
- Evidence: the Graph gap lives in files the upstream window did not change; it pre-dates this merge in the FORK.
- User directive on 2026-11-25: the goal is pulling the upstream update and merging per CUSTOM.md, without expanding into unrelated fork repairs.
- Decision: Graph work is out of scope for this change; it is not implemented or registered. `CP-FCB-004` is intentionally not executed. Gate 3 must show this as an unresolved/out-of-scope item.

## Implementation adjustments

- Inbox managed writes now pass the prepared `content` to the door instead of the raw event body; provenance, source snapshot, revision, idempotency, and permission guards are unchanged.
- `query.trace` carries the complete emitted retrieval metadata in `trace.retrieval`; MCP `_meta.retrieval` stays independent; Admin consumes `_meta` through an optional callback without changing the default response shape.
- Windows test-harness fixes normalize `\`/`/` in shard file headers, accept native drive paths and convert JUnit output with `cygpath -m`, and normalize the `relative()` path in the takes-caller census.
- Verification-script adjustments only classify intentional candidate-window paths and read Bun JUnit’s `file` attribute; no product behavior changed.

## Verification limitations

- Full `bun run test` cannot be claimed on this Windows host because the documented runner baseline executes one Bun process per file over 1145 files/shard; `test/setup.test.ts` also has documented Windows launcher failures. Targeted merge-surface batches and the `remaining` CP supply the actual signal.
- `bun run verify` retains 14 documented Windows-only baseline failures; the failing inputs are files this merge did not touch.
- No real Postgres E2E or isolated legacy-database upgrade was run; `database_upgrade_verified=False`.
