#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/multica-test-go.XXXXXX")
BIN_DIR="$TEST_DIR/bin"
CALLS_FILE="$TEST_DIR/go-calls.log"
LIST_FILE="$TEST_DIR/go-lists.log"
OUTPUT_FILE="$TEST_DIR/output.log"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"
export MULTICA_TEST_GO_CALLS="$CALLS_FILE"
export MULTICA_TEST_GO_LISTS="$LIST_FILE"
: >"$CALLS_FILE"
: >"$LIST_FILE"

cat >"$BIN_DIR/go" <<'FAKE'
#!/usr/bin/env bash
set -eu

case "${1:-}" in
  list)
    if [ "$#" -ne 2 ] || [ "$2" != "./..." ]; then
      echo "unexpected go list arguments: $*" >&2
      exit 2
    fi
    printf '%s\n' "$*" >>"$MULTICA_TEST_GO_LISTS"
    case "${MULTICA_TEST_GO_LIST_MODE:-normal}" in
      empty) exit 0 ;;
      agent-only) printf '%s\n' github.com/multica-ai/multica/server/pkg/agent; exit 0 ;;
      fail) echo 'injected go list failure' >&2; exit 77 ;;
    esac
    printf '%s\n' \
      github.com/multica-ai/multica/server \
      github.com/multica-ai/multica/server/internal/daemon \
      github.com/multica-ai/multica/server/pkg/agent \
      github.com/multica-ai/multica/server/pkg/agent/internal/testutil
    ;;
  test)
    printf '%s\n' "$*" >>"$MULTICA_TEST_GO_CALLS"
    ;;
  *)
    echo "unexpected go command: $*" >&2
    exit 2
    ;;
esac
FAKE
chmod 755 "$BIN_DIR/go"

regular_call='test -race github.com/multica-ai/multica/server github.com/multica-ai/multica/server/internal/daemon'
agent_call='test -race -p 2 -parallel 2 ./pkg/agent/...'

# $1: case label; $2: expected go calls, one per line. Clears the log after.
expect_calls() {
  actual_calls=$(cat "$CALLS_FILE")
  if [ "$actual_calls" != "$2" ]; then
    echo "$1: unexpected go test calls:" >&2
    printf '%s\n' "$actual_calls" >&2
    exit 1
  fi
  : >"$CALLS_FILE"
  : >"$LIST_FILE"
}

# $1: case label; the rest are arguments for test-go.sh. Asserts the usage
# exit status, the usage line, and that go was never invoked.
expect_usage_failure() {
  label=$1
  shift
  set +e
  PATH="$BIN_DIR:$PATH" bash "$SCRIPT_DIR/test-go.sh" "$@" >"$OUTPUT_FILE" 2>&1
  status=$?
  set -e

  if [ "$status" -ne 2 ]; then
    echo "$label returned status $status, want 2" >&2
    cat "$OUTPUT_FILE" >&2
    exit 1
  fi
  if [ -s "$CALLS_FILE" ] || [ -s "$LIST_FILE" ]; then
    echo "$label invoked go:" >&2
    cat "$CALLS_FILE" "$LIST_FILE" >&2
    exit 1
  fi
  if ! grep -q '^usage: .*test-go.sh \[--race\] \[--only regular|agent\]$' "$OUTPUT_FILE"; then
    echo "$label did not print usage" >&2
    cat "$OUTPUT_FILE" >&2
    exit 1
  fi
}

PATH="$BIN_DIR:$PATH" bash "$SCRIPT_DIR/test-go.sh" --race
expect_calls "--race" "$regular_call
$agent_call"

PATH="$BIN_DIR:$PATH" bash "$SCRIPT_DIR/test-go.sh" --race --only regular
expect_calls "--race --only regular" "$regular_call"
PATH="$BIN_DIR:$PATH" bash "$SCRIPT_DIR/test-go.sh" --only regular --race
expect_calls "--only regular --race" "$regular_call"

# Option order must not matter: CI spells it one way, humans another.
for order in first last; do
  if [ "$order" = first ]; then
    PATH="$BIN_DIR:$PATH" bash "$SCRIPT_DIR/test-go.sh" --only agent --race
  else
    PATH="$BIN_DIR:$PATH" bash "$SCRIPT_DIR/test-go.sh" --race --only agent
  fi
  if [ -s "$LIST_FILE" ]; then
    echo "agent-only unexpectedly invoked go list" >&2
    exit 1
  fi
  expect_calls "agent-only $order" "$agent_call"
done

expect_usage_failure "unknown option" --unknown
expect_usage_failure "unknown --only scope" --only everything
expect_usage_failure "missing --only scope" --only

for mode in empty agent-only fail; do
  set +e
  MULTICA_TEST_GO_LIST_MODE="$mode" PATH="$BIN_DIR:$PATH" bash "$SCRIPT_DIR/test-go.sh" --only regular >"$OUTPUT_FILE" 2>&1
  status=$?
  set -e
  if [ "$status" -eq 0 ] || [ -s "$CALLS_FILE" ]; then
    echo "$mode: expected failure without running go test, got status $status" >&2
    cat "$OUTPUT_FILE" >&2
    exit 1
  fi
  if [ "$mode" = fail ]; then
    if [ "$status" -ne 77 ]; then
      echo "go list failure returned $status, want 77" >&2
      exit 1
    fi
  elif ! grep -q 'no regular Go packages' "$OUTPUT_FILE"; then
    echo "$mode: missing empty-package diagnostic" >&2
    cat "$OUTPUT_FILE" >&2
    exit 1
  fi
done

echo "test-go.test.sh: PASS"
