## Document-Centered Worktree Mode (REQUIRED)

You are operating in document-centered orchestration. Coordination must be driven by project docs,
not by a single scheduler role. Keep `plan.md`, `goal-tracker.md`, and `worktree-assignment.md`
as the source of truth for task routing and lane ownership.

Roles (recorded in `worktree-assignment.md`):
- **Worker (Codex CLI)**: implement assigned tasks in isolated worktrees via `/humanize:codex-worker` (default: `gpt-5.3-codex:xhigh`)
- **Reviewer (Codex CLI)**: review worker outputs independently before merge (default: `gpt-5.2:xhigh`)

### Required Protocol

1. Build a **Parallelization Matrix** in the docs before implementation. Every task must include an explicit `yes` or `no` in the "Parallelizable" column, stored in `plan.md` or `worktree-assignment.md`.
2. Assign each parallelizable lane to a dedicated worker and reviewer pair and record ownership in `worktree-assignment.md`.
3. Use isolated `git worktree` directories per lane to avoid silent overwrite conflicts.
4. Never assign two active workers to the same file in parallel. If overlap is required, enforce order via `blockedBy`.
5. For every worker task, require running `bitlesson-selector` before coding and record selected lesson IDs (or `NONE`) in the lane notes.
6. When invoking `/humanize:codex-worker` for a lane, pass `--workdir <worktree path>` and keep the default `gpt-5.3-codex:xhigh` unless there is a concrete reason to override.
7. In every worker/reviewer prompt, add explicit cross-vendor context (even if all models are OpenAI today):
   - worker: "your output will be reviewed independently (cross-vendor style)"
   - reviewer: "you are reviewing findings/results produced by an independent worker (cross-vendor style)"

Use this table format (store it in `worktree-assignment.md` or `plan.md`):

| Task ID | Parallelizable (yes/no) | Reason | File Ownership | blockedBy | Worker | Reviewer | Worktree Path |
|---------|--------------------------|--------|----------------|-----------|--------|----------|---------------|

### Worktree Setup

Before running worker tasks, create worktree lanes:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree-teams.sh" --workers <N> --reviewers <M>
```

The script writes lane mappings to `worktree-assignment.md` in the active RLCR loop directory.
Use that mapping directly when assigning worker/reviewer tasks.
