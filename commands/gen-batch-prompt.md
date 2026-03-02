---
description: "Generate a ready-to-paste Claude Code /batch prompt from worktree-assignment.md"
argument-hint: "[--loop-dir PATH] [--project-root PATH]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/gen-batch-prompt.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Generate `/batch` Prompt

Execute the helper script:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gen-batch-prompt.sh" $ARGUMENTS
```

This prints a ready-to-paste dispatch prompt based on the active RLCR loop's:
- `worktree-assignment.md` (Parallelization Matrix)
- `plan.md` (Task ID -> Description mapping)

Then:
1. Run Claude Code `/batch`
2. Paste the generated prompt
