#!/usr/bin/env python3
"""
task-graph.py -- Markdown table parser and DAG builder for the humanize plugin.

Parses task dependency information from two sources:
  1. A plan file (Markdown table with columns: Task ID, Depends On)
  2. A worktree-assignment.md file (Parallelization Matrix table with columns: Task ID, blockedBy)

Provides subcommands:
  parse          -- Parse and validate the dependency graph; print results to stdout
  init           -- Lazily initialize task-state.json from the plan task table
  reconcile      -- Reconcile task-state.json with the current plan and assignment
  increment-lane -- Increment the iteration count for a lane; print escalation if cap reached
  reset-lane     -- Reset the iteration count for a lane to 0
  ready          -- Compute and print the ready set of tasks in topological order
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from typing import Optional


# ---------------------------------------------------------------------------
# Markdown table parsing helpers
# ---------------------------------------------------------------------------


def _split_cells(row: str) -> list[str]:
    """Split a Markdown table row by '|', strip whitespace from each cell.

    Handles both rows with and without a trailing pipe:
      | task1 | -  |   -> ["task1", "-"]   (trailing pipe present)
      | task1 | -      -> ["task1", "-"]   (no trailing pipe)
    """
    parts = row.split("|")
    if row.startswith("|"):
        parts = parts[1:]  # discard leading empty string from leading '|'
    if parts and parts[-1].strip() == "":
        parts = parts[:-1]  # discard trailing empty string only when trailing '|' was present
    return [p.strip() for p in parts]


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
            # Only add dep as a graph edge when it refers to a known task.
            # External constraints (free-form text) are not graph dependencies;
            # they are surfaced as warnings by validate_graph() / compute_ready_set().
            if dep in plan_deps or dep in assignment_blocked:
                graph[task_id].add(dep)

    return graph


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------


def detect_cycle(graph: dict[str, set[str]]) -> Optional[list[str]]:
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

    def dfs(node: str) -> Optional[list[str]]:
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
# Lane iteration tracking helpers
# ---------------------------------------------------------------------------


def get_lane_count(state: dict, lane: str) -> int:
    """
    Return the current iteration count for the given lane.

    Returns 0 if the lane is not present in lane_iterations.
    """
    lane_iterations: dict = state.get("lane_iterations", {})
    lane_info: dict = lane_iterations.get(lane, {})
    return lane_info.get("count", 0)


def get_lane_max(state: dict, lane: str, default_max: int = 5) -> int:
    """
    Return the configured max iterations for the given lane.

    Falls back to default_max if the lane is not present or has no 'max' set.
    """
    lane_iterations: dict = state.get("lane_iterations", {})
    lane_info: dict = lane_iterations.get(lane, {})
    return lane_info.get("max", default_max)


def is_lane_at_cap(state: dict, lane: str, default_max: int = 5) -> bool:
    """
    Return True if the lane's iteration count has reached or exceeded its max.
    """
    count = get_lane_count(state, lane)
    max_count = get_lane_max(state, lane, default_max)
    return count >= max_count


def format_escalation_message(lane: str, count: int, max_count: int, task_ids: list[str]) -> str:
    """
    Return a human-readable escalation message for a lane that has reached its
    iteration cap.

    The message includes the lane name, iteration count/max, the task IDs
    associated with the lane, and a suggestion to re-scope or re-plan.
    """
    tasks_str = ", ".join(task_ids) if task_ids else "(none)"
    return (
        f"ESCALATION: Lane '{lane}' has reached the iteration cap ({count}/{max_count}).\n"
        f"Tasks in this lane: {tasks_str}\n"
        f"Action required: re-scope or re-plan the above tasks before continuing."
    )


# ---------------------------------------------------------------------------
# Subcommand: increment-lane
# ---------------------------------------------------------------------------


def cmd_increment_lane(args: argparse.Namespace) -> int:
    """
    Increment the iteration count for a lane in task-state.json.

    If --max N is provided, validates N >= 1 and sets/updates the max for the lane.
    If --tasks is provided, sets/updates the tasks list for the lane.
    After incrementing, if count >= max, prints the escalation message to stdout
    and prints 'LANE_CAP_REACHED' on a separate line.

    Exit code: 0 always (except when --max is invalid, which exits with 1).
    """
    # Validate --max if provided
    if args.max is not None and args.max < 1:
        print("ERROR: lane_max_iterations must be >= 1", file=sys.stderr)
        return 1

    state = read_state(args.state)

    # Ensure top-level structure is present
    if "version" not in state:
        state["version"] = 1
    if "tasks" not in state:
        state["tasks"] = {}
    if "lane_iterations" not in state:
        state["lane_iterations"] = {}

    lane_iterations: dict = state["lane_iterations"]
    if args.lane not in lane_iterations:
        lane_iterations[args.lane] = {"count": 0, "max": 5, "tasks": []}

    lane_info: dict = lane_iterations[args.lane]

    # Update max if provided
    if args.max is not None:
        lane_info["max"] = args.max

    # Update tasks list if provided
    if args.tasks is not None:
        lane_info["tasks"] = [t.strip() for t in args.tasks.split(",") if t.strip()]

    # Increment count
    lane_info["count"] = lane_info.get("count", 0) + 1

    write_state(state, args.state)

    current_count: int = lane_info["count"]
    current_max: int = lane_info.get("max", 5)
    current_tasks: list[str] = lane_info.get("tasks", [])

    if current_count >= current_max:
        msg = format_escalation_message(args.lane, current_count, current_max, current_tasks)
        print(msg)
        print("LANE_CAP_REACHED")

    return 0


# ---------------------------------------------------------------------------
# Subcommand: reset-lane
# ---------------------------------------------------------------------------


def cmd_reset_lane(args: argparse.Namespace) -> int:
    """
    Reset the iteration count for a lane to 0 in task-state.json.

    Preserves the existing 'max' and 'tasks' values for the lane.

    Exit code: 0 always.
    """
    state = read_state(args.state)

    # Ensure top-level structure is present
    if "version" not in state:
        state["version"] = 1
    if "tasks" not in state:
        state["tasks"] = {}
    if "lane_iterations" not in state:
        state["lane_iterations"] = {}

    lane_iterations: dict = state["lane_iterations"]
    if args.lane not in lane_iterations:
        lane_iterations[args.lane] = {"count": 0, "max": 5, "tasks": []}
    else:
        lane_iterations[args.lane]["count"] = 0

    write_state(state, args.state)

    print(f"Lane '{args.lane}' iteration count reset to 0.")
    return 0


# ---------------------------------------------------------------------------
# Topological sort
# ---------------------------------------------------------------------------


def topological_sort(graph: dict[str, set[str]]) -> list[str]:
    """
    Return a topological ordering of all nodes in graph using Kahn's algorithm.

    graph[task_id] = set of prerequisite task IDs (edges point FROM dependents TO deps).
    Nodes with equal in-degree are processed in alphabetical order to ensure a
    deterministic output.

    Raises ValueError if a cycle is detected (defensive; validate_graph should
    have caught any cycle beforehand).
    """
    # Collect all nodes (including dep nodes that might not be top-level keys)
    all_nodes: set[str] = set(graph.keys())
    for deps in graph.values():
        all_nodes.update(deps)

    # Compute in-degree: number of tasks that depend ON each node.
    # In our graph representation, graph[A] = {B, C} means A depends on B and C,
    # so there is an edge A -> B and A -> C in the dependency direction.
    # For topological sort, we want to process nodes with no dependents first
    # (i.e., nodes that are not depended upon by anyone, or whose deps are done).
    # Standard topo-sort: in-degree = number of incoming edges.
    # Edge direction: A depends on B => edge B -> A (B must come before A).
    # So in-degree[A] = number of tasks that have A as a dependency.
    in_degree: dict[str, int] = {node: 0 for node in all_nodes}
    # Build reverse adjacency: for each dep B in graph[A], B -> A
    reverse_adj: dict[str, list[str]] = {node: [] for node in all_nodes}
    for task_id in sorted(graph.keys()):
        for dep in graph[task_id]:
            if dep in all_nodes:
                in_degree[task_id] += 1
                reverse_adj[dep].append(task_id)

    # Initialize queue with nodes that have in-degree 0 (no unresolved deps)
    # sorted alphabetically for deterministic tie-breaking
    queue: list[str] = sorted(node for node in all_nodes if in_degree[node] == 0)

    result: list[str] = []
    while queue:
        # Pop first node (smallest alphabetically among zero-in-degree nodes)
        node = queue.pop(0)
        result.append(node)
        # Reduce in-degree of dependents; add newly zero-in-degree nodes
        new_ready: list[str] = []
        for dependent in reverse_adj[node]:
            in_degree[dependent] -= 1
            if in_degree[dependent] == 0:
                new_ready.append(dependent)
        # Insert new ready nodes in sorted position to maintain alphabetic order
        new_ready.sort()
        # Merge into queue keeping sort order
        merged: list[str] = []
        qi = 0
        ni = 0
        while qi < len(queue) and ni < len(new_ready):
            if queue[qi] <= new_ready[ni]:
                merged.append(queue[qi])
                qi += 1
            else:
                merged.append(new_ready[ni])
                ni += 1
        merged.extend(queue[qi:])
        merged.extend(new_ready[ni:])
        queue = merged

    if len(result) != len(all_nodes):
        remaining = sorted(all_nodes - set(result))
        raise ValueError(
            f"Cycle detected during topological sort; could not process: {remaining}"
        )

    return result


# ---------------------------------------------------------------------------
# Ready-set computation
# ---------------------------------------------------------------------------


def compute_ready_set(
    graph: dict[str, set[str]],
    state: dict,
    assignment_blocked: dict[str, list[str]],
    default_lane_max: int = 5,
) -> list[str]:
    """
    Compute and return the list of task IDs that are currently READY.

    A task is READY iff ALL of the following hold:
      1. Its status in state["tasks"] is "pending" or "ready" (not in_progress,
         done, failed, or deferred).  If the task is unknown in state but present
         in graph, it is treated as "pending".
      2. All of its dependencies (graph[task_id]) have status "done" in state.
      3. The task's assigned lane (from state["lane_iterations"]) is NOT at cap.
      4. The task has no non-task-ID blockedBy values in assignment_blocked
         (external constraints block the task).

    For tasks blocked by external (non-task-ID) blockedBy values a WARNING is
    printed to stderr.

    If state is empty (e.g., no task-state.json exists), ALL tasks in graph are
    treated as ready (backward-compatible behavior).

    Returns the ready task IDs in topological order with alphabetic tie-breaking.
    The result is stable: identical inputs always produce identical outputs.
    """
    known_tasks: set[str] = set(graph.keys())

    # Build set of task IDs from plan (used to distinguish task-ID blockedBy from external)
    all_task_ids: set[str] = set(graph.keys())
    for deps in graph.values():
        all_task_ids.update(deps)

    # Identify which tasks have external (non-task-ID) blockers
    external_blocked: dict[str, list[str]] = {}
    for task_id, blocked_list in assignment_blocked.items():
        ext = [b for b in blocked_list if b not in all_task_ids]
        if ext:
            external_blocked[task_id] = ext

    # Backward compat: if state is empty, return all tasks in topological order
    if not state:
        topo = topological_sort(graph)
        return [t for t in topo if t in known_tasks]

    tasks_state: dict[str, dict] = state.get("tasks", {})

    def get_status(task_id: str) -> str:
        return tasks_state.get(task_id, {}).get("status", "pending")

    # Find the lane for each task by scanning lane_iterations tasks lists
    task_to_lane: dict[str, str] = {}
    lane_iterations: dict = state.get("lane_iterations", {})
    for lane_name, lane_info in lane_iterations.items():
        for tid in lane_info.get("tasks", []):
            task_to_lane[tid] = lane_name

    ready_ids: list[str] = []

    topo = topological_sort(graph)
    for task_id in topo:
        if task_id not in known_tasks:
            continue

        status = get_status(task_id)

        # Condition 1: status must be pending or ready
        if status not in ("pending", "ready"):
            continue

        # Condition 2: all deps must be done
        deps_done = all(get_status(dep) == "done" for dep in graph[task_id])
        if not deps_done:
            continue

        # Condition 3: assigned lane must not be at cap
        lane = task_to_lane.get(task_id)
        if lane is not None and is_lane_at_cap(state, lane, default_lane_max):
            continue

        # Condition 4: no external blockers
        if task_id in external_blocked:
            for blocker in external_blocked[task_id]:
                print(
                    f"WARNING: task '{task_id}' is blocked by external constraint: '{blocker}'",
                    file=sys.stderr,
                )
            continue

        ready_ids.append(task_id)

    return ready_ids


# ---------------------------------------------------------------------------
# Subcommand: ready
# ---------------------------------------------------------------------------


def cmd_ready(args: argparse.Namespace) -> int:
    """
    Compute and print the set of ready tasks.

    Parses the plan and optional assignment file, reads the state (if present),
    computes the ready set, and prints one task ID per line to stdout.

    If --show-blocked is given, also prints blocked tasks with annotation
    BLOCKED: task_id (reason: X).

    Exit code: 0 on success, 1 on validation error (cycle, unknown dep).
    """
    plan_deps = parse_plan_file(args.plan)

    assignment_blocked: dict[str, list[str]] = {}
    if args.assignment:
        if not os.path.isfile(args.assignment):
            print(
                f"ERROR: Assignment file not found: {args.assignment}",
                file=sys.stderr,
            )
            return 1
        assignment_blocked = parse_assignment_file(args.assignment)

    graph = build_graph(plan_deps, assignment_blocked)
    valid = validate_graph(graph, plan_deps, assignment_blocked)
    if not valid:
        return 1

    default_lane_max: int = args.lane_max if args.lane_max is not None else 5

    # read_state returns {} if file does not exist
    state = read_state(args.state)

    ready_ids = compute_ready_set(graph, state, assignment_blocked, default_lane_max)

    for task_id in ready_ids:
        print(task_id)

    if args.show_blocked:
        ready_set = set(ready_ids)
        all_task_ids: set[str] = set(graph.keys())
        for dep_set in graph.values():
            all_task_ids.update(dep_set)

        topo = topological_sort(graph)
        tasks_state: dict[str, dict] = state.get("tasks", {}) if state else {}

        def get_status(task_id: str) -> str:
            return tasks_state.get(task_id, {}).get("status", "pending")

        # Find lane for each task
        task_to_lane: dict[str, str] = {}
        lane_iterations: dict = state.get("lane_iterations", {}) if state else {}
        for lane_name, lane_info in lane_iterations.items():
            for tid in lane_info.get("tasks", []):
                task_to_lane[tid] = lane_name

        # External blockers per task
        external_blocked: dict[str, list[str]] = {}
        for task_id, blocked_list in assignment_blocked.items():
            ext = [b for b in blocked_list if b not in all_task_ids]
            if ext:
                external_blocked[task_id] = ext

        for task_id in topo:
            if task_id not in graph:
                continue
            if task_id in ready_set:
                continue

            status = get_status(task_id)
            if status in ("done", "deferred"):
                continue

            # Determine reason
            reasons: list[str] = []

            if status in ("in_progress", "failed"):
                reasons.append(f"status={status}")
            elif status in ("pending", "ready"):
                # Check why it's not ready
                unmet_deps = [
                    dep for dep in graph[task_id] if get_status(dep) != "done"
                ]
                if unmet_deps:
                    reasons.append(f"waiting on deps: {', '.join(sorted(unmet_deps))}")

                lane = task_to_lane.get(task_id)
                if lane is not None and is_lane_at_cap(state, lane, default_lane_max):
                    reasons.append(f"lane '{lane}' at cap")

                if task_id in external_blocked:
                    for blocker in external_blocked[task_id]:
                        reasons.append(f"external block: {blocker}")

            reason_str = "; ".join(reasons) if reasons else "unknown"
            print(f"BLOCKED: {task_id} (reason: {reason_str})")

    return 0


# ---------------------------------------------------------------------------
# Self-verification (invoked when --verify flag is passed to the script)
# ---------------------------------------------------------------------------


def _run_verification() -> None:
    """
    Run acceptance tests for read_state, write_state, validate_transition,
    reconcile logic, and lane iteration tracking. Prints VERIFICATION PASSED
    on success or raises AssertionError with a descriptive message on failure.
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
    # Test 6: get_lane_count on empty state returns 0
    # ------------------------------------------------------------------
    empty_state: dict = {}
    check("get_lane_count on empty state returns 0", get_lane_count(empty_state, "worker-1") == 0)

    state_no_lane: dict = {"lane_iterations": {}}
    check(
        "get_lane_count on state with no lane entry returns 0",
        get_lane_count(state_no_lane, "worker-1") == 0,
    )

    # ------------------------------------------------------------------
    # Test 7: increment-lane reaches cap after 5 increments (default max=5)
    # and prints LANE_CAP_REACHED
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as tmpdir:
        state_path = os.path.join(tmpdir, "task-state.json")

        class _Args:
            pass

        for i in range(4):
            inc_args = _Args()
            inc_args.lane = "worker-1"  # type: ignore[attr-defined]
            inc_args.state = state_path  # type: ignore[attr-defined]
            inc_args.max = None  # type: ignore[attr-defined]
            inc_args.tasks = None  # type: ignore[attr-defined]
            ret = cmd_increment_lane(inc_args)
            check(f"increment-lane iteration {i+1} returns 0", ret == 0)

        # 5th increment should reach cap
        import io
        from contextlib import redirect_stdout

        inc_args5 = _Args()
        inc_args5.lane = "worker-1"  # type: ignore[attr-defined]
        inc_args5.state = state_path  # type: ignore[attr-defined]
        inc_args5.max = None  # type: ignore[attr-defined]
        inc_args5.tasks = None  # type: ignore[attr-defined]

        captured = io.StringIO()
        with redirect_stdout(captured):
            ret5 = cmd_increment_lane(inc_args5)
        output5 = captured.getvalue()

        check("increment-lane 5th increment returns 0", ret5 == 0)
        check("increment-lane 5th increment prints LANE_CAP_REACHED", "LANE_CAP_REACHED" in output5)
        check(
            "increment-lane 5th increment prints ESCALATION",
            "ESCALATION" in output5,
        )

        final_state = read_state(state_path)
        check(
            "increment-lane count is 5 after 5 increments",
            get_lane_count(final_state, "worker-1") == 5,
        )
        check(
            "is_lane_at_cap returns True after 5 increments",
            is_lane_at_cap(final_state, "worker-1") is True,
        )

    # ------------------------------------------------------------------
    # Test 8: increment-lane with --max 3 reaches cap after 3 increments
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as tmpdir:
        state_path = os.path.join(tmpdir, "task-state.json")

        for i in range(2):
            inc_args = _Args()
            inc_args.lane = "lane-x"  # type: ignore[attr-defined]
            inc_args.state = state_path  # type: ignore[attr-defined]
            inc_args.max = 3  # type: ignore[attr-defined]
            inc_args.tasks = None  # type: ignore[attr-defined]
            cmd_increment_lane(inc_args)

        inc_args3 = _Args()
        inc_args3.lane = "lane-x"  # type: ignore[attr-defined]
        inc_args3.state = state_path  # type: ignore[attr-defined]
        inc_args3.max = 3  # type: ignore[attr-defined]
        inc_args3.tasks = None  # type: ignore[attr-defined]

        captured3 = io.StringIO()
        with redirect_stdout(captured3):
            cmd_increment_lane(inc_args3)
        output3 = captured3.getvalue()

        check(
            "increment-lane --max 3 prints LANE_CAP_REACHED on 3rd increment",
            "LANE_CAP_REACHED" in output3,
        )
        s3 = read_state(state_path)
        check(
            "increment-lane --max 3 count is 3 after 3 increments",
            get_lane_count(s3, "lane-x") == 3,
        )
        check(
            "is_lane_at_cap with max=3 returns True after 3 increments",
            is_lane_at_cap(s3, "lane-x", default_max=3) is True,
        )

    # ------------------------------------------------------------------
    # Test 9: reset-lane resets count to 0
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as tmpdir:
        state_path = os.path.join(tmpdir, "task-state.json")

        # Increment twice first
        for _ in range(2):
            inc_args = _Args()
            inc_args.lane = "worker-2"  # type: ignore[attr-defined]
            inc_args.state = state_path  # type: ignore[attr-defined]
            inc_args.max = None  # type: ignore[attr-defined]
            inc_args.tasks = None  # type: ignore[attr-defined]
            cmd_increment_lane(inc_args)

        pre_reset = read_state(state_path)
        check(
            "reset-lane pre-condition: count is 2",
            get_lane_count(pre_reset, "worker-2") == 2,
        )

        reset_args = _Args()
        reset_args.lane = "worker-2"  # type: ignore[attr-defined]
        reset_args.state = state_path  # type: ignore[attr-defined]
        ret_reset = cmd_reset_lane(reset_args)

        check("reset-lane returns 0", ret_reset == 0)
        post_reset = read_state(state_path)
        check(
            "reset-lane resets count to 0",
            get_lane_count(post_reset, "worker-2") == 0,
        )
        # max must be preserved
        check(
            "reset-lane preserves max",
            get_lane_max(post_reset, "worker-2") == 5,
        )

    # ------------------------------------------------------------------
    # Test 10: increment-lane --max 0 exits with code 1
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as tmpdir:
        state_path = os.path.join(tmpdir, "task-state.json")
        bad_args = _Args()
        bad_args.lane = "worker-1"  # type: ignore[attr-defined]
        bad_args.state = state_path  # type: ignore[attr-defined]
        bad_args.max = 0  # type: ignore[attr-defined]
        bad_args.tasks = None  # type: ignore[attr-defined]
        ret_bad = cmd_increment_lane(bad_args)
        check("increment-lane --max 0 exits with code 1", ret_bad == 1)

        neg_args = _Args()
        neg_args.lane = "worker-1"  # type: ignore[attr-defined]
        neg_args.state = state_path  # type: ignore[attr-defined]
        neg_args.max = -3  # type: ignore[attr-defined]
        neg_args.tasks = None  # type: ignore[attr-defined]
        ret_neg = cmd_increment_lane(neg_args)
        check("increment-lane --max -3 exits with code 1", ret_neg == 1)

    # ------------------------------------------------------------------
    # Test 11: format_escalation_message contains required fields
    # ------------------------------------------------------------------
    msg = format_escalation_message("worker-1", 5, 5, ["task1", "task2"])
    check(
        "format_escalation_message contains lane name",
        "worker-1" in msg,
    )
    check(
        "format_escalation_message contains count/max",
        "5/5" in msg,
    )
    check(
        "format_escalation_message contains task IDs",
        "task1" in msg and "task2" in msg,
    )
    check(
        "format_escalation_message contains re-scope or re-plan",
        "re-scope or re-plan" in msg,
    )

    # ------------------------------------------------------------------
    # Test 12: topological_sort on simple linear DAG task1->task2->task3
    # ------------------------------------------------------------------
    linear_graph: dict[str, set[str]] = {
        "task1": set(),
        "task2": {"task1"},
        "task3": {"task2"},
    }
    topo_result = topological_sort(linear_graph)
    check(
        "topological_sort linear: task1 before task2",
        topo_result.index("task1") < topo_result.index("task2"),
    )
    check(
        "topological_sort linear: task2 before task3",
        topo_result.index("task2") < topo_result.index("task3"),
    )
    check(
        "topological_sort linear: all 3 tasks present",
        set(topo_result) == {"task1", "task2", "task3"},
    )

    # ------------------------------------------------------------------
    # Test 13: topological_sort alphabetic tie-breaking
    # ------------------------------------------------------------------
    diamond_graph: dict[str, set[str]] = {
        "root": set(),
        "b_task": {"root"},
        "a_task": {"root"},
        "leaf": {"a_task", "b_task"},
    }
    topo_diamond = topological_sort(diamond_graph)
    check(
        "topological_sort diamond: root is first",
        topo_diamond[0] == "root",
    )
    check(
        "topological_sort diamond: a_task before b_task (alphabetic)",
        topo_diamond.index("a_task") < topo_diamond.index("b_task"),
    )
    check(
        "topological_sort diamond: leaf is last",
        topo_diamond[-1] == "leaf",
    )

    # ------------------------------------------------------------------
    # Test 14: topological_sort raises ValueError on cycle
    # ------------------------------------------------------------------
    cycle_graph: dict[str, set[str]] = {
        "A": {"B"},
        "B": {"A"},
    }
    try:
        topological_sort(cycle_graph)
        check("topological_sort raises ValueError on cycle", False)
    except ValueError:
        check("topological_sort raises ValueError on cycle", True)

    # ------------------------------------------------------------------
    # Test 15: compute_ready_set -- simple DAG, task1=done -> task2 ready, task3 not
    # ------------------------------------------------------------------
    simple_graph: dict[str, set[str]] = {
        "task1": set(),
        "task2": {"task1"},
        "task3": {"task2"},
    }
    simple_state: dict = {
        "version": 1,
        "tasks": {
            "task1": {"status": "done"},
            "task2": {"status": "pending"},
            "task3": {"status": "pending"},
        },
        "lane_iterations": {},
    }
    ready = compute_ready_set(simple_graph, simple_state, {})
    check("test15: task2 is ready (task1=done)", "task2" in ready)
    check("test15: task3 is NOT ready (task2 not done)", "task3" not in ready)
    check("test15: task1 is NOT ready (already done)", "task1" not in ready)

    # ------------------------------------------------------------------
    # Test 16: compute_ready_set -- no state file -> all tasks returned in topo order
    # ------------------------------------------------------------------
    ready_no_state = compute_ready_set(simple_graph, {}, {})
    check("test16: all tasks returned when state is empty", set(ready_no_state) == {"task1", "task2", "task3"})
    check(
        "test16: task1 before task2 in topo order",
        ready_no_state.index("task1") < ready_no_state.index("task2"),
    )
    check(
        "test16: task2 before task3 in topo order",
        ready_no_state.index("task2") < ready_no_state.index("task3"),
    )

    # ------------------------------------------------------------------
    # Test 17: compute_ready_set -- external blockedBy blocks task; WARNING printed
    # ------------------------------------------------------------------
    import io
    from contextlib import redirect_stderr

    ext_graph: dict[str, set[str]] = {
        "taskA": set(),
        "taskB": set(),
    }
    ext_state: dict = {
        "version": 1,
        "tasks": {
            "taskA": {"status": "pending"},
            "taskB": {"status": "pending"},
        },
        "lane_iterations": {},
    }
    ext_assignment: dict[str, list[str]] = {
        "taskB": ["external-blocker"],
    }
    stderr_capture = io.StringIO()
    with redirect_stderr(stderr_capture):
        ready_ext = compute_ready_set(ext_graph, ext_state, ext_assignment)
    stderr_out = stderr_capture.getvalue()
    check("test17: taskA is ready (no blocker)", "taskA" in ready_ext)
    check("test17: taskB is NOT ready (external blocker)", "taskB" not in ready_ext)
    check("test17: WARNING printed for taskB", "WARNING" in stderr_out and "taskB" in stderr_out)

    # ------------------------------------------------------------------
    # Test 18: compute_ready_set -- lane at cap blocks task
    # ------------------------------------------------------------------
    lane_graph: dict[str, set[str]] = {
        "taskX": set(),
        "taskY": set(),
    }
    lane_state: dict = {
        "version": 1,
        "tasks": {
            "taskX": {"status": "pending"},
            "taskY": {"status": "pending"},
        },
        "lane_iterations": {
            "lane-A": {"count": 5, "max": 5, "tasks": ["taskX"]},
        },
    }
    ready_lane = compute_ready_set(lane_graph, lane_state, {})
    check("test18: taskY is ready (no lane cap)", "taskY" in ready_lane)
    check("test18: taskX is NOT ready (lane-A at cap)", "taskX" not in ready_lane)

    # ------------------------------------------------------------------
    # Test 19: compute_ready_set determinism (same input -> same output)
    # ------------------------------------------------------------------
    det_graph: dict[str, set[str]] = {
        "t1": set(),
        "t2": set(),
        "t3": {"t1", "t2"},
    }
    det_state: dict = {
        "version": 1,
        "tasks": {
            "t1": {"status": "done"},
            "t2": {"status": "done"},
            "t3": {"status": "pending"},
        },
        "lane_iterations": {},
    }
    result_a = compute_ready_set(det_graph, det_state, {})
    result_b = compute_ready_set(det_graph, det_state, {})
    check("test19: determinism: same output on second call", result_a == result_b)

    # ------------------------------------------------------------------
    # Test 20: cmd_ready --show-blocked prints BLOCKED annotation
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as tmpdir:
        plan_path = os.path.join(tmpdir, "plan.md")
        plan_content = (
            "| Task ID | Depends On |\n"
            "|---------|------------|\n"
            "| task1   | -          |\n"
            "| task2   | task1      |\n"
            "| task3   | task2      |\n"
        )
        with open(plan_path, "w", encoding="utf-8") as pf:
            pf.write(plan_content)

        state_path = os.path.join(tmpdir, "task-state.json")
        sb_state = {
            "version": 1,
            "tasks": {
                "task1": {"status": "done"},
                "task2": {"status": "pending"},
                "task3": {"status": "pending"},
            },
            "lane_iterations": {},
        }
        write_state(sb_state, state_path)

        class _Args:
            pass

        sb_args = _Args()
        sb_args.plan = plan_path  # type: ignore[attr-defined]
        sb_args.state = state_path  # type: ignore[attr-defined]
        sb_args.assignment = None  # type: ignore[attr-defined]
        sb_args.lane_max = None  # type: ignore[attr-defined]
        sb_args.show_blocked = True  # type: ignore[attr-defined]

        captured_sb = io.StringIO()
        with redirect_stdout(captured_sb):
            ret_sb = cmd_ready(sb_args)
        out_sb = captured_sb.getvalue()

        check("test20: cmd_ready returns 0", ret_sb == 0)
        check("test20: task2 printed as ready", "task2" in out_sb)
        check("test20: BLOCKED annotation for task3", "BLOCKED: task3" in out_sb)

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

    # -- increment-lane subcommand --
    inc_parser = subparsers.add_parser(
        "increment-lane",
        help="Increment the iteration count for a lane; print escalation message if cap is reached.",
    )
    inc_parser.add_argument("lane", help="Name of the lane to increment.")
    inc_parser.add_argument(
        "--state",
        default="task-state.json",
        help="Path to the task-state.json file (default: task-state.json).",
    )
    inc_parser.add_argument(
        "--max",
        type=int,
        default=None,
        help="Set/update the maximum iterations for this lane (must be >= 1).",
    )
    inc_parser.add_argument(
        "--tasks",
        default=None,
        help="Comma-separated list of task IDs to associate with this lane.",
    )

    # -- reset-lane subcommand --
    reset_parser = subparsers.add_parser(
        "reset-lane",
        help="Reset the iteration count for a lane to 0 (preserves max and tasks).",
    )
    reset_parser.add_argument("lane", help="Name of the lane to reset.")
    reset_parser.add_argument(
        "--state",
        default="task-state.json",
        help="Path to the task-state.json file (default: task-state.json).",
    )

    # -- ready subcommand --
    ready_parser = subparsers.add_parser(
        "ready",
        help="Compute and print the ready set of tasks in topological order.",
    )
    ready_parser.add_argument("--plan", required=True, help="Path to the plan Markdown file.")
    ready_parser.add_argument(
        "--state",
        default="task-state.json",
        help="Path to the task-state.json file (default: task-state.json).",
    )
    ready_parser.add_argument(
        "--assignment",
        default=None,
        help="Path to the worktree-assignment.md file (optional).",
    )
    ready_parser.add_argument(
        "--lane-max",
        type=int,
        default=None,
        dest="lane_max",
        help="Default maximum iterations per lane (default: 5).",
    )
    ready_parser.add_argument(
        "--show-blocked",
        action="store_true",
        default=False,
        dest="show_blocked",
        help="Also print blocked tasks with BLOCKED: task_id (reason: X) annotations.",
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
    elif args.subcommand == "increment-lane":
        return cmd_increment_lane(args)
    elif args.subcommand == "reset-lane":
        return cmd_reset_lane(args)
    elif args.subcommand == "ready":
        return cmd_ready(args)
    else:
        print(f"ERROR: Unknown subcommand '{args.subcommand}'", file=sys.stderr)
        return 1


if __name__ == "__main__":
    # Allow --verify flag to run self-verification tests instead of normal CLI
    if len(sys.argv) == 2 and sys.argv[1] == "--verify":
        _run_verification()
    else:
        sys.exit(main())
