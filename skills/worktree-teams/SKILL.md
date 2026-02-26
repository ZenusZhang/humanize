---
name: worktree-teams
description: Provision scheduler/worker/reviewer git worktree lanes for RLCR agent-teams rounds.
argument-hint: "[--workers N] [--reviewers N] [--loop-dir PATH] [--worktree-root PATH] [--branch-prefix PREFIX] [--base-ref REF]"
allowed-tools: "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree-teams.sh:*)"
---

# Worktree Teams

Provision isolated git worktree lanes for worker and reviewer agents during RLCR implementation rounds.

## How to Use

Run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree-teams.sh" $ARGUMENTS
```

## Typical Flow

1. Start RLCR loop with `--agent-teams --worktree-teams`
2. Run this skill to create worker/reviewer lanes
3. Use `worktree-assignment.md` in the active loop directory for scheduler assignments

## Notes

- Defaults to the active RLCR loop if `--loop-dir` is not provided
- Defaults reviewer count to worker count
- Writes lane mapping to `worktree-assignment.md`
