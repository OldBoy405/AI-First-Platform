# AIFI-45 balanced2 disposable DB rerun

- at: 2026-10-24T16:48:21.382Z
- runner: scripts/aifi45-db/run.mjs (frozen); cwd: C:/Users/GOBAO/Downloads/AI/multica
- container: 666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823
- preserved DB: stdd_aifi45_20261022 (read-only snapshot; 82 approval rows are post-incident state, not a 83 recovery)
- note: governance completed in the first bounded batch (runner checks passed); that batch then stopped on a harness typo that subtracted the 82 approval rows from the 6228 table-row sum. Governance was not rerun; handler/daemon ran in this follow-up. No runner anomaly.
- governance: pkg=./internal/governance pattern=^Test; nonce=35fbfe726b26cbf4; db=aifi45_tmp_35fbfe726b26cbf4; role=aifi45_role_35fbfe726b26cbf4; exit=0; run=817; pass=817; fail=0; skip=0; leaf_pass=739; pkg_fail=0; SKIP=[none]; FAIL=[none]
  - original_unchanged=true; cleaned=true; error=null; before=after=true; tables=137; table_rows=6228; approval_rows=82; last_event=resources-absence-verified(database_present=false,role_present=false)
  - evidence=disposable-db-20261024T162608Z-balanced2-governance.*
- handler: pkg=./internal/handler pattern=^TestStartClaim; nonce=9dd86b9aec38842c; db=aifi45_tmp_9dd86b9aec38842c; role=aifi45_role_9dd86b9aec38842c; exit=0; run=13; pass=13; fail=0; skip=0; leaf_pass=10; pkg_fail=0; SKIP=[none]; FAIL=[none]
  - original_unchanged=true; cleaned=true; error=null; before=after=true; tables=137; table_rows=6228; approval_rows=82; last_event=resources-absence-verified(database_present=false,role_present=false)
  - evidence=disposable-db-20261024T162608Z-balanced2-handler.*
- daemon: pkg=./internal/daemon pattern=Test.*Execution; nonce=e15036af089776c0; db=aifi45_tmp_e15036af089776c0; role=aifi45_role_e15036af089776c0; exit=0; run=48; pass=47; fail=0; skip=1; leaf_pass=44; pkg_fail=0; SKIP=[TestExecutionTrustRefusesLinkedRootInsideWorkspace]; FAIL=[none]
  - original_unchanged=true; cleaned=true; error=null; before=after=true; tables=137; table_rows=6228; approval_rows=82; last_event=resources-absence-verified(database_present=false,role_present=false)
  - evidence=disposable-db-20261024T162608Z-balanced2-daemon.*

Scope: disposable-DB dynamic rerun only. This is not evidence of 49 TC, 5-major, Gate3, or consumer acceptance.
Runtime: requested Gobao/deepseek-flash/max; actual backend/model receipt unknown.
DB execution authority: released after this scripted batch; no further DB commands run here.
