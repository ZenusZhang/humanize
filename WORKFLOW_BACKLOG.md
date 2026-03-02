# Workflow Backlog / 工作流待办

## Lane-level worker↔reviewer pair loop / Lane 级 worker↔reviewer 配对循环

- 2026-03-02 (TODO): 给 lane 级 worker↔reviewer pair loop 增加最大轮数限制：**5**。达到上限仍未 signoff 时，必须升级到全局协调（re-scope / re-plan），避免无限循环。
- 2026-03-02 (TODO): Add a hard cap of **5** iterations for each lane-level worker↔reviewer pair loop. If the cap is reached without signoff, escalate to the coordinator (re-scope / re-plan) instead of looping indefinitely.

