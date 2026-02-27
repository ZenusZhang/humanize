# BitLesson Workflow Implementation Plan

## 1. New Knowledge File and Schema

- Create `bitlesson.md` in the repository root.
- Define a strict entry template with fields:
  - `Lesson ID`
  - `Scope`
  - `Problem Description`
  - `Root Cause`
  - `Solution`
  - `Constraints`
  - `Validation Evidence`
  - `Source Rounds`
- Goal: make "problem description + solution" reusable and precise, not generic guidance.

## 2. New Selector Agent

- Add `agents/bitlesson-selector.md`.
- Responsibility:
  - Input: current worker sub-task, related file paths, and `bitlesson.md`.
  - Output: required lesson IDs for this task (or `NONE`) with concise rationale.
- Keep output format stable so prompts and tests can validate it reliably.

## 3. Integrate BitLesson into RLCR/Worktree Workflow

- Update round-0 initialization prompt generation in `scripts/setup-rlcr-loop.sh`:
  - Require reading `bitlesson.md`.
  - Require running lesson selection before execution.
- Update next-round prompt generation in `hooks/loop-codex-stop-hook.sh`:
  - Re-apply the same requirement per round.
- Update templates to enforce selector usage in scheduler/worker flow:
  - `prompt-template/claude/agent-teams-core.md`
  - `prompt-template/claude/agent-teams-continue.md`
  - `prompt-template/claude/worktree-teams-instructions.md`
  - `prompt-template/claude/worktree-teams-continue.md`
  - `prompt-template/claude/next-round-prompt.md`

## 4. Multi-Round Problem Capture Rule

- Require each round summary to include a `BitLesson Delta` section with `none/add/update`.
- If a problem is solved only after multiple rounds:
  - It must be added/updated in `bitlesson.md`.
  - Entry must include precise problem statement and precise solution.
- Add lightweight stop-hook enforcement:
  - Block if `BitLesson Delta` is missing.
  - Keep validation simple first to reduce false positives.

## 5. Documentation Updates

- Update `README.md` with bitlesson workflow and selector usage.
- Update `commands/start-rlcr-loop.md` with the same operational rules.

## 6. Test Plan

- Add/update tests to cover:
  - `agents/bitlesson-selector.md` frontmatter and structure validity.
  - Round-0/next-round prompts include mandatory bitlesson steps.
  - Agent-teams/worktree-teams prompts include selector invocation constraints.
  - Stop hook blocks when `BitLesson Delta` section is missing.
- Ensure test registration in `tests/run-all-tests.sh` where needed.

