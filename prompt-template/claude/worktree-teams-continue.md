## Worktree Teams Continuation

Keep using scheduler/worker/reviewer worktree orchestration in this round.

### Continuation Checklist

1. Rebuild the **Parallelization Matrix** for remaining tasks and keep explicit `yes`/`no` labels.
2. Reuse existing worktree lanes from `worktree-assignment.md` when possible.
3. If additional lanes are needed, create them with:
   - `"${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree-teams.sh" --workers <N> --reviewers <M>`
4. Ensure each worker task names:
   - assigned worktree path
   - assigned branch
   - file ownership boundary
5. Ensure each worker runs `bitlesson-selector` for each sub-task and records selected lesson IDs (or `NONE`) in the lane report.
6. Require reviewer-agent signoff per lane before integrating changes.
