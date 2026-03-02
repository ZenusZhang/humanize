# Workflow Backlog / 工作流待办

## Lane-level worker↔reviewer pair loop / Lane 级 worker↔reviewer 配对循环

- 2026-03-02 (TODO): Add a hard cap of **5** iterations for each lane-level worker↔reviewer pair loop. If the cap is reached without signoff, escalate to the coordinator (re-scope / re-plan) instead of looping indefinitely.
- 2026-03-02 (TODO): 给 lane 级 worker↔reviewer pair loop 增加最大轮数限制：**5**。达到上限仍未 signoff 时，升级到全局协调（re-scope / re-plan），避免无限循环。

## Bilingual plan generation / 双语 plan 生成

- 2026-03-02 (TODO): When generating bilingual plans, write two files: the default plan uses the original filename; the Chinese plan adds `_zh` before the extension (e.g. `docs/plan.md` + `docs/plan_zh.md`).
- 2026-03-02 (TODO): 生成双语 plan 时输出两个文件：默认版本用原文件名；中文版本在文件名（扩展名之前）加 `_zh` 后缀（例：`docs/plan.md` + `docs/plan_zh.md`）。

## Dependency graph dispatch / 依赖图调度（compute graph）

- 2026-03-02 (Context): Task dependencies are currently *recorded* but not *enforced* for dispatch.
  - Plan schema: tasks include `Depends On` (`prompt-template/plan/gen-plan-template.md:80`).
  - Worktree matrix: includes `blockedBy` and is used as a doc-based coordination aid (`prompt-template/claude/worktree-teams-instructions.md:25`).
  - Dispatch helper: `/humanize:gen-batch-prompt` selects tasks only where `Parallelizable == yes` and does not gate on dependency readiness (`scripts/gen-batch-prompt.sh:37`, `scripts/gen-batch-prompt.sh:268`).
  - `blockedBy` is currently surfaced as metadata only (printed in the task line) (`scripts/gen-batch-prompt.sh:291`).
  - Repo search: no `toposort`/`topological`/`Kahn`/`in_degree` scheduling implementation found (no hits for those terms).

- 2026-03-02 (TODO): Model plan tasks as a dependency graph (nodes = `Task ID`; edges from `Depends On` / `blockedBy`). Persist per-task status (e.g., `pending`/`in_progress`/`done`) and compute the “ready” set (all deps done).
- 2026-03-02 (TODO): When dispatching work to lane-level worker↔reviewer pairs, automatically batch and send only currently-ready tasks (respecting dependencies) to available lanes; do not dispatch blocked tasks.
- 2026-03-02 (TODO): Integrate readiness filtering into `/humanize:gen-batch-prompt` (or a new scheduler helper) so the generated `/batch` prompt includes only ready tasks by default; optionally allow an override (e.g., `--include-blocked`) for debugging.
- 2026-03-02 (TODO): 以计算图方式记录 task 依赖，并在每次分发给 pair 时只发送“当前已解锁/可执行”的一批 task；blocked task 不应被分发（除非显式 override）。

- 2026-03-02 (Spec): Canonical task graph inputs and normalization
  - Node identity: `Task ID` is required and must be unique (recommended format: `task<alnum._->`).
  - Dependency sources:
    - `Depends On` from plan task table is the primary semantic dependency.
    - `blockedBy` from `worktree-assignment.md` is an additional coordination dependency (e.g., file-overlap ordering).
  - Normalization rules (proposed):
    - Allow `-` / empty to mean no dependencies.
    - Allow comma-separated lists in `Depends On` and `blockedBy` (e.g., `task1, task2`).
    - Treat unknown referenced task IDs as an error (fail-fast).
    - Detect and error on dependency cycles.

- 2026-03-02 (Spec): Status model (minimum viable)
  - Persisted status must be machine-readable and updated each dispatch cycle.
  - Proposed states: `pending` | `ready` | `in_progress` | `done` | `blocked` | `deferred` | `failed`.
  - Source of truth (choose one; do not split brain):
    - Option A: extend `worktree-assignment.md` matrix with a `Status` column (plus optional `Last Updated`).
    - Option B: add a machine-readable file in the loop dir, e.g. `task-state.json` or `task-state.yml`.
  - Define what makes a task `done`:
    - lane reviewer signoff + merged commit (preferred), or
    - an explicit coordinator status update (manual fallback).

- 2026-03-02 (Spec): Ready-set computation (DAG)
  - A task is `ready` iff:
    - status is `pending` (or `blocked` but now unblocked), AND
    - all dependencies are `done`, AND
    - its lane constraints are satisfiable (ownership boundaries, no forbidden overlaps).
  - Implementation sketch:
    - Build `deps[task] -> set(taskDeps)` and `reverseDeps`.
    - Maintain `doneSet`.
    - Compute readiness by checking `deps[task] ⊆ doneSet` (or Kahn/in-degree if you want incremental updates).
    - Output stable ordering (topological order + deterministic tie-breaker).

- 2026-03-02 (Spec): Batch dispatch to lane-level worker↔reviewer pairs
  - Input: available lanes (from `worktree-assignment.md`), lane ownership boundaries, and task readiness.
  - Output: one `/batch` payload containing:
    - only `ready` tasks by default, grouped per worker lane
    - explicit lane reviewer mapping for signoff expectations
    - explicit `blockedBy`/`Depends On` shown for audit
  - Policy knobs (proposed CLI flags for `gen-batch-prompt` or a new scheduler helper):
    - `--ready-only` (default: true)
    - `--include-blocked` (default: false; debugging only)
    - `--max-tasks-per-lane <N>` (default: 1 or small number)
    - `--prefer-same-lane` (keep related tasks in same lane when safe)

- 2026-03-02 (AC): Minimal acceptance criteria for the feature
  - Given `task2` depends on `task1`, and `task1` is not `done`, `task2` is not emitted in `/batch` output (unless `--include-blocked`).
  - When `task1` becomes `done`, `task2` appears in the next dispatch batch automatically.
  - Cycles (e.g., `task1 -> task2 -> task1`) produce a clear error and non-zero exit.
  - Unknown dependencies (typos) produce a clear error and non-zero exit.
  - Unit tests cover: parse, readiness filtering, cycle detection, and stable ordering.

## Plan template investigation / 计划模板排查

- 2026-03-02 (TODO): Investigate why generated plans include a \"Codex 团队工作流\" section (potentially redundant). Trace the introducing commit and find the originating Codex session; ensure we do not confuse \"workflow for developing humanize\" with \"humanize workflow for other projects\".
