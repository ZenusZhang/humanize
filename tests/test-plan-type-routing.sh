#!/bin/bash
#
# Tests for plan-type routing in RLCR loop
#
# Validates:
# - --plan-type argument parsing/validation
# - state.md plan_type field persistence
# - round prompts include Codex execution routing for design plans
# - stop hook keeps routing note in follow-up prompts for design plans
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# Source shared loop library for parse_state_file checks
HOOKS_LIB_DIR="$(cd "$SCRIPT_DIR/../hooks/lib" && pwd)"
source "$HOOKS_LIB_DIR/loop-common.sh"

SETUP_SCRIPT="$PROJECT_ROOT/scripts/setup-rlcr-loop.sh"
STOP_HOOK="$PROJECT_ROOT/hooks/loop-codex-stop-hook.sh"

echo "=========================================="
echo "Plan Type Routing Tests"
echo "=========================================="
echo ""

create_mock_codex() {
    local bin_dir="$1"
    local exec_output="${2:-Need follow-up work}"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/codex" << MOCK_EOF
#!/bin/bash
if [[ "\$1" == "exec" ]]; then
    cat << 'OUT'
$exec_output
OUT
elif [[ "\$1" == "review" ]]; then
    echo "No issues found."
else
    echo "mock-codex: unsupported command \$1" >&2
    exit 1
fi
MOCK_EOF
    chmod +x "$bin_dir/codex"
}

create_plan_and_repo() {
    local repo_dir="$1"
    local plan_body="$2"

    init_test_git_repo "$repo_dir"
    mkdir -p "$repo_dir/plans"
    cat > "$repo_dir/plans/plan.md" << EOF
$plan_body
EOF
    cat > "$repo_dir/.gitignore" << 'EOF'
plans/
.humanize/
bin/
.cache/
EOF
    git -C "$repo_dir" add .gitignore
    git -C "$repo_dir" commit -q -m "Add gitignore for test artifacts"
}

# ========================================
# Test: --plan-type validation
# ========================================

setup_test_dir
create_plan_and_repo "$TEST_DIR/repo-validate" '# Plan

## Goal
Validation test.

## Acceptance Criteria
- One
- Two
- Three'
create_mock_codex "$TEST_DIR/repo-validate/bin"

set +e
OUTPUT=$(cd "$TEST_DIR/repo-validate" && PATH="$TEST_DIR/repo-validate/bin:$PATH" CLAUDE_PROJECT_DIR="$TEST_DIR/repo-validate" bash "$SETUP_SCRIPT" plans/plan.md --plan-type invalid 2>&1)
EXIT_CODE=$?
set -e
if [[ "$EXIT_CODE" -ne 0 ]] && echo "$OUTPUT" | grep -qi "invalid --plan-type value"; then
    pass "--plan-type rejects unsupported values"
else
    fail "--plan-type rejects unsupported values" "non-zero exit with validation error" "exit=$EXIT_CODE output=$OUTPUT"
fi

# ========================================
# Test: design plan type saved and prompt routed to Codex
# ========================================

setup_test_dir
create_plan_and_repo "$TEST_DIR/repo-design" '# Design Analysis Plan

## Goal
Analyze requirements and produce architecture decisions.

## Acceptance Criteria
- Documented assumptions
- Tradeoff analysis
- Decision record'
create_mock_codex "$TEST_DIR/repo-design/bin"

cd "$TEST_DIR/repo-design"
PATH="$TEST_DIR/repo-design/bin:$PATH" CLAUDE_PROJECT_DIR="$TEST_DIR/repo-design" bash "$SETUP_SCRIPT" plans/plan.md --plan-type design > /dev/null 2>&1

STATE_FILE=$(find "$TEST_DIR/repo-design/.humanize/rlcr" -name "state.md" -type f | head -1)
PROMPT_FILE=$(find "$TEST_DIR/repo-design/.humanize/rlcr" -name "round-0-prompt.md" -type f | head -1)

if [[ -n "$STATE_FILE" ]] && grep -q "^plan_type: design" "$STATE_FILE"; then
    pass "state.md stores plan_type: design"
else
    fail "state.md stores plan_type: design" "plan_type: design" "$(grep '^plan_type:' "$STATE_FILE" 2>/dev/null || echo 'missing')"
fi

if [[ -n "$PROMPT_FILE" ]] && grep -q "Execution Routing (Plan Type: design-analysis)" "$PROMPT_FILE"; then
    pass "round-0 prompt includes design routing section"
else
    fail "round-0 prompt includes design routing section" "routing section present" "missing"
fi

if [[ -n "$PROMPT_FILE" ]] && grep -q "/humanize:ask-codex" "$PROMPT_FILE"; then
    pass "round-0 prompt tells user to execute tasks via ask-codex"
else
    fail "round-0 prompt tells user to execute tasks via ask-codex" "ask-codex instruction" "missing"
fi

# ========================================
# Test: default routing remains coding
# ========================================

setup_test_dir
create_plan_and_repo "$TEST_DIR/repo-default" '# Implementation Plan

## Goal
Implement feature code and tests.

## Acceptance Criteria
- New endpoint implemented
- Tests added
- Bug fixed'
create_mock_codex "$TEST_DIR/repo-default/bin"

cd "$TEST_DIR/repo-default"
PATH="$TEST_DIR/repo-default/bin:$PATH" CLAUDE_PROJECT_DIR="$TEST_DIR/repo-default" bash "$SETUP_SCRIPT" plans/plan.md > /dev/null 2>&1

STATE_FILE=$(find "$TEST_DIR/repo-default/.humanize/rlcr" -name "state.md" -type f | head -1)
PROMPT_FILE=$(find "$TEST_DIR/repo-default/.humanize/rlcr" -name "round-0-prompt.md" -type f | head -1)

if [[ -n "$STATE_FILE" ]] && grep -q "^plan_type: coding" "$STATE_FILE"; then
    pass "state.md defaults plan_type to coding"
else
    fail "state.md defaults plan_type to coding" "plan_type: coding" "$(grep '^plan_type:' "$STATE_FILE" 2>/dev/null || echo 'missing')"
fi

if [[ -n "$PROMPT_FILE" ]] && ! grep -q "Execution Routing (Plan Type: design-analysis)" "$PROMPT_FILE"; then
    pass "coding prompt does not include design routing section"
else
    fail "coding prompt does not include design routing section" "no design routing section" "found in prompt"
fi

# ========================================
# Test: parse_state_file reads/defaults plan_type
# ========================================

setup_test_dir
mkdir -p "$TEST_DIR/state-check"
cat > "$TEST_DIR/state-check/state-with-type.md" << 'EOF'
---
current_round: 1
max_iterations: 5
review_started: false
base_branch: main
plan_tracked: false
start_branch: main
plan_type: design
---
EOF
if parse_state_file "$TEST_DIR/state-check/state-with-type.md" && [[ "${STATE_PLAN_TYPE:-}" == "design" ]]; then
    pass "parse_state_file reads plan_type"
else
    fail "parse_state_file reads plan_type" "design" "${STATE_PLAN_TYPE:-empty}"
fi

cat > "$TEST_DIR/state-check/state-without-type.md" << 'EOF'
---
current_round: 1
max_iterations: 5
review_started: false
base_branch: main
plan_tracked: false
start_branch: main
---
EOF
if parse_state_file "$TEST_DIR/state-check/state-without-type.md" && [[ "${STATE_PLAN_TYPE:-}" == "coding" ]]; then
    pass "parse_state_file defaults plan_type to coding when missing"
else
    fail "parse_state_file defaults plan_type to coding when missing" "coding" "${STATE_PLAN_TYPE:-empty}"
fi

# ========================================
# Stop hook follow-up prompt routing
# ========================================

setup_stophook_repo() {
    local repo_dir="$1"
    local plan_type="$2"

    init_test_git_repo "$repo_dir"
    mkdir -p "$repo_dir/plans"
    cat > "$repo_dir/plans/plan.md" << 'EOF'
# Routing Hook Plan

## Goal
Generate design and requirement outputs.

## Acceptance Criteria
- Produce artifacts
- Keep decisions traceable
EOF
    cat > "$repo_dir/.gitignore" << 'EOF'
plans/
.humanize/
bin/
.cache/
EOF
    git -C "$repo_dir" add .gitignore
    git -C "$repo_dir" commit -q -m "Add gitignore"

    local current_branch
    current_branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD)

    local loop_dir="$repo_dir/.humanize/rlcr/2024-02-01_12-00-00"
    mkdir -p "$loop_dir"
    cat > "$loop_dir/state.md" << EOF
---
current_round: 0
max_iterations: 10
codex_model: gpt-5.3-codex
codex_effort: xhigh
codex_timeout: 5400
push_every_round: false
plan_file: plans/plan.md
plan_type: $plan_type
plan_tracked: false
start_branch: $current_branch
base_branch: main
base_commit: abc123
review_started: false
ask_codex_question: false
full_review_round: 5
session_id:
---
EOF
    cp "$repo_dir/plans/plan.md" "$loop_dir/plan.md"
    cat > "$loop_dir/goal-tracker.md" << 'EOF'
# Goal Tracker
## IMMUTABLE SECTION
### Ultimate Goal
Route tasks correctly.
### Acceptance Criteria
| ID | Criterion |
|----|-----------|
| AC-1 | Routing note is present when required |
---
## MUTABLE SECTION
#### Active Tasks
| Task | Target AC | Status |
|------|-----------|--------|
| Route prompt | AC-1 | in_progress |
EOF
    cat > "$loop_dir/round-0-summary.md" << 'EOF'
# Round 0 Summary

Some items remain and need more work.
EOF
}

setup_test_dir
setup_stophook_repo "$TEST_DIR/hook-design" "design"
create_mock_codex "$TEST_DIR/hook-design/bin" "## Review Feedback

Issue remains unresolved.

CONTINUE"
export PATH="$TEST_DIR/hook-design/bin:$PATH"
export XDG_CACHE_HOME="$TEST_DIR/hook-design/.cache"
HOOK_INPUT='{"stop_hook_active": false, "transcript": [], "session_id": ""}'
echo "$HOOK_INPUT" | CLAUDE_PROJECT_DIR="$TEST_DIR/hook-design" bash "$STOP_HOOK" > /dev/null 2>&1 || true
NEXT_PROMPT="$TEST_DIR/hook-design/.humanize/rlcr/2024-02-01_12-00-00/round-1-prompt.md"

if [[ -f "$NEXT_PROMPT" ]] && grep -q "Execution Routing (Plan Type: design-analysis)" "$NEXT_PROMPT"; then
    pass "stop hook keeps routing note for design plans"
else
    fail "stop hook keeps routing note for design plans" "routing note in round-1 prompt" "missing"
fi

if [[ -f "$NEXT_PROMPT" ]] && grep -q "/humanize:ask-codex" "$NEXT_PROMPT"; then
    pass "stop hook design prompt includes ask-codex instruction"
else
    fail "stop hook design prompt includes ask-codex instruction" "ask-codex instruction in round-1 prompt" "missing"
fi

setup_test_dir
setup_stophook_repo "$TEST_DIR/hook-coding" "coding"
create_mock_codex "$TEST_DIR/hook-coding/bin" "## Review Feedback

Issue remains unresolved.

CONTINUE"
export PATH="$TEST_DIR/hook-coding/bin:$PATH"
export XDG_CACHE_HOME="$TEST_DIR/hook-coding/.cache"
echo "$HOOK_INPUT" | CLAUDE_PROJECT_DIR="$TEST_DIR/hook-coding" bash "$STOP_HOOK" > /dev/null 2>&1 || true
NEXT_PROMPT="$TEST_DIR/hook-coding/.humanize/rlcr/2024-02-01_12-00-00/round-1-prompt.md"

if [[ -f "$NEXT_PROMPT" ]] && ! grep -q "Execution Routing (Plan Type: design-analysis)" "$NEXT_PROMPT"; then
    pass "stop hook omits design routing note for coding plans"
else
    fail "stop hook omits design routing note for coding plans" "no design routing note in coding round-1 prompt" "found"
fi

print_test_summary "Plan Type Routing Tests"
