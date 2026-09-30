#!/usr/bin/env bash
# CR-2026-073 B-C2: rerun the full DB-backed Go suite on one of the three recorded commits.
# usage: bash run_one.sh <cond-a-tasktmp|cond-b-shorttmp> <merged|premerge|upstream>
#
# Same command shape as the recorded 7th-sync run: `go run ./cmd/migrate up`, then
# `bash scripts/test-go.sh` (no --race: this host has no gcc). No merge/rebase, no
# multica source edits. Fresh empty DB + fresh GOCACHE per tree, so every package
# executes and no result is reused from an earlier attempt.
#
# Conditions:
#   cond-a-tasktmp  = TMPDIR as inherited from this agent task
#                     (C:\Users\GOBAO\AppData\Local\Temp\multica-task-<id>)
#   cond-b-shorttmp = TMPDIR/TEMP forced to the short root C:/rt/<cond>-<tree>,
#                     to quantify the Windows long-path class of failures that the
#                     deep task temp root induces in the repo-cache/daemon tests.
#
# One documented deviation: the two pre-merge trees check out
# scripts/agent-cli-command-names.txt with CRLF (attr text=auto), which aborts the
# guard script with "invalid agent CLI command name" (the exact Windows trap CUSTOM.md
# records, fixed for the merged tree by the `eol=lf` rule in .gitattributes). Before
# running, that one file is normalized CRLF -> LF here too; content is proven identical
# after stripping \r, and the action is recorded in 00-lineendings-normalization.txt.
set -uo pipefail

COND="${1:?usage: run_one.sh <cond> <tree>}"
TREE_NAME="${2:?usage: run_one.sh <cond> <tree>}"

ROOT="C:/Users/GOBAO/Downloads/AI/cr073-rerun"
EVID="C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/knowledge-base/requirement/CR-2026-073/change-requests/CR-2026-073/test-evidence/upstream-sync/rerun"
GOCACHE_ROOT="D:/cr073-gocache"
NAMES_FILE="scripts/agent-cli-command-names.txt"

case "$TREE_NAME" in
  merged)   EXPECT_SHA=820bb5a11a53463486383c4c1f5e9c17c5a9a43e; DB=cr073_${COND##*-}_merged ;;
  premerge) EXPECT_SHA=95da7c9d7b026918fa0827652644b944a744b336; DB=cr073_${COND##*-}_premerge ;;
  upstream) EXPECT_SHA=4736a85d41b966b10ce9f60778cbfc47cecad4cb; DB=cr073_${COND##*-}_upstream ;;
  *) echo "unknown tree: $TREE_NAME" >&2; exit 2 ;;
esac
DB=$(echo "$DB" | tr -c 'a-zA-Z0-9_' '_')

TREE="$ROOT/$TREE_NAME"
ACTUAL_SHA=$(git -C "$TREE" rev-parse HEAD)
if [ "$ACTUAL_SHA" != "$EXPECT_SHA" ]; then
  echo "SHA MISMATCH for $TREE_NAME: expected $EXPECT_SHA got $ACTUAL_SHA" >&2
  exit 3
fi

OUT="$EVID/$COND/$TREE_NAME"
mkdir -p "$OUT"

# ---- temp root per condition ----
if [ "$COND" = "cond-b-shorttmp" ]; then
  export TMPDIR="C:/rt/$COND-$TREE_NAME"
  export TEMP="$TMPDIR"
  export TMP="$TMPDIR"
  mkdir -p "$TMPDIR"
fi

# ---- line-ending normalization of the guard's name list (documented deviation) ----
{
  echo "# scripts/agent-cli-command-names.txt line-ending normalization ($(date -Iseconds))"
  echo "purpose=the recorded Windows trap: the guard reads the list line-wise and a CRLF checkout gives names with a trailing \\r"
  echo "merged_tree_rule=.gitattributes pins this file to 'text eol=lf'; the two pre-merge commits check it out CRLF under core.autocrlf=true"
  echo "eol_before=$(git -C "$TREE" ls-files --eol "$NAMES_FILE")"
  echo "dirty_lines_before=$(git -C "$TREE" status --porcelain | wc -l)"
  if git -C "$TREE" ls-files --eol "$NAMES_FILE" | grep -q 'w/crlf'; then
    cp "$TREE/$NAMES_FILE" "$OUT/agent-cli-command-names.txt.orig-crlf"
    echo "sha256_before=$(sha256sum "$OUT/agent-cli-command-names.txt.orig-crlf" | awk '{print $1}')"
    sed -i 's/\r$//' "$TREE/$NAMES_FILE"
    echo "sha256_after=$(sha256sum "$TREE/$NAMES_FILE" | awk '{print $1}')"
    echo "sha256_of_orig_with_cr_stripped=$(tr -d '\r' < "$OUT/agent-cli-command-names.txt.orig-crlf" | sha256sum | awk '{print $1}')"
    if [ "$(sha256sum "$TREE/$NAMES_FILE" | awk '{print $1}')" = "$(tr -d '\r' < "$OUT/agent-cli-command-names.txt.orig-crlf" | sha256sum | awk '{print $1}')" ]; then
      echo "content_identical_after_cr_strip=yes"
    else
      echo "content_identical_after_cr_strip=NO"
    fi
    echo "action=converted CRLF -> LF (trailing \\r stripped), no other byte changed"
  else
    echo "action=none (file already LF in the working tree)"
  fi
  echo "eol_after=$(git -C "$TREE" ls-files --eol "$NAMES_FILE")"
  echo "git_status_porcelain_after_normalization="
  git -C "$TREE" status --porcelain
  echo -n "git_diff_ignore_cr_at_eol_exit_code="
  git -C "$TREE" diff --ignore-cr-at-eol --exit-code >/dev/null 2>&1; echo "$?"
} > "$OUT/00-lineendings-normalization.txt" 2>&1

PGPW=$(sed -n 's#^DATABASE_URL=postgres://multica:\([^@]*\)@.*#\1#p' "C:/Users/GOBAO/Downloads/AI/multica/.env" | head -1)
if [ -z "$PGPW" ]; then echo "no DATABASE_URL password found in multica/.env" >&2; exit 5; fi
export DATABASE_URL="postgres://multica:${PGPW}@127.0.0.1:5432/${DB}?sslmode=disable"
export GOCACHE="$GOCACHE_ROOT/$COND-$TREE_NAME"
rm -rf "$GOCACHE"   # pristine per run: no cached test results from any earlier attempt
mkdir -p "$GOCACHE"

# Fresh, empty database (dropped first so a rerun of this script is reproducible).
{
  echo "# db setup $(date -Iseconds)"
  docker exec multica-postgres psql -U multica -d multica -c "drop database if exists ${DB} (force);"
  docker exec multica-postgres psql -U multica -d multica -c "create database ${DB};"
} > "$OUT/00-db-setup.log" 2>&1
DB_SETUP_EXIT=$?

{
  echo "condition=$COND"
  echo "case=$TREE_NAME"
  echo "purpose=CR-2026-073 B-C2 upstream-sync rerun (three recorded commits, same conditions per condition set)"
  echo "tree=$TREE"
  echo "tree_head=$ACTUAL_SHA"
  echo "expected_sha=$EXPECT_SHA"
  echo "tree_dirty_lines=$(git -C "$TREE" status --porcelain | wc -l)"
  echo "database=$DB (fresh, empty at start; dropped+created in 00-db-setup.log)"
  echo "database_url=postgres://multica:***@127.0.0.1:5432/$DB?sslmode=disable"
  echo "db_setup_exit=$DB_SETUP_EXIT"
  echo "migrate_cwd=$TREE/server"
  echo "migrate_command=go run ./cmd/migrate up"
  echo "suite_cwd=$TREE"
  echo "suite_command=bash scripts/test-go.sh   # no --race: no gcc on this host"
  echo "gocache=$GOCACHE (wiped before the run: no cached test results, every package executes)"
  echo "tmpdir=${TMPDIR:-<unset>}"
  echo "tmpdir_length=$(printf %s "${TMPDIR:-<unset>}" | wc -c)"
  echo "start=$(date -Iseconds)"
  echo "go_version=$(go version)"
  echo "node_version=$(node --version)"
  echo "host_kernel=$(uname -sr)"
  echo "cpu_count=$(nproc)"
  echo "autocrlf=$(git -C "$TREE" config --get core.autocrlf)"
} > "$OUT/00-meta.txt"

cd "$TREE/server" || exit 4
go run ./cmd/migrate up > "$OUT/01-migrate.log" 2>&1
MIGRATE_EXIT=$?
{
  echo "migrate_exit=$MIGRATE_EXIT"
  echo "migrate_end=$(date -Iseconds)"
} >> "$OUT/00-meta.txt"

cd "$TREE" || exit 4
bash scripts/test-go.sh > "$OUT/02-test-go.log" 2>&1
SUITE_EXIT=$?
{
  echo "suite_exit=$SUITE_EXIT"
  echo "suite_end=$(date -Iseconds)"
  echo "test_go_log_bytes=$(wc -c < "$OUT/02-test-go.log")"
  echo "test_go_log_sha256=$(sha256sum "$OUT/02-test-go.log" | awk '{print $1}')"
  echo "migrate_log_bytes=$(wc -c < "$OUT/01-migrate.log")"
  echo "migrate_log_sha256=$(sha256sum "$OUT/01-migrate.log" | awk '{print $1}')"
  echo "cached_result_lines=$(grep -c '(cached)' "$OUT/02-test-go.log")"
} >> "$OUT/00-meta.txt"

echo "DONE $COND $TREE_NAME migrate=$MIGRATE_EXIT suite=$SUITE_EXIT"
