## Document-Centered Worktree Mode (REQUIRED)

You are operating in document-centered orchestration. Coordination must be driven by project docs,
not by a single scheduler role. Keep `plan.md`, `goal-tracker.md`, and `worktree-assignment.md`
as the source of truth for task routing and lane ownership.

Roles (recorded in `worktree-assignment.md`):
- **Worker Agents**: implement assigned tasks in isolated worktrees
- **Reviewer Agents**: review worker outputs independently before merge

### Required Protocol

1. Build a **Parallelization Matrix** in the docs before implementation. Every task must include an explicit `yes` or `no` in the "Parallelizable" column, stored in `plan.md` or `worktree-assignment.md`.
2. Assign each parallelizable lane to a dedicated worker and reviewer pair and record ownership in `worktree-assignment.md`.
3. Use isolated `git worktree` directories per lane to avoid silent overwrite conflicts.
4. Never assign two active workers to the same file in parallel. If overlap is required, enforce order via `blockedBy`.
5. For every worker task, require running `bitlesson-selector` before coding and record selected lesson IDs (or `NONE`) in the lane notes.
6. When spawning worker agents, explicitly set `model: sonnet` in each Task tool invocation.
7. In every worker/reviewer Task prompt, add explicit Claude/Codex context:
   - worker/explorer: "your output will be reviewed by Codex"
   - reviewer over Codex feedback: "you are reviewing Codex-produced findings/results"

Use this table format (store it in `worktree-assignment.md` or `plan.md`):

| Task ID | Parallelizable (yes/no) | Reason | File Ownership | blockedBy | Worker | Reviewer | Worktree Path |
|---------|--------------------------|--------|----------------|-----------|--------|----------|---------------|

### Worktree Setup

Before spawning implementation teammates, create worktree lanes:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree-teams.sh" --workers <N> --reviewers <M>
```

The script writes lane mappings to `worktree-assignment.md` in the active RLCR loop directory.
Use that mapping directly when assigning worker/reviewer tasks.
