#!/usr/bin/env bash
# CR-2026-073 B-C2: item-by-item check of the 25 tests that fail in the merged tree but
# showed no failure line in the pre-merge run (whose cmd/multica package was killed by the
# default 10-minute package timeout). Re-runs exactly those tests in the pre-merge tree,
# under cond-b conditions, with -count=1 so no result is reused.
# Excluded (documented): TestRunDaemonDiskUsageJSONSurvivesServerFailure, the test that hangs
# until the 10-minute package timeout in the pre-merge tree.
set -uo pipefail

EVID="C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/knowledge-base/requirement/CR-2026-073/change-requests/CR-2026-073/test-evidence/upstream-sync/rerun/cond-b-shorttmp/premerge"
TREE="C:/Users/GOBAO/Downloads/AI/cr073-rerun/premerge"
DB=cr073_cond-b-shorttmp_premerge

PGPW=$(sed -n 's#^DATABASE_URL=postgres://multica:\([^@]*\)@.*#\1#p' "C:/Users/GOBAO/Downloads/AI/multica/.env" | head -1)
export DATABASE_URL="postgres://multica:${PGPW}@127.0.0.1:5432/${DB}?sslmode=disable"
export GOCACHE="D:/cr073-gocache/cond-b-shorttmp-premerge"
export TMPDIR="C:/rt/cond-b-shorttmp-premerge"
export TEMP="$TMPDIR"
export TMP="$TMPDIR"

MULTICA_RE='^(TestDaemonLifecycleRefusesForeignDaemon|TestDaemonLogSourcePathResolvesPerProfile|TestDaemonRefusesDaemonWithUnreadableIdentity|TestDaemonRestartUnauthenticatedFailsBeforeStopping|TestDaemonStatusKnownProfileStillReportsStopped|TestDaemonStatusNestedProfileStillProbes|TestDaemonStatusReportsPortConflictInsteadOfClaimingItsOwn|TestDaemonStatusShowsWhoManagesTheDaemon|TestDaemonStatusUnknownProfile|TestDaemonStopAcceptsDaemonWithoutProfileField|TestEnumerateDiskUsageRoots|TestEnumerateDiskUsageRootsUsesAndDeduplicatesProfileConfig|TestFileWithinWorkingDirWindowsPaths|TestGuardLocalPathLinksOnlyFiresInAgentContext|TestPrintDiskUsageOtherRootsHintFiresWhenCurrentRootNonEmpty|TestPrintDiskUsageOtherRootsHintSuggestsProfilesWithTasks|TestRequireKnownProfile|TestResolveDiskUsageRootTaskContext|TestRunDaemonDiskUsageAllProfilesUsesPerProfileToken|TestRunDaemonLogsMissingFileNamesProfilePath|TestRunRuntimeProfileSetAndUnsetPath|TestRunRuntimeProfileSetPathPreservesExistingConfig)$'

{
  echo "purpose=item-by-item recheck of the 25 tests that fail in the merged tree but produced no failure line in the pre-merge full run"
  echo "tree=$TREE head=$(git -C "$TREE" rev-parse HEAD)"
  echo "database=$DB"
  echo "tmpdir=$TMPDIR"
  echo "start=$(date -Iseconds)"
  echo "command=cd server && go test -count=1 -timeout 300s -run '<25 names minus the hanging one>' ./cmd/multica/ ./cmd/migrate/ ./internal/daemon/repocache/"
  echo "excluded=TestRunDaemonDiskUsageJSONSurvivesServerFailure (hangs to the 10m package timeout in this tree)"
  echo "---"
} > "$EVID/03-targeted-merged-only-tests.log"

cd "$TREE/server"
{
  go test -count=1 -timeout 300s -run "$MULTICA_RE" ./cmd/multica/ ./cmd/migrate/ ./internal/daemon/repocache/
  echo "targeted_exit=$?"
  echo "targeted_end=$(date -Iseconds)"
} >> "$EVID/03-targeted-merged-only-tests.log" 2>&1

echo "DONE targeted premerge"
