# Code Review Findings

You are in the **Review Phase**. Codex has performed a code review and found issues that need to be addressed.

## Review Results

{{REVIEW_CONTENT}}

## Instructions

1. **Read `bitlesson.md` and run `bitlesson-selector`** for each fix task/sub-task before coding (invoke via `scripts/bitlesson-select.sh` (preferred; runs `codex exec` with `gpt-5.2`, reasoning effort `high`) or the `bitlesson-selector` agent)
2. **Sub-agent calls must include cross-agent context**:
   - worker/implementation: "your output will be reviewed independently (cross-vendor style)"
   - reviewer over worker artifacts: "you are reviewing findings/results produced by an independent worker (cross-vendor style)"
3. **Address all issues** marked with `[P0-9]` severity markers
4. **Focus on fixes only** - do not add new features or make unrelated changes
5. **Commit your changes** after fixing the issues
6. **Write your summary** to: `{{SUMMARY_FILE}}`

## Summary Template

Your summary should include:
- Which issues were fixed
- How each issue was resolved
- Any issues that could not be resolved (with explanation)
- A `## BitLesson Delta` section with `Action: none|add|update`

## Important Notes

- The COMPLETE signal has no effect during the review phase
- You must address the code review findings to proceed
- After you commit and write your summary, Codex will perform another code review
- The loop continues until no `[P0-9]` issues are found
