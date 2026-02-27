#!/bin/bash
#
# Tests for project-level BitLesson workflow integration
#
# Validates:
# - bitlesson.md schema file exists with required fields
# - bitlesson-selector agent exists with valid frontmatter and stable output format
# - setup-rlcr-loop initializes project bitlesson.md and injects round-0 requirements
# - next-round prompt preserves BitLesson selector requirements
# - stop hook blocks summaries missing BitLesson Delta
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SETUP_SCRIPT="$PROJECT_ROOT/scripts/setup-rlcr-loop.sh"
STOP_HOOK="$PROJECT_ROOT/hooks/loop-codex-stop-hook.sh"

echo "=========================================="
echo "BitLesson Workflow Tests"
echo "=========================================="
echo ""

create_mock_codex() {
    local bin_dir="$1"
    local exec_output="${2:-Need follow-up changes

CONTINUE}"
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

# ========================================
# Test 1: BitLesson assets exist and are structured
# ========================================

if [[ -f "$PROJECT_ROOT/bitlesson.md" ]]; then
    pass "bitlesson.md exists in repository root"
else
    fail "bitlesson.md exists in repository root" "file exists" "not found"
fi

if [[ -f "$PROJECT_ROOT/bitlesson.md" ]] && \
   grep -q "Lesson ID" "$PROJECT_ROOT/bitlesson.md" && \
   grep -q "Problem Description" "$PROJECT_ROOT/bitlesson.md" && \
   grep -q "Root Cause" "$PROJECT_ROOT/bitlesson.md" && \
   grep -q "Solution" "$PROJECT_ROOT/bitlesson.md" && \
   grep -q "Constraints" "$PROJECT_ROOT/bitlesson.md" && \
   grep -q "Validation Evidence" "$PROJECT_ROOT/bitlesson.md" && \
   grep -q "Source Rounds" "$PROJECT_ROOT/bitlesson.md"; then
    pass "bitlesson.md contains strict lesson schema fields"
else
    fail "bitlesson.md contains strict lesson schema fields" "all required fields" "missing one or more"
fi

SELECTOR_FILE="$PROJECT_ROOT/agents/bitlesson-selector.md"
if [[ -f "$SELECTOR_FILE" ]]; then
    pass "bitlesson-selector agent file exists"
else
    fail "bitlesson-selector agent file exists" "file exists" "not found"
fi

if [[ -f "$SELECTOR_FILE" ]] && grep -q "^name: bitlesson-selector$" "$SELECTOR_FILE"; then
    pass "bitlesson-selector has correct name frontmatter"
else
    fail "bitlesson-selector has correct name frontmatter" "name: bitlesson-selector" "missing or different"
fi

if [[ -f "$SELECTOR_FILE" ]] && grep -q "^description:" "$SELECTOR_FILE" && grep -q "^model:" "$SELECTOR_FILE"; then
    pass "bitlesson-selector has required frontmatter fields"
else
    fail "bitlesson-selector has required frontmatter fields" "description and model" "missing"
fi

if [[ -f "$SELECTOR_FILE" ]] && grep -q "LESSON_IDS:" "$SELECTOR_FILE" && grep -q "RATIONALE:" "$SELECTOR_FILE"; then
    pass "bitlesson-selector defines stable output format"
else
    fail "bitlesson-selector defines stable output format" "LESSON_IDS and RATIONALE format" "missing"
fi

# ========================================
# Test 2: Setup initializes project-level bitlesson and round-0 requirements
# ========================================

setup_test_dir
init_test_git_repo "$TEST_DIR/project"
mkdir -p "$TEST_DIR/project/plans" "$TEST_DIR/project/bin"
cat > "$TEST_DIR/project/plans/plan.md" << 'EOF'
# BitLesson Plan

## Goal
Ship a small feature safely.

## Acceptance Criteria
- AC-1: Feature works
- AC-2: Validation is documented

## Task Breakdown
| Task ID | Description | Target AC | Tag (`coding`/`analyze`) | Depends On |
|---------|-------------|-----------|----------------------------|------------|
| task1 | Implement feature | AC-1 | coding | - |
| task2 | Analyze behavior | AC-2 | analyze | task1 |
EOF
cat > "$TEST_DIR/project/.gitignore" << 'EOF'
plans/
.humanize/
bin/
.cache/
EOF
git -C "$TEST_DIR/project" add .gitignore
git -C "$TEST_DIR/project" commit -q -m "Add gitignore"
create_mock_codex "$TEST_DIR/project/bin"

cd "$TEST_DIR/project"
PATH="$TEST_DIR/project/bin:$PATH" CLAUDE_PROJECT_DIR="$TEST_DIR/project" bash "$SETUP_SCRIPT" plans/plan.md > /dev/null 2>&1

if [[ -f "$TEST_DIR/project/bitlesson.md" ]]; then
    pass "setup initializes project-level bitlesson.md when missing"
else
    fail "setup initializes project-level bitlesson.md when missing" "bitlesson.md created" "not found"
fi

# Keep stop-hook tests focused on BitLesson logic, not git-clean gating.
git -C "$TEST_DIR/project" add bitlesson.md
git -C "$TEST_DIR/project" commit -q -m "Track bitlesson template for test"

LOOP_DIR=$(find "$TEST_DIR/project/.humanize/rlcr" -mindepth 1 -maxdepth 1 -type d | head -1)
PROMPT_FILE="$LOOP_DIR/round-0-prompt.md"
STATE_FILE="$LOOP_DIR/state.md"

if [[ -f "$PROMPT_FILE" ]] && grep -q "BitLesson Selection (REQUIRED BEFORE EXECUTION)" "$PROMPT_FILE"; then
    pass "round-0 prompt includes BitLesson selection section"
else
    fail "round-0 prompt includes BitLesson selection section" "section present" "missing"
fi

if [[ -f "$PROMPT_FILE" ]] && grep -q "bitlesson-selector" "$PROMPT_FILE"; then
    pass "round-0 prompt requires bitlesson-selector invocation"
else
    fail "round-0 prompt requires bitlesson-selector invocation" "bitlesson-selector text" "missing"
fi

if [[ -f "$STATE_FILE" ]] && grep -q "^bitlesson_required: true$" "$STATE_FILE" && grep -q "^bitlesson_file: bitlesson.md$" "$STATE_FILE"; then
    pass "state file records bitlesson requirement fields"
else
    fail "state file records bitlesson requirement fields" "bitlesson_required/bitlesson_file set" "missing"
fi

# ========================================
# Test 3: Team/worktree templates enforce selector constraints
# ========================================

for template in \
    "$PROJECT_ROOT/prompt-template/claude/agent-teams-core.md" \
    "$PROJECT_ROOT/prompt-template/claude/agent-teams-continue.md" \
    "$PROJECT_ROOT/prompt-template/claude/worktree-teams-instructions.md" \
    "$PROJECT_ROOT/prompt-template/claude/worktree-teams-continue.md" \
    "$PROJECT_ROOT/prompt-template/claude/next-round-prompt.md"
do
    if [[ -f "$template" ]] && grep -q "bitlesson-selector" "$template"; then
        pass "$(basename "$template") includes bitlesson-selector constraint"
    else
        fail "$(basename "$template") includes bitlesson-selector constraint" "contains bitlesson-selector" "missing"
    fi
done

# ========================================
# Test 4: Next-round prompt keeps BitLesson requirements
# ========================================

# Move loop to round 1 so stop hook skips round-0 goal tracker initialization check
sed -i 's/^current_round: 0$/current_round: 1/' "$STATE_FILE"
cat > "$LOOP_DIR/round-1-summary.md" << 'EOF'
# Round 1 Summary

Implemented follow-up fixes.

## BitLesson Delta
- Action: none
- Lesson ID(s): NONE
- Notes: Existing lessons were sufficient.
EOF

export PATH="$TEST_DIR/project/bin:$PATH"
export XDG_CACHE_HOME="$TEST_DIR/project/.cache"
HOOK_INPUT='{"stop_hook_active": false, "transcript": [], "session_id": ""}'
echo "$HOOK_INPUT" | CLAUDE_PROJECT_DIR="$TEST_DIR/project" bash "$STOP_HOOK" > /dev/null 2>&1 || true

NEXT_PROMPT="$LOOP_DIR/round-2-prompt.md"
if [[ -f "$NEXT_PROMPT" ]] && grep -q "BitLesson Selection (REQUIRED BEFORE EXECUTION)" "$NEXT_PROMPT"; then
    pass "next-round prompt includes BitLesson selection section"
else
    fail "next-round prompt includes BitLesson selection section" "section present in round-2 prompt" "missing"
fi

if [[ -f "$NEXT_PROMPT" ]] && grep -q "bitlesson-selector" "$NEXT_PROMPT"; then
    pass "next-round prompt requires bitlesson-selector invocation"
else
    fail "next-round prompt requires bitlesson-selector invocation" "bitlesson-selector text in round-2 prompt" "missing"
fi

# ========================================
# Test 5: Stop hook blocks when BitLesson Delta is missing
# ========================================

cat > "$LOOP_DIR/round-2-summary.md" << 'EOF'
# Round 2 Summary

Did more work but forgot the required delta section.
EOF

BLOCK_RESULT=$(echo "$HOOK_INPUT" | CLAUDE_PROJECT_DIR="$TEST_DIR/project" bash "$STOP_HOOK")
if echo "$BLOCK_RESULT" | grep -q '"decision": "block"' && echo "$BLOCK_RESULT" | grep -q "BitLesson Delta"; then
    pass "stop hook blocks summary when BitLesson Delta section is missing"
else
    fail "stop hook blocks summary when BitLesson Delta section is missing" "block decision mentioning BitLesson Delta" "$BLOCK_RESULT"
fi

print_test_summary "BitLesson Workflow Tests"
