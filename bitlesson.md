# BitLesson Knowledge Base

This file is project-specific. Keep entries precise and reusable for future rounds.

## Entry Template (Strict)

Use this exact field order for every entry:

```markdown
## Lesson: <unique-id>
Lesson ID: <BL-YYYYMMDD-short-name>
Scope: <component/subsystem/files>
Problem Description: <specific failure mode with trigger conditions>
Root Cause: <direct technical cause>
Solution: <exact fix that resolved the problem>
Constraints: <limits, assumptions, non-goals>
Validation Evidence: <tests/commands/logs/PR evidence>
Source Rounds: <round numbers where problem appeared and was solved>
```

## Entries

<!-- Add lessons below using the strict template. -->

## Lesson: trailing-pipe-split
Lesson ID: BL-20260302-trailing-pipe-split
Scope: scripts/task-graph.py, any Markdown table parser
Problem Description: `_split_cells()` used `row.split("|")[1:-1]` which
  assumes every table row has a trailing `|`. Rows without trailing pipe
  (valid Markdown) silently dropped the last cell, causing missing tasks
  and dependencies in all downstream parse functions.
Root Cause: `parts[1:-1]` unconditionally discards both first and last
  elements; the last element is only empty when the trailing `|` is present.
Solution: Use `parts[1:]` to discard the leading empty string, then
  additionally strip the last element only when it is blank:
    parts = parts[1:]
    if parts and parts[-1].strip() == "":
        parts = parts[:-1]
Constraints: Applies to any parser that splits Markdown table rows on `|`.
  Rows without a leading `|` are also handled (no initial strip needed).
Validation Evidence: 6 regression tests added in TestSplitCellsTrailingPipe;
  95/95 pytest pass. Round 5 code review cleared.
Source Rounds: 5

