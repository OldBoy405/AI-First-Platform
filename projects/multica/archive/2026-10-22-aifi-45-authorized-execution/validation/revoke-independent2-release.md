# AIFI-45 独立复验第2轮 — DB release note

Independent balanced run, 2026-10-24. Full report and index are in the T change validation:
`projects/tools/changes/2026-10-22-aifi-45-authorized-execution/validation/revoke-independent2-report.md`
and `revoke-independent2-index.json`.

Dedicated container verified by full ID:
`666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823`,
label `2026-10-22-aifi-45-authorized-execution`, running, `127.0.0.1:55432`,
`stdd_aifi45_20261022/stdd`. Strict runner `/Temp/aifi45-gotest.cjs` hash
`b876a3835fbe835fd15f73d8ddf81db9adee340f7f17308d6f2cb78ed61ad4b6`; `GOPROXY=off`.

M results (events, not business TCs): governance 550/550/0/0, real router 14/14/0/0,
daemon refusal 2/2/0/0, current-T revoke HTTP→Node interop 3/3/0/0; all exit 0.
No failure/skip/zero selection in these runs.

Baseline before `revoke-independent2-before-1792848312113.json`: 83 rows, 83 unique IDs,
0 locks, 0 other sessions, 671/latest 642.
Final `revoke-independent2-after-1792848489114.json`: 83→83, missing/added/changed = 0/0/0,
literal identical=true; 0 locks, 0 other client sessions; migrations unchanged.
No new fixture, no baseline deletion.

M 29-file source set still matches `revoke-source-manifest.json`; no source/config/CUSTOM/
task-status changes by this run. Git: `main`, HEAD `f6e90ab8090c8a712c7fe2a324e977f10a39499c`,
staged 0.

**DB released at 2026-10-24T13:28:09Z; no DB access after the final proof.**
Harness: `PI_PROVIDER=Gobao`, `PI_MODEL=deepseek-flash`, `PI_REASONING_LEVEL=max`; actual unknown.
