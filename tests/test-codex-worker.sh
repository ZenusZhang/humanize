#!/bin/bash
#
# Tests for codex-worker.sh using a mock codex binary.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CODEX_WORKER_SCRIPT="$SCRIPT_DIR/../scripts/codex-worker.sh"
CODEX_WORKER_SKILL="$SCRIPT_DIR/../skills/codex-worker/SKILL.md"

echo "=========================================="
echo "Codex Worker Tests (mock)"
echo "=========================================="
echo ""

setup_test_dir

MOCK_PROJECT="$TEST_DIR/project"
init_test_git_repo "$MOCK_PROJECT"

MOCK_BIN_DIR="$TEST_DIR/mock-bin"
mkdir -p "$MOCK_BIN_DIR"

cat > "$MOCK_BIN_DIR/codex" << 'MOCK_EOF'
#!/bin/bash
if [[ -n "${MOCK_CODEX_ARGS_FILE:-}" ]]; then
    printf '%s\n' "$*" > "$MOCK_CODEX_ARGS_FILE"
fi
if [[ -n "${MOCK_CODEX_STDERR:-}" ]]; then
    echo "$MOCK_CODEX_STDERR" >&2
fi
if [[ -n "${MOCK_CODEX_STDOUT:-}" ]]; then
    echo "$MOCK_CODEX_STDOUT"
fi
cat > /dev/null
exit "${MOCK_CODEX_EXIT_CODE:-0}"
MOCK_EOF
chmod +x "$MOCK_BIN_DIR/codex"

export MOCK_CODEX_EXIT_CODE=""
export MOCK_CODEX_STDOUT=""
export MOCK_CODEX_STDERR=""
export MOCK_CODEX_ARGS_FILE=""

reset_mock() {
    export MOCK_CODEX_EXIT_CODE="0"
    export MOCK_CODEX_STDOUT=""
    export MOCK_CODEX_STDERR=""
    export MOCK_CODEX_ARGS_FILE=""
}

run_codex_worker() {
    (
        cd "$MOCK_PROJECT"
        export CLAUDE_PROJECT_DIR="$MOCK_PROJECT"
        export XDG_CACHE_HOME="$TEST_DIR/cache"
        PATH="$MOCK_BIN_DIR:$PATH" bash "$CODEX_WORKER_SCRIPT" "$@"
    )
}

assert_file_contains() {
    local description="$1"
    local pattern="$2"
    local file="$3"
    if [[ -f "$file" ]] && grep -q -- "$pattern" "$file"; then
        pass "$description"
    else
        fail "$description" "$pattern in $file" "$(cat "$file" 2>/dev/null || echo missing)"
    fi
}

echo "--- Validation Tests ---"
echo ""

EXIT_CODE=0
OUTPUT=$(run_codex_worker 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 1 ]] && echo "$OUTPUT" | grep -q "No task/instructions provided"; then
    pass "empty task exits 1 with error message"
else
    fail "empty task exits 1 with error message" "exit 1 + missing task error" "exit=$EXIT_CODE output=$OUTPUT"
fi

EXIT_CODE=0
OUTPUT=$(run_codex_worker --help 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]] && echo "$OUTPUT" | grep -q "USAGE"; then
    pass "--help exits 0 with usage info"
else
    fail "--help exits 0 with usage info" "exit 0 + USAGE" "exit=$EXIT_CODE output=$OUTPUT"
fi

EXIT_CODE=0
OUTPUT=$(run_codex_worker --bad-flag test 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 1 ]] && echo "$OUTPUT" | grep -q "Unknown option"; then
    pass "unknown option exits 1"
else
    fail "unknown option exits 1" "exit 1 + Unknown option" "exit=$EXIT_CODE output=$OUTPUT"
fi

EXIT_CODE=0
OUTPUT=$(run_codex_worker --worker-model 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 1 ]] && echo "$OUTPUT" | grep -q "requires a MODEL:EFFORT"; then
    pass "--worker-model without argument exits 1"
else
    fail "--worker-model without argument exits 1" "exit 1 + missing MODEL:EFFORT" "exit=$EXIT_CODE output=$OUTPUT"
fi

EXIT_CODE=0
OUTPUT=$(run_codex_worker --worker-timeout 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 1 ]] && echo "$OUTPUT" | grep -q "requires a number"; then
    pass "--worker-timeout without argument exits 1"
else
    fail "--worker-timeout without argument exits 1" "exit 1 + missing timeout" "exit=$EXIT_CODE output=$OUTPUT"
fi

EXIT_CODE=0
OUTPUT=$(run_codex_worker --worker-timeout nope test 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 1 ]] && echo "$OUTPUT" | grep -q "must be a positive integer"; then
    pass "--worker-timeout rejects non-numeric values"
else
    fail "--worker-timeout rejects non-numeric values" "exit 1 + integer validation" "exit=$EXIT_CODE output=$OUTPUT"
fi

EXIT_CODE=0
OUTPUT=$(run_codex_worker --workdir 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 1 ]] && echo "$OUTPUT" | grep -q "requires a path argument"; then
    pass "--workdir without argument exits 1"
else
    fail "--workdir without argument exits 1" "exit 1 + missing path" "exit=$EXIT_CODE output=$OUTPUT"
fi

EXIT_CODE=0
OUTPUT=$(run_codex_worker --worker-model 'bad;model' test 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 1 ]] && echo "$OUTPUT" | grep -q "invalid characters"; then
    pass "invalid worker model exits 1"
else
    fail "invalid worker model exits 1" "exit 1 + invalid model characters" "exit=$EXIT_CODE output=$OUTPUT"
fi

EXIT_CODE=0
OUTPUT=$(run_codex_worker --worker-model 'gpt-5.4:bad;effort' test 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 1 ]] && echo "$OUTPUT" | grep -q "invalid characters"; then
    pass "invalid worker effort exits 1"
else
    fail "invalid worker effort exits 1" "exit 1 + invalid effort characters" "exit=$EXIT_CODE output=$OUTPUT"
fi

echo ""
echo "--- Successful Run Tests ---"
echo ""

reset_mock
export MOCK_CODEX_STDOUT="Worker completed successfully"
STDOUT=$(run_codex_worker "Implement the requested change" 2>/dev/null)
if echo "$STDOUT" | grep -q "Worker completed successfully"; then
    pass "successful run outputs worker response to stdout"
else
    fail "successful run outputs worker response to stdout" "Worker completed successfully" "$STDOUT"
fi

SKILL_DIRS=$(find "$MOCK_PROJECT/.humanize/skill" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
LATEST_DIR=$(printf '%s\n' "$SKILL_DIRS" | tail -1)
assert_file_contains "successful run creates output.md with worker response" "Worker completed successfully" "$LATEST_DIR/output.md"
assert_file_contains "successful run creates metadata.md with status: success" "status: success" "$LATEST_DIR/metadata.md"
assert_file_contains "successful run saves task to input.md" "Implement the requested change" "$LATEST_DIR/input.md"

reset_mock
ARGS_FILE="$TEST_DIR/codex-args.txt"
mkdir -p "$MOCK_PROJECT/subdir"
export MOCK_CODEX_STDOUT="workdir ok"
export MOCK_CODEX_ARGS_FILE="$ARGS_FILE"
run_codex_worker --workdir "$MOCK_PROJECT/subdir" "Implement from subdir" > /dev/null 2>&1
assert_file_contains "codex-worker forwards explicit workdir to codex exec" "-C $MOCK_PROJECT/subdir" "$ARGS_FILE"

reset_mock
ARGS_FILE="$TEST_DIR/default-args.txt"
export MOCK_CODEX_STDOUT="defaults ok"
export MOCK_CODEX_ARGS_FILE="$ARGS_FILE"
run_codex_worker "Check default worker model" > /dev/null 2>&1
assert_file_contains "codex-worker uses default gpt-5.4 model" "-m gpt-5.4" "$ARGS_FILE"
assert_file_contains "codex-worker uses default xhigh effort" "model_reasoning_effort=xhigh" "$ARGS_FILE"

echo ""
echo "--- Error Handling Tests ---"
echo ""

reset_mock
export MOCK_CODEX_EXIT_CODE="42"
export MOCK_CODEX_STDERR="worker failed"
EXIT_CODE=0
run_codex_worker "propagate failure" > /dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 42 ]]; then
    pass "codex-worker propagates non-zero codex exit code"
else
    fail "codex-worker propagates non-zero codex exit code" "exit 42" "exit=$EXIT_CODE"
fi

LATEST_DIR=$(find "$MOCK_PROJECT/.humanize/skill" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1)
assert_file_contains "codex-worker error writes metadata status: error" "status: error" "$LATEST_DIR/metadata.md"

reset_mock
export MOCK_CODEX_STDOUT=""
EXIT_CODE=0
run_codex_worker "empty response" > /dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 1 ]]; then
    pass "empty worker response exits 1"
else
    fail "empty worker response exits 1" "exit 1" "exit=$EXIT_CODE"
fi

LATEST_DIR=$(find "$MOCK_PROJECT/.humanize/skill" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1)
assert_file_contains "empty worker response writes metadata status: empty_response" "status: empty_response" "$LATEST_DIR/metadata.md"

echo ""
echo "--- Loop Marker Tests ---"
echo ""

setup_test_dir
MARKER_PROJECT="$TEST_DIR/marker-project"
init_test_git_repo "$MARKER_PROJECT"
mkdir -p "$MARKER_PROJECT/.humanize/rlcr/2026-01-02_00-00-00"
LOOP_DIR="$MARKER_PROJECT/.humanize/rlcr/2026-01-02_00-00-00"
cat > "$LOOP_DIR/state.md" << 'STATE_EOF'
---
current_round: 2
max_iterations: 42
review_started: false
---
STATE_EOF

mkdir -p "$TEST_DIR/marker-bin"
cat > "$TEST_DIR/marker-bin/codex" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "exec" ]]; then
    cat > /dev/null
    echo "Worker completed"
    exit 0
fi
exit 1
MOCK_EOF
chmod +x "$TEST_DIR/marker-bin/codex"

set +e
WORKER_OUTPUT=$(
    cd "$MARKER_PROJECT" && \
    PATH="$TEST_DIR/marker-bin:$PATH" XDG_CACHE_HOME="$TEST_DIR/marker-cache" \
        bash "$CODEX_WORKER_SCRIPT" "Implement marker behavior test"
)
WORKER_EXIT=$?
set -e

if [[ "$WORKER_EXIT" -eq 0 ]]; then
    pass "codex-worker succeeds inside an active loop"
else
    fail "codex-worker succeeds inside an active loop" "exit 0" "exit $WORKER_EXIT"
fi

if [[ -f "$LOOP_DIR/.worker-invoked-round-2" ]]; then
    pass "codex-worker creates round marker in active loop"
else
    fail "codex-worker creates round marker in active loop" ".worker-invoked-round-2 exists" "not found"
fi

if echo "$WORKER_OUTPUT" | grep -q "Worker completed"; then
    pass "codex-worker returns stdout inside an active loop"
else
    fail "codex-worker returns stdout inside an active loop" "Worker completed in stdout" "$WORKER_OUTPUT"
fi

setup_test_dir
NOLOOP_PROJECT="$TEST_DIR/no-loop-project"
init_test_git_repo "$NOLOOP_PROJECT"
mkdir -p "$NOLOOP_PROJECT/.humanize/rlcr"

mkdir -p "$TEST_DIR/no-loop-bin"
cat > "$TEST_DIR/no-loop-bin/codex" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "exec" ]]; then
    cat > /dev/null
    echo "Worker completed"
    exit 0
fi
exit 1
MOCK_EOF
chmod +x "$TEST_DIR/no-loop-bin/codex"

set +e
WORKER_OUTPUT=$(
    cd "$NOLOOP_PROJECT" && \
    PATH="$TEST_DIR/no-loop-bin:$PATH" XDG_CACHE_HOME="$TEST_DIR/no-loop-cache" \
        bash "$CODEX_WORKER_SCRIPT" "Implement outside-loop marker behavior test"
)
WORKER_EXIT=$?
set -e

if [[ "$WORKER_EXIT" -eq 0 ]]; then
    pass "codex-worker succeeds outside an active loop"
else
    fail "codex-worker succeeds outside an active loop" "exit 0" "exit $WORKER_EXIT"
fi

if [[ -z "$(find "$NOLOOP_PROJECT/.humanize/rlcr" -name '.worker-invoked-round-*' -print 2>/dev/null)" ]]; then
    pass "codex-worker does not create a round marker outside an active loop"
else
    fail "codex-worker does not create a round marker outside an active loop" "no .worker-invoked-round-* files" "$(find "$NOLOOP_PROJECT/.humanize/rlcr" -name '.worker-invoked-round-*' -print 2>/dev/null | tr '\n' ' ')"
fi

if echo "$WORKER_OUTPUT" | grep -q "Worker completed"; then
    pass "codex-worker returns stdout outside an active loop"
else
    fail "codex-worker returns stdout outside an active loop" "Worker completed in stdout" "$WORKER_OUTPUT"
fi

echo ""
echo "--- Skill Wrapper Tests ---"
echo ""

if grep -Fq 'Never run this unsafe form' "$CODEX_WORKER_SKILL" && grep -Fq '"${CLAUDE_PLUGIN_ROOT}/scripts/codex-worker.sh" $ARGUMENTS' "$CODEX_WORKER_SKILL"; then
    pass "codex-worker skill warns against bare \$ARGUMENTS shell expansion"
else
    fail "codex-worker skill warns against bare \$ARGUMENTS shell expansion" "explicit unsafe-form warning" "missing"
fi

if grep -Fq '"${CLAUDE_PLUGIN_ROOT}/scripts/codex-worker.sh" "$ARGUMENTS"' "$CODEX_WORKER_SKILL"; then
    pass "codex-worker skill documents quoted single-argument invocation"
else
    fail "codex-worker skill documents quoted single-argument invocation" "quoted invocation present" "not found"
fi

if grep -Fq 'one quoted final argument' "$CODEX_WORKER_SKILL"; then
    pass "codex-worker skill requires one quoted final argument for free-form text"
else
    fail "codex-worker skill requires one quoted final argument for free-form text" "quoted final argument guidance" "missing"
fi

print_test_summary "Codex Worker Test Summary"
