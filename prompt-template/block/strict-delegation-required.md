# Strict Delegation Required

This RLCR loop is running in strict delegation mode for round {{CURRENT_ROUND}}.

Claude must not {{ACTION}} {{TARGET}} directly. In strict mode, source-code changes
must go through `/humanize:codex-worker`.

Allowed coordinator actions:
- update `.humanize/` coordination files
- update `bitlesson.md` when required by the workflow
- inspect files, diffs, and run non-mutating commands

Next step: invoke `/humanize:codex-worker` for the coding task, then continue coordinating from Claude.
