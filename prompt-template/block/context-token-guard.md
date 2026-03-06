# Context Token Guard Triggered

Estimated context size from stop-hook input: {{ESTIMATED_TOKENS}} tokens.  
Safety threshold: {{TOKEN_THRESHOLD}} tokens.

The loop is blocked to avoid low-quality reviews caused by context pressure.

## Recovery Steps

1. Start a **fresh Claude session** (avoid `claude --resume` when context is already huge).
2. Run `/humanize:continue-rlcr-loop` to print the current round prompt from on-disk state.
3. Resume from loop docs:
   - Plan: {{PLAN_FILE}}
   - Goal tracker: {{GOAL_TRACKER_FILE}}
   - Summary: {{SUMMARY_FILE}}
4. Recovery note: {{RECOVERY_NOTE_FILE}}

