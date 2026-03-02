#!/bin/bash
#
# gen-batch-prompt.sh
#
# Generate a ready-to-paste prompt for Claude Code's `/batch` using the active
# RLCR loop's document-centered `worktree-assignment.md` Parallelization Matrix.
#
# This helper does NOT start any agents. It only prints a prompt to stdout.
#
# Usage:
#   /humanize:gen-batch-prompt [--loop-dir <PATH>] [--project-root <PATH>]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Source shared loop utilities (find_active_loop, resolve_active_state_file)
HOOKS_LIB_DIR="$(cd "$SCRIPT_DIR/../hooks/lib" && pwd)"
source "$HOOKS_LIB_DIR/loop-common.sh"

PROJECT_ROOT=""
LOOP_DIR=""
INCLUDE_BLOCKED=0
MAX_TASKS_PER_LANE=0
PREFER_SAME_LANE=0
STRICT_BLOCKEDBY=0

show_help() {
    cat << 'HELP_EOF'
gen-batch-prompt - Generate a Claude Code `/batch` dispatch prompt from worktree-assignment.md

USAGE:
  /humanize:gen-batch-prompt [OPTIONS]

OPTIONS:
  --loop-dir <PATH>         Explicit RLCR loop directory (defaults to active loop)
  --project-root <PATH>     Project root (defaults to git root of CWD)
  --include-blocked         Include ALL Parallelizable=yes tasks; annotate blocked tasks
                            with "[BLOCKED: check task-state.json]". Skips readiness check.
  --max-tasks-per-lane <N>  Limit the number of tasks output per worker lane to N.
                            Default: 0 (unlimited). When N > 0, only the first N tasks
                            per lane are included; excess tasks are silently omitted.
  --prefer-same-lane        Prefer batching same-lane tasks together. Tasks are already
                            grouped by lane by default, so this flag is a no-op that
                            prints an informational message to stderr.
  --strict-blockedby        Treat tasks with external (non-task-ID) blockedBy values as
                            hard blockers. Prints an error to stderr for each such task
                            and (in --include-blocked mode) annotates them with
                            [STRICT-BLOCKED] instead of [BLOCKED: check task-state.json].
  -h, --help                Show this help message

NOTES:
  - By default, only tasks in the ready set (from task-graph.py ready) are included.
  - If task-state.json does not exist, all Parallelizable=yes tasks are included (backward compat).
  - If task-graph.py is unavailable, readiness filtering is skipped with a warning.
  - Tasks are selected from the "Parallelization Matrix" where
    Parallelizable (yes/no) == "yes" (case-insensitive).
  - If no tasks are marked as parallelizable, the script prints a reminder
    to edit worktree-assignment.md.
HELP_EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        --loop-dir)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --loop-dir requires a path argument" >&2
                exit 1
            fi
            LOOP_DIR="$2"
            shift 2
            ;;
        --project-root)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --project-root requires a path argument" >&2
                exit 1
            fi
            PROJECT_ROOT="$2"
            shift 2
            ;;
        --include-blocked)
            INCLUDE_BLOCKED=1
            shift
            ;;
        --max-tasks-per-lane)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --max-tasks-per-lane requires a numeric argument" >&2
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --max-tasks-per-lane value must be a non-negative integer, got: $2" >&2
                exit 1
            fi
            MAX_TASKS_PER_LANE="$2"
            shift 2
            ;;
        --prefer-same-lane)
            PREFER_SAME_LANE=1
            shift
            ;;
        --strict-blockedby)
            STRICT_BLOCKEDBY=1
            shift
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

if [[ "$PREFER_SAME_LANE" -eq 1 ]]; then
    echo "INFO: --prefer-same-lane is enabled (tasks already grouped by lane by default)" >&2
fi

if [[ -z "$PROJECT_ROOT" ]]; then
    local_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
    if git -C "$local_root" rev-parse --show-toplevel >/dev/null 2>&1; then
        PROJECT_ROOT=$(git -C "$local_root" rev-parse --show-toplevel)
    else
        PROJECT_ROOT="$local_root"
    fi
fi

if [[ -z "$LOOP_DIR" ]]; then
    LOOP_DIR=$(find_active_loop "$PROJECT_ROOT/.humanize/rlcr")
    if [[ -z "$LOOP_DIR" ]]; then
        echo "Error: No active RLCR loop found under: $PROJECT_ROOT/.humanize/rlcr" >&2
        echo "Hint: Run /humanize:start-rlcr-loop first, or pass --loop-dir explicitly." >&2
        exit 1
    fi
fi

if [[ "$LOOP_DIR" != /* ]]; then
    LOOP_DIR="$PROJECT_ROOT/$LOOP_DIR"
fi

ASSIGNMENT_FILE="$LOOP_DIR/worktree-assignment.md"
if [[ ! -f "$ASSIGNMENT_FILE" ]]; then
    echo "Error: worktree assignment file not found: $ASSIGNMENT_FILE" >&2
    echo "Hint: Run /humanize:setup-worktree-teams (or start loop with --worktree-teams)." >&2
    exit 1
fi

PLAN_FILE="$LOOP_DIR/plan.md"
if [[ ! -f "$PLAN_FILE" ]]; then
    STATE_FILE=$(resolve_active_state_file "$LOOP_DIR")
    if [[ -n "$STATE_FILE" ]]; then
        PLAN_FILE_FROM_STATE=$(sed -n '/^---$/,/^---$/{ /^plan_file:/{ s/^plan_file:[[:space:]]*//; p; } }' "$STATE_FILE" | head -n 1)
        if [[ -n "$PLAN_FILE_FROM_STATE" ]]; then
            if [[ "$PLAN_FILE_FROM_STATE" = /* ]]; then
                PLAN_FILE="$PLAN_FILE_FROM_STATE"
            else
                PLAN_FILE="$PROJECT_ROOT/$PLAN_FILE_FROM_STATE"
            fi
        fi
    fi
fi

if [[ ! -f "$PLAN_FILE" ]]; then
    echo "Warning: plan file not found; task descriptions may be missing." >&2
    echo "  Expected: $LOOP_DIR/plan.md or plan_file from state.md" >&2
    PLAN_FILE="/dev/null"
fi

# ---------------------------------------------------------------------------
# Readiness filtering
# ---------------------------------------------------------------------------
# READY_TASK_IDS: space-separated list of ready task IDs.
# READY_FILTER_ACTIVE: 1 when task-graph.py ran successfully with a state file,
#   so AWK enforces the ready set even when it is empty (nothing ready = no
#   tasks emitted).  0 means no state file / fallback: all tasks pass through.
# BLOCKED_ANNOTATION_ACTIVE: set to 1 if --include-blocked was given.
READY_TASK_IDS=""
READY_FILTER_ACTIVE=0
BLOCKED_ANNOTATION_ACTIVE=0
TASK_STATE_FILE="$LOOP_DIR/task-state.json"
TASK_GRAPH_SCRIPT="$SCRIPT_DIR/task-graph.py"

if [[ "$INCLUDE_BLOCKED" -eq 1 ]]; then
    # --include-blocked: include all tasks; use ready set only for annotation.
    echo "WARNING: --include-blocked is active; output may include non-ready tasks" >&2
    BLOCKED_ANNOTATION_ACTIVE=1
    # Still attempt to get the ready set so we can annotate non-ready tasks.
    if [[ -f "$TASK_STATE_FILE" ]]; then
        if ! python3 "$TASK_GRAPH_SCRIPT" --help >/dev/null 2>&1; then
            echo "WARNING: task-graph.py not available; blocked annotations will not be applied" >&2
        else
            READY_CMD_ARGS=(ready --plan "$PLAN_FILE" --state "$TASK_STATE_FILE")
            if [[ -f "$ASSIGNMENT_FILE" ]]; then
                READY_CMD_ARGS+=(--assignment "$ASSIGNMENT_FILE")
            fi
            if READY_OUTPUT=$(python3 "$TASK_GRAPH_SCRIPT" "${READY_CMD_ARGS[@]}" 2>/dev/null); then
                READY_TASK_IDS=$(printf '%s' "$READY_OUTPUT" | tr '\n' ' ')
                # Mark filter active so AWK can annotate non-ready tasks correctly
                READY_FILTER_ACTIVE=1
            else
                echo "WARNING: task-graph.py ready failed; blocked annotations will not be applied" >&2
            fi
        fi
    fi
elif [[ ! -f "$TASK_STATE_FILE" ]]; then
    # No state file: backward-compatible, include all tasks without filtering
    : # do nothing; READY_FILTER_ACTIVE and READY_TASK_IDS stay at defaults
else
    # State file exists: attempt readiness check via task-graph.py
    if ! python3 "$TASK_GRAPH_SCRIPT" --help >/dev/null 2>&1; then
        echo "WARNING: task-graph.py not available; skipping readiness check" >&2
    else
        # Build the ready subcommand arguments
        READY_CMD_ARGS=(ready --plan "$PLAN_FILE" --state "$TASK_STATE_FILE")
        if [[ -f "$ASSIGNMENT_FILE" ]]; then
            READY_CMD_ARGS+=(--assignment "$ASSIGNMENT_FILE")
        fi
        # Run task-graph.py ready; on success activate filter (even if empty)
        if READY_OUTPUT=$(python3 "$TASK_GRAPH_SCRIPT" "${READY_CMD_ARGS[@]}" 2>/dev/null); then
            # Build a space-separated list of ready task IDs (one per line from output)
            READY_TASK_IDS=$(printf '%s' "$READY_OUTPUT" | tr '\n' ' ')
            # Mark filter active: an empty ready set means nothing is ready yet
            READY_FILTER_ACTIVE=1
        else
            echo "WARNING: task-graph.py ready failed; skipping readiness check" >&2
        fi
    fi
fi

# ---------------------------------------------------------------------------
# --strict-blockedby: external blockedBy detection and stderr error reporting
# is delegated entirely to the AWK script below via the strict_blockedby
# variable. The AWK script calls is_task_id() on each task's blockedBy value
# and prints ERROR lines to /dev/stderr for any external constraints found.
# No additional shell-level pre-scan is needed.
# ---------------------------------------------------------------------------

cat << 'HEADER_EOF'
# `/batch` Parallel Dispatch (Humanize) / `/batch` 并行分发（Humanize）

Paste the next section into Claude Code `/batch`.

- Goal: start truly-parallel work across isolated lanes (worktrees) WITHOUT file conflicts.
- Source of truth: `worktree-assignment.md` "Parallelization Matrix".

Hard rules:
1. Do not modify files outside your lane's `File Ownership`.
2. Work inside your lane's `Worktree Path` (git worktree isolation).
3. Respect `blockedBy` dependencies. If a dependency is owned by another lane, coordinate before starting.
4. Each lane produces focused commits and a short written summary (files changed + tests run).

Cross-vendor context (required by Humanize):
- Your output will be reviewed independently (cross-vendor style), even if all models are from the same provider today.

---

## Lanes / Lane 列表
HEADER_EOF

printf '\n- Project root: `%s`\n' "$PROJECT_ROOT"
printf -- '- Loop dir: `%s`\n' "$LOOP_DIR"
printf -- '- Plan: `%s`\n' "$PLAN_FILE"
printf -- '- Assignment: `%s`\n' "$ASSIGNMENT_FILE"

LANES_OUTPUT=$(
    awk \
        -v ready_ids="$READY_TASK_IDS" \
        -v ready_filter_active="$READY_FILTER_ACTIVE" \
        -v blocked_annotation="$BLOCKED_ANNOTATION_ACTIVE" \
        -v max_tasks_per_lane="$MAX_TASKS_PER_LANE" \
        -v strict_blockedby="$STRICT_BLOCKEDBY" \
        '
        function trim(text) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", text)
            return text
        }
        function strip_ticks(text) {
            text = trim(text)
            if (text ~ /^`[^`]*`$/) {
                return substr(text, 2, length(text) - 2)
            }
            return text
        }
        function is_separator_row() {
            if (cell_count == 0) return 1
            for (k = 1; k <= cell_count; k++) {
                if (cells_lc[k] !~ /^:?-+:?$/) return 0
            }
            return 1
        }
        function parse_md_row(line) {
            cell_count = 0
            n = split(line, raw_cells, "|")
            for (i = 1; i <= n; i++) {
                cell = trim(raw_cells[i])
                if ((i == 1 || i == n) && cell == "") {
                    continue
                }
                cell_count++
                cells_raw[cell_count] = cell
                cells_lc[cell_count] = tolower(cell)
            }
            return cell_count
        }
        # Returns 1 if the value looks like a task ID (e.g., task1, task-2, task2a),
        # returns 0 if it looks like an external constraint.
        # A dash or empty value is not an external constraint.
        function is_task_id(val,    lc) {
            lc = tolower(val)
            if (lc == "" || lc == "-" || lc == "none" || lc == "n/a") return 1
            if (lc ~ /^task[0-9a-z._-]+$/) return 1
            return 0
        }
        # Returns 1 if every non-empty comma-separated token in val looks like a
        # task ID (or a placeholder like "-").  Handles "task1, task2" correctly.
        function all_task_ids(val,    parts, n, i) {
            n = split(val, parts, /[,[:space:]]+/)
            for (i = 1; i <= n; i++) {
                if (parts[i] != "" && !is_task_id(parts[i])) return 0
            }
            return 1
        }

        BEGIN {
            # Build a lookup set from the space-separated ready_ids string.
            # use_ready_filter is enabled by ready_filter_active (set when task-graph.py
            # ran successfully with a state file) so that an empty ready set correctly
            # filters ALL tasks out rather than falling back to no-filter behavior.
            use_ready_filter = (ready_filter_active == 1)
            if (ready_ids != "") {
                n_ready = split(ready_ids, ready_arr, " ")
                for (ri = 1; ri <= n_ready; ri++) {
                    tid = ready_arr[ri]
                    if (tid != "") ready_set[tid] = 1
                }
            }

            # plan mapping
            plan_task_col = 0
            plan_desc_col = 0

            # assignment matrix
            in_matrix = 0
            mat_task_col = 0
            mat_parallel_col = 0
            mat_owner_col = 0
            mat_blocked_col = 0
            mat_worker_col = 0
            mat_reviewer_col = 0
            mat_worktree_col = 0

            worker_count = 0
            task_total = 0
        }

        FNR == NR {
            # Parse any markdown table that contains "Task ID" and "Description"
            if ($0 ~ /^\|/) {
                parse_md_row($0)
                if (cell_count == 0 || is_separator_row()) next

                if (plan_task_col == 0 || plan_desc_col == 0) {
                    tmp_task_col = 0
                    tmp_desc_col = 0
                    for (j = 1; j <= cell_count; j++) {
                        if (cells_lc[j] == "task id" || cells_lc[j] == "taskid" || cells_lc[j] == "task") tmp_task_col = j
                        if (cells_lc[j] == "description" || cells_lc[j] == "desc") tmp_desc_col = j
                    }
                    if (tmp_task_col > 0 && tmp_desc_col > 0) {
                        plan_task_col = tmp_task_col
                        plan_desc_col = tmp_desc_col
                        next
                    }
                }

                if (plan_task_col > 0 && plan_desc_col > 0 && plan_task_col <= cell_count && plan_desc_col <= cell_count) {
                    task_id = trim(cells_raw[plan_task_col])
                    desc = trim(cells_raw[plan_desc_col])
                    if (tolower(task_id) ~ /^task[0-9a-z._-]+$/) {
                        plan_desc[task_id] = desc
                    }
                }
            }
            next
        }

        {
            if ($0 ~ /^##[[:space:]]+Parallelization Matrix[[:space:]]*$/) {
                in_matrix = 1
                next
            }
            if (!in_matrix) next

            if ($0 !~ /^\|/) next
            parse_md_row($0)
            if (cell_count == 0 || is_separator_row()) next

            # Detect matrix header row
            if (mat_task_col == 0) {
                for (j = 1; j <= cell_count; j++) {
                    if (cells_lc[j] == "task id" || cells_lc[j] == "taskid" || cells_lc[j] == "task") mat_task_col = j
                    if (cells_lc[j] ~ /^parallelizable/) mat_parallel_col = j
                    if (cells_lc[j] == "file ownership" || cells_lc[j] == "ownership") mat_owner_col = j
                    if (cells_lc[j] == "blockedby" || cells_lc[j] == "blocked by" || cells_lc[j] == "depends on") mat_blocked_col = j
                    if (cells_lc[j] == "worker") mat_worker_col = j
                    if (cells_lc[j] == "reviewer") mat_reviewer_col = j
                    if (cells_lc[j] == "worktree path" || cells_lc[j] == "worktree") mat_worktree_col = j
                }
                if (mat_task_col > 0 && mat_parallel_col > 0 && mat_worker_col > 0 && mat_worktree_col > 0) {
                    next
                }
            }

            if (mat_task_col == 0 || mat_parallel_col == 0) next

            task_id = trim(cells_raw[mat_task_col])
            parallel = tolower(trim(cells_raw[mat_parallel_col]))
            if (parallel != "yes") next

            # Readiness filter: when use_ready_filter is active and task is not ready,
            # either skip it (default) or annotate it (--include-blocked mode).
            is_blocked_task = 0
            if (use_ready_filter && !(task_id in ready_set)) {
                if (blocked_annotation) {
                    is_blocked_task = 1
                } else {
                    next
                }
            }

            worker = (mat_worker_col > 0 && mat_worker_col <= cell_count) ? strip_ticks(cells_raw[mat_worker_col]) : ""
            reviewer = (mat_reviewer_col > 0 && mat_reviewer_col <= cell_count) ? strip_ticks(cells_raw[mat_reviewer_col]) : ""
            worktree = (mat_worktree_col > 0 && mat_worktree_col <= cell_count) ? strip_ticks(cells_raw[mat_worktree_col]) : ""
            blocked = (mat_blocked_col > 0 && mat_blocked_col <= cell_count) ? trim(cells_raw[mat_blocked_col]) : "-"
            ownership = (mat_owner_col > 0 && mat_owner_col <= cell_count) ? trim(cells_raw[mat_owner_col]) : ""

            if (worker == "") worker = "worker-?"
            if (worktree == "") worktree = "[missing worktree path]"
            if (blocked == "") blocked = "-"
            if (ownership == "") ownership = "[missing file ownership]"

            # --strict-blockedby: detect external (non-task-ID) blockers and emit
            # errors to stderr. Also track strict-blocked status for annotation.
            is_strict_blocked = 0
            if (strict_blockedby && !all_task_ids(blocked)) {
                print "ERROR: task '" task_id "' blocked by external constraint '" blocked "' (strict mode; resolve before dispatching)" > "/dev/stderr"
                is_strict_blocked = 1
            }

            if (!(worker in seen_worker)) {
                worker_count++
                worker_order[worker_count] = worker
                seen_worker[worker] = 1
                worker_worktree[worker] = worktree
                worker_reviewer[worker] = reviewer
            }

            desc = (task_id in plan_desc) ? plan_desc[task_id] : "[missing description in plan]"

            # --max-tasks-per-lane: enforce per-lane task count limit.
            # Track how many tasks have been recorded for each worker lane.
            if (max_tasks_per_lane > 0) {
                worker_task_count[worker]++
                if (worker_task_count[worker] > max_tasks_per_lane) {
                    next
                }
            }

            task_total++
            if (is_strict_blocked && blocked_annotation) {
                tasks[worker] = tasks[worker] sprintf("- %s: %s (blockedBy: %s; ownership: %s) [STRICT-BLOCKED]\n", task_id, desc, blocked, ownership)
            } else if (is_blocked_task) {
                tasks[worker] = tasks[worker] sprintf("- %s: %s (blockedBy: %s; ownership: %s) [BLOCKED: check task-state.json]\n", task_id, desc, blocked, ownership)
            } else {
                tasks[worker] = tasks[worker] sprintf("- %s: %s (blockedBy: %s; ownership: %s)\n", task_id, desc, blocked, ownership)
            }
        }

        END {
            if (task_total == 0) {
                exit 0
            }

            for (i = 1; i <= worker_count; i++) {
                w = worker_order[i]
                print ""
                printf("### Lane %s\n", w)
                printf("- Worktree: `%s`\n", worker_worktree[w])
                if (worker_reviewer[w] != "") {
                    printf("- Reviewer: `%s`\n", worker_reviewer[w])
                }
                printf("- Commands: `cd %s`\n", worker_worktree[w])
                print "- Tasks:"
                # Indent task lines under the Tasks bullet for readability
                split(tasks[w], lines, "\n")
                for (j = 1; j <= length(lines); j++) {
                    if (lines[j] == "") continue
                    printf("  %s\n", lines[j])
                }
            }
        }
    ' "$PLAN_FILE" "$ASSIGNMENT_FILE"
)

if [[ -z "$LANES_OUTPUT" ]]; then
    if [[ "$READY_FILTER_ACTIVE" -eq 1 ]]; then
        # Readiness filtering is active but no tasks are currently ready.
        # This is a correct state: all tasks have unmet dependencies.
        cat << 'EMPTY_EOF'

No tasks are currently ready (all dependencies are unmet or the lane cap is reached).

Next:
1) Check `task-state.json` to see which tasks are `done` vs `pending`
2) Use `python3 scripts/task-graph.py ready --state <task-state.json>` to debug
3) Or re-run with `--include-blocked` to see blocked tasks with annotations
EMPTY_EOF
    else
        cat << 'EMPTY_EOF'

No tasks are marked `Parallelizable=yes` in `worktree-assignment.md`.

Next:
1) Open `worktree-assignment.md` and set `Parallelizable (yes/no)` to `yes` for safe tasks
2) Fill `File Ownership` to prevent collisions
3) Re-run: `/humanize:gen-batch-prompt`
EMPTY_EOF
    fi
    exit 0
fi

echo "$LANES_OUTPUT"
