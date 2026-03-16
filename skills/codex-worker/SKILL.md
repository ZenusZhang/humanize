---
name: codex-worker
description: Run Codex CLI as the implementation worker (default: gpt-5.4:xhigh).
argument-hint: "[--worker-model MODEL:EFFORT] [--worker-timeout SECONDS] [--workdir PATH] [task or instructions]"
allowed-tools: "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/codex-worker.sh:*)"
---

# Codex Worker

Run Codex CLI as the **implementation worker** for `coding` tasks.

## How to Use

Do not pass free-form user text to the shell unquoted. The task may contain spaces or shell metacharacters such as `(`, `)`, `;`, `#`, `*`, or `[`.

If the user only supplied a task or instructions, execute:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/codex-worker.sh" "$ARGUMENTS"
```

If the user supplied flags such as `--worker-model`, `--worker-timeout`, or `--workdir`, reconstruct the command so those flags remain separate shell arguments and the remaining free-form task is passed as one quoted final argument.

Example:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/codex-worker.sh" --worker-model gpt-5.4:xhigh --workdir /repo/worktree "Implement the pending coding task and run relevant checks"
```

Never run this unsafe form:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/codex-worker.sh" $ARGUMENTS
```

because the shell will re-parse the task text and can fail before `codex-worker.sh` starts.

## Output

- The script outputs the worker response to **stdout** and status info to **stderr**
- Read the stdout output carefully and incorporate the worker result into your coordination flow
- If the script exits with a non-zero code, report the error to the user

## Error Handling

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success - worker response is in stdout |
| 1 | Validation error (missing codex, empty task, invalid flags, empty response) |
| 124 | Timeout - suggest using `--worker-timeout` with a larger value |
| Other | Codex process error - report the exit code and any stderr output |

## Notes

- Default worker model is `gpt-5.4:xhigh`
- The response is saved to `.humanize/skill/<timestamp>/output.md` for reference
