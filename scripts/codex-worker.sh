#!/bin/bash
#
# Codex Worker - Implementation worker via Codex CLI
#
# Runs `codex exec` to implement a concrete coding task.
#
# Usage:
#   codex-worker.sh [--worker-model MODEL:EFFORT] [--worker-timeout SECONDS] [--workdir PATH] [task...]
#
# Output:
#   stdout: Codex worker response (for the coordinator to read)
#   stderr: Status/debug info (model, effort, log paths)
#
# Storage:
#   Project-local: .humanize/skill/<unique-id>/{input,output,metadata}.md
#   Cache: ~/.cache/humanize/<sanitized-path>/skill-<unique-id>/codex-run.{cmd,out,log}
#

set -euo pipefail

# ========================================
# Source Shared Libraries
# ========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Source portable timeout wrapper
source "$SCRIPT_DIR/portable-timeout.sh"

# Source shared loop library for DEFAULT_CODEX_WORKER_MODEL and DEFAULT_CODEX_WORKER_EFFORT
HOOKS_LIB_DIR="$(cd "$SCRIPT_DIR/../hooks/lib" && pwd)"
source "$HOOKS_LIB_DIR/loop-common.sh"

# ========================================
# Default Configuration
# ========================================

DEFAULT_CODEX_WORKER_TIMEOUT=5400

WORKER_MODEL="$DEFAULT_CODEX_WORKER_MODEL"
WORKER_EFFORT="$DEFAULT_CODEX_WORKER_EFFORT"
WORKER_TIMEOUT="$DEFAULT_CODEX_WORKER_TIMEOUT"
WORKDIR=""

# ========================================
# Help
# ========================================

show_help() {
    cat << 'HELP_EOF'
codex-worker - Implementation worker via Codex CLI

USAGE:
  /humanize:codex-worker [OPTIONS] <task or instructions>

OPTIONS:
  --worker-model <MODEL:EFFORT>
                       Worker model and reasoning effort (default: gpt-5.3-codex:xhigh)
  --worker-timeout <SECONDS>
                       Timeout for the worker run in seconds (default: 5400)
  --workdir <PATH>     Directory to run in (defaults to current working directory)
  -h, --help           Show this help message

DESCRIPTION:
  Runs Codex CLI as an implementation worker. Use this for `coding` tasks.

ENVIRONMENT:
  HUMANIZE_CODEX_BYPASS_SANDBOX
    Set to "true" or "1" to bypass Codex sandbox protections.
    WARNING: This is dangerous. See README for details.
HELP_EOF
    exit 0
}

# ========================================
# Parse Arguments
# ========================================

TASK_PARTS=()
OPTIONS_DONE=false

while [[ $# -gt 0 ]]; do
    if [[ "$OPTIONS_DONE" == "true" ]]; then
        TASK_PARTS+=("$1")
        shift
        continue
    fi
    case $1 in
        -h|--help)
            show_help
            ;;
        --)
            OPTIONS_DONE=true
            shift
            ;;
        --worker-model)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --worker-model requires a MODEL:EFFORT argument" >&2
                exit 1
            fi
            if [[ "$2" == *:* ]]; then
                WORKER_MODEL="${2%%:*}"
                WORKER_EFFORT="${2#*:}"
            else
                WORKER_MODEL="$2"
                WORKER_EFFORT="$DEFAULT_CODEX_WORKER_EFFORT"
            fi
            shift 2
            ;;
        --worker-timeout)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --worker-timeout requires a number argument (seconds)" >&2
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --worker-timeout must be a positive integer (seconds), got: $2" >&2
                exit 1
            fi
            WORKER_TIMEOUT="$2"
            shift 2
            ;;
        --workdir)
            if [[ -z "${2:-}" ]] || [[ "${2:-}" == -* ]]; then
                echo "Error: --workdir requires a path argument" >&2
                exit 1
            fi
            WORKDIR="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
        *)
            TASK_PARTS+=("$1")
            OPTIONS_DONE=true
            shift
            ;;
    esac
done

TASK="${TASK_PARTS[*]}"

# ========================================
# Validate Prerequisites
# ========================================

if ! command -v codex &>/dev/null; then
    echo "Error: 'codex' command is not installed or not in PATH" >&2
    echo "" >&2
    echo "Please install Codex CLI: https://github.com/openai/codex" >&2
    echo "Then retry: /humanize:codex-worker <your task>" >&2
    exit 1
fi

if [[ -z "$TASK" ]]; then
    echo "Error: No task/instructions provided" >&2
    echo "" >&2
    echo "Usage: /humanize:codex-worker [OPTIONS] <task or instructions>" >&2
    echo "" >&2
    echo "For help: /humanize:codex-worker --help" >&2
    exit 1
fi

if [[ ! "$WORKER_MODEL" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Error: Worker model contains invalid characters" >&2
    echo "  Model: $WORKER_MODEL" >&2
    echo "  Only alphanumeric, hyphen, underscore, dot allowed" >&2
    exit 1
fi

if [[ ! "$WORKER_EFFORT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Worker effort contains invalid characters" >&2
    echo "  Effort: $WORKER_EFFORT" >&2
    echo "  Only alphanumeric, hyphen, underscore allowed" >&2
    exit 1
fi

if [[ -z "$WORKDIR" ]]; then
    WORKDIR="$(pwd)"
fi

# ========================================
# Detect Project Root
# ========================================

find_humanize_project_root() {
    local start_dir="$1"
    local current_dir=""

    if [[ ! -d "$start_dir" ]]; then
        return 1
    fi

    current_dir="$(cd "$start_dir" && pwd)"
    while true; do
        if [[ -d "$current_dir/.humanize" ]]; then
            echo "$current_dir"
            return 0
        fi
        if [[ "$current_dir" == "/" ]]; then
            break
        fi
        current_dir="$(dirname "$current_dir")"
    done

    return 1
}

find_active_loop_for_marker() {
    local project_root="$1"
    local loop_base="$project_root/.humanize/rlcr"
    local candidate=""

    if [[ -n "${LOOP_DIR_ENV:-}" ]]; then
        if [[ -f "${LOOP_DIR_ENV}/state.md" ]] && [[ ! -f "${LOOP_DIR_ENV}/cancel-state.md" ]] && [[ ! -f "${LOOP_DIR_ENV}/finalize-state.md" ]]; then
            echo "$LOOP_DIR_ENV"
        fi
        return 0
    fi

    if [[ ! -d "$loop_base" ]]; then
        return 0
    fi

    while IFS= read -r candidate; do
        if [[ -f "$candidate/state.md" ]] && [[ ! -f "$candidate/cancel-state.md" ]] && [[ ! -f "$candidate/finalize-state.md" ]]; then
            echo "$candidate"
            return 0
        fi
    done < <(find "$loop_base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)

    return 0
}

extract_state_current_round() {
    local state_file="$1"
    local frontmatter=""
    local current_round=""

    if [[ ! -f "$state_file" ]]; then
        return 0
    fi

    frontmatter=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$state_file" 2>/dev/null || true)
    current_round=$(echo "$frontmatter" | sed -n 's/^current_round:[[:space:]]*//p' | head -1 | tr -d ' "')

    if [[ "$current_round" =~ ^[0-9]+$ ]]; then
        echo "$current_round"
    fi
    return 0
}

write_worker_invocation_marker() {
    local project_root="$1"
    local loop_dir=""
    local current_round=""
    local marker_file=""

    # Honour LOOP_DIR if set (passed by stop hook to identify its own loop)
    if [[ -n "${LOOP_DIR:-}" ]]; then
        loop_dir="$LOOP_DIR"
        if [[ ! -f "$loop_dir/state.md" ]] || [[ -f "$loop_dir/cancel-state.md" ]] || [[ -f "$loop_dir/finalize-state.md" ]]; then
            return 0
        fi
    else
        loop_dir="$(find_active_loop_for_marker "$project_root")"
    fi

    if [[ -z "$loop_dir" ]]; then
        return 0
    fi

    current_round="$(extract_state_current_round "$loop_dir/state.md")"
    if [[ -z "$current_round" ]]; then
        return 0
    fi

    marker_file="$loop_dir/.worker-invoked-round-$current_round"
    if ! date -u +%Y-%m-%dT%H:%M:%SZ > "$marker_file" 2>/dev/null; then
        : > "$marker_file" 2>/dev/null || true
    fi

    return 0
}

WORKDIR_ABS="$WORKDIR"
if [[ -d "$WORKDIR" ]]; then
    WORKDIR_ABS="$(cd "$WORKDIR" && pwd)"
fi

PROJECT_ROOT="$(find_humanize_project_root "$WORKDIR_ABS" || true)"
if [[ -z "$PROJECT_ROOT" ]]; then
    if git -C "$WORKDIR" rev-parse --show-toplevel &>/dev/null; then
        PROJECT_ROOT=$(git -C "$WORKDIR" rev-parse --show-toplevel)
    else
        PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$WORKDIR_ABS}"
    fi
fi

# ========================================
# Create Storage Directories
# ========================================

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
UNIQUE_ID="${TIMESTAMP}-$$-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"

SKILL_DIR="$PROJECT_ROOT/.humanize/skill/$UNIQUE_ID"
mkdir -p "$SKILL_DIR"

SANITIZED_PROJECT_PATH=$(echo "$PROJECT_ROOT" | sed 's/[^a-zA-Z0-9._-]/-/g' | sed 's/--*/-/g')
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_DIR="$CACHE_BASE/humanize/$SANITIZED_PROJECT_PATH/skill-$UNIQUE_ID"
if ! mkdir -p "$CACHE_DIR" 2>/dev/null; then
    CACHE_DIR="$SKILL_DIR/cache"
    mkdir -p "$CACHE_DIR"
    echo "codex-worker: warning: home cache not writable, using $CACHE_DIR" >&2
fi

# ========================================
# Save Input
# ========================================

CROSS_VENDOR_CONTEXT=$(cat << 'CONTEXT_EOF'
## Cross-Vendor Review Context (Simulated)

- You are the **implementation worker** running via **Codex CLI**.
- Your work will be reviewed by an **independent analyzer/reviewer** (cross-vendor style), even if both use OpenAI models today.
- Produce concrete, verifiable changes: edit code, run relevant checks, and report what you changed + how to validate.
CONTEXT_EOF
)

FINAL_PROMPT="$CROSS_VENDOR_CONTEXT

---

$TASK"

cat > "$SKILL_DIR/input.md" << EOF
# Codex Worker Input

## Question

$TASK

## Configuration

- Model: $WORKER_MODEL
- Effort: $WORKER_EFFORT
- Timeout: ${WORKER_TIMEOUT}s
- Timestamp: $TIMESTAMP
- Workdir: $WORKDIR
EOF

# ========================================
# Build Codex Command
# ========================================

CODEX_EXEC_ARGS=("-m" "$WORKER_MODEL")
if [[ -n "$WORKER_EFFORT" ]]; then
    CODEX_EXEC_ARGS+=("-c" "model_reasoning_effort=${WORKER_EFFORT}")
fi

CODEX_AUTO_FLAG="--full-auto"
if [[ "${HUMANIZE_CODEX_BYPASS_SANDBOX:-}" == "true" ]] || [[ "${HUMANIZE_CODEX_BYPASS_SANDBOX:-}" == "1" ]]; then
    CODEX_AUTO_FLAG="--dangerously-bypass-approvals-and-sandbox"
fi

CODEX_EXEC_ARGS+=("$CODEX_AUTO_FLAG" "-C" "$WORKDIR_ABS")

# ========================================
# Save Debug Command
# ========================================

CODEX_CMD_FILE="$CACHE_DIR/codex-run.cmd"
CODEX_STDOUT_FILE="$CACHE_DIR/codex-run.out"
CODEX_STDERR_FILE="$CACHE_DIR/codex-run.log"

{
    echo "# Codex worker invocation debug info"
    echo "# Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# Working directory: $WORKDIR_ABS"
    echo "# Workdir argument: $WORKDIR"
    echo "# Timeout: $WORKER_TIMEOUT seconds"
    echo ""
    echo "codex exec ${CODEX_EXEC_ARGS[*]} \"<prompt>\""
    echo ""
    echo "# Prompt content:"
    echo "$FINAL_PROMPT"
} > "$CODEX_CMD_FILE"

# ========================================
# Run Codex
# ========================================

echo "codex-worker: model=$WORKER_MODEL effort=$WORKER_EFFORT timeout=${WORKER_TIMEOUT}s" >&2
echo "codex-worker: cache=$CACHE_DIR" >&2
echo "codex-worker: running codex exec..." >&2

epoch_to_iso() {
    local epoch="$1"
    date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
    date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
    echo "unknown"
}

START_TIME=$(date +%s)

CODEX_EXIT_CODE=0
printf '%s' "$FINAL_PROMPT" | run_with_timeout "$WORKER_TIMEOUT" codex exec "${CODEX_EXEC_ARGS[@]}" - \
    > "$CODEX_STDOUT_FILE" 2> "$CODEX_STDERR_FILE" || CODEX_EXIT_CODE=$?

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "codex-worker: exit_code=$CODEX_EXIT_CODE duration=${DURATION}s" >&2

# ========================================
# Handle Results
# ========================================

if [[ $CODEX_EXIT_CODE -eq 124 ]]; then
    echo "Error: Codex worker timed out after ${WORKER_TIMEOUT} seconds" >&2
    echo "" >&2
    echo "Try increasing the timeout:" >&2
    echo "  /humanize:codex-worker --worker-timeout $((WORKER_TIMEOUT * 2)) <your task>" >&2
    echo "" >&2
    echo "Debug logs: $CACHE_DIR" >&2

    cat > "$SKILL_DIR/metadata.md" << EOF
---
model: $WORKER_MODEL
effort: $WORKER_EFFORT
timeout: $WORKER_TIMEOUT
exit_code: 124
duration: ${DURATION}s
status: timeout
started_at: $(epoch_to_iso "$START_TIME")
---
EOF
    exit 124
fi

if [[ $CODEX_EXIT_CODE -ne 0 ]]; then
    echo "Error: Codex worker exited with code $CODEX_EXIT_CODE" >&2
    if [[ -s "$CODEX_STDERR_FILE" ]]; then
        echo "" >&2
        echo "Codex stderr (last 20 lines):" >&2
        tail -20 "$CODEX_STDERR_FILE" >&2
    fi
    echo "" >&2
    echo "Debug logs: $CACHE_DIR" >&2

    cat > "$SKILL_DIR/metadata.md" << EOF
---
model: $WORKER_MODEL
effort: $WORKER_EFFORT
timeout: $WORKER_TIMEOUT
exit_code: $CODEX_EXIT_CODE
duration: ${DURATION}s
status: error
started_at: $(epoch_to_iso "$START_TIME")
---
EOF
    exit "$CODEX_EXIT_CODE"
fi

if [[ ! -s "$CODEX_STDOUT_FILE" ]]; then
    echo "Error: Codex worker returned empty response" >&2
    if [[ -s "$CODEX_STDERR_FILE" ]]; then
        echo "" >&2
        echo "Codex stderr (last 20 lines):" >&2
        tail -20 "$CODEX_STDERR_FILE" >&2
    fi
    echo "" >&2
    echo "Debug logs: $CACHE_DIR" >&2

    cat > "$SKILL_DIR/metadata.md" << EOF
---
model: $WORKER_MODEL
effort: $WORKER_EFFORT
timeout: $WORKER_TIMEOUT
exit_code: 0
duration: ${DURATION}s
status: empty_response
started_at: $(epoch_to_iso "$START_TIME")
---
EOF
    exit 1
fi

# ========================================
# Save Output and Metadata
# ========================================

cp "$CODEX_STDOUT_FILE" "$SKILL_DIR/output.md"

cat > "$SKILL_DIR/metadata.md" << EOF
---
model: $WORKER_MODEL
effort: $WORKER_EFFORT
timeout: $WORKER_TIMEOUT
exit_code: 0
duration: ${DURATION}s
status: success
started_at: $(epoch_to_iso "$START_TIME")
---
EOF

echo "codex-worker: response saved to $SKILL_DIR/output.md" >&2

# ========================================
# Output Response
# ========================================

cat "$CODEX_STDOUT_FILE"

