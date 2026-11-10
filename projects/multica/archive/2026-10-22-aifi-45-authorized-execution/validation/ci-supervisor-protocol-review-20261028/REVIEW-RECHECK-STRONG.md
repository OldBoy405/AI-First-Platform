# AIFI-45 supervisor-protocol — STDD strong independent recheck

Scope: read-only review of one fixed snapshot. Earlier strong-session output was treated as leads only and was not accepted as evidence.
No DB, containers, real processes, or source edits were used. The only things run were the target Node test and my own temporary probes/mutants, in `/tmp/aifiprobe`, outside the repo.

**Version boundary:** the author may currently be changing the tests or source. These conclusions apply **only** to the SHAs below. They do not cover any newer version. A changed SHA needs a new review.

## Reviewed snapshot (raw SHA-256)

| File | SHA-256 |
|---|---|
| `C:/Users/GOBAO/Downloads/AI/multica/scripts/aifi45-db/supervisor-protocol.mjs` | `bed82664f2f17918b47302a94255e3061cbce9f516f578a074a997671b75452c` |
| `C:/Users/GOBAO/Downloads/AI/multica/scripts/aifi45-db/supervisor-protocol.test.mjs` | `98c1b388a6818821a3120d2953f631196872e9c35bf9344b5e2ab7f72266aa6c` |

Environment: Node v24.15.0. Command: `node --test supervisor-protocol.test.mjs`. Result: **21 tests, 21 pass, 0 fail**.

## Overall conclusion

- The code accepts the snapshot as a narrow pure decoder that fails closed on every input I tested, **assuming intact realm intrinsics**.
- No blocking code defect was found.
- The test suite is **not sufficient** to prove these claims: snapshot semantics, bound-before-copy ordering, frame-count vs partial-header precedence, and global-intrinsic hardening.
- It also contains a vacuous assertion and loose error assertions. Status: **not accepted as verified** until the test gaps below are closed and the wording is narrowed.

## Confirmed by independent probes (this snapshot only)

- **Result shape:** every probed path returns a fresh, frozen, null-prototype object with exactly two own data properties.
  - Values are fixed strings only.
  - Error results have no inherited `reportedOutcome`, `cleanup` or `toString`.
  - No payload bytes, caller objects or exception text were observed in results (with intrinsics intact).
- **No cleanup or exit assertion:** no field or frame type can express tree-empty, OS exit or cleanup permission. Type 4 and above are rejected.
- **Forged own properties are ignored:** own `length`, `byteLength`, `byteOffset`, `buffer`, own method overrides, `constructor` and `Symbol.toStringTag` do not change the result.
- **Rejected as `INVALID_INPUT`:**
  - `Object.create(Buffer.prototype)`
  - a Proxy over a real Buffer (its `get` trap ran 0 times)
  - a revoked Proxy
  - a Proxy whose `getPrototypeOf` throws
  - a Proxy reporting `Buffer.prototype`
  - a SharedArrayBuffer-backed Buffer, including a growable SAB
  - a Buffer with a detached backing store
- **Resizable ArrayBuffer:** the length is read once and bounded before the copy.
  - A length-tracking view grown to 100000 bytes gives `TOTAL_LIMIT`.
  - A shrunk view fails closed.
- **Boundaries:**
  - A declared payload length of 0x80000000 or 1025 with no body gives `FRAME_LIMIT`.
  - Sequence 0x80000000 gives `INVALID_SEQUENCE`.
  - Reserved 0x8000 gives `INVALID_HEADER`.
  - 128 data frames + terminal give `FRAME_COUNT_LIMIT`.
  - 128 data frames + 5 bytes give `FRAME_COUNT_LIMIT`.
  - 128 data frames with no terminal give `MISSING_TERMINAL`.
  - A 65537-byte subarray gives `TOTAL_LIMIT`.

## Findings

### F1 — `decoded` semantics and misuse risk (contract / consumer)
`decoded:true` means wire decoding succeeded only. It is returned for `REJECTED`, `OUTPUT_LIMIT` and `EXITED_NONZERO` too.
A consumer writing `if (r.decoded)` could treat it as success or cleanup permission. The parser cannot prevent this, and no consumer exists yet, so this is unchecked.
Downstream code must branch on `reportedOutcome` and must never derive cleanup authority from this result.

### F2 — Intrinsic hardening is partial (code)
Only the three TypedArray getters (`buffer`, `byteOffset`, `byteLength`) are captured at module load.
These are looked up when called: `Buffer.isBuffer`, `Buffer.from`, `Uint8Array`, `Object.freeze`, `types.isSharedArrayBuffer` and `Buffer.prototype.read*`.
A probe showed that replacing `Object.freeze` with a throwing function lets an exception carrying attacker text **escape** the decoder.
So "never throws / never exposes exception text" holds only while realm globals are intact. The code comments, test header and CUSTOM.md must not claim more.

### F3 — "Buffer" is a prototype-chain check (spec gap)
These are accepted and decoded:
- a `Uint8Array` reprototyped to `Buffer.prototype`
- a subclass chained to `Buffer.prototype`

A real Buffer reprototyped to `Uint8Array.prototype` is rejected. This is not unsafe, because reads go through intrinsics and a copy, but the contract does not specify it.

### F4 — Inconsistent error for exotic backing stores (spec gap)
A detached backing store gives `INVALID_INPUT`. An out-of-bounds fixed view on a shrunk resizable ArrayBuffer gives `MISSING_TERMINAL`. Both fail closed, but neither behavior is specified or tested.

### F5 — Catch-all masks internal bugs (code)
Any internal exception maps to `INVALID_INPUT`, so a parser bug would show up as an input error.

## Test bugs and weaknesses

- **T1:** the Proxy test asserts `Number.isSafeInteger(prototypeChecks)`, which is always true, even for 0. It proves nothing about trap behavior.
- **T2:** "errors never return earlier data or attacker bytes" takes `code` from the result itself and checks only membership in a 6-value set. It does not pin the expected error for each case. Leak-freedom is covered by `assertResult`'s exact-keys check; per-case correctness is not.
- **T3:** the stdout/stderr test is titled "rejection, overflow and parse failures", but its first two inputs decode successfully. It also detects only writes through `process.stdout.write` / `process.stderr.write`, not direct fd writes or `process._rawDebug`.
- **T4:** missing cases:
  - detached, resizable or growable-SAB Buffers
  - reprototyped `Uint8Array`
  - a Proxy over a real Buffer
  - 128 frames followed by a partial header (frame-count vs partial-header precedence)
  - exactly 128 data frames with no terminal
  - tampered globals

## Mutant survivors (each passed all 21 tests on this snapshot)

| Mutant | Change | What it shows is unproven |
|---|---|---|
| M2 | Partial-header (`TRUNCATED`) check moved before the frame-count check | The stated precedence "frame count before partial header" |
| M5 | `FRAME_COUNT_LIMIT` returned at the 128-frame boundary even with no remaining bytes | The 128-data-frames/no-terminal outcome (the spec is also ambiguous) |
| M17 | Snapshot copy taken before the total-size bound | Bound-before-copy, i.e. the memory-DoS ordering |
| M19 | Snapshot removed; input read directly | The snapshot claim; it is unobservable synchronously because SAB is rejected first |
| M21 | `Buffer.isBuffer` replaced by a direct `getPrototypeOf === Buffer.prototype` check | Proxy-trap behavior (see T1) |
| M27 | Each opaque payload body copied before being discarded | "Data is discarded, not retained or copied" |

Killed for reference:
- M24: catch-all mapped to a different code
- M25: hidden non-enumerable `treeEmpty` on success
- M26: changed trailing-data code

## Explicitly not covered by this review

- Any version of either file other than the SHAs above, including the author's in-progress test changes.
- Transport, provenance authentication, streaming or collection, OS-exit or process-tree proof, and cleanup or container authorization (all out of scope by contract; nothing here supports them).
- Integration with lifecycle, the runner or a real engine. There are no consumers of `decodeSupervisorBuffer` in the repo.
- Behavior under realm or global tampering beyond the probes noted in F2, cross-realm Buffers, `vm` contexts, and worker transfer.
- Behavior on other Node versions; only v24.15.0 was used.
- Performance, resource exhaustion beyond the size bounds, and fd-level output.

## Recommended before acceptance

1. Fix T1, T2 and T3.
2. Add the T4 cases.
3. Add tests that kill M2, and M5 once the spec is settled.
4. Either add instrumentation that kills M17, M19 and M27, or remove those claims.
5. Narrow the F2 wording in the code comment, test header and CUSTOM.md entry 261.
6. Specify F3 and F4.
7. Add a consumer-side contract test for F1 once a consumer exists.
