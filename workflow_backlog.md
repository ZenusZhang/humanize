# Workflow Backlog / 工作流待办

## Lane-level worker↔reviewer pair loop / Lane 级 worker↔reviewer 配对循环

- 2026-03-02 (TODO): Add a hard cap of **5** iterations for each lane-level worker↔reviewer pair loop. If the cap is reached without signoff, escalate to the coordinator (re-scope / re-plan) instead of looping indefinitely.
- 2026-03-02 (TODO): 给 lane 级 worker↔reviewer pair loop 增加最大轮数限制：**5**。达到上限仍未 signoff 时，升级到全局协调（re-scope / re-plan），避免无限循环。

## Bilingual plan generation / 双语 plan 生成

- 2026-03-02 (TODO): When generating bilingual plans, write two files: the default plan uses the original filename; the Chinese plan adds `_zh` before the extension (e.g. `docs/plan.md` + `docs/plan_zh.md`).
- 2026-03-02 (TODO): 生成双语 plan 时输出两个文件：默认版本用原文件名；中文版本在文件名（扩展名之前）加 `_zh` 后缀（例：`docs/plan.md` + `docs/plan_zh.md`）。

## Dependency graph dispatch / 依赖图调度（compute graph）

- 2026-03-02 (TODO): Model plan tasks as a dependency graph (nodes = `Task ID`; edges from `Depends On` / `blockedBy`). Persist per-task status (e.g., `pending`/`in_progress`/`done`) and compute the “ready” set (all deps done).
- 2026-03-02 (TODO): When dispatching work to lane-level worker↔reviewer pairs, automatically batch and send only currently-ready tasks (respecting dependencies) to available lanes; do not dispatch blocked tasks.
- 2026-03-02 (TODO): Integrate readiness filtering into `/humanize:gen-batch-prompt` (or a new scheduler helper) so the generated `/batch` prompt includes only ready tasks by default; optionally allow an override (e.g., `--include-blocked`) for debugging.
- 2026-03-02 (TODO): 以计算图方式记录 task 依赖，并在每次分发给 pair 时只发送“当前已解锁/可执行”的一批 task；blocked task 不应被分发（除非显式 override）。

## Plan template investigation / 计划模板排查

- 2026-03-02 (TODO): Investigate why generated plans include a \"Codex 团队工作流\" section (potentially redundant). Trace the introducing commit and find the originating Codex session; ensure we do not confuse \"workflow for developing humanize\" with \"humanize workflow for other projects\".
