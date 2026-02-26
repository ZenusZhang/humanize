#!/bin/bash
#
# Setup script for scheduler/worker/reviewer git worktree lanes in RLCR loops.
#
# Usage:
#   setup-worktree-teams.sh [--workers N] [--reviewers N] [--loop-dir PATH]
#                           [--worktree-root PATH] [--branch-prefix PREFIX]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Source shared loop utilities
source "$SCRIPT_DIR/portable-timeout.sh"
HOOKS_LIB_DIR="$(cd "$SCRIPT_DIR/../hooks/lib" && pwd)"
source "$HOOKS_LIB_DIR/loop-common.sh"

DEFAULT_WORKERS=2
DEFAULT_BRANCH_PREFIX="rlcr-worktree"

WORKERS="$DEFAULT_WORKERS"
REVIEWERS=""
LOOP_DIR=""
WORKTREE_ROOT=""
BRANCH_PREFIX="$DEFAULT_BRANCH_PREFIX"
BASE_REF=""

show_help() {
    cat << 'HELP_EOF'
setup-worktree-teams - Provision worker/reviewer git worktree lanes for an active RLCR loop

USAGE:
  setup-worktree-teams.sh [OPTIONS]

OPTIONS:
  --workers <N>         Number of worker lanes (default: 2)
  --reviewers <N>       Number of reviewer lanes (default: same as workers)
  --loop-dir <PATH>     Active RLCR loop directory (auto-detected if omitted)
  --worktree-root <PATH>
                        Root directory for worktrees (default: from state, then .humanize/worktrees/<loop-id>)
  --branch-prefix <P>   Branch prefix for generated lanes (default: rlcr-worktree)
  --base-ref <REF>      Base ref for new branches (default: start_branch from state, else current branch)
  -h, --help            Show this help message

OUTPUT:
  - Creates worktrees and branches for worker/reviewer lanes
  - Writes lane mapping to <loop-dir>/worktree-assignment.md
HELP_EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        --workers)
            if [[ -z "${2:-}" ]] || ! [[ "${2:-}" =~ ^[0-9]+$ ]] || [[ "${2:-0}" -lt 1 ]]; then
                echo "Error: --workers requires an integer >= 1" >&2
                exit 1
            fi
            WORKERS="$2"
            shift 2
            ;;
        --reviewers)
            if [[ -z "${2:-}" ]] || ! [[ "${2:-}" =~ ^[0-9]+$ ]] || [[ "${2:-0}" -lt 1 ]]; then
                echo "Error: --reviewers requires an integer >= 1" >&2
                exit 1
            fi
            REVIEWERS="$2"
            shift 2
            ;;
        --loop-dir)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --loop-dir requires a path argument" >&2
                exit 1
            fi
            LOOP_DIR="$2"
            shift 2
            ;;
        --worktree-root)
            if [[ -z "${2:-}" ]] || [[ "${2:-}" == -* ]]; then
                echo "Error: --worktree-root requires a path argument" >&2
                exit 1
            fi
            WORKTREE_ROOT="$2"
            shift 2
            ;;
        --branch-prefix)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --branch-prefix requires a value" >&2
                exit 1
            fi
            BRANCH_PREFIX="$2"
            shift 2
            ;;
        --base-ref)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --base-ref requires a ref value" >&2
                exit 1
            fi
            BASE_REF="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

if [[ -z "$REVIEWERS" ]]; then
    REVIEWERS="$WORKERS"
fi

if [[ ! "$BRANCH_PREFIX" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
    echo "Error: --branch-prefix contains invalid characters: $BRANCH_PREFIX" >&2
    exit 1
fi

if [[ -n "$WORKTREE_ROOT" ]]; then
    while [[ "$WORKTREE_ROOT" == ./* ]]; do
        WORKTREE_ROOT="${WORKTREE_ROOT#./}"
    done
    while [[ "$WORKTREE_ROOT" == *"//"* ]]; do
        WORKTREE_ROOT="${WORKTREE_ROOT//\/\//\/}"
    done
    WORKTREE_ROOT="${WORKTREE_ROOT%/}"

    if [[ "$WORKTREE_ROOT" = /* ]]; then
        # Absolute paths are allowed for this helper script
        :
    elif [[ ! "$WORKTREE_ROOT" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
        echo "Error: --worktree-root contains unsupported characters." >&2
        echo "  Allowed characters: letters, numbers, dot, underscore, slash, hyphen" >&2
        exit 1
    elif [[ "$WORKTREE_ROOT" =~ (^|/)\.\.(/|$) ]]; then
        echo "Error: --worktree-root must not contain parent-directory traversal" >&2
        exit 1
    elif [[ "$WORKTREE_ROOT" == "." || "$WORKTREE_ROOT" == ".git" || "$WORKTREE_ROOT" == .git/* ]]; then
        echo "Error: --worktree-root must not target repository root or .git internals" >&2
        exit 1
    fi
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if ! run_with_timeout 30 git -C "$PROJECT_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "Error: This command must run inside a git repository." >&2
    exit 1
fi
PROJECT_ROOT=$(run_with_timeout 30 git -C "$PROJECT_ROOT" rev-parse --show-toplevel)

if [[ -z "$LOOP_DIR" ]]; then
    LOOP_DIR=$(find_active_loop "$PROJECT_ROOT/.humanize/rlcr")
    if [[ -z "$LOOP_DIR" ]]; then
        echo "Error: No active RLCR loop found. Provide --loop-dir explicitly." >&2
        exit 1
    fi
fi

if [[ "$LOOP_DIR" != /* ]]; then
    LOOP_DIR="$PROJECT_ROOT/$LOOP_DIR"
fi

if [[ ! -d "$LOOP_DIR" ]]; then
    echo "Error: Loop directory does not exist: $LOOP_DIR" >&2
    exit 1
fi

STATE_FILE=$(resolve_active_state_file "$LOOP_DIR")
if [[ -z "$STATE_FILE" ]]; then
    echo "Error: No active state file found in loop directory: $LOOP_DIR" >&2
    exit 1
fi

if ! parse_state_file "$STATE_FILE"; then
    echo "Error: Failed to parse state file: $STATE_FILE" >&2
    exit 1
fi

if [[ "${STATE_WORKTREE_TEAMS:-false}" != "true" ]]; then
    echo "Warning: Loop state does not enable worktree teams. Continuing anyway." >&2
fi

if [[ -z "$WORKTREE_ROOT" ]]; then
    WORKTREE_ROOT="${STATE_WORKTREE_ROOT:-}"
fi
if [[ -z "$WORKTREE_ROOT" ]]; then
    WORKTREE_ROOT=".humanize/worktrees/$(basename "$LOOP_DIR")"
fi
while [[ "$WORKTREE_ROOT" == ./* ]]; do
    WORKTREE_ROOT="${WORKTREE_ROOT#./}"
done
while [[ "$WORKTREE_ROOT" == *"//"* ]]; do
    WORKTREE_ROOT="${WORKTREE_ROOT//\/\//\/}"
done
WORKTREE_ROOT="${WORKTREE_ROOT%/}"

if [[ "$WORKTREE_ROOT" != /* ]]; then
    if [[ ! "$WORKTREE_ROOT" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
        echo "Error: worktree_root from state contains unsupported characters." >&2
        exit 1
    fi
    if [[ "$WORKTREE_ROOT" =~ (^|/)\.\.(/|$) ]]; then
        echo "Error: worktree_root from state contains parent-directory traversal." >&2
        exit 1
    fi
    if [[ -z "$WORKTREE_ROOT" || "$WORKTREE_ROOT" == "." || "$WORKTREE_ROOT" == ".git" || "$WORKTREE_ROOT" == .git/* ]]; then
        echo "Error: worktree_root from state targets repository root or .git internals." >&2
        exit 1
    fi
fi

if [[ "$WORKTREE_ROOT" = /* ]]; then
    WORKTREE_ROOT_ABS="$WORKTREE_ROOT"
else
    WORKTREE_ROOT_ABS="$PROJECT_ROOT/$WORKTREE_ROOT"
fi

if [[ "$WORKTREE_ROOT" != /* ]]; then
    PROJECT_ROOT_REAL=$(cd "$PROJECT_ROOT" && pwd -P)
    if command -v python3 >/dev/null 2>&1; then
        WORKTREE_ROOT_REAL=$(python3 - "$WORKTREE_ROOT_ABS" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
)
    elif command -v readlink >/dev/null 2>&1; then
        WORKTREE_ROOT_REAL=$(readlink -f "$WORKTREE_ROOT_ABS" 2>/dev/null || readlink -m "$WORKTREE_ROOT_ABS" 2>/dev/null || echo "")
    else
        WORKTREE_ROOT_REAL=""
    fi

    if [[ -z "$WORKTREE_ROOT_REAL" ]]; then
        echo "Error: Unable to resolve canonical path for worktree root: $WORKTREE_ROOT_ABS" >&2
        exit 1
    fi
    if [[ "$WORKTREE_ROOT_REAL" != "$PROJECT_ROOT_REAL" && "$WORKTREE_ROOT_REAL" != "$PROJECT_ROOT_REAL/"* ]]; then
        echo "Error: worktree root resolves outside project root via symlink traversal." >&2
        exit 1
    fi
fi

mkdir -p "$WORKTREE_ROOT_ABS"

if [[ -z "$BASE_REF" ]]; then
    BASE_REF="${STATE_START_BRANCH:-}"
fi
if [[ -z "$BASE_REF" ]]; then
    BASE_REF=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)
fi
if ! run_with_timeout 30 git -C "$PROJECT_ROOT" rev-parse --verify "$BASE_REF^{commit}" >/dev/null 2>&1; then
    echo "Error: Base ref does not resolve to a commit: $BASE_REF" >&2
    exit 1
fi

RUN_ID="$(basename "$LOOP_DIR")"
ASSIGNMENT_FILE="$LOOP_DIR/worktree-assignment.md"

lane_path_exists() {
    local lane_path="$1"
    run_with_timeout 30 git -C "$PROJECT_ROOT" worktree list --porcelain | grep -Fq "worktree $lane_path"
}

ensure_lane() {
    local lane_name="$1"
    local lane_role="$2"

    local lane_path="$WORKTREE_ROOT_ABS/$lane_name"
    local lane_branch="$BRANCH_PREFIX/$RUN_ID/$lane_name"
    local lane_status="created"

    if lane_path_exists "$lane_path"; then
        lane_status="existing"
    else
        if run_with_timeout 30 git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/heads/$lane_branch"; then
            run_with_timeout 30 git -C "$PROJECT_ROOT" worktree add "$lane_path" "$lane_branch" >/dev/null
        else
            run_with_timeout 30 git -C "$PROJECT_ROOT" worktree add -b "$lane_branch" "$lane_path" "$BASE_REF" >/dev/null
        fi
    fi

    local display_path="$lane_path"
    if [[ "$display_path" == "$PROJECT_ROOT/"* ]]; then
        display_path="${display_path#$PROJECT_ROOT/}"
    fi

    local active_branch
    active_branch=$(git -C "$lane_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$lane_branch")

    printf '| %s | %s | `%s` | `%s` | %s |\n' "$lane_name" "$lane_role" "$active_branch" "$display_path" "$lane_status" >> "$ASSIGNMENT_FILE"
}

{
    echo "# Worktree Assignment"
    echo ""
    echo "- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Loop Directory: \`$LOOP_DIR\`"
    if [[ "$WORKTREE_ROOT_ABS" == "$PROJECT_ROOT/"* ]]; then
        echo "- Worktree Root: \`${WORKTREE_ROOT_ABS#$PROJECT_ROOT/}\`"
    else
        echo "- Worktree Root: \`$WORKTREE_ROOT_ABS\`"
    fi
    echo "- Base Ref: \`$BASE_REF\`"
    echo ""
    echo "## Lane Registry"
    echo ""
    echo "| Lane | Role | Branch | Path | Status |"
    echo "|------|------|--------|------|--------|"
} > "$ASSIGNMENT_FILE"

for ((i = 1; i <= WORKERS; i++)); do
    ensure_lane "worker-$i" "worker"
done
for ((i = 1; i <= REVIEWERS; i++)); do
    ensure_lane "reviewer-$i" "reviewer"
done

echo "" >> "$ASSIGNMENT_FILE"
echo "## Suggested Pairing" >> "$ASSIGNMENT_FILE"
echo "" >> "$ASSIGNMENT_FILE"
echo "| Worker Lane | Reviewer Lane |" >> "$ASSIGNMENT_FILE"
echo "|-------------|---------------|" >> "$ASSIGNMENT_FILE"
for ((i = 1; i <= WORKERS; i++)); do
    reviewer_index=$(( ((i - 1) % REVIEWERS) + 1 ))
    printf '| `worker-%s` | `reviewer-%s` |\n' "$i" "$reviewer_index" >> "$ASSIGNMENT_FILE"
done

echo "Worktree lanes ready."
echo "Assignment file: $ASSIGNMENT_FILE"
