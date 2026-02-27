## Scheduler + Worktree Mode (REQUIRED)

You are operating with explicit role separation:
- **Scheduler Agent** (you): task classification, assignment, sequencing
- **Worker Agents**: implement assigned tasks in isolated worktrees
- **Reviewer Agents**: review worker outputs independently before merge

### Required Protocol

1. Build a **Parallelization Matrix** before implementation. Every task must include an explicit `yes` or `no` in the "Parallelizable" column.
2. Assign each parallelizable lane to a dedicated worker and reviewer pair.
3. Use isolated `git worktree` directories per lane to avoid silent overwrite conflicts.
4. Never assign two active workers to the same file in parallel. If overlap is required, enforce order via `blockedBy`.
5. For every worker task, require running `bitlesson-selector` before coding and record selected lesson IDs (or `NONE`) in the lane notes.

Use this table format:

| Task ID | Parallelizable (yes/no) | Reason | File Ownership | blockedBy | Worker | Reviewer | Worktree Path |
|---------|--------------------------|--------|----------------|-----------|--------|----------|---------------|

### Worktree Setup

Before spawning implementation teammates, create worktree lanes:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree-teams.sh" --workers <N> --reviewers <M>
```

The script writes lane mappings to `worktree-assignment.md` in the active RLCR loop directory.
Use that mapping directly when assigning worker/reviewer tasks.
