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
5. Ensure each worker runs `bitlesson-selector` for each sub-task and records selected lesson IDs (or `NONE`) in the lane report.
6. Ensure worker Task invocations explicitly set `model: sonnet`.
7. Require reviewer-agent signoff per lane before integrating changes.
8. Ensure every Task prompt includes explicit Claude/Codex cross-review context:
   - "your output will be reviewed by Codex", or
   - "you are reviewing Codex-produced findings/results."
