## Worktree Teams Continuation

Keep using document-centered worktree orchestration in this round.

### Continuation Checklist

1. Update the doc-based **Parallelization Matrix** for remaining tasks and keep explicit `yes`/`no` labels in `plan.md` or `worktree-assignment.md`.
2. Reuse existing worktree lanes from `worktree-assignment.md` when possible.
3. If additional lanes are needed, create them with:
   - `"${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree-teams.sh" --workers <N> --reviewers <M>`
4. Ensure each worker task names:
   - assigned worktree path
   - assigned branch
   - file ownership boundary
5. Ensure each worker runs `bitlesson-selector` for each sub-task (invoke via `scripts/bitlesson-select.sh` (preferred; runs `codex exec -m gpt-5.4 -c model_reasoning_effort=xhigh`) or the `bitlesson-selector` agent) and records selected lesson IDs (or `NONE`) in the lane report.
6. Ensure each worker run uses `/humanize:codex-worker --workdir <worktree path>` (default: `gpt-5.4:xhigh`).
7. Require reviewer-agent signoff per lane before integrating changes.
8. Ensure every worker/reviewer prompt includes explicit cross-vendor review context:
   - worker: "your output will be reviewed independently (cross-vendor style)"
   - reviewer: "you are reviewing findings/results produced by an independent worker (cross-vendor style)"
