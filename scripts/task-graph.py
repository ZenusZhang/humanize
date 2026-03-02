#!/usr/bin/env python3
"""
task-graph.py -- Markdown table parser and DAG builder for the humanize plugin.

Parses task dependency information from two sources:
  1. A plan file (Markdown table with columns: Task ID, Depends On)
  2. A worktree-assignment.md file (Parallelization Matrix table with columns: Task ID, blockedBy)

Provides subcommands:
  parse      -- Parse and validate the dependency graph; print results to stdout
  init       -- Lazily initialize task-state.json from the plan task table
  reconcile  -- Reconcile task-state.json with the current plan and assignment
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone


# ---------------------------------------------------------------------------
# Markdown table parsing helpers
# ---------------------------------------------------------------------------


def _split_cells(row: str) -> list[str]:
    """Split a Markdown table row by '|', strip whitespace from each cell."""
    parts = row.split("|")
    # Leading and trailing empty strings from surrounding pipes are discarded
    return [p.strip() for p in parts[1:-1]] if row.startswith("|") else [p.strip() for p in parts]


def _parse_table_header(line: str) -> list[str]:
    """Return lowercased column names from a Markdown table header row."""
    return [cell.lower() for cell in _split_cells(line)]


def _is_separator_row(line: str) -> bool:
    """Return True if the line is a Markdown table separator (e.g., |---|---|)."""
    stripped = line.strip()
    if not stripped.startswith("|"):
        return False
    inner = stripped.strip("|").strip()
    return all(c in "-: |" for c in inner) and "-" in inner


def _normalize_dep_list(raw: str) -> list[str]:
    """
    Parse a comma-separated dependency cell value into a list of task IDs.

    Normalization rules applied:
      - Strip backtick wrapping (e.g., `task1` -> task1)
      - Treat '-' or empty string as meaning no dependencies
      - Strip surrounding whitespace from each entry
    """
    raw = raw.strip()
    if not raw or raw == "-":
        return []
    parts = raw.split(",")
    result = []
    for part in parts:
        part = part.strip().strip("`").strip()
        if part and part != "-":
            result.append(part)
    return result


def _find_column_index(headers: list[str], name: str) -> int:
    """Return 0-based index of a column by name, or -1 if not found."""
    try:
        return headers.index(name.lower())
    except ValueError:
        return -1


def parse_plan_file(path: str) -> dict[str, list[str]]:
    """
    Parse the plan Markdown file and extract task_id -> list_of_dep_ids from
    a table containing columns 'Task ID' and 'Depends On'.

    Returns a dict mapping each task ID to its list of declared dependencies.
    Returns an empty dict if no matching table is found.
    """
    deps: dict[str, list[str]] = {}

    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    i = 0
    while i < len(lines):
        line = lines[i].rstrip("\n")
        # Check if this looks like a table header row containing both columns
        if "|" in line:
            headers = _parse_table_header(line)
            task_id_col = _find_column_index(headers, "task id")
            depends_on_col = _find_column_index(headers, "depends on")

            if task_id_col >= 0 and depends_on_col >= 0:
                # Verify next line is a separator
                if i + 1 < len(lines) and _is_separator_row(lines[i + 1]):
                    i += 2  # skip header and separator
                    # Parse data rows
                    while i < len(lines):
                        row_line = lines[i].rstrip("\n")
                        if not row_line.strip() or not row_line.strip().startswith("|"):
                            break
                        if _is_separator_row(row_line):
                            break
                        cells = _split_cells(row_line)
                        # Ensure enough columns
                        max_col = max(task_id_col, depends_on_col)
                        if len(cells) > max_col:
                            task_id = cells[task_id_col].strip().strip("`").strip()
                            depends_on_raw = cells[depends_on_col]
                            if task_id:
                                deps[task_id] = _normalize_dep_list(depends_on_raw)
                        i += 1
                    continue
        i += 1

    return deps


def parse_assignment_file(path: str) -> dict[str, list[str]]:
    """
    Parse the worktree-assignment.md file and extract task_id -> list_of_blocked_by_ids
    from the 'Parallelization Matrix' section table containing columns
    'Task ID' and 'blockedBy'.

    Returns a dict mapping each task ID to its list of declared blockedBy values.
    Returns an empty dict if no matching section or table is found.
    """
    blocked_by: dict[str, list[str]] = {}

    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # Find the "Parallelization Matrix" section
    in_section = False
    i = 0
    while i < len(lines):
        line = lines[i].rstrip("\n")
        if "parallelization matrix" in line.lower():
            in_section = True
            i += 1
            continue

        if in_section:
            # Look for table header
            if "|" in line:
                headers = _parse_table_header(line)
                task_id_col = _find_column_index(headers, "task id")
                blocked_by_col = _find_column_index(headers, "blockedby")

                if task_id_col >= 0 and blocked_by_col >= 0:
                    # Verify next line is a separator
                    if i + 1 < len(lines) and _is_separator_row(lines[i + 1]):
                        i += 2  # skip header and separator
                        while i < len(lines):
                            row_line = lines[i].rstrip("\n")
                            # Stop at blank line or non-table line (but skip HTML comments)
                            stripped = row_line.strip()
                            if stripped.startswith("<!--"):
                                i += 1
                                continue
                            if not stripped or not stripped.startswith("|"):
                                break
                            if _is_separator_row(row_line):
                                break
                            cells = _split_cells(row_line)
                            max_col = max(task_id_col, blocked_by_col)
                            if len(cells) > max_col:
                                task_id = cells[task_id_col].strip().strip("`").strip()
                                blocked_raw = cells[blocked_by_col]
                                if task_id:
                                    blocked_by[task_id] = _normalize_dep_list(blocked_raw)
                            i += 1
                        break

            # Stop searching if we hit the next section header
            if line.startswith("##") and "parallelization matrix" not in line.lower():
                break

        i += 1

    return blocked_by


# ---------------------------------------------------------------------------
# Graph builder
# ---------------------------------------------------------------------------


def build_graph(
    plan_deps: dict[str, list[str]],
    assignment_blocked: dict[str, list[str]],
) -> dict[str, set[str]]:
    """
    Merge plan dependencies and assignment blockedBy entries into a unified
    directed graph.

    graph[task_id] = set of prerequisite task IDs that must complete before
    task_id is considered ready.

    All task IDs known from plan_deps are included in the graph even if they
    have no dependencies. Task IDs that appear only in assignment_blocked are
    also added.
    """
    graph: dict[str, set[str]] = {}

    # Seed graph with all plan tasks
    for task_id, dep_list in plan_deps.items():
        if task_id not in graph:
            graph[task_id] = set()
        for dep in dep_list:
            graph[task_id].add(dep)

    # Merge blockedBy from assignment (only known task IDs as deps)
    for task_id, blocked_list in assignment_blocked.items():
        if task_id not in graph:
            graph[task_id] = set()
        for dep in blocked_list:
            graph[task_id].add(dep)

    return graph


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------


def detect_cycle(graph: dict[str, set[str]]) -> list[str] | None:
    """
    Perform a DFS-based cycle detection on a directed graph.

    Each key in graph maps to a set of prerequisite (dependency) task IDs.
    The DFS traverses edges from a task to its dependencies.

    Returns None if the graph is a valid DAG (no cycle found).
    Returns a list of task IDs representing the cycle path if a cycle is
    detected (e.g., ["task1", "task2", "task1"]).
    """
    # DFS color states: 0 = unvisited, 1 = in current path (gray), 2 = done (black)
    color: dict[str, int] = {node: 0 for node in graph}
    # Track the DFS path stack for cycle reconstruction
    path: list[str] = []

    def dfs(node: str) -> list[str] | None:
        color[node] = 1
        path.append(node)
        for neighbor in graph.get(node, set()):
            if neighbor not in color:
                # Neighbor is a dependency referenced but not a top-level key;
                # treat as a leaf (no outgoing edges), skip.
                continue
            if color[neighbor] == 1:
                # Back edge found: neighbor is on the current DFS path -> cycle
                cycle_start = path.index(neighbor)
                return path[cycle_start:] + [neighbor]
            if color[neighbor] == 0:
                result = dfs(neighbor)
                if result is not None:
                    return result
        path.pop()
        color[node] = 2
        return None

    for node in list(graph.keys()):
        if color[node] == 0:
            result = dfs(node)
            if result is not None:
                return result

    return None


def validate_graph(
    graph: dict[str, set[str]],
    plan_deps: dict[str, list[str]],
    assignment_blocked: dict[str, list[str]],
) -> bool:
    """
    Validate the graph for unknown task IDs and cycles.

    Rules:
      - Any dep referenced in 'Depends On' (plan_deps) that is not a known
        task ID causes a fatal error printed to stderr; returns False.
      - Any dep referenced in 'blockedBy' (assignment_blocked) that is not
        a known task ID generates a WARNING (not fatal).
      - A cycle in the dependency graph is a fatal error; returns False.

    Returns True if no fatal errors were found, False otherwise.
    """
    known_tasks = set(graph.keys())
    valid = True

    # Check plan Depends On references
    for task_id, dep_list in plan_deps.items():
        for dep in dep_list:
            if dep not in known_tasks:
                print(
                    f"ERROR: Unknown task ID '{dep}' referenced in 'Depends On' of task '{task_id}'",
                    file=sys.stderr,
                )
                valid = False

    # Check assignment blockedBy references
    for task_id, blocked_list in assignment_blocked.items():
        for dep in blocked_list:
            if dep not in known_tasks:
                print(
                    f"WARNING: Non-task-ID value '{dep}' in blockedBy of '{task_id}'"
                    " -- treating as external block",
                    file=sys.stderr,
                )

    # Check for cycles in the dependency graph
    cycle = detect_cycle(graph)
    if cycle is not None:
        cycle_str = " -> ".join(cycle)
        print(f"ERROR: Cycle detected: {cycle_str}", file=sys.stderr)
        valid = False

    return valid


# ---------------------------------------------------------------------------
# Subcommand: parse
# ---------------------------------------------------------------------------


def cmd_parse(args: argparse.Namespace) -> int:
    """
    Parse the plan and optional assignment file, build the DAG, validate it,
    and print each task's sorted dependency list to stdout.

    Exit code: 0 on success, 1 on validation error.
    """
    plan_deps = parse_plan_file(args.plan)

    assignment_blocked: dict[str, list[str]] = {}
    if args.assignment:
        if not os.path.isfile(args.assignment):
            print(f"ERROR: Assignment file not found: {args.assignment}", file=sys.stderr)
            return 1
        assignment_blocked = parse_assignment_file(args.assignment)

    graph = build_graph(plan_deps, assignment_blocked)
    valid = validate_graph(graph, plan_deps, assignment_blocked)

    # Print results sorted by task_id
    for task_id in sorted(graph.keys()):
        deps_sorted = sorted(graph[task_id])
        print(f"{task_id}: {deps_sorted}")

    if valid:
        print("Graph is valid.")

    return 0 if valid else 1


# ---------------------------------------------------------------------------
# Subcommand: init
# ---------------------------------------------------------------------------


def _utc_now_iso() -> str:
    """Return the current UTC time as an ISO 8601 string with 'Z' suffix."""
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%SZ")


def cmd_init(args: argparse.Namespace) -> int:
    """
    Lazily initialize task-state.json from the plan task table.

    If the state file already exists, print a notice and exit 0 without
    overwriting. Otherwise, write a new state file with all tasks set to
    'pending', using atomic write (tmp -> rename).

    Exit code: 0 always.
    """
    state_path = args.state

    if os.path.isfile(state_path):
        print(f"task-state.json already exists at '{state_path}'; skipping initialization.")
        return 0

    plan_deps = parse_plan_file(args.plan)

    assignment_blocked: dict[str, list[str]] = {}
    if args.assignment:
        if os.path.isfile(args.assignment):
            assignment_blocked = parse_assignment_file(args.assignment)

    graph = build_graph(plan_deps, assignment_blocked)

    now_str = _utc_now_iso()
    tasks_state: dict[str, dict] = {}
    for task_id in sorted(graph.keys()):
        tasks_state[task_id] = {
            "status": "pending",
            "last_updated": now_str,
            "reviewer_signoff": False,
        }

    state: dict = {
        "version": 1,
        "tasks": tasks_state,
        "lane_iterations": {},
    }

    # Atomic write: write to .tmp then rename
    tmp_path = state_path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)
        f.write("\n")
    os.replace(tmp_path, state_path)

    print(f"Initialized '{state_path}' with {len(tasks_state)} task(s) set to 'pending'.")
    return 0


# ---------------------------------------------------------------------------
# State read/write helpers
# ---------------------------------------------------------------------------


def read_state(path: str) -> dict:
    """
    Read task-state.json (schema v1) from path.

    Returns the parsed dict on success. If the file does not exist, returns
    an empty dict. If the file contains invalid JSON, prints a WARNING to
    stderr and returns an empty dict.
    """
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        print(f"WARNING: Failed to parse state file '{path}': {exc}", file=sys.stderr)
        return {}


def write_state(state: dict, path: str) -> None:
    """
    Atomically write state dict to path.

    Writes to <path>.tmp first, then renames to path to avoid partial writes.
    """
    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)
        f.write("\n")
    os.replace(tmp_path, path)


# ---------------------------------------------------------------------------
# State transition validation
# ---------------------------------------------------------------------------

# Allowed transitions: map from old_status to the set of permitted new statuses.
# "deferred" is reachable from any status (handled separately in validate_transition).
_ALLOWED_TRANSITIONS: dict[str, set[str]] = {
    "pending": {"ready", "in_progress", "deferred"},
    "ready": {"in_progress", "deferred"},
    "in_progress": {"done", "failed", "deferred"},
    "failed": {"pending", "deferred"},
    # "done" and "deferred" intentionally have no outgoing allowed transitions
    # except for deferred which allows deferred->deferred (handled below).
}


def validate_transition(old_status: str, new_status: str) -> bool:
    """
    Return True if transitioning from old_status to new_status is permitted.

    Allowed transitions:
      pending    -> ready, in_progress, deferred
      ready      -> in_progress, deferred
      in_progress -> done, failed, deferred
      failed     -> pending, deferred
      done       -> (terminal; no transitions allowed)
      any        -> deferred  (manual coordinator deferral)
    """
    if old_status == "done":
        # done is a terminal state; no transitions allowed from it
        return False
    # deferred is reachable from any non-done status
    if new_status == "deferred":
        return True
    allowed = _ALLOWED_TRANSITIONS.get(old_status, set())
    return new_status in allowed


# ---------------------------------------------------------------------------
# Subcommand: reconcile
# ---------------------------------------------------------------------------


def cmd_reconcile(args: argparse.Namespace) -> int:
    """
    Reconcile task-state.json with the current set of tasks from the plan
    and optional assignment file.

    Logic:
      1. Parse plan (and assignment if provided) to get the live task ID set.
      2. Read existing state file (or empty dict if missing).
      3. For each task in the live set NOT in state: add it as 'pending'.
      4. For each task in state NOT in the live set: if its status is not
         already 'deferred' or 'done', set it to 'deferred'.
      5. Write updated state atomically.
      6. Print summary: tasks added (pending) and tasks deferred.

    Exit code: 0 always.
    """
    plan_deps = parse_plan_file(args.plan)

    assignment_blocked: dict[str, list[str]] = {}
    if args.assignment:
        if os.path.isfile(args.assignment):
            assignment_blocked = parse_assignment_file(args.assignment)

    graph = build_graph(plan_deps, assignment_blocked)
    live_tasks: set[str] = set(graph.keys())

    state = read_state(args.state)

    # Ensure top-level structure is present
    if "tasks" not in state:
        state["tasks"] = {}
    if "version" not in state:
        state["version"] = 1
    if "lane_iterations" not in state:
        state["lane_iterations"] = {}

    tasks_state: dict[str, dict] = state["tasks"]
    now_str = _utc_now_iso()

    added_count = 0
    deferred_count = 0

    # Add tasks that are in the live set but not yet in state
    for task_id in sorted(live_tasks):
        if task_id not in tasks_state:
            tasks_state[task_id] = {
                "status": "pending",
                "last_updated": now_str,
                "reviewer_signoff": False,
            }
            added_count += 1

    # Defer tasks that are in state but no longer in the live set
    for task_id, task_info in tasks_state.items():
        if task_id not in live_tasks:
            current_status = task_info.get("status", "pending")
            if current_status not in ("deferred", "done"):
                task_info["status"] = "deferred"
                task_info["last_updated"] = now_str
                deferred_count += 1

    state["tasks"] = tasks_state
    write_state(state, args.state)

    print(f"Reconcile complete: {added_count} task(s) added as pending, "
          f"{deferred_count} task(s) deferred.")
    return 0


# ---------------------------------------------------------------------------
# Self-verification (invoked when --verify flag is passed to the script)
# ---------------------------------------------------------------------------


def _run_verification() -> None:
    """
    Run acceptance tests for read_state, write_state, validate_transition,
    and the reconcile logic. Prints VERIFICATION PASSED on success or raises
    AssertionError with a descriptive message on failure.
    """
    import tempfile

    failures: list[str] = []

    def check(label: str, condition: bool) -> None:
        if not condition:
            failures.append(f"FAIL: {label}")

    # ------------------------------------------------------------------
    # Test 1: read_state on a non-existent file returns {}
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as tmpdir:
        missing_path = os.path.join(tmpdir, "nonexistent.json")
        result = read_state(missing_path)
        check("read_state non-existent file returns {}", result == {})

    # ------------------------------------------------------------------
    # Test 2: write_state then read_state round-trips data exactly
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as tmpdir:
        state_path = os.path.join(tmpdir, "state.json")
        original = {
            "version": 1,
            "tasks": {
                "task1": {"status": "pending", "last_updated": "2026-01-01T00:00:00Z",
                          "reviewer_signoff": False},
            },
            "lane_iterations": {},
        }
        write_state(original, state_path)
        loaded = read_state(state_path)
        check("write_state/read_state round-trip", loaded == original)

    # ------------------------------------------------------------------
    # Test 3: validate_transition edge cases
    # ------------------------------------------------------------------
    check("done -> pending is NOT allowed", not validate_transition("done", "pending"))
    check("pending -> ready is allowed", validate_transition("pending", "ready"))
    check("failed -> pending is allowed", validate_transition("failed", "pending"))
    check("pending -> in_progress is allowed", validate_transition("pending", "in_progress"))
    check("ready -> in_progress is allowed", validate_transition("ready", "in_progress"))
    check("in_progress -> done is allowed", validate_transition("in_progress", "done"))
    check("in_progress -> failed is allowed", validate_transition("in_progress", "failed"))
    check("any -> deferred: pending -> deferred", validate_transition("pending", "deferred"))
    check("any -> deferred: ready -> deferred", validate_transition("ready", "deferred"))
    check("any -> deferred: in_progress -> deferred", validate_transition("in_progress", "deferred"))
    check("any -> deferred: failed -> deferred", validate_transition("failed", "deferred"))
    check("done -> deferred is NOT allowed (done is terminal)", not validate_transition("done", "deferred"))
    check("done -> done is NOT allowed", not validate_transition("done", "done"))
    check("pending -> failed is NOT allowed", not validate_transition("pending", "failed"))

    # ------------------------------------------------------------------
    # Test 4: reconcile with existing state (task1=done, task2=pending),
    # plan adds task3 and removes task2 -> task3 added as pending,
    # task2 deferred, task1 stays done.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as tmpdir:
        # Write a plan with task1 and task3 (no task2)
        plan_path = os.path.join(tmpdir, "plan.md")
        plan_content = (
            "| Task ID | Depends On |\n"
            "|---------|------------|\n"
            "| task1   | -          |\n"
            "| task3   | task1      |\n"
        )
        with open(plan_path, "w", encoding="utf-8") as pf:
            pf.write(plan_content)

        state_path = os.path.join(tmpdir, "task-state.json")
        initial_state = {
            "version": 1,
            "tasks": {
                "task1": {"status": "done", "last_updated": "2026-01-01T00:00:00Z",
                          "reviewer_signoff": True},
                "task2": {"status": "pending", "last_updated": "2026-01-01T00:00:00Z",
                          "reviewer_signoff": False},
            },
            "lane_iterations": {},
        }
        write_state(initial_state, state_path)

        # Simulate reconcile
        class _Args:
            pass

        rec_args = _Args()
        rec_args.plan = plan_path  # type: ignore[attr-defined]
        rec_args.state = state_path  # type: ignore[attr-defined]
        rec_args.assignment = None  # type: ignore[attr-defined]

        cmd_reconcile(rec_args)

        final = read_state(state_path)
        tasks = final.get("tasks", {})

        check("test4: task1 stays done", tasks.get("task1", {}).get("status") == "done")
        check("test4: task2 becomes deferred", tasks.get("task2", {}).get("status") == "deferred")
        check("test4: task3 added as pending", tasks.get("task3", {}).get("status") == "pending")

    # ------------------------------------------------------------------
    # Test 5: reconcile when state file does not exist creates new state
    # with all tasks as pending.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as tmpdir:
        plan_path = os.path.join(tmpdir, "plan.md")
        plan_content = (
            "| Task ID | Depends On |\n"
            "|---------|------------|\n"
            "| taskA   | -          |\n"
            "| taskB   | taskA      |\n"
        )
        with open(plan_path, "w", encoding="utf-8") as pf:
            pf.write(plan_content)

        state_path = os.path.join(tmpdir, "task-state.json")
        # Ensure the file does not exist
        assert not os.path.isfile(state_path)

        rec_args = _Args()
        rec_args.plan = plan_path  # type: ignore[attr-defined]
        rec_args.state = state_path  # type: ignore[attr-defined]
        rec_args.assignment = None  # type: ignore[attr-defined]

        cmd_reconcile(rec_args)

        check("test5: state file was created", os.path.isfile(state_path))
        final = read_state(state_path)
        tasks = final.get("tasks", {})
        check("test5: taskA is pending", tasks.get("taskA", {}).get("status") == "pending")
        check("test5: taskB is pending", tasks.get("taskB", {}).get("status") == "pending")

    # ------------------------------------------------------------------
    # Report
    # ------------------------------------------------------------------
    if failures:
        for msg in failures:
            print(msg, file=sys.stderr)
        sys.exit(1)
    else:
        print("VERIFICATION PASSED")


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    """Build and return the argument parser."""
    parser = argparse.ArgumentParser(
        prog="task-graph.py",
        description="Markdown table parser and DAG builder for task dependency management.",
    )
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    # -- parse subcommand --
    parse_parser = subparsers.add_parser(
        "parse",
        help="Parse plan and optional assignment file; validate and print dependency graph.",
    )
    parse_parser.add_argument("--plan", required=True, help="Path to the plan Markdown file.")
    parse_parser.add_argument(
        "--assignment",
        default=None,
        help="Path to the worktree-assignment.md file (optional).",
    )

    # -- init subcommand --
    init_parser = subparsers.add_parser(
        "init",
        help="Lazily initialize task-state.json from the plan task table.",
    )
    init_parser.add_argument("--plan", required=True, help="Path to the plan Markdown file.")
    init_parser.add_argument(
        "--state",
        default="task-state.json",
        help="Path to the task-state.json file to create (default: task-state.json).",
    )
    init_parser.add_argument(
        "--assignment",
        default=None,
        help="Path to the worktree-assignment.md file (optional).",
    )

    # -- reconcile subcommand --
    reconcile_parser = subparsers.add_parser(
        "reconcile",
        help="Reconcile task-state.json with the current plan and assignment.",
    )
    reconcile_parser.add_argument("--plan", required=True, help="Path to the plan Markdown file.")
    reconcile_parser.add_argument(
        "--state",
        default="task-state.json",
        help="Path to the task-state.json file to reconcile (default: task-state.json).",
    )
    reconcile_parser.add_argument(
        "--assignment",
        default=None,
        help="Path to the worktree-assignment.md file (optional).",
    )

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.subcommand == "parse":
        return cmd_parse(args)
    elif args.subcommand == "init":
        return cmd_init(args)
    elif args.subcommand == "reconcile":
        return cmd_reconcile(args)
    else:
        print(f"ERROR: Unknown subcommand '{args.subcommand}'", file=sys.stderr)
        return 1


if __name__ == "__main__":
    # Allow --verify flag to run self-verification tests instead of normal CLI
    if len(sys.argv) == 2 and sys.argv[1] == "--verify":
        _run_verification()
    else:
        sys.exit(main())
