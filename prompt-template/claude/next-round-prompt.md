Your work is not finished. Read and execute the below with ultrathink.

## Original Implementation Plan

**IMPORTANT**: Before proceeding, review the original plan you are implementing:
@{{PLAN_FILE}}

This plan contains the full scope of work and requirements. Ensure your work aligns with this plan.

---

For all tasks that need to be completed, please use the Task system (TaskCreate, TaskUpdate, TaskList) to track each item in order of importance.
You are strictly prohibited from only addressing the most important issues - you MUST create Tasks for ALL discovered issues and attempt to resolve each one.

## Sub-Agent Cross-Review Protocol (MANDATORY)

For every sub-agent invocation in this round (Task agents, `bitlesson-selector`, code simplifier, etc.), include explicit Claude/Codex context in the prompt:
- Either: "Your output will be reviewed by Codex."
- Or: "You are reviewing Codex-produced findings/results."

---
Below is Codex's review result:
<!-- CODEX's REVIEW RESULT START -->
{{REVIEW_CONTENT}}
<!-- CODEX's REVIEW RESULT  END  -->
---

## BitLesson Selection (REQUIRED BEFORE EXECUTION)

Before executing any task or sub-task in this round:
- Read @{{BITLESSON_FILE}}
- Run `bitlesson-selector` with sub-task + related paths + `bitlesson.md`
- Apply selected lesson IDs (or `NONE`) during implementation
- If a problem is solved only after multiple rounds, add/update the lesson entry in `bitlesson.md`

---

## Goal Tracker Reference (READ-ONLY after Round 0)

Before starting work, **read** @{{GOAL_TRACKER_FILE}} to understand:
- The Ultimate Goal and Acceptance Criteria you're working toward
- Which tasks are Active, Completed, or Deferred
- Any Plan Evolution that has occurred
- Open Issues that need attention

**IMPORTANT**: You CANNOT directly modify goal-tracker.md after Round 0.
If you need to update the Goal Tracker, include a "Goal Tracker Update Request" section in your summary (see below).
