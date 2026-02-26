---
description: "Provision scheduler/worker/reviewer git worktree lanes for an active RLCR loop"
argument-hint: "[--workers N] [--reviewers N] [--loop-dir PATH] [--worktree-root PATH] [--branch-prefix PREFIX] [--base-ref REF]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree-teams.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Setup Worktree Teams

Execute the setup script to create worker/reviewer worktree lanes:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree-teams.sh" $ARGUMENTS
```

This command:

1. Finds the active RLCR loop (or uses `--loop-dir`)
2. Creates isolated worker/reviewer `git worktree` lanes
3. Reuses existing lanes if they already exist
4. Writes lane mapping to `worktree-assignment.md` in the loop directory

## Common Usage

```bash
/humanize:setup-worktree-teams --workers 3 --reviewers 2
```

## Notes

- Run this after `/humanize:start-rlcr-loop --agent-teams --worktree-teams`
- `--reviewers` defaults to the same count as `--workers`
- `--worktree-root` defaults to state value, then `.humanize/worktrees/<loop-id>`
- `--base-ref` defaults to `start_branch` from loop state, then current branch
