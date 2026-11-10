# AIFI-45 balanced3 disposable DB final supplemental rerun

- at: 2026-10-24T16:52:38.139Z
- runner: scripts/aifi45-db/run.mjs (frozen after original-release check); cwd: C:/Users/GOBAO/Downloads/AI/multica
- container: 666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823
- preserved DB: stdd_aifi45_20261022; 82 approval rows remain post-incident state, not an 83 recovery
- governance: pkg=./internal/governance pattern=^Test; nonce=e31515b4dd2f6c71; db=aifi45_tmp_e31515b4dd2f6c71; role=aifi45_role_e31515b4dd2f6c71; exit=0; run=817; pass=817; fail=0; skip=0; leaf_pass=739; pkg_fail=0; SKIP=none; FAIL=[none]
  - original_unchanged=true; original_release={"sessions":0,"locks":0}; cleaned=true; error=null; before=after=true; tables=137; table_rows=6228; approval_rows=82; absence(database_present=false,role_present=false)
  - evidence=disposable-db-20261024T162608Z-balanced3-governance.*
- handler: pkg=./internal/handler pattern=^TestStartClaim; nonce=b442ae178ea98084; db=aifi45_tmp_b442ae178ea98084; role=aifi45_role_b442ae178ea98084; exit=0; run=13; pass=13; fail=0; skip=0; leaf_pass=10; pkg_fail=0; SKIP=none; FAIL=[none]
  - original_unchanged=true; original_release={"sessions":0,"locks":0}; cleaned=true; error=null; before=after=true; tables=137; table_rows=6228; approval_rows=82; absence(database_present=false,role_present=false)
  - evidence=disposable-db-20261024T162608Z-balanced3-handler.*
- daemon: pkg=./internal/daemon pattern=Test.*Execution; nonce=6734151f137ea2d5; db=aifi45_tmp_6734151f137ea2d5; role=aifi45_role_6734151f137ea2d5; exit=0; run=48; pass=47; fail=0; skip=1; leaf_pass=44; pkg_fail=0; SKIP={"TestExecutionTrustRefusesLinkedRootInsideWorkspace":"=== RUN   TestExecutionTrustRefusesLinkedRootInsideWorkspace | execution_trust_test.go:133: directory link unsupported: symlink C:\\Users\\GOBAO\\AppData\\Local\\Temp\\TestExecutionTrustRefusesLinkedRootInsideWorkspace1538949672\\001\\workspace\\execution-trust C:\\Users\\GOBAO\\AppData\\Local\\Temp\\TestExecutionTrustRefusesLinkedRootInsideWorkspace1538949672\\002\\home\\.multica\\execution-trust: A required privilege is not held by the client. | --- SKIP: TestExecutionTrustRefusesLinkedRootInsideWorkspace (0.00s)"}; FAIL=[none]
  - original_unchanged=true; original_release={"sessions":0,"locks":0}; cleaned=true; error=null; before=after=true; tables=137; table_rows=6228; approval_rows=82; absence(database_present=false,role_present=false)
  - evidence=disposable-db-20261024T162608Z-balanced3-daemon.*

Scope: disposable-DB supplemental rerun only; not 49 TC, 5-major, Gate3, or consumer acceptance.
Runtime: requested Gobao/deepseek-flash/max; actual backend/model receipt unknown.
DB execution authority: released after this scripted batch; no further DB commands run here.
