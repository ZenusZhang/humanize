---
description: "Continue active RLCR loop (print current round prompt)"
argument-hint: "[--paths-only] [--max-prompt-bytes N] [--loop-dir PATH]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/continue-rlcr-loop.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Continue RLCR Loop

Print the current round prompt from the active RLCR loop directory:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/continue-rlcr-loop.sh" $ARGUMENTS
```

This is useful when you start a fresh Claude session (for example after hitting
context length limits) and want to resume the loop from on-disk state, without
using `claude --resume`.

