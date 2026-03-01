#!/bin/bash
#
# Continue script for continue-rlcr-loop
#
# Prints the current round prompt for the active RLCR loop so you can resume in a
# fresh Claude session (without relying on `claude --resume`, which can get
# stuck when the prompt/context becomes too large).
#
# Usage:
#   continue-rlcr-loop.sh [--paths-only] [--max-prompt-bytes N] [--loop-dir PATH]
#
# Exit codes:
#   0 - Success
#   1 - No active loop found
#   2 - Active loop found but state/prompt missing or invalid
#   3 - Other error (invalid arguments)
#

set -euo pipefail

# ========================================
# Defaults
# ========================================

PRINT_PROMPT="true"
MAX_PROMPT_BYTES="200000"
LOOP_DIR_OVERRIDE=""

show_help() {
    cat << 'HELP_EOF'
continue-rlcr-loop - Continue active RLCR loop (print current round prompt)

USAGE:
  continue-rlcr-loop.sh [OPTIONS]

OPTIONS:
  --paths-only           Print loop file paths only (do not print the prompt)
  --max-prompt-bytes N   If prompt file exceeds N bytes, print a truncated view
                         (default: 200000)
  --loop-dir PATH        Override loop directory (relative to project root or absolute)
  -h, --help             Show this help message

DESCRIPTION:
  Finds the newest active RLCR loop directory in the current project and prints
  the on-disk prompt for the current round. This is intended for "new session"
  recovery when `claude --resume` is failing due to context limits.

EXIT CODES:
  0 - Success
  1 - No active RLCR loop found
  2 - Loop found but required files missing/invalid
  3 - Invalid arguments
HELP_EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --paths-only)
            PRINT_PROMPT="false"
            shift
            ;;
        --max-prompt-bytes)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --max-prompt-bytes requires a number argument" >&2
                exit 3
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --max-prompt-bytes must be a non-negative integer, got: $2" >&2
                exit 3
            fi
            MAX_PROMPT_BYTES="$2"
            shift 2
            ;;
        --loop-dir)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --loop-dir requires a path argument" >&2
                exit 3
            fi
            LOOP_DIR_OVERRIDE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 3
            ;;
    esac
done

# ========================================
# Find Loop Directory
# ========================================

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOOP_BASE_DIR="$PROJECT_ROOT/.humanize/rlcr"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../hooks/lib/loop-common.sh"

resolve_loop_dir() {
    local override="$1"

    if [[ -n "$override" ]]; then
        local resolved="$override"
        if [[ "$resolved" != /* ]]; then
            resolved="$PROJECT_ROOT/$resolved"
        fi
        # Normalize trailing slash
        echo "${resolved%/}"
        return
    fi

    find_active_loop "$LOOP_BASE_DIR"
}

LOOP_DIR=$(resolve_loop_dir "$LOOP_DIR_OVERRIDE")

if [[ -z "$LOOP_DIR" ]] || [[ ! -d "$LOOP_DIR" ]]; then
    echo "NO_LOOP"
    echo "No active RLCR loop found in: $LOOP_BASE_DIR"
    exit 1
fi

STATE_FILE=$(resolve_active_state_file "$LOOP_DIR")
if [[ -z "$STATE_FILE" ]] || [[ ! -f "$STATE_FILE" ]]; then
    echo "INVALID_STATE"
    echo "Loop directory exists but no active state file found (expected state.md or finalize-state.md)."
    echo "loop_dir: $LOOP_DIR"
    exit 2
fi

# Parse state file (strict) to get current_round/max_iterations/plan_file
if ! parse_state_file_strict "$STATE_FILE" >/dev/null 2>&1; then
    echo "INVALID_STATE"
    echo "Failed to parse state file."
    echo "state_file: $STATE_FILE"
    exit 2
fi

CURRENT_ROUND="${STATE_CURRENT_ROUND}"
MAX_ITERATIONS="${STATE_MAX_ITERATIONS}"
PLAN_FILE="${STATE_PLAN_FILE:-}"
REVIEW_STARTED="${STATE_REVIEW_STARTED:-}"

PROMPT_FILE="$LOOP_DIR/round-${CURRENT_ROUND}-prompt.md"
SUMMARY_FILE="$LOOP_DIR/round-${CURRENT_ROUND}-summary.md"
GOAL_TRACKER_FILE="$LOOP_DIR/goal-tracker.md"

if [[ ! -f "$PROMPT_FILE" ]]; then
    # Fallback: pick the newest prompt file if the expected one is missing
    NEWEST_PROMPT=$(ls -1 "$LOOP_DIR"/round-*-prompt.md 2>/dev/null | sort -V | tail -1)
    if [[ -n "$NEWEST_PROMPT" ]] && [[ -f "$NEWEST_PROMPT" ]]; then
        PROMPT_FILE="$NEWEST_PROMPT"
    fi
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "MISSING_PROMPT"
    echo "No round prompt file found for current_round=$CURRENT_ROUND."
    echo "loop_dir: $LOOP_DIR"
    echo "expected: $LOOP_DIR/round-${CURRENT_ROUND}-prompt.md"
    exit 2
fi

# ========================================
# Output
# ========================================

echo "CONTINUE_RLCR_LOOP"
echo "project_root: $PROJECT_ROOT"
echo "loop_dir: $LOOP_DIR"
echo "state_file: $STATE_FILE"
echo "current_round: $CURRENT_ROUND"
echo "max_iterations: $MAX_ITERATIONS"
echo "review_started: ${REVIEW_STARTED:-false}"
if [[ -n "$PLAN_FILE" ]]; then
    echo "plan_file: $PLAN_FILE"
fi
echo "goal_tracker: $GOAL_TRACKER_FILE"
echo "summary_file: $SUMMARY_FILE"
echo "prompt_file: $PROMPT_FILE"

if [[ "$PRINT_PROMPT" != "true" ]]; then
    exit 0
fi

echo ""
echo "---"
echo ""

PROMPT_BYTES=$(wc -c < "$PROMPT_FILE" | tr -d ' ')
PROMPT_BYTES=${PROMPT_BYTES:-0}

if [[ "$MAX_PROMPT_BYTES" -eq 0 ]] || [[ "$PROMPT_BYTES" -le "$MAX_PROMPT_BYTES" ]]; then
    cat "$PROMPT_FILE"
    exit 0
fi

echo "[Prompt truncated] prompt_bytes=$PROMPT_BYTES max_prompt_bytes=$MAX_PROMPT_BYTES"
echo ""
echo "----- BEGIN (head) -----"
head -n 200 "$PROMPT_FILE"
echo ""
echo "----- END (tail) -----"
tail -n 200 "$PROMPT_FILE"

exit 0

