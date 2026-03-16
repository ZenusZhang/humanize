#!/bin/bash
#
# Tests for humanize-plugin-worktree.sh and plugin branch statusline identity.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

HELPER_SCRIPT="$SCRIPT_DIR/../scripts/humanize-plugin-worktree.sh"
STATUSLINE_SCRIPT="$SCRIPT_DIR/../scripts/statusline.sh"

echo "=========================================="
echo "Humanize Plugin Worktree Tests"
echo "=========================================="
echo ""

create_plugin_repo() {
    local repo_dir="$1"
    mkdir -p "$repo_dir/.claude-plugin"
    mkdir -p "$repo_dir/scripts"
    cat > "$repo_dir/.claude-plugin/plugin.json" << 'EOF'
{
  "name": "humanize",
  "version": "9.9.9"
}
EOF
    cp "$STATUSLINE_SCRIPT" "$repo_dir/scripts/statusline.sh"
    chmod +x "$repo_dir/scripts/statusline.sh"
    init_test_git_repo "$repo_dir"
    (
        cd "$repo_dir"
        git branch -M main
        git add .claude-plugin/plugin.json scripts/statusline.sh
        git commit -q -m "Add plugin manifest and statusline"
        git branch "feature/demo"
        git checkout -q -b scratch
    )
}

assert_contains() {
    local desc="$1"
    local needle="$2"
    local haystack="$3"
    if printf '%s' "$haystack" | grep -Fq "$needle"; then
        pass "$desc"
    else
        fail "$desc" "$needle" "$haystack"
    fi
}

strip_ansi() {
    printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

setup_test_dir

PLUGIN_REPO="$TEST_DIR/humanize-plugin"
WORKTREE_ROOT="$TEST_DIR/worktrees"
TARGET_PROJECT="$TEST_DIR/target-project"
mkdir -p "$TARGET_PROJECT"

create_plugin_repo "$PLUGIN_REPO"

MAIN_PATH=$("$HELPER_SCRIPT" ensure --branch main --source "$PLUGIN_REPO" --worktree-root "$WORKTREE_ROOT")
if git -C "$MAIN_PATH" rev-parse --show-toplevel >/dev/null 2>&1 && [[ "$(git -C "$MAIN_PATH" branch --show-current)" == "main" ]]; then
    pass "ensure creates managed worktree for main branch"
else
    fail "ensure creates managed worktree for main branch" "main worktree" "$MAIN_PATH"
fi

FEATURE_PATH=$("$HELPER_SCRIPT" ensure --branch feature/demo --source "$PLUGIN_REPO" --worktree-root "$WORKTREE_ROOT")
if git -C "$FEATURE_PATH" rev-parse --show-toplevel >/dev/null 2>&1 && [[ "$(git -C "$FEATURE_PATH" branch --show-current)" == "feature/demo" ]]; then
    pass "ensure creates managed worktree for slash branch names"
else
    fail "ensure creates managed worktree for slash branch names" "feature/demo worktree" "$FEATURE_PATH"
fi

EXPECTED_FEATURE_PATH="$WORKTREE_ROOT/feature_demo"
if [[ "$FEATURE_PATH" == "$EXPECTED_FEATURE_PATH" ]]; then
    pass "slash branch names are sanitized into stable worktree paths"
else
    fail "slash branch names are sanitized into stable worktree paths" "$EXPECTED_FEATURE_PATH" "$FEATURE_PATH"
fi

FEATURE_PATH_AGAIN=$("$HELPER_SCRIPT" ensure --branch feature/demo --source "$PLUGIN_REPO" --worktree-root "$WORKTREE_ROOT")
if [[ "$FEATURE_PATH_AGAIN" == "$FEATURE_PATH" ]]; then
    pass "ensure reuses existing worktree for the same branch"
else
    fail "ensure reuses existing worktree for the same branch" "$FEATURE_PATH" "$FEATURE_PATH_AGAIN"
fi

INFO_OUTPUT=$("$HELPER_SCRIPT" info --plugin-dir "$FEATURE_PATH")
assert_contains "info reports plugin directory" "plugin_dir=$FEATURE_PATH" "$INFO_OUTPUT"
assert_contains "info reports plugin version" "plugin_version=9.9.9" "$INFO_OUTPUT"
assert_contains "info reports plugin branch" "plugin_branch=feature/demo" "$INFO_OUTPUT"

LAUNCH_OUTPUT=$("$HELPER_SCRIPT" launch --branch feature/demo --source "$PLUGIN_REPO" --worktree-root "$WORKTREE_ROOT" --project "$TARGET_PROJECT" --print-only)
assert_contains "launch --print-only reports project directory" "project_dir=$TARGET_PROJECT" "$LAUNCH_OUTPUT"
assert_contains "launch --print-only reports feature plugin path" "plugin_dir=$FEATURE_PATH" "$LAUNCH_OUTPUT"
assert_contains "launch --print-only reports selected plugin branch" "plugin_branch=feature/demo" "$LAUNCH_OUTPUT"

(
    cd "$TARGET_PROJECT"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test User"
    git config commit.gpgsign false
)

STATUS_INPUT=$(cat <<EOF
{"model":{"display_name":"Claude Test"},"cwd":"$TARGET_PROJECT","session_id":"session-1","transcript_path":"","cost":{"total_cost_usd":0,"total_duration_ms":0,"total_lines_added":0,"total_lines_removed":0},"context_window":{"used_percentage":0}}
EOF
)

STATUS_OUTPUT=$(printf '%s' "$STATUS_INPUT" | "$FEATURE_PATH/scripts/statusline.sh")
assert_contains "statusline shows plugin branch identity" "Plugin: feature/demo@" "$(strip_ansi "$STATUS_OUTPUT")"

print_test_summary "Humanize Plugin Worktree Test Summary"
