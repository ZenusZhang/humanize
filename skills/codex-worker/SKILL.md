---
name: codex-worker
description: Run Codex CLI as the implementation worker (default: gpt-5.3-codex:xhigh).
argument-hint: "[--worker-model MODEL:EFFORT] [--worker-timeout SECONDS] [--workdir PATH] [task or instructions]"
allowed-tools: "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/codex-worker.sh:*)"
---

# Codex Worker

Run Codex CLI as the **implementation worker** for `coding` tasks.

## How to Use

Run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/codex-worker.sh" $ARGUMENTS
```

## Output

- The script outputs the worker response to **stdout**
- Debug/status info is written to **stderr**
- Logs are saved under `.humanize/skill/<unique-id>/` and `~/.cache/humanize/.../skill-<unique-id>/`

## Notes

- Default worker model is `gpt-5.3-codex:xhigh`
- Analyzer/reviewer should use `gpt-5.2:xhigh` (non-codex) via `/humanize:ask-codex`
