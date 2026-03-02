# Workflow Backlog / 工作流待办

## Lane-level worker↔reviewer pair loop / Lane 级 worker↔reviewer 配对循环

- 2026-03-02 (TODO): 给 lane 级 worker↔reviewer pair loop 增加最大轮数限制：**5**。达到上限仍未 signoff 时，必须升级到全局协调（re-scope / re-plan），避免无限循环。
- 2026-03-02 (TODO): Add a hard cap of **5** iterations for each lane-level worker↔reviewer pair loop. If the cap is reached without signoff, escalate to the coordinator (re-scope / re-plan) instead of looping indefinitely.

## Bilingual plan generation / 双语 plan 生成

- 2026-03-02 (TODO): 生成双语 plan 时输出两个文件：默认版本用原文件名；中文版本在文件名（扩展名之前）加 `_zh` 后缀（例：`docs/plan.md` + `docs/plan_zh.md`）。
- 2026-03-02 (TODO): When generating bilingual plans, write two files: the default plan uses the original filename; the Chinese plan adds `_zh` before the extension (e.g. `docs/plan.md` + `docs/plan_zh.md`).
