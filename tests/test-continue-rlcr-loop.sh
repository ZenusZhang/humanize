#!/bin/bash
#
# Tests for continue-rlcr-loop.sh
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
TESTS_PASSED=0
TESTS_FAILED=0

pass() { echo -e "${GREEN}PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; echo "  Expected: $2"; echo "  Got: $3"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

CONTINUE_SCRIPT="$PROJECT_ROOT/scripts/continue-rlcr-loop.sh"

echo "=== Test: continue-rlcr-loop ==="
echo ""

# ========================================
# NEGATIVE: No loop
# ========================================

echo "NEGATIVE TEST 1: No active loop found"
export CLAUDE_PROJECT_DIR="$TEST_DIR"

set +e
OUTPUT=$("$CONTINUE_SCRIPT" 2>&1)
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -eq 1 ]] && echo "$OUTPUT" | head -n 1 | grep -q "^NO_LOOP$"; then
    pass "No loop returns NO_LOOP with exit 1"
else
    fail "No loop" "exit 1 + first line NO_LOOP" "exit $EXIT_CODE: $(echo "$OUTPUT" | head -n 3)"
fi

# ========================================
# Setup helper
# ========================================

setup_active_loop() {
    local round="$1"
    local prompt_content="$2"

    rm -rf "$TEST_DIR/.humanize" 2>/dev/null || true
    LOOP_DIR="$TEST_DIR/.humanize/rlcr/2024-01-01_12-00-00"
    mkdir -p "$LOOP_DIR"

    cat > "$LOOP_DIR/state.md" << EOF
---
current_round: $round
max_iterations: 10
plan_file: plans/plan.md
plan_tracked: false
start_branch: main
base_branch: main
review_started: false
---
EOF

    mkdir -p "$TEST_DIR/plans"
    echo "# Plan" > "$TEST_DIR/plans/plan.md"
    echo "# Goal Tracker" > "$LOOP_DIR/goal-tracker.md"
    echo "# Round $round Summary" > "$LOOP_DIR/round-$round-summary.md"
    printf "%s\n" "$prompt_content" > "$LOOP_DIR/round-$round-prompt.md"
}

# ========================================
# POSITIVE: Prints prompt by default
# ========================================

echo "POSITIVE TEST 1: Active loop prints current prompt"
setup_active_loop "3" "# Prompt\nHello RLCR\n"
export CLAUDE_PROJECT_DIR="$TEST_DIR"

set +e
OUTPUT=$("$CONTINUE_SCRIPT" 2>&1)
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -eq 0 ]] \
    && echo "$OUTPUT" | head -n 1 | grep -q "^CONTINUE_RLCR_LOOP$" \
    && echo "$OUTPUT" | grep -q "current_round: 3" \
    && echo "$OUTPUT" | grep -q "Hello RLCR"; then
    pass "Active loop prints prompt content"
else
    fail "Active loop prints prompt" "exit 0 + marker + prompt content" "exit $EXIT_CODE: $(echo "$OUTPUT" | head -n 20)"
fi

# ========================================
# POSITIVE: --paths-only omits prompt content
# ========================================

echo "POSITIVE TEST 2: --paths-only prints paths only"
setup_active_loop "4" "THIS_SHOULD_NOT_APPEAR"
export CLAUDE_PROJECT_DIR="$TEST_DIR"

set +e
OUTPUT=$("$CONTINUE_SCRIPT" --paths-only 2>&1)
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -eq 0 ]] \
    && echo "$OUTPUT" | head -n 1 | grep -q "^CONTINUE_RLCR_LOOP$" \
    && echo "$OUTPUT" | grep -q "current_round: 4" \
    && ! echo "$OUTPUT" | grep -q "THIS_SHOULD_NOT_APPEAR"; then
    pass "--paths-only omits prompt content"
else
    fail "--paths-only" "exit 0 + no prompt body" "exit $EXIT_CODE: $(echo "$OUTPUT" | head -n 30)"
fi

# ========================================
# POSITIVE: Truncation
# ========================================

echo "POSITIVE TEST 3: Prompt truncates when exceeding max bytes"
BIG_PROMPT=$(python3 - << 'PY'
print("BEGIN")
for i in range(300):
    print("x" * 200)
print("END")
PY
)

setup_active_loop "2" "$BIG_PROMPT"
export CLAUDE_PROJECT_DIR="$TEST_DIR"

set +e
OUTPUT=$("$CONTINUE_SCRIPT" --max-prompt-bytes 1024 2>&1)
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -eq 0 ]] \
    && echo "$OUTPUT" | grep -q "\\[Prompt truncated\\]" \
    && echo "$OUTPUT" | grep -q "^BEGIN$" \
    && echo "$OUTPUT" | grep -q "^END$"; then
    pass "Truncation prints head+tail with marker"
else
    fail "Truncation" "exit 0 + truncated marker + BEGIN/END present" "exit $EXIT_CODE: $(echo "$OUTPUT" | head -n 40)"
fi

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0

