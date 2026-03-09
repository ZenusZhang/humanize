# Feature Commit Map (66 Commits)

This document is the SHA assignment table for extracting features from local `main` ahead of upstream.

- Total assigned commits: `66`
- Feature groups: `F1` to `F9` (`F8` rolled back and absent from git history)
- Admin/Infra commits are listed separately and are not submitted as feature PRs.

## Summary

| Group | Name | Commit Count |
|---|---|---:|
| F1 | feat-rlcr-loop-improvements | 7 |
| F2 | feat-gen-plan-convergence | 9 |
| F3 | feat-task-graph | 13 |
| F4 | feat-gen-batch-prompt | 4 |
| F5 | feat-delegation-enforcement | 5 |
| F6 | feat-worktree-teams | 8 |
| F7 | feat-bitlesson-rlcr-integration | 8 |
| F8 | feat-bitlesson-extraction (rolled back) | 0 |
| F9 | feat-misc | 4 |
| Admin/Infra | not submitted as feature PRs | 8 |
| Total |  | 66 |

Note: Analyzer text labeled F9 as "6 commits remaining", but only 4 F9 SHAs were provided. The full provided SHA set still totals exactly 66 commits.

## F1: feat-rlcr-loop-improvements (7)

Note: F1 did **not** ship the worktree-team/worktree-lane feature. Worktree orchestration
belongs to later work (F6), and the `WORKTREE_ROOT_SAFE` mention in commit `07d67bf` should
not be read as evidence that worktree support landed with F1.

| Order | SHA | Subject |
|---:|---|---|
| 1 | 61e45a1 | feat: add continue-rlcr-loop command |
| 2 | c5378a6 | Add codex-worker and split worker/reviewer models |
| 3 | 0a7b4fe | Clarify role/model policy for Codex worker and review |
| 4 | 5678449 | Set Codex defaults to gpt-5.2:xhigh across workflows |
| 5 | bc1c135 | fix: use WORKDIR_ABS for codex exec -C and portable sed -E in stop hook |
| 6 | 09b1134 | fix: use LOOP_DIR for marker placement and correct --workdir help text |
| 7 | 07d67bf | refactor: simplify WORKTREE_ROOT_SAFE guard and remove unused local in loop marker |

## F2: feat-gen-plan-convergence (9)

Note: The Context Token Guard feature did **not** ship with F2. It was introduced later in
local `main`/`zenus/main` worktree-flow commits (see `ee70f4d` under F6), so it was not merged
into upstream `origin/main` together with the F2 gen-plan-convergence series.

| Order | SHA | Subject |
|---:|---|---|
| 1 | c283a92 | feat: add claude-codex debate flow to gen-plan |
| 2 | 9c0eef7 | feat: make gen-plan codex-first with convergence loop |
| 3 | 5156a05 | Add plan-type routing for Claude vs Codex execution |
| 4 | 002308a | Revert "Add plan-type routing for Claude vs Codex execution" |
| 5 | 8ba3a57 | Implement task-tag routing for coding/analyze execution |
| 6 | 437567b | Enhance gen-plan with ultrathink and converged auto-start |
| 7 | 3c8caf5 | feat: cap gen-plan convergence loop to 3 rounds |
| 8 | 4a57429 | feat: add _zh bilingual file output option to gen-plan pipeline (task8) |
| 9 | 821f225 | fix: switch gen-plan default to English-only with optional _zh variant via config |

## F3: feat-task-graph (13)

| Order | SHA | Subject |
|---:|---|---|
| 1 | ca96484 | feat: add task-graph.py parser and DAG builder (task1) |
| 2 | 9920412 | feat: add DFS cycle detection to task-graph.py (task2) |
| 3 | 81e617b | feat: add state read/write and reconcile subcommand (task3) |
| 4 | fed29d9 | feat: add lane iteration tracking and cap enforcement (task7) |
| 5 | 60dadca | feat: add ready-set computation and ready subcommand (task4) |
| 6 | b0747b3 | feat: add pytest unit tests for task-graph.py (task9) |
| 7 | e8e3255 | fix: normalize none/n/a as no-deps, add plan file preflight, fix assignment file handling |
| 8 | 1abe1e4 | fix: normalize backticked task IDs in gen-batch-prompt, catch OSErrors, fix docstrings |
| 9 | 2685897 | fix: catch OSErrors in parse_assignment_file to prevent tracebacks |
| 10 | cf5725b | fix: address Round 6 code review issues P1/P2 and bump to 1.10.16 |
| 11 | 97b280e | fix: address Round 7 code review issues P2/P3 and bump to 1.10.17 |
| 12 | 0c0716b | chore: gitignore plans/ and workflow_backlog.md, bump version to 1.10.12 |
| 13 | fdc5132 | fix: address code review issues P2/P3 and bump version to 1.10.15 |

## F4: feat-gen-batch-prompt (4)

| Order | SHA | Subject |
|---:|---|---|
| 1 | ac570d5 | fix: avoid backtick substitution in worktree matrix scaffold |
| 2 | b0f9aaa | feat: add /batch prompt generator from worktree matrix |
| 3 | ebcd1f0 | feat: integrate readiness filtering into gen-batch-prompt (task5) |
| 4 | d9138d5 | feat: add policy knobs to gen-batch-prompt (task6) |

## F5: feat-delegation-enforcement (5)

| Order | SHA | Subject |
|---:|---|---|
| 1 | 96ce1f5 | feat: add worker invocation marker file and stop-hook warning for missing delegation |
| 2 | 766e619 | feat: strengthen delegation enforcement with consequence language and HUMANIZE_CODEX_DELEGATION_ENFORCEMENT support |
| 3 | 1a57574 | test: add coverage for delegation enforcement and worker marker file behaviors |
| 4 | ae2c56b | test: fix false-positive stop-hook test assertions and add outside-loop negative test |
| 5 | 6e86b65 | chore: bump version 1.10.20 -> 1.10.21 |

## F6: feat-worktree-teams (8)

| Order | SHA | Subject |
|---:|---|---|
| 1 | a5f94fc | feat: add worktree team orchestration and setup command |
| 2 | c8d484a | Enable agent/worktree teams by default for RLCR startup |
| 3 | 7c128c4 | test: align teams defaults and compact next-round prompts |
| 4 | f8e4bb5 | docs: align worktree teams guidance with document-centered workflow |
| 5 | df534b2 | docs: replace scheduler-centric README wording with document-centered worktree mode |
| 6 | 0504e25 | Enforce Claude/Codex cross-review context in sub-agent workflow |
| 7 | ee70f4d | feat(rlcr): enforce doc-first worktree flow for features 2-5 |
| 8 | 111bfde | feat: apply unapplied worktree-teams patch manually (context drift from 1.10.4) |

## F7: feat-bitlesson-rlcr-integration (8)

| Order | SHA | Subject |
|---:|---|---|
| 1 | 857878e | docs: add bitlesson workflow implementation plan |
| 2 | e81f3ab | Integrate project-level BitLesson workflow into RLCR loop |
| 3 | d5143d7 | Move BitLesson template into templates directory |
| 4 | 6618a53 | fix: enforce BitLesson delta consistency in stop hook |
| 5 | 4b5a1ff | Default allow empty bitlesson for Action:none and add strict toggle |
| 6 | dfbc525 | chore: track bitlesson.md and bump version to 1.10.14 |
| 7 | a4942a8 | docs: add trailing-pipe-split lesson to bitlesson.md |
| 8 | a0fb925 | gen-plan: default final plans to bilingual Chinese/English |

## F8: feat-bitlesson-extraction (rolled back)

No commits present in current git history.

## F9: feat-misc (4)

| Order | SHA | Subject |
|---:|---|---|
| 1 | b6de551 | Add local update_human command to refresh Claude humanize install from dev tree |
| 2 | 3e6be9c | chore: remove stale draft plan files |
| 3 | f34d79c | feat: add plan template investigation document (task10) |
| 4 | a92dc71 | feat: bump version to 1.10.13 for workflow improvements (task11) |

## Admin/Infra (Not Submitted as Feature PRs) (8)

| Order | SHA | Subject |
|---:|---|---|
| 1 | 4fc73c3 | Merge origin/main into main |
| 2 | 99d04d8 | merge: integrate origin/main (v1.11.0) skill system and bump to v1.11.1 |
| 3 | ccc0ef5 | docs: record lane pair max-rounds todo |
| 4 | 4d0cc7b | docs: add bilingual plan output todo |
| 5 | 8892c39 | docs: add dependency-graph dispatch backlog |
| 6 | 4410871 | docs: expand dependency-graph dispatch backlog |
| 7 | dbf6a6a | docs: add swarm-backend interface draft and PoC file checklist |
| 8 | 14544de | docs: assign codex owners for swarm backend PoC tasks |
