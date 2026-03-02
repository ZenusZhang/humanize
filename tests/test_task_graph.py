"""
Comprehensive pytest unit tests for scripts/task-graph.py.

These tests cover parsing, graph building, cycle detection, validation,
ready-set computation, topological sort, atomic writes, lane tracking,
reconciliation, and state transitions.
"""

import importlib.util
import io
import json
import os
import sys
from contextlib import redirect_stderr, redirect_stdout

import pytest

# ---------------------------------------------------------------------------
# Module loading: task-graph.py has a hyphen in its name so we use importlib.
# ---------------------------------------------------------------------------

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

_SCRIPT_PATH = os.path.join(os.path.dirname(__file__), "..", "scripts", "task-graph.py")
_spec = importlib.util.spec_from_file_location("task_graph", _SCRIPT_PATH)
task_graph = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(task_graph)


# ---------------------------------------------------------------------------
# Helpers: write temporary Markdown plan / assignment files
# ---------------------------------------------------------------------------


def write_plan_file(path: str, rows: list[tuple[str, str]]) -> None:
    """
    Write a minimal plan Markdown file with columns 'Task ID' and 'Depends On'.
    Each row is (task_id, depends_on_value).
    """
    lines = ["| Task ID | Depends On |\n", "|---------|------------|\n"]
    for task_id, depends_on in rows:
        lines.append(f"| {task_id} | {depends_on} |\n")
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)


def write_assignment_file(path: str, rows: list[tuple[str, str]]) -> None:
    """
    Write a minimal worktree-assignment Markdown file with a Parallelization
    Matrix section containing 'Task ID' and 'blockedBy' columns.
    Each row is (task_id, blocked_by_value).
    """
    lines = [
        "## Parallelization Matrix\n",
        "\n",
        "| Task ID | blockedBy |\n",
        "|---------|----------|\n",
    ]
    for task_id, blocked_by in rows:
        lines.append(f"| {task_id} | {blocked_by} |\n")
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)


def make_simple_args(**kwargs):
    """Return a simple namespace-like object with the given attributes."""

    class _Args:
        pass

    args = _Args()
    for key, value in kwargs.items():
        setattr(args, key, value)
    return args


# ===========================================================================
# 1. Parsing tests
# ===========================================================================


class TestNormalizeDepList:
    """Tests for _normalize_dep_list."""

    def test_dash_returns_empty(self):
        assert task_graph._normalize_dep_list("-") == []

    def test_empty_string_returns_empty(self):
        assert task_graph._normalize_dep_list("") == []

    def test_whitespace_only_returns_empty(self):
        assert task_graph._normalize_dep_list("   ") == []

    def test_single_plain_id(self):
        assert task_graph._normalize_dep_list("task1") == ["task1"]

    def test_comma_separated(self):
        result = task_graph._normalize_dep_list("task1, task2, task3")
        assert result == ["task1", "task2", "task3"]

    def test_backtick_wrapped(self):
        result = task_graph._normalize_dep_list("`task1`")
        assert result == ["task1"]

    def test_backtick_wrapped_comma_separated(self):
        result = task_graph._normalize_dep_list("`task1`, `task2`")
        assert result == ["task1", "task2"]

    def test_mixed_backtick_and_plain(self):
        result = task_graph._normalize_dep_list("`task1`, task2")
        assert result == ["task1", "task2"]

    def test_dash_in_comma_list_skipped(self):
        # A '-' entry within a comma list should be skipped
        result = task_graph._normalize_dep_list("task1, -, task2")
        assert result == ["task1", "task2"]


class TestParsePlanFile:
    """Tests for parse_plan_file."""

    def test_no_deps_dash(self, tmp_path):
        plan = str(tmp_path / "plan.md")
        write_plan_file(plan, [("task1", "-")])
        result = task_graph.parse_plan_file(plan)
        assert "task1" in result
        assert result["task1"] == []

    def test_single_dep(self, tmp_path):
        plan = str(tmp_path / "plan.md")
        write_plan_file(plan, [("task1", "-"), ("task2", "task1")])
        result = task_graph.parse_plan_file(plan)
        assert result["task2"] == ["task1"]

    def test_comma_separated_deps(self, tmp_path):
        plan = str(tmp_path / "plan.md")
        write_plan_file(plan, [("task1", "-"), ("task2", "-"), ("task3", "task1, task2")])
        result = task_graph.parse_plan_file(plan)
        assert set(result["task3"]) == {"task1", "task2"}

    def test_backtick_wrapped_ids(self, tmp_path):
        plan = str(tmp_path / "plan.md")
        write_plan_file(plan, [("task1", "-"), ("task2", "`task1`")])
        result = task_graph.parse_plan_file(plan)
        assert result["task2"] == ["task1"]

    def test_multiple_tasks_all_present(self, tmp_path):
        plan = str(tmp_path / "plan.md")
        write_plan_file(plan, [("t1", "-"), ("t2", "t1"), ("t3", "t2")])
        result = task_graph.parse_plan_file(plan)
        assert set(result.keys()) == {"t1", "t2", "t3"}

    def test_no_table_returns_empty(self, tmp_path):
        plan = str(tmp_path / "plan.md")
        with open(plan, "w", encoding="utf-8") as f:
            f.write("# No table here\nJust some text.\n")
        result = task_graph.parse_plan_file(plan)
        assert result == {}


class TestParseAssignmentFile:
    """Tests for parse_assignment_file."""

    def test_parses_blocked_by(self, tmp_path):
        assignment = str(tmp_path / "assignment.md")
        write_assignment_file(assignment, [("task1", "-"), ("task2", "task1")])
        result = task_graph.parse_assignment_file(assignment)
        assert "task2" in result
        assert result["task2"] == ["task1"]

    def test_dash_means_no_blockers(self, tmp_path):
        assignment = str(tmp_path / "assignment.md")
        write_assignment_file(assignment, [("task1", "-")])
        result = task_graph.parse_assignment_file(assignment)
        assert result.get("task1", []) == []

    def test_missing_section_returns_empty(self, tmp_path):
        assignment = str(tmp_path / "assignment.md")
        with open(assignment, "w", encoding="utf-8") as f:
            f.write("# Worktree Assignment\n\nNo parallelization matrix here.\n")
        result = task_graph.parse_assignment_file(assignment)
        assert result == {}

    def test_external_blocker_value(self, tmp_path):
        assignment = str(tmp_path / "assignment.md")
        write_assignment_file(assignment, [("task1", "external-review")])
        result = task_graph.parse_assignment_file(assignment)
        assert result["task1"] == ["external-review"]


# ===========================================================================
# 2. Graph building tests
# ===========================================================================


class TestBuildGraph:
    """Tests for build_graph."""

    def test_all_plan_tasks_present_as_keys(self):
        plan_deps = {"t1": [], "t2": ["t1"], "t3": ["t1", "t2"]}
        graph = task_graph.build_graph(plan_deps, {})
        assert set(graph.keys()) == {"t1", "t2", "t3"}

    def test_plan_deps_merged_correctly(self):
        plan_deps = {"t1": [], "t2": ["t1"]}
        graph = task_graph.build_graph(plan_deps, {})
        assert "t1" in graph["t2"]

    def test_assignment_blocked_merged(self):
        plan_deps = {"t1": [], "t2": []}
        assignment_blocked = {"t2": ["t1"]}
        graph = task_graph.build_graph(plan_deps, assignment_blocked)
        assert "t1" in graph["t2"]

    def test_assignment_only_tasks_added(self):
        plan_deps = {"t1": []}
        assignment_blocked = {"t2": ["t1"]}
        graph = task_graph.build_graph(plan_deps, assignment_blocked)
        assert "t2" in graph

    def test_no_duplicate_edges(self):
        # t2 depends on t1 both via plan and assignment; should appear only once
        plan_deps = {"t1": [], "t2": ["t1"]}
        assignment_blocked = {"t2": ["t1"]}
        graph = task_graph.build_graph(plan_deps, assignment_blocked)
        # graph[t2] is a set so duplicates are impossible, but verify cardinality
        assert graph["t2"] == {"t1"}

    def test_empty_inputs_return_empty_graph(self):
        graph = task_graph.build_graph({}, {})
        assert graph == {}


# ===========================================================================
# 3. Cycle detection tests
# ===========================================================================


class TestDetectCycle:
    """Tests for detect_cycle."""

    def test_valid_dag_returns_none(self):
        graph = {"t1": set(), "t2": {"t1"}, "t3": {"t2"}}
        assert task_graph.detect_cycle(graph) is None

    def test_simple_cycle_a_b_a(self):
        graph = {"A": {"B"}, "B": {"A"}}
        cycle = task_graph.detect_cycle(graph)
        assert cycle is not None
        assert isinstance(cycle, list)
        assert len(cycle) >= 2
        # First and last element should be the same node
        assert cycle[0] == cycle[-1]

    def test_self_loop(self):
        graph = {"A": {"A"}}
        cycle = task_graph.detect_cycle(graph)
        assert cycle is not None
        assert "A" in cycle

    def test_three_node_cycle(self):
        graph = {"A": {"C"}, "B": {"A"}, "C": {"B"}}
        cycle = task_graph.detect_cycle(graph)
        assert cycle is not None

    def test_diamond_no_cycle(self):
        graph = {"root": set(), "left": {"root"}, "right": {"root"}, "leaf": {"left", "right"}}
        assert task_graph.detect_cycle(graph) is None


# ===========================================================================
# 4. Unknown dependency validation tests
# ===========================================================================


class TestValidateGraph:
    """Tests for validate_graph."""

    def test_unknown_plan_dep_causes_false(self, capsys):
        plan_deps = {"t1": ["nonexistent"]}
        graph = task_graph.build_graph(plan_deps, {})
        valid = task_graph.validate_graph(graph, plan_deps, {})
        assert valid is False
        captured = capsys.readouterr()
        assert "nonexistent" in captured.err

    def test_unknown_blocked_by_only_warning(self, capsys):
        plan_deps = {"t1": [], "t2": []}
        assignment_blocked = {"t2": ["external-blocker"]}
        graph = task_graph.build_graph(plan_deps, assignment_blocked)
        # external-blocker is NOT a known task so it should only warn, not fail
        valid = task_graph.validate_graph(graph, plan_deps, assignment_blocked)
        assert valid is True
        captured = capsys.readouterr()
        assert "WARNING" in captured.err

    def test_all_known_deps_returns_true(self):
        plan_deps = {"t1": [], "t2": ["t1"]}
        graph = task_graph.build_graph(plan_deps, {})
        valid = task_graph.validate_graph(graph, plan_deps, {})
        assert valid is True

    def test_cycle_causes_false(self, capsys):
        plan_deps = {"A": ["B"], "B": ["A"]}
        graph = task_graph.build_graph(plan_deps, {})
        valid = task_graph.validate_graph(graph, plan_deps, {})
        assert valid is False
        captured = capsys.readouterr()
        assert "Cycle" in captured.err or "cycle" in captured.err


# ===========================================================================
# 5. Ready-set computation tests
# ===========================================================================


class TestComputeReadySet:
    """Tests for compute_ready_set."""

    def _make_state(self, task_statuses: dict[str, str], lane_iterations=None) -> dict:
        tasks = {tid: {"status": s} for tid, s in task_statuses.items()}
        return {
            "version": 1,
            "tasks": tasks,
            "lane_iterations": lane_iterations or {},
        }

    def test_task_with_all_deps_done_is_ready(self):
        graph = {"t1": set(), "t2": {"t1"}}
        state = self._make_state({"t1": "done", "t2": "pending"})
        ready = task_graph.compute_ready_set(graph, state, {})
        assert "t2" in ready

    def test_task_with_undone_dep_is_not_ready(self):
        graph = {"t1": set(), "t2": {"t1"}}
        state = self._make_state({"t1": "pending", "t2": "pending"})
        ready = task_graph.compute_ready_set(graph, state, {})
        assert "t2" not in ready

    def test_no_state_empty_returns_all_tasks(self):
        graph = {"t1": set(), "t2": {"t1"}, "t3": {"t2"}}
        ready = task_graph.compute_ready_set(graph, {}, {})
        assert set(ready) == {"t1", "t2", "t3"}

    def test_no_state_order_respects_topology(self):
        graph = {"t1": set(), "t2": {"t1"}, "t3": {"t2"}}
        ready = task_graph.compute_ready_set(graph, {}, {})
        assert ready.index("t1") < ready.index("t2")
        assert ready.index("t2") < ready.index("t3")

    def test_external_blocked_by_marks_not_ready(self):
        graph = {"tA": set(), "tB": set()}
        state = self._make_state({"tA": "pending", "tB": "pending"})
        assignment_blocked = {"tB": ["external-dep"]}
        stderr_buf = io.StringIO()
        with redirect_stderr(stderr_buf):
            ready = task_graph.compute_ready_set(graph, state, assignment_blocked)
        assert "tB" not in ready
        assert "tA" in ready

    def test_external_blocked_prints_warning(self):
        graph = {"tA": set()}
        state = self._make_state({"tA": "pending"})
        assignment_blocked = {"tA": ["external-dep"]}
        stderr_buf = io.StringIO()
        with redirect_stderr(stderr_buf):
            task_graph.compute_ready_set(graph, state, assignment_blocked)
        assert "WARNING" in stderr_buf.getvalue()
        assert "tA" in stderr_buf.getvalue()

    def test_lane_at_cap_marks_tasks_not_ready(self):
        graph = {"tX": set(), "tY": set()}
        state = {
            "version": 1,
            "tasks": {"tX": {"status": "pending"}, "tY": {"status": "pending"}},
            "lane_iterations": {
                "lane-A": {"count": 5, "max": 5, "tasks": ["tX"]},
            },
        }
        ready = task_graph.compute_ready_set(graph, state, {})
        assert "tX" not in ready
        assert "tY" in ready

    def test_done_task_not_in_ready(self):
        graph = {"t1": set()}
        state = self._make_state({"t1": "done"})
        ready = task_graph.compute_ready_set(graph, state, {})
        assert "t1" not in ready

    def test_in_progress_task_not_in_ready(self):
        graph = {"t1": set()}
        state = self._make_state({"t1": "in_progress"})
        ready = task_graph.compute_ready_set(graph, state, {})
        assert "t1" not in ready

    def test_deferred_task_not_in_ready(self):
        graph = {"t1": set()}
        state = self._make_state({"t1": "deferred"})
        ready = task_graph.compute_ready_set(graph, state, {})
        assert "t1" not in ready


# ===========================================================================
# 6. Stable ordering (topological sort) tests
# ===========================================================================


class TestTopologicalSort:
    """Tests for topological_sort."""

    def test_same_graph_twice_produces_same_order(self):
        graph = {"t1": set(), "t2": {"t1"}, "t3": {"t1"}, "t4": {"t2", "t3"}}
        result_a = task_graph.topological_sort(graph)
        result_b = task_graph.topological_sort(graph)
        assert result_a == result_b

    def test_alphabetic_tie_breaking(self):
        # Both 'alpha' and 'beta' have no dependencies; alpha should come first
        graph = {"alpha": set(), "beta": set(), "leaf": {"alpha", "beta"}}
        result = task_graph.topological_sort(graph)
        assert result.index("alpha") < result.index("beta")
        assert result[-1] == "leaf"

    def test_linear_chain_ordered_correctly(self):
        graph = {"t1": set(), "t2": {"t1"}, "t3": {"t2"}}
        result = task_graph.topological_sort(graph)
        assert result.index("t1") < result.index("t2")
        assert result.index("t2") < result.index("t3")

    def test_all_nodes_present_in_result(self):
        graph = {"t1": set(), "t2": {"t1"}, "t3": {"t2"}}
        result = task_graph.topological_sort(graph)
        assert set(result) == {"t1", "t2", "t3"}

    def test_cycle_raises_value_error(self):
        graph = {"A": {"B"}, "B": {"A"}}
        with pytest.raises(ValueError):
            task_graph.topological_sort(graph)

    def test_independent_tasks_sorted_alphabetically(self):
        graph = {"zebra": set(), "apple": set(), "mango": set()}
        result = task_graph.topological_sort(graph)
        assert result == ["apple", "mango", "zebra"]


# ===========================================================================
# 7. Atomic write/read round-trip tests
# ===========================================================================


class TestWriteReadState:
    """Tests for write_state and read_state."""

    def test_round_trip_preserves_data(self, tmp_path):
        state_path = str(tmp_path / "state.json")
        original = {
            "version": 1,
            "tasks": {
                "task1": {
                    "status": "pending",
                    "last_updated": "2026-01-01T00:00:00Z",
                    "reviewer_signoff": False,
                },
            },
            "lane_iterations": {},
        }
        task_graph.write_state(original, state_path)
        loaded = task_graph.read_state(state_path)
        assert loaded == original

    def test_read_state_missing_file_returns_empty(self, tmp_path):
        missing = str(tmp_path / "nonexistent.json")
        result = task_graph.read_state(missing)
        assert result == {}

    def test_write_state_atomic_no_tmp_leftover(self, tmp_path):
        state_path = str(tmp_path / "state.json")
        state = {"version": 1, "tasks": {}, "lane_iterations": {}}
        task_graph.write_state(state, state_path)
        tmp_file = state_path + ".tmp"
        # The .tmp file should not remain after a successful write
        assert not os.path.isfile(tmp_file)

    def test_read_state_invalid_json_returns_empty(self, tmp_path, capsys):
        state_path = str(tmp_path / "bad.json")
        with open(state_path, "w", encoding="utf-8") as f:
            f.write("{ this is not valid json }")
        result = task_graph.read_state(state_path)
        assert result == {}
        captured = capsys.readouterr()
        assert "WARNING" in captured.err

    def test_round_trip_complex_state(self, tmp_path):
        state_path = str(tmp_path / "state.json")
        original = {
            "version": 1,
            "tasks": {
                "t1": {"status": "done", "last_updated": "2026-02-01T10:00:00Z", "reviewer_signoff": True},
                "t2": {"status": "in_progress", "last_updated": "2026-02-02T11:00:00Z", "reviewer_signoff": False},
            },
            "lane_iterations": {
                "worker-1": {"count": 3, "max": 5, "tasks": ["t1", "t2"]},
            },
        }
        task_graph.write_state(original, state_path)
        loaded = task_graph.read_state(state_path)
        assert loaded == original


# ===========================================================================
# 8. Lane iteration tracking tests
# ===========================================================================


class TestLaneTracking:
    """Tests for get_lane_count, is_lane_at_cap, and format_escalation_message."""

    def test_get_lane_count_missing_lane_returns_zero(self):
        state = {"lane_iterations": {}}
        assert task_graph.get_lane_count(state, "nonexistent") == 0

    def test_get_lane_count_empty_state_returns_zero(self):
        assert task_graph.get_lane_count({}, "worker-1") == 0

    def test_get_lane_count_returns_correct_value(self):
        state = {"lane_iterations": {"worker-1": {"count": 3, "max": 5}}}
        assert task_graph.get_lane_count(state, "worker-1") == 3

    def test_is_lane_at_cap_true_when_count_equals_max(self):
        state = {"lane_iterations": {"worker-1": {"count": 5, "max": 5}}}
        assert task_graph.is_lane_at_cap(state, "worker-1") is True

    def test_is_lane_at_cap_true_when_count_exceeds_max(self):
        state = {"lane_iterations": {"worker-1": {"count": 6, "max": 5}}}
        assert task_graph.is_lane_at_cap(state, "worker-1") is True

    def test_is_lane_at_cap_false_when_count_below_max(self):
        state = {"lane_iterations": {"worker-1": {"count": 3, "max": 5}}}
        assert task_graph.is_lane_at_cap(state, "worker-1") is False

    def test_is_lane_at_cap_false_for_missing_lane(self):
        # Missing lane has count=0, default max=5, so not at cap
        state = {"lane_iterations": {}}
        assert task_graph.is_lane_at_cap(state, "nonexistent") is False

    def test_is_lane_at_cap_custom_default_max(self):
        state = {"lane_iterations": {"lane-x": {"count": 3, "max": 5}}}
        # With default_max=3 and stored max=5, stored max wins; count=3 < 5 -> False
        assert task_graph.is_lane_at_cap(state, "lane-x", default_max=3) is False

    def test_format_escalation_message_contains_lane_name(self):
        msg = task_graph.format_escalation_message("worker-1", 5, 5, ["t1", "t2"])
        assert "worker-1" in msg

    def test_format_escalation_message_contains_count_max(self):
        msg = task_graph.format_escalation_message("worker-1", 5, 5, ["t1"])
        assert "5/5" in msg

    def test_format_escalation_message_contains_rescope(self):
        msg = task_graph.format_escalation_message("worker-1", 5, 5, [])
        assert "re-scope or re-plan" in msg

    def test_format_escalation_message_contains_task_ids(self):
        msg = task_graph.format_escalation_message("lane-A", 3, 3, ["task1", "task2"])
        assert "task1" in msg
        assert "task2" in msg

    def test_format_escalation_message_empty_task_list(self):
        msg = task_graph.format_escalation_message("lane-A", 5, 5, [])
        assert "lane-A" in msg
        assert "(none)" in msg


# ===========================================================================
# 9. Reconciliation tests
# ===========================================================================


class TestCmdReconcile:
    """Tests for cmd_reconcile."""

    def test_new_tasks_added_as_pending(self, tmp_path):
        plan_path = str(tmp_path / "plan.md")
        state_path = str(tmp_path / "state.json")
        write_plan_file(plan_path, [("t1", "-"), ("t2", "t1")])
        # State has only t1
        initial = {
            "version": 1,
            "tasks": {"t1": {"status": "done", "last_updated": "2026-01-01T00:00:00Z", "reviewer_signoff": True}},
            "lane_iterations": {},
        }
        task_graph.write_state(initial, state_path)
        args = make_simple_args(plan=plan_path, state=state_path, assignment=None)
        task_graph.cmd_reconcile(args)
        final = task_graph.read_state(state_path)
        assert final["tasks"]["t2"]["status"] == "pending"

    def test_removed_tasks_deferred(self, tmp_path):
        plan_path = str(tmp_path / "plan.md")
        state_path = str(tmp_path / "state.json")
        # Plan only has t1; state has t1 + t2
        write_plan_file(plan_path, [("t1", "-")])
        initial = {
            "version": 1,
            "tasks": {
                "t1": {"status": "pending", "last_updated": "2026-01-01T00:00:00Z", "reviewer_signoff": False},
                "t2": {"status": "pending", "last_updated": "2026-01-01T00:00:00Z", "reviewer_signoff": False},
            },
            "lane_iterations": {},
        }
        task_graph.write_state(initial, state_path)
        args = make_simple_args(plan=plan_path, state=state_path, assignment=None)
        task_graph.cmd_reconcile(args)
        final = task_graph.read_state(state_path)
        assert final["tasks"]["t2"]["status"] == "deferred"

    def test_done_tasks_not_touched(self, tmp_path):
        plan_path = str(tmp_path / "plan.md")
        state_path = str(tmp_path / "state.json")
        write_plan_file(plan_path, [("t1", "-"), ("t2", "t1")])
        initial = {
            "version": 1,
            "tasks": {
                "t1": {"status": "done", "last_updated": "2026-01-01T00:00:00Z", "reviewer_signoff": True},
                "t2": {"status": "pending", "last_updated": "2026-01-01T00:00:00Z", "reviewer_signoff": False},
            },
            "lane_iterations": {},
        }
        task_graph.write_state(initial, state_path)
        args = make_simple_args(plan=plan_path, state=state_path, assignment=None)
        task_graph.cmd_reconcile(args)
        final = task_graph.read_state(state_path)
        assert final["tasks"]["t1"]["status"] == "done"

    def test_already_deferred_task_not_double_deferred(self, tmp_path):
        plan_path = str(tmp_path / "plan.md")
        state_path = str(tmp_path / "state.json")
        write_plan_file(plan_path, [("t1", "-")])
        # t2 is already deferred and not in plan -> should stay deferred, no change
        initial = {
            "version": 1,
            "tasks": {
                "t1": {"status": "pending", "last_updated": "2026-01-01T00:00:00Z", "reviewer_signoff": False},
                "t2": {"status": "deferred", "last_updated": "2026-01-01T00:00:00Z", "reviewer_signoff": False},
            },
            "lane_iterations": {},
        }
        task_graph.write_state(initial, state_path)
        args = make_simple_args(plan=plan_path, state=state_path, assignment=None)
        task_graph.cmd_reconcile(args)
        final = task_graph.read_state(state_path)
        assert final["tasks"]["t2"]["status"] == "deferred"

    def test_missing_state_file_creates_new_state(self, tmp_path):
        plan_path = str(tmp_path / "plan.md")
        state_path = str(tmp_path / "state.json")
        write_plan_file(plan_path, [("tA", "-"), ("tB", "tA")])
        assert not os.path.isfile(state_path)
        args = make_simple_args(plan=plan_path, state=state_path, assignment=None)
        task_graph.cmd_reconcile(args)
        assert os.path.isfile(state_path)
        final = task_graph.read_state(state_path)
        assert final["tasks"]["tA"]["status"] == "pending"
        assert final["tasks"]["tB"]["status"] == "pending"

    def test_reconcile_returns_zero(self, tmp_path):
        plan_path = str(tmp_path / "plan.md")
        state_path = str(tmp_path / "state.json")
        write_plan_file(plan_path, [("t1", "-")])
        args = make_simple_args(plan=plan_path, state=state_path, assignment=None)
        ret = task_graph.cmd_reconcile(args)
        assert ret == 0


# ===========================================================================
# 10. State transition tests
# ===========================================================================


class TestValidateTransition:
    """Tests for validate_transition."""

    def test_done_to_pending_is_false(self):
        assert task_graph.validate_transition("done", "pending") is False

    def test_done_to_deferred_is_false(self):
        # done is terminal; even deferred is blocked
        assert task_graph.validate_transition("done", "deferred") is False

    def test_done_to_ready_is_false(self):
        assert task_graph.validate_transition("done", "ready") is False

    def test_pending_to_ready_is_true(self):
        assert task_graph.validate_transition("pending", "ready") is True

    def test_failed_to_pending_is_true(self):
        assert task_graph.validate_transition("failed", "pending") is True

    def test_pending_to_in_progress_is_true(self):
        assert task_graph.validate_transition("pending", "in_progress") is True

    def test_ready_to_in_progress_is_true(self):
        assert task_graph.validate_transition("ready", "in_progress") is True

    def test_in_progress_to_done_is_true(self):
        assert task_graph.validate_transition("in_progress", "done") is True

    def test_in_progress_to_failed_is_true(self):
        assert task_graph.validate_transition("in_progress", "failed") is True

    def test_pending_to_deferred_is_true(self):
        assert task_graph.validate_transition("pending", "deferred") is True

    def test_ready_to_deferred_is_true(self):
        assert task_graph.validate_transition("ready", "deferred") is True

    def test_in_progress_to_deferred_is_true(self):
        assert task_graph.validate_transition("in_progress", "deferred") is True

    def test_failed_to_deferred_is_true(self):
        assert task_graph.validate_transition("failed", "deferred") is True

    def test_pending_to_failed_is_false(self):
        assert task_graph.validate_transition("pending", "failed") is False

    def test_pending_to_done_is_false(self):
        # pending cannot skip directly to done
        assert task_graph.validate_transition("pending", "done") is False
