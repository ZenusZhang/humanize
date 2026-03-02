#!/bin/bash
#
# Tests for /humanize:gen-batch-prompt helper.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SETUP_SCRIPT="$SCRIPT_DIR/../scripts/setup-rlcr-loop.sh"
GEN_SCRIPT="$SCRIPT_DIR/../scripts/gen-batch-prompt.sh"

create_task_table_plan_repo() {
    local repo_dir="$1"
    init_test_git_repo "$repo_dir"
    mkdir -p "$repo_dir/temp"
    cat > "$repo_dir/temp/plan.md" << 'EOF'
# Test Plan

| Priority | Task ID | Description | Owner | Files | blockedBy |
|----------|---------|-------------|-------|-------|-----------|
| P1 | task1 | Implement setup preflight | claude | scripts/setup-rlcr-loop.sh | - |
| P1 | task2 | Add matrix generation | codex | scripts/setup-worktree-teams.sh | task1 |
EOF
    echo "temp/" > "$repo_dir/.gitignore"
    (
        cd "$repo_dir"
        git add .gitignore
        git commit -q -m "Add gitignore"
    )
}

echo "=========================================="
echo "Gen Batch Prompt Tests"
echo "=========================================="
echo ""

# ========================================
# Test: script outputs lane tasks when marked parallelizable=yes
# ========================================

setup_test_dir
create_task_table_plan_repo "$TEST_DIR/project"

cd "$TEST_DIR/project"
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams temp/plan.md > /dev/null 2>&1 || true

ACTIVE_LOOP_DIR=$(find "$TEST_DIR/project/.humanize/rlcr" -mindepth 1 -maxdepth 1 -type d | head -1)
ASSIGN_FILE="$ACTIVE_LOOP_DIR/worktree-assignment.md"

if [[ ! -f "$ASSIGN_FILE" ]]; then
    fail "setup created worktree-assignment.md" "assignment file exists" "not found"
else
    # Flip task1 to parallelizable=yes so it appears in output
    tmp_file=$(mktemp)
    sed 's/| task1 | no |/| task1 | yes |/' "$ASSIGN_FILE" > "$tmp_file"
    mv "$tmp_file" "$ASSIGN_FILE"

    OUTPUT=$(CLAUDE_PROJECT_DIR="$TEST_DIR/project" bash "$GEN_SCRIPT" --loop-dir "$ACTIVE_LOOP_DIR")

    if echo "$OUTPUT" | grep -q 'Paste the next section into Claude Code `/batch`'; then
        pass "output includes /batch instruction header"
    else
        fail "output includes /batch instruction header" "header line present" "$OUTPUT"
    fi

    if echo "$OUTPUT" | grep -q "### Lane worker-1"; then
        pass "output includes worker lane section"
    else
        fail "output includes worker lane section" "Lane worker-1 section" "$OUTPUT"
    fi

    if echo "$OUTPUT" | grep -q "task1: Implement setup preflight"; then
        pass "output includes task description from plan table"
    else
        fail "output includes task description from plan table" "task1 description line" "$OUTPUT"
    fi
fi

print_test_summary "Gen Batch Prompt Tests"
