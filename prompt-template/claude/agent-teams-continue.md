## Agent Teams Continuation

Continue using **Agent Teams mode** as the **Team Leader** within the RLCR development cycle. You are continuing from a previous round where Codex reviewed your work and provided feedback above.

### Continuation Context

- **Previous Team No Longer Exists**: Treat the previous round's worker runs as gone. Do NOT assume any retained context across worker/analyzer calls.
- **Review First**: Before running any worker tasks, carefully analyze the Codex review feedback above. Understand which issues are most critical and plan your work package allocation accordingly.
- **Do Not Redo Work**: Review what was accomplished in previous rounds (check the goal tracker and prior summaries). Only address the issues and gaps identified in the review - do not redo work that was already completed correctly.
- **Cold Start for Worker Runs**: Each `/humanize:codex-worker` call is a cold start. Provide: what was already accomplished, current file state, specific review findings to address, and clear acceptance criteria.
- **Worker Model Default**: Use `/humanize:codex-worker` with default `gpt-5.3-codex:xhigh` unless there is a concrete reason to override.
- **Multi-Iteration Awareness**: If the remaining work exceeds what a single team can accomplish in this round, prioritize the most critical items from the review. Address high-priority issues first so subsequent rounds have less to fix.
- **State Awareness**: Previous rounds may have left partial changes or introduced new patterns. Verify the current state of files (e.g., with quick reads or greps) before assigning file ownership boundaries.
- **BitLesson Selector Required**: For each sub-task, run `bitlesson-selector` first (invoke via `scripts/bitlesson-select.sh` (preferred; runs `codex exec` with `gpt-5.2`, reasoning effort `high`) or the `bitlesson-selector` agent) and record selected lesson IDs (or `NONE`) before invoking the worker.
- **Cross-Vendor Context Required**: Every worker/analyzer/reviewer prompt must explicitly state the cross-vendor-style relationship:
  - worker: "your output will be reviewed independently (cross-vendor style)"
  - analyzer/reviewer: "you are reviewing findings/results produced by an independent worker (cross-vendor style)"
