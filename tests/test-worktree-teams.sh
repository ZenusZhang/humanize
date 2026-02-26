#!/bin/bash
#
# Tests for worktree-team orchestration in RLCR loop.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# Source shared loop library
HOOKS_LIB_DIR="$(cd "$SCRIPT_DIR/../hooks/lib" && pwd)"
source "$HOOKS_LIB_DIR/loop-common.sh"

echo "=========================================="
echo "Worktree Teams Feature Tests"
echo "=========================================="
echo ""

SETUP_SCRIPT="$SCRIPT_DIR/../scripts/setup-rlcr-loop.sh"
WORKTREE_SETUP_SCRIPT="$SCRIPT_DIR/../scripts/setup-worktree-teams.sh"
STOP_HOOK="$SCRIPT_DIR/../hooks/loop-codex-stop-hook.sh"

create_gitignored_plan_repo() {
    local repo_dir="$1"
    init_test_git_repo "$repo_dir"
    mkdir -p "$repo_dir/temp"
    cat > "$repo_dir/temp/plan.md" << 'EOF'
# Test Plan

Task line 1
Task line 2
Task line 3
Task line 4
Task line 5
EOF
    echo "temp/" > "$repo_dir/.gitignore"
    (
        cd "$repo_dir"
        git add .gitignore
        git commit -q -m "Add gitignore"
    )
}

# ========================================
# Test: --worktree-teams requires --agent-teams
# ========================================

setup_test_dir
create_gitignored_plan_repo "$TEST_DIR/project"

cd "$TEST_DIR/project"
set +e
SETUP_OUTPUT=$(CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" bash "$SETUP_SCRIPT" --worktree-teams temp/plan.md 2>&1)
SETUP_EXIT=$?
set -e

if [[ "$SETUP_EXIT" -ne 0 ]]; then
    pass "--worktree-teams fails without --agent-teams"
else
    fail "--worktree-teams fails without --agent-teams" "non-zero exit" "exit 0"
fi
if echo "$SETUP_OUTPUT" | grep -q "requires --agent-teams"; then
    pass "validation message mentions --agent-teams requirement"
else
    fail "validation message mentions --agent-teams requirement" "requires --agent-teams" "$SETUP_OUTPUT"
fi

# ========================================
# Test: --worktree-root requires --worktree-teams
# ========================================

setup_test_dir
create_gitignored_plan_repo "$TEST_DIR/project"

cd "$TEST_DIR/project"
set +e
SETUP_OUTPUT=$(CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-root .humanize/custom-root temp/plan.md 2>&1)
SETUP_EXIT=$?
set -e

if [[ "$SETUP_EXIT" -ne 0 ]]; then
    pass "--worktree-root fails without --worktree-teams"
else
    fail "--worktree-root fails without --worktree-teams" "non-zero exit" "exit 0"
fi
if echo "$SETUP_OUTPUT" | grep -q "requires --worktree-teams"; then
    pass "validation message mentions --worktree-teams requirement"
else
    fail "validation message mentions --worktree-teams requirement" "requires --worktree-teams" "$SETUP_OUTPUT"
fi

# ========================================
# Test: --worktree-root rejects traversal and missing value
# ========================================

setup_test_dir
create_gitignored_plan_repo "$TEST_DIR/project"

cd "$TEST_DIR/project"
set +e
SETUP_OUTPUT=$(CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams --worktree-root ../escape temp/plan.md 2>&1)
SETUP_EXIT=$?
set -e

if [[ "$SETUP_EXIT" -ne 0 ]] && echo "$SETUP_OUTPUT" | grep -q "must stay within the project directory"; then
    pass "--worktree-root rejects parent-directory traversal"
else
    fail "--worktree-root rejects parent-directory traversal" "traversal rejection error" "$SETUP_OUTPUT"
fi

BAD_ROOT=$'.humanize/worktrees/\tbad'
set +e
SETUP_OUTPUT=$(CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams --worktree-root "$BAD_ROOT" temp/plan.md 2>&1)
SETUP_EXIT=$?
set -e

if [[ "$SETUP_EXIT" -ne 0 ]] && echo "$SETUP_OUTPUT" | grep -q "contains unsupported characters"; then
    pass "--worktree-root rejects control characters"
else
    fail "--worktree-root rejects control characters" "unsupported characters error" "$SETUP_OUTPUT"
fi

set +e
SETUP_OUTPUT=$(CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams --worktree-root --max 10 temp/plan.md 2>&1)
SETUP_EXIT=$?
set -e

if [[ "$SETUP_EXIT" -ne 0 ]] && echo "$SETUP_OUTPUT" | grep -q "requires a relative path argument"; then
    pass "--worktree-root rejects flag-like missing value"
else
    fail "--worktree-root rejects flag-like missing value" "relative path argument error" "$SETUP_OUTPUT"
fi

set +e
SETUP_OUTPUT=$(CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams --skip-impl temp/plan.md 2>&1)
SETUP_EXIT=$?
set -e

if [[ "$SETUP_EXIT" -ne 0 ]] && echo "$SETUP_OUTPUT" | grep -q "cannot be used with --skip-impl"; then
    pass "--worktree-teams rejects --skip-impl combination"
else
    fail "--worktree-teams rejects --skip-impl combination" "skip-impl incompatibility error" "$SETUP_OUTPUT"
fi

setup_test_dir
create_gitignored_plan_repo "$TEST_DIR/project"
mkdir -p "$TEST_DIR/outside"
ln -s "$TEST_DIR/outside" "$TEST_DIR/project/temp/link-out"

cd "$TEST_DIR/project"
set +e
SETUP_OUTPUT=$(CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams --worktree-root temp/link-out/worktrees temp/plan.md 2>&1)
SETUP_EXIT=$?
set -e

if [[ "$SETUP_EXIT" -ne 0 ]] && echo "$SETUP_OUTPUT" | grep -q "resolves outside project root"; then
    pass "--worktree-root rejects symlink escape outside project"
else
    fail "--worktree-root rejects symlink escape outside project" "symlink traversal rejection error" "$SETUP_OUTPUT"
fi

set +e
SETUP_OUTPUT=$(CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams --worktree-root . temp/plan.md 2>&1)
SETUP_EXIT=$?
set -e

if [[ "$SETUP_EXIT" -ne 0 ]] && echo "$SETUP_OUTPUT" | grep -q "must not target repository root"; then
    pass "--worktree-root rejects repository root"
else
    fail "--worktree-root rejects repository root" "repository root rejection error" "$SETUP_OUTPUT"
fi

set +e
SETUP_OUTPUT=$(CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams --worktree-root ./ temp/plan.md 2>&1)
SETUP_EXIT=$?
set -e

if [[ "$SETUP_EXIT" -ne 0 ]] && (echo "$SETUP_OUTPUT" | grep -q "must not target repository root" || echo "$SETUP_OUTPUT" | grep -q "contains unsupported characters"); then
    pass "--worktree-root rejects normalized repository root variants"
else
    fail "--worktree-root rejects normalized repository root variants" "repository root rejection error" "$SETUP_OUTPUT"
fi

set +e
SETUP_OUTPUT=$(CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams --worktree-root .git/worktrees/custom temp/plan.md 2>&1)
SETUP_EXIT=$?
set -e

if [[ "$SETUP_EXIT" -ne 0 ]] && echo "$SETUP_OUTPUT" | grep -q "must not target repository root"; then
    pass "--worktree-root rejects .git internals"
else
    fail "--worktree-root rejects .git internals" ".git rejection error" "$SETUP_OUTPUT"
fi

set +e
SETUP_OUTPUT=$(CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams --worktree-root ./.git/worktrees/custom temp/plan.md 2>&1)
SETUP_EXIT=$?
set -e

if [[ "$SETUP_EXIT" -ne 0 ]] && echo "$SETUP_OUTPUT" | grep -q "must not target repository root"; then
    pass "--worktree-root rejects normalized .git variants"
else
    fail "--worktree-root rejects normalized .git variants" ".git rejection error" "$SETUP_OUTPUT"
fi

# ========================================
# Test: setup records worktree state and prompt guidance
# ========================================

setup_test_dir
create_gitignored_plan_repo "$TEST_DIR/project"

cd "$TEST_DIR/project"
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams temp/plan.md > /dev/null 2>&1 || true

STATE_FILE=$(find "$TEST_DIR/project/.humanize/rlcr" -name "state.md" -type f 2>/dev/null | head -1)
PROMPT_FILE=$(find "$TEST_DIR/project/.humanize/rlcr" -name "round-0-prompt.md" -type f 2>/dev/null | head -1)

if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
    if grep -q "^worktree_teams: true" "$STATE_FILE"; then
        pass "state.md records worktree_teams: true"
    else
        fail "state.md records worktree_teams: true" "worktree_teams: true" "$(grep '^worktree_teams:' "$STATE_FILE" || echo 'missing')"
    fi
    if grep -q "^worktree_root: .humanize/worktrees/" "$STATE_FILE"; then
        pass "state.md records default worktree_root"
    else
        fail "state.md records default worktree_root" "worktree_root under .humanize/worktrees/" "$(grep '^worktree_root:' "$STATE_FILE" || echo 'missing')"
    fi
else
    fail "state.md exists after setup" "state file path" "not found"
fi

setup_test_dir
mkdir -p "$TEST_DIR/loop"
cat > "$TEST_DIR/loop/state.md" << 'EOF'
---
current_round: 0
max_iterations: 10
review_started: false
base_branch: main
plan_tracked: false
start_branch: main
worktree_root: ".humanize/worktrees/quoted"
---
EOF
if parse_state_file "$TEST_DIR/loop/state.md" && [[ "${STATE_WORKTREE_ROOT:-}" == ".humanize/worktrees/quoted" ]]; then
    pass "parse_state_file strips wrapping quotes from worktree_root"
else
    fail "parse_state_file strips wrapping quotes from worktree_root" ".humanize/worktrees/quoted" "${STATE_WORKTREE_ROOT:-empty}"
fi

cat > "$TEST_DIR/loop/state-legacy.md" << 'EOF'
---
current_round: 1
max_iterations: 10
review_started: false
base_branch: main
plan_tracked: false
start_branch: main
---
EOF
if parse_state_file "$TEST_DIR/loop/state-legacy.md" && [[ "${STATE_WORKTREE_TEAMS:-}" == "false" && -z "${STATE_WORKTREE_ROOT:-}" ]]; then
    pass "parse_state_file keeps backward compatibility for missing worktree fields"
else
    fail "parse_state_file keeps backward compatibility for missing worktree fields" "worktree_teams=false and empty root" "worktree_teams=${STATE_WORKTREE_TEAMS:-empty}, root=${STATE_WORKTREE_ROOT:-empty}"
fi

if [[ -n "$PROMPT_FILE" && -f "$PROMPT_FILE" ]]; then
    if grep -qi "Parallelization Matrix" "$PROMPT_FILE"; then
        pass "round-0 prompt includes explicit parallelization matrix instructions"
    else
        fail "round-0 prompt includes explicit parallelization matrix instructions" "Parallelization Matrix text" "not found"
    fi
    if grep -qi "git worktree" "$PROMPT_FILE"; then
        pass "round-0 prompt includes git worktree instructions"
    else
        fail "round-0 prompt includes git worktree instructions" "git worktree text" "not found"
    fi
else
    fail "round-0 prompt exists after setup" "round-0-prompt.md exists" "not found"
fi

# ========================================
# Test: --worktree-root is persisted
# ========================================

setup_test_dir
create_gitignored_plan_repo "$TEST_DIR/project"

cd "$TEST_DIR/project"
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams --worktree-root .humanize/custom-wt temp/plan.md > /dev/null 2>&1 || true

STATE_FILE=$(find "$TEST_DIR/project/.humanize/rlcr" -name "state.md" -type f 2>/dev/null | head -1)
if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
    if grep -q "^worktree_root: .humanize/custom-wt$" "$STATE_FILE"; then
        pass "--worktree-root value is stored in state.md"
    else
        fail "--worktree-root value is stored in state.md" "worktree_root: .humanize/custom-wt" "$(grep '^worktree_root:' "$STATE_FILE" || echo 'missing')"
    fi
else
    fail "state.md exists for custom worktree root test" "state file path" "not found"
fi

# ========================================
# Test: setup-worktree-teams script provisions lanes
# ========================================

setup_test_dir
create_gitignored_plan_repo "$TEST_DIR/project"

cd "$TEST_DIR/project"
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    bash "$SETUP_SCRIPT" --agent-teams --worktree-teams temp/plan.md > /dev/null 2>&1 || true

ACTIVE_LOOP_DIR=$(find "$TEST_DIR/project/.humanize/rlcr" -mindepth 1 -maxdepth 1 -type d | head -1)
if [[ -z "$ACTIVE_LOOP_DIR" ]]; then
    fail "active loop directory exists for worktree setup script test" "loop dir path" "not found"
else
    CLAUDE_PROJECT_DIR="$TEST_DIR/project" bash "$WORKTREE_SETUP_SCRIPT" --workers 2 --reviewers 1 > /dev/null 2>&1 || true

    ASSIGN_FILE="$ACTIVE_LOOP_DIR/worktree-assignment.md"
    if [[ -f "$ASSIGN_FILE" ]]; then
        pass "setup-worktree-teams writes worktree-assignment.md"
    else
        fail "setup-worktree-teams writes worktree-assignment.md" "assignment file exists" "not found"
    fi

    if [[ -d "$TEST_DIR/project/.humanize/worktrees/$(basename "$ACTIVE_LOOP_DIR")/worker-1" ]]; then
        pass "worker-1 worktree directory is created"
    else
        fail "worker-1 worktree directory is created" "worker-1 directory exists" "not found"
    fi

    if [[ -d "$TEST_DIR/project/.humanize/worktrees/$(basename "$ACTIVE_LOOP_DIR")/reviewer-1" ]]; then
        pass "reviewer-1 worktree directory is created"
    else
        fail "reviewer-1 worktree directory is created" "reviewer-1 directory exists" "not found"
    fi

    if grep -q "worker-1" "$ASSIGN_FILE" && grep -q "reviewer-1" "$ASSIGN_FILE"; then
        pass "assignment file lists worker and reviewer lanes"
    else
        fail "assignment file lists worker and reviewer lanes" "worker-1 and reviewer-1 entries" "$(cat "$ASSIGN_FILE" 2>/dev/null || echo 'missing')"
    fi
fi

# ========================================
# Test: stop hook adds worktree continuation in implementation phase
# ========================================

setup_test_dir
setup_stophook_test() {
    setup_test_dir
    cd "$TEST_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git config commit.gpgsign false
    echo "init" > init.txt
    git add init.txt
    git -c commit.gpgsign=false commit -q -m "Initial"

    mkdir -p plans
    cat > plans/test-plan.md << 'PLAN_EOF'
# Test Plan

This is a test plan with enough content.
Line 3 with meaningful content.
Line 4 with more content.
Line 5 final content line.
PLAN_EOF

    cat > .gitignore << 'GI_EOF'
plans/
.humanize/
bin/
.cache/
GI_EOF
    git add .gitignore
    git -c commit.gpgsign=false commit -q -m "Add gitignore"

    LOOP_DIR="$TEST_DIR/.humanize/rlcr/2026-01-01_00-00-00"
    mkdir -p "$LOOP_DIR"

    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    cat > "$LOOP_DIR/state.md" << STATE_EOF
---
current_round: 3
max_iterations: 42
codex_model: gpt-5.3-codex
codex_effort: xhigh
codex_timeout: 300
push_every_round: false
full_review_round: 5
plan_file: plans/test-plan.md
plan_tracked: false
start_branch: $CURRENT_BRANCH
base_branch: main
base_commit: abc123
review_started: false
ask_codex_question: false
session_id:
agent_teams: true
worktree_teams: true
worktree_root: .humanize/worktrees/2026-01-01_00-00-00
---
STATE_EOF
    cp plans/test-plan.md "$LOOP_DIR/plan.md"
    cat > "$LOOP_DIR/goal-tracker.md" << 'GT_EOF'
# Goal Tracker
## IMMUTABLE SECTION
### Ultimate Goal
Test
### Acceptance Criteria
| ID | Criterion |
|----|-----------|
| AC-1 | Pass |
---
## MUTABLE SECTION
#### Active Tasks
| Task | Target AC | Status |
|------|-----------|--------|
| Test | AC-1 | completed |
GT_EOF
    cat > "$LOOP_DIR/round-3-summary.md" << 'SUM_EOF'
# Round Summary
done
SUM_EOF
}

setup_mock_codex_impl_feedback() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/codex" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "exec" ]]; then
cat << 'REVIEW'
## Review Feedback

- Issue 1: Missing validation

Please address and try again.

CONTINUE
REVIEW
else
echo "No issues"
fi
MOCK_EOF
    chmod +x "$TEST_DIR/bin/codex"
    export PATH="$TEST_DIR/bin:$PATH"
}

setup_stophook_test
setup_mock_codex_impl_feedback
export XDG_CACHE_HOME="$TEST_DIR/.cache"

HOOK_INPUT='{"stop_hook_active": false, "transcript": [], "session_id": ""}'
set +e
echo "$HOOK_INPUT" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$STOP_HOOK" > /dev/null 2>&1
HOOK_EXIT=$?
set -e

NEXT_PROMPT="$LOOP_DIR/round-4-prompt.md"
if [[ -f "$NEXT_PROMPT" ]]; then
    if grep -qi "Worktree Teams Continuation" "$NEXT_PROMPT"; then
        pass "stop hook adds worktree continuation template in implementation phase"
    else
        fail "stop hook adds worktree continuation template in implementation phase" "Worktree Teams Continuation text" "not found"
    fi
    if grep -qi "parallelizable" "$NEXT_PROMPT"; then
        pass "continuation prompt enforces explicit parallelizable labels"
    else
        fail "continuation prompt enforces explicit parallelizable labels" "parallelizable text" "not found"
    fi
else
    fail "round-4 prompt exists after stop hook in worktree mode" "round-4-prompt.md exists" "not found (hook exit=$HOOK_EXIT)"
fi

# Verify malformed worktree_root values from state are not injected into prompts
setup_stophook_test
awk '{
    if ($0 ~ /^worktree_root:/) {
        print "worktree_root: ../unsafe"
    } else {
        print
    }
}' "$LOOP_DIR/state.md" > "$LOOP_DIR/state.tmp"
mv "$LOOP_DIR/state.tmp" "$LOOP_DIR/state.md"
setup_mock_codex_impl_feedback
export XDG_CACHE_HOME="$TEST_DIR/.cache"

set +e
echo "$HOOK_INPUT" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$STOP_HOOK" > /dev/null 2>&1
HOOK_EXIT=$?
set -e

NEXT_PROMPT="$LOOP_DIR/round-4-prompt.md"
if [[ -f "$NEXT_PROMPT" ]]; then
    if ! grep -q "Current worktree root from state" "$NEXT_PROMPT"; then
        pass "stop hook skips malformed worktree_root values from state"
    else
        fail "stop hook skips malformed worktree_root values from state" "no worktree_root state echo" "found malformed root echo in prompt"
    fi
else
    fail "round-4 prompt exists for malformed worktree_root test" "round-4-prompt.md exists" "not found (hook exit=$HOOK_EXIT)"
fi

setup_stophook_test
awk '{
    if ($0 ~ /^worktree_root:/) {
        print "worktree_root: /tmp/outside-root"
    } else {
        print
    }
}' "$LOOP_DIR/state.md" > "$LOOP_DIR/state.tmp"
mv "$LOOP_DIR/state.tmp" "$LOOP_DIR/state.md"
setup_mock_codex_impl_feedback
export XDG_CACHE_HOME="$TEST_DIR/.cache"

set +e
echo "$HOOK_INPUT" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$STOP_HOOK" > /dev/null 2>&1
HOOK_EXIT=$?
set -e

NEXT_PROMPT="$LOOP_DIR/round-4-prompt.md"
if [[ -f "$NEXT_PROMPT" ]]; then
    if ! grep -q "Current worktree root from state" "$NEXT_PROMPT"; then
        pass "stop hook skips absolute worktree_root values from state"
    else
        fail "stop hook skips absolute worktree_root values from state" "no absolute worktree_root state echo" "found absolute root echo in prompt"
    fi
else
    fail "round-4 prompt exists for absolute worktree_root test" "round-4-prompt.md exists" "not found (hook exit=$HOOK_EXIT)"
fi

# ========================================
# Template existence checks
# ========================================

if [[ -f "$SCRIPT_DIR/../prompt-template/claude/worktree-teams-instructions.md" ]]; then
    pass "worktree-teams-instructions template exists"
else
    fail "worktree-teams-instructions template exists" "template file" "missing"
fi

if [[ -f "$SCRIPT_DIR/../prompt-template/claude/worktree-teams-continue.md" ]]; then
    pass "worktree-teams-continue template exists"
else
    fail "worktree-teams-continue template exists" "template file" "missing"
fi

WORKTREE_COMMAND_FILE="$SCRIPT_DIR/../commands/setup-worktree-teams.md"
if [[ -f "$WORKTREE_COMMAND_FILE" ]]; then
    pass "setup-worktree-teams command wrapper exists"
else
    fail "setup-worktree-teams command wrapper exists" "command file" "missing"
fi

if [[ -f "$WORKTREE_COMMAND_FILE" ]] && grep -q "scripts/setup-worktree-teams.sh" "$WORKTREE_COMMAND_FILE"; then
    pass "setup-worktree-teams command wrapper references setup script"
else
    fail "setup-worktree-teams command wrapper references setup script" "script reference" "missing"
fi

print_test_summary "Worktree Teams Feature Tests"
