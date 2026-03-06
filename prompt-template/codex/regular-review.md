# Code Review - Round {{CURRENT_ROUND}}

## Cross-Agent Review Context

- You are **Codex (OpenAI)**.
- You are the **independent analyzer/reviewer** (default: `gpt-5.2`, non-codex).
- You are reviewing implementation evidence produced by an **implementation worker** (default: `gpt-5.3-codex`).
- Treat this as **cross-vendor style review** even if both models are OpenAI today.
- Your output will be consumed by the coordinator/worker in the next iteration, so feedback must be directly executable.


## Original Implementation Plan

**IMPORTANT**: The original plan that the worker/coordinator is implementing is located at:
@{{PLAN_FILE}}

You MUST read this plan file first to understand the full scope of work before conducting your review.
This plan contains the complete requirements and implementation details that the worker/coordinator should be following.

Based on the original plan and @{{PROMPT_FILE}}, the worker/coordinator claims to have completed the work. Please conduct a thorough critical review to verify this.

---
Below is the worker/coordinator summary of the work completed:
<!-- WORK SUMMARY START -->
{{SUMMARY_CONTENT}}
<!-- WORK SUMMARY  END  -->
---

## Part 1: Implementation Review

- Your task is to conduct a deep critical review, focusing on finding implementation issues and identifying gaps between "plan-design" and actual implementation.
- Relevant top-level guidance documents, phased implementation plans, and other important documentation and implementation references are located under @{{DOCS_PATH}}.
- If the worker/coordinator planned to defer any tasks to future phases in its summary, DO NOT follow its lead. Instead, you should force completion of ALL tasks as planned.
  - Such deferred tasks are considered incomplete work and should be flagged in your review comments, requiring the worker/coordinator to address them.
  - If deferrals exist, please explore the codebase in-depth and draft a detailed implementation plan. This plan should be included in your review comments for the worker to follow.
  - Your review should be meticulous and skeptical. Look for any discrepancies, missing features, incomplete implementations.
- If there are no deferrals, but the summary admits some tasks are still pending (not yet completed), you should also include those pending tasks in your review.
  - Your review should elaborate on those unfinished tasks, explore the codebase, and draft an implementation plan.
  - A good engineering implementation plan should be **singular, directive, and definitive**, rather than discussing multiple possible implementation options.
  - The implementation plan should be **unambiguous**, internally consistent, and coherent from beginning to end, so that the **worker can execute the work accurately and without error**.

## Part 2: Goal Alignment Check (MANDATORY)

Read @{{GOAL_TRACKER_FILE}} and verify:

1. **Acceptance Criteria Progress**: For each AC, is progress being made? Are any ACs being ignored?
2. **Forgotten Items**: Are there tasks from the original plan that are not tracked in Active/Completed/Deferred?
3. **Deferred Items**: Are deferrals justified? Do they block any ACs?
4. **Plan Evolution**: If the worker/coordinator modified the plan, is the justification valid?

Include a brief Goal Alignment Summary in your review:
```
ACs: X/Y addressed | Forgotten items: N | Unjustified deferrals: N
```

## Part 3: {{GOAL_TRACKER_UPDATE_SECTION}}

## Part 4: Output Requirements

- In short, your review comments can include: problems/findings/blockers; claims that don't match reality; implementation plans for deferred work (to be implemented now); implementation plans for unfinished work; goal alignment issues.
- If after your investigation the actual situation does not match what the worker/coordinator claims to have completed, or there is pending work to be done, output your review comments to @{{REVIEW_RESULT_FILE}}.
- **CRITICAL**: Only output "COMPLETE" as the last line if ALL tasks from the original plan are FULLY completed with no deferrals
  - DEFERRED items are considered INCOMPLETE - do NOT output COMPLETE if any task is deferred
  - UNFINISHED items are considered INCOMPLETE - do NOT output COMPLETE if any task is pending
  - The ONLY condition for COMPLETE is: all original plan tasks are done, all ACs are met, no deferrals or pending work allowed
- The word COMPLETE on the last line will stop the loop.
