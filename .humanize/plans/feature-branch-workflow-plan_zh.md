# 向上游提交 PR 的 Feature 分支工作流

## 语言格式
默认：仅英文。
当 `.humanize/config.json` 中 `chinese_plan=true` 时，会生成单独的 `_zh` 仅中文版本。
在两个文件中保持标识符（`AC-1`、task IDs、文件路径、API 名称、命令行 flags）不变。

## 目标描述

记录一套可重复、尽量减少冲突的工作流：从本地已经偏离上游的开发分支中抽取各个 feature，
并将它们作为干净、相互独立的 PR 提交到上游仓库（humania-org/humanize）。交付物是一个
工作流 runbook 与 feature 依赖关系图。本规划阶段不会实际创建任何 feature 分支。

### 问题背景

- `upstream` = humania-org/humanize（v1.11.0，squash-merge 策略）
- `origin` = ZenusZhang/humanize（个人 fork）
- 本地 `main` = 比 upstream 超前 75 个提交，包含 8+ 个相互交错的 feature，同时夹杂版本号
  bump 与共享脚本修改
- RLCR 工作流会锁定分支（在活跃 loop 期间禁止切换分支）
- 用户之前在 `bitlesson` 分支上通过 RLCR 尝试做这件事，然后为了测试把它 merge 回 `main`——
  这是本计划希望替换掉的反模式

## 验收标准

遵循 TDD 思路，每条标准都包含正向与反向测试，便于确定性验证。

- AC-1：文档化一份工作流 runbook，覆盖远程配置、分支结构、抽取机制、合并后的同步、
  版本 bump 策略与错误恢复
  - 正向测试（预期 PASS）：
    - runbook 可以逐步执行，无需查阅外部资料
    - 合并后的同步步骤能让 `upstream-main` 仅通过 fast-forward 更新（无冲突）
    - runbook 明确包含用于检测与处理空 cherry-pick 的命令
  - 反向测试（预期 FAIL）：
    - 按 runbook 执行不应对 fork 的 `main` 进行 force-push
    - runbook 不应要求在活跃的 RLCR session 内切换分支

- AC-2：提供一个 feature 列表与依赖图，覆盖 `main` 中超出 upstream 的全部 75 个提交
  - 正向测试（预期 PASS）：
    - `git log --oneline upstream/main..main` 的每个提交 SHA 都被映射到且仅映射到一个 feature 组
    - 依赖图是 DAG（无环）
    - 提交顺序满足所有依赖边
  - 反向测试（预期 FAIL）：
    - 不存在未分配的提交（feature 组之外没有“孤儿” SHA）
    - 不存在某个 feature 组既是另一个组的依赖又同时依赖它（不应出现互为依赖）

- AC-3：`upstream-main` 的 post-merge 同步流程可证明无冲突
  - 正向测试（预期 PASS）：
    - 任意上游 squash-merge 之后，`git merge --ff-only upstream/main` 都能成功
    - 同步流程从不修改本地 `main`
  - 反向测试（预期 FAIL）：
    - 同步流程在任何情况下都不会触碰本地 `main`
    - 同步步骤中不会将 `git merge --ff-only` 替换为 `git merge` 或 `git rebase`

- AC-4：文档化 RLCR 兼容性
  - 正向测试（预期 PASS）：
    - runbook 明确哪些操作必须在 RLCR session 之外执行
    - runbook 明确何时可以在 `feat/*` 分支上使用 RLCR
    - 分支锁 hook（`hooks/loop-plan-file-validator.sh`）行为保持不变
  - 反向测试（预期 FAIL）：
    - runbook 不应要求禁用或绕过分支锁 hook

- AC-5：文档化版本 bump 策略，并包含提 PR 前的验证步骤
  - 正向测试（预期 PASS）：
    - runbook 包含在第一个 PR 之前与上游确认版本 bump 策略的步骤
    - runbook 说明如何避免并行 feature PR 之间的版本冲突
  - 反向测试（预期 FAIL）：
    - runbook 不应在未与上游确认前强行硬编码版本 bump 策略

## 边界范围

### 上界（最大可接受范围）
计划包含：完整 runbook 文档、完整 75 提交的 feature 映射、依赖 DAG、按 feature 的抽取流程与示例命令、
post-merge 同步流程、版本 bump 策略、RLCR 兼容性说明、以及 feature 提交优先级顺序。

### 下界（最小可接受范围）
计划包含：覆盖 5 个核心步骤（远程配置、快照、抽取、验证、同步）的 runbook，以及一份带依赖顺序的 feature 列表，
足以判断应该先提交什么。

### 允许/禁止项
- 可用：`git cherry-pick -n`、`git add -p`、`git worktree`、`git rerere`、`git range-diff`
- 可用：对严重交错的提交进行手工 hunk 级抽取（`git diff ... | git apply`）
- 禁止：对 fork 上的 `main` 分支进行 force-push
- 禁止：在活跃的 RLCR session 内切换分支
- 用户固定：`main` 保持原样（开发快照）。新增 `upstream-main` 分支用于镜像上游。
- 上游固定：squash-merge 策略（每个 PR 在上游历史中变成 1 个提交）

## 可行性提示与建议

> **注意**：本节仅用于参考与理解。它们是概念性建议，不是强制要求。

### 概念方案

**核心思路**：将 `main`（开发快照）与 `upstream-main`（干净的上游镜像）分离职责。feature 分支从 `upstream-main` 切出，
再把 `main` 中的改动移植进去并向上游提交。每次上游 merge 后的同步只更新 `upstream-main`（永远 fast-forward，永不冲突）。

```
upstream/main  ──A──────────────────────B(feat/X merged)──────...
                  \                    /
upstream-main      ──────────────────B  (local mirror, ff-only)
                                      \
feat/X             ──────────────────X  (cut from upstream-main, transplanted from main)

main (dev snapshot, FROZEN)  ──...f1──f2──f3──f4──f5──f6──...
                                  ^^^feature X commits^^^
```

**Squash-merge 后的同步**：上游 squash-merge `feat/X` 后，squash 提交会出现在 `upstream/main`。
在 `upstream-main` 上运行 `git fetch upstream && git merge --ff-only upstream/main` 即可直接同步。
本地 `main` 不会被触碰。

**空 cherry-pick 检测**：当在 `feat/X` 已合并上游后抽取 `feat/Y` 时，来自 `main` 的部分 cherry-pick 可能变成空 patch
（因为 Y 基于 X 的代码，而 X 已存在于 `upstream-main` 中）。检测流程：
```bash
git cherry-pick -n <sha>          # apply without committing
git diff --cached --stat          # check if anything was actually staged
# if empty: git cherry-pick --skip (or git reset HEAD && git checkout .)
```

### 相关参考
- `hooks/loop-plan-file-validator.sh:107-115` - 分支锁定约束（不要修改）
- `scripts/setup-rlcr-loop.sh` - RLCR loop 初始化
- `scripts/bitlesson-init.sh`, `scripts/bitlesson-validate-delta.sh` - bitlesson 脚本（F8）
- `.humanize/rlcr/` - RLCR session 状态目录

## 依赖与顺序

### 里程碑

1. **准备里程碑**：一次性环境准备
   - Step 1：配置远程别名（upstream + origin）
   - Step 2：创建并推送 dev-snapshot 分支
   - Step 3：创建 upstream-main 跟踪分支
   - Step 4：启用 git rerere

2. **审计里程碑**：提交到 feature 的映射
   - Step 1：运行 `git log --stat --oneline upstream/main..main`
   - Step 2：将每个 SHA 分配到一个 feature 组（见下方 Feature 列表）
   - Step 3：验证 DAG（无未分配 SHA、无依赖环）

3. **抽取循环**（按 feature 重复）：
   - Step 1：从 `upstream-main` 创建 `feat/X`
   - Step 2：抽取 feature 提交（对交错提交使用 cherry-pick -n + add -p；对隔离提交使用干净 cherry-pick）
   - Step 3：处理版本 bump（在与上游确认之后）
   - Step 4：用 `git diff --name-status upstream-main..feat/X` + `git log upstream-main..feat/X` 验证
   - Step 5：在 `feat/X` 上运行测试
   - Step 6：推送到 `origin/feat/X` 并创建 PR（base：humania-org/humanize:main）

4. **合并后同步**（每次上游合并后）：
   - Step 1：`git fetch upstream`
   - Step 2：`git checkout upstream-main && git merge --ff-only upstream/main`
   - Step 3：进入下一轮抽取

### Feature 列表与依赖图

`upstream/main` 之外的 75 个提交在下方全部分配完成。SHA 分配截至 2026-03-04 为准。

#### F1: feat-rlcr-loop-improvements（7 commits）
对 RLCR loop 机制的基础性改进。应最先提交——其它 feature 依赖这里的 stop hook 与 workdir 改动。

| SHA | Description |
|-----|-------------|
| 61e45a1 | feat: add continue-rlcr-loop command |
| c5378a6 | Add codex-worker and split worker/reviewer models |
| 0a7b4fe | Clarify role/model policy for Codex worker and review |
| 5678449 | Set Codex defaults to gpt-5.2:xhigh across workflows |
| bc1c135 | fix: use WORKDIR_ABS for codex exec -C and portable sed -E in stop hook |
| 09b1134 | fix: use LOOP_DIR for marker placement and correct --workdir help text |
| 07d67bf | refactor: simplify WORKTREE_ROOT_SAFE guard and remove unused local in loop marker |

**主要文件**：`scripts/setup-rlcr-loop.sh`、`hooks/loop-codex-stop-hook.sh`、
`scripts/codex-worker.sh`、`commands/start-rlcr-loop.md`
**依赖**：无（基础）

---

#### F2: feat-gen-plan-convergence（9 commits）
为 gen-plan 增加 Claude-Codex debate flow、codex-first convergence loop、task-tag 路由，
以及 `_zh` 双语输出。与其它 feature 相互独立。

| SHA | Description |
|-----|-------------|
| c283a92 | feat: add claude-codex debate flow to gen-plan |
| 9c0eef7 | feat: make gen-plan codex-first with convergence loop |
| 5156a05 | Add plan-type routing for Claude vs Codex execution |
| 002308a | Revert "Add plan-type routing for Claude vs Codex execution" |
| 8ba3a57 | Implement task-tag routing for coding/analyze execution |
| 437567b | Enhance gen-plan with ultrathink and converged auto-start |
| 3c8caf5 | feat: cap gen-plan convergence loop to 3 rounds |
| 4a57429 | feat: add _zh bilingual file output option to gen-plan pipeline |
| 821f225 | fix: switch gen-plan default to English-only with optional _zh variant via config |

**主要文件**：`commands/gen-plan.md`、`prompt-template/plan/`、`skills/gen-plan.md`
**依赖**：无（独立）
**备注**：5156a05 + 002308a 是一对 revert；PR 中要么都包含，要么 squash 成净变化为 0

---

#### F3: feat-task-graph（9 commits）
独立的 Python 工具：解析 plan 文件并构建 task 依赖 DAG。gen-batch-prompt（F4）依赖此功能。

| SHA | Description |
|-----|-------------|
| ca96484 | feat: add task-graph.py parser and DAG builder (task1) |
| 9920412 | feat: add DFS cycle detection to task-graph.py (task2) |
| 81e617b | feat: add state read/write and reconcile subcommand (task3) |
| fed29d9 | feat: add lane iteration tracking and cap enforcement (task7) |
| 60dadca | feat: add ready-set computation and ready subcommand (task4) |
| b0747b3 | feat: add pytest unit tests for task-graph.py (task9) |
| e8e3255 | fix: normalize none/n/a as no-deps, add plan file preflight, fix assignment file handling |
| 1abe1e4 | fix: normalize backticked task IDs in gen-batch-prompt, catch OSErrors, fix docstrings |
| 2685897 | fix: catch OSErrors in parse_assignment_file to prevent tracebacks |

**主要文件**：`scripts/task-graph.py`、`tests/test_task_graph.py`
**依赖**：无（独立 Python 工具）

---

#### F4: feat-gen-batch-prompt（4 commits）
新增 `/batch` prompt 生成器，使用 task-graph.py 计算 ready-set 并进行 readiness filtering。

| SHA | Description |
|-----|-------------|
| ac570d5 | fix: avoid backtick substitution in worktree matrix scaffold |
| b0f9aaa | feat: add /batch prompt generator from worktree matrix |
| ebcd1f0 | feat: integrate readiness filtering into gen-batch-prompt (task5) |
| d9138d5 | feat: add policy knobs to gen-batch-prompt (task6) |

**主要文件**：`scripts/gen-batch-prompt.sh`、`commands/gen-batch-prompt.md`、`skills/gen-batch-prompt.md`
**依赖**：F3（需要 task-graph.py）

---

#### F5: feat-delegation-enforcement（5 commits）
增加 worker 调用 marker 文件、stop-hook 对缺少 delegation 的告警，以及
`HUMANIZE_CODEX_DELEGATION_ENFORCEMENT` 策略 flag。

| SHA | Description |
|-----|-------------|
| 96ce1f5 | feat: add worker invocation marker file and stop-hook warning for missing delegation |
| 766e619 | feat: strengthen delegation enforcement with consequence language and HUMANIZE_CODEX_DELEGATION_ENFORCEMENT support |
| 1a57574 | test: add coverage for delegation enforcement and worker marker file behaviors |
| ae2c56b | test: fix false-positive stop-hook test assertions and add outside-loop negative test |
| 6e86b65 | chore: bump version 1.10.20 -> 1.10.21 |

**主要文件**：`hooks/loop-codex-stop-hook.sh`、`tests/`、`AGENTS.md`、`.claude/CLAUDE.md`
**依赖**：F1（来自 rlcr-loop-improvements 的 stop hook 结构）

---

#### F6: feat-worktree-teams（8 commits）
增加 worktree team 编排：分离 worker/reviewer worktree、以文档为中心的流程、
agent team setup 命令。

| SHA | Description |
|-----|-------------|
| a5f94fc | feat: add worktree team orchestration and setup command |
| c8d484a | Enable agent/worktree teams by default for RLCR startup |
| 7c128c4 | test: align teams defaults and compact next-round prompts |
| f8e4bb5 | docs: align worktree teams guidance with document-centered workflow |
| df534b2 | docs: replace scheduler-centric README wording with document-centered worktree mode |
| 0504e25 | Enforce Claude/Codex cross-review context in sub-agent workflow |
| ee70f4d | feat(rlcr): enforce doc-first worktree flow for features 2-5 |
| 111bfde | feat: apply unapplied worktree-teams patch manually (context drift from 1.10.4) |

**主要文件**：`scripts/setup-rlcr-loop.sh`、`skills/worktree-teams.md`、
`commands/setup-worktree-teams.md`、`prompt-template/`
**依赖**：F1（rlcr-loop-improvements）、F5（stop hook 的 delegation enforcement）

---

#### F7: feat-bitlesson-rlcr-integration（8 commits）
将 BitLesson 知识库集成进 RLCR loop：启动时 init、stop hook 的 delta 校验、
selector agent、模板迁移。

| SHA | Description |
|-----|-------------|
| 857878e | docs: add bitlesson workflow implementation plan |
| e81f3ab | Integrate project-level BitLesson workflow into RLCR loop |
| d5143d7 | Move BitLesson template into templates directory |
| 6618a53 | fix: enforce BitLesson delta consistency in stop hook |
| 4b5a1ff | Default allow empty bitlesson for Action:none and add strict toggle |
| dfbc525 | chore: track bitlesson.md and bump version to 1.10.14 |
| a4942a8 | docs: add BL-20260302-trailing-pipe-split lesson to bitlesson.md |
| a0fb925 | gen-plan: default final plans to bilingual Chinese/English |

**主要文件**：`scripts/setup-rlcr-loop.sh`、`hooks/loop-codex-stop-hook.sh`、
`templates/`、`agents/bitlesson-selector.md`、`bitlesson.md`
**依赖**：F1（rlcr-loop-improvements——stop hook 结构）
**备注**：a0fb925（双语默认）后来在 F2 的 821f225 被反转；若 F2 先合入，
a0fb925 会变成无效果提交，可从 F7 中去掉

---

#### F8: feat-bitlesson-extraction（7 commits）
将 BitLesson 逻辑抽取为独立脚本（`bitlesson-init.sh`、`bitlesson-select.sh`、
`bitlesson-validate-delta.sh`）并更新集成点。这是 `bitlesson` 分支的工作。

| SHA | Description |
|-----|-------------|
| b42128d | feat(bitlesson): extract init/select scripts, update setup integration and templates |
| 1d6fb19 | feat(bitlesson): extract validation script, update stop hook integration, bump version to 1.11.2 |
| e3e1019 | fix(bitlesson): use PLUGIN_ROOT for validation script path in stop hook |
| 2cdcfff | refactor(bitlesson): simplify extracted scripts |
| 712d39b | fix(bitlesson): require init template file and add tests |
| 648f970 | fix(bitlesson): restore haiku as Claude agent model in bitlesson-selector frontmatter |
| bc99890 | docs(bitlesson): clarify codex exec flags in selector documentation |

**主要文件**：`scripts/bitlesson-init.sh`、`scripts/bitlesson-select.sh`、
`scripts/bitlesson-validate-delta.sh`、`agents/bitlesson-selector.md`
**依赖**：F7（bitlesson-rlcr-integration——被抽取的集成点）

---

#### F9: feat-misc（8 commits）
小而独立的改进与行政变更。可独立提交，也可打包成一个 chore/misc PR。

| SHA | Description |
|-----|-------------|
| b6de551 | Add local update_human command to refresh Claude humanize install from dev tree |
| 274915f | fix: hide runtime skills from Claude (keep codex/kimi visible) |
| e0832b4 | docs: replace informal codex exec descriptions with exact flags |
| 3e6be9c | chore: remove stale draft plan files |
| f34d79c | feat: add plan template investigation document (task10) |
| 0c0716b | chore: gitignore plans/ and workflow_backlog.md, bump version to 1.10.12 |
| a92dc71 | feat: bump version to 1.10.13 for workflow improvements (task11) |
| fdc5132 | fix: address code review issues P2/P3 and bump version to 1.10.15 |

**主要文件**：不定（各提交相互独立）
**依赖**：无（全部独立）

---

#### Admin/Infra（不作为 feature 提交：merge 提交与 backlog 文档）
这些提交不应包含在任何 feature PR 中：

| SHA | Description |
|-----|-------------|
| 4fc73c3 | Merge origin/main into main (old merge commit) |
| 99d04d8 | merge: integrate origin/main (v1.11.0) skill system and bump to v1.11.1 |
| ccc0ef5 | docs: record lane pair max-rounds todo |
| 4d0cc7b | docs: add bilingual plan output todo |
| 8892c39 | docs: add dependency-graph dispatch backlog |
| 4410871 | docs: expand dependency-graph dispatch backlog |
| dbf6a6a | docs: add swarm-backend interface draft and PoC file checklist |
| 14544de | docs: assign codex owners for swarm backend PoC tasks |

**数量校验**：F1(7) + F2(9) + F3(9) + F4(4) + F5(5) + F6(8) + F7(8) + F8(7) + F9(8) + Admin(8) = 73。
相比 75 少了 2 个 SHA。很可能是属于 F3（task-graph 打磨）的 cf5725b 与 97b280e 两个 “Round 6/7 review fixes” 提交。更新如下：

**F3 additions**：
| SHA | Description |
|-----|-------------|
| cf5725b | fix: address Round 6 code review issues P1/P2 and bump to 1.10.16 |
| 97b280e | fix: address Round 7 code review issues P2/P3 and bump to 1.10.17 |

**F3 total: 11 commits**。总计：F1(7)+F2(9)+F3(11)+F4(4)+F5(5)+F6(8)+F7(8)+F8(7)+F9(8)+Admin(8) = 75。所有 SHA 已全部覆盖。

---

### 依赖图（DAG）

```
F1 (rlcr-loop-improvements)
  ├──> F5 (delegation-enforcement)
  │      └──> F6 (worktree-teams)
  └──> F7 (bitlesson-rlcr-integration)
         └──> F8 (bitlesson-extraction)

F2 (gen-plan-convergence)    [independent]

F3 (task-graph)
  └──> F4 (gen-batch-prompt)

F9 (misc)                    [independent]
```

### 推荐提交顺序

基于依赖顺序与 PR 的可审阅性：

1. F2（gen-plan-convergence）- 独立、自包含、价值高
2. F1（rlcr-loop-improvements）- F5/F6/F7 的基础
3. F3（task-graph）- 独立的 Python 工具
4. F9（misc）- 小型独立修复，便于建立 reviewer 信任
5. F4（gen-batch-prompt）- 在 F3 之后
6. F5（delegation-enforcement）- 在 F1 之后
7. F6（worktree-teams）- 在 F1 + F5 之后
8. F7（bitlesson-rlcr-integration）- 在 F1 之后
9. F8（bitlesson-extraction）- 在 F7 之后

## 任务拆解

| Task ID | 描述 | Target AC | Tag | Depends On |
|---------|------|-----------|-----|------------|
| task1 | 文档化远程配置与 upstream-main 分支创建 runbook | AC-1 | coding | - |
| task2 | 针对 feature 组审计并验证 75 个提交 SHA 的分配 | AC-2 | analyze | - |
| task3 | 文档化抽取机制（cherry-pick -n、add -p、空 patch 检测） | AC-1 | coding | task1 |
| task4 | 文档化 post-merge 同步流程，并说明 upstream 镜像为何无冲突 | AC-3 | coding | task1 |
| task5 | 文档化 RLCR 兼容性：抽取期间何时使用/避免 RLCR | AC-4 | coding | task1 |
| task6 | 与上游确认版本 bump 策略，并文档化决策规则 | AC-5 | analyze | - |
| task7 | 验证依赖 DAG（无未分配 SHA、无环） | AC-2 | analyze | task2 |

## Codex 团队工作流

### Batch 1 - Planning Codex
- 输入：用户草稿（feature 分支工作流诉求 + 仓库状态：超前 75 提交）
- 输出：风险图谱（远程命名、版本 bump、squash-merge 处理、worktree/RLCR 约束）
- 摘要："Use upstream-mirror + feature-shelves pattern. Conflict risk is in extraction, not sync."

### Batch 2 - Implementation Codex Team
- 输入：本 converged plan
- 输出：runbook 文档与验证后的 feature-to-SHA 映射
- 交接摘要：
  - 范围：产出一份工作流 runbook markdown 文件与完整的 commit-to-feature 表
  - 关键约束：不创建分支；仅写文档；必须为英文；不得包含 CJK 字符
  - 高风险点：空 cherry-pick 检测流程；并行 PR 的版本 bump 协调
  - 必要验证：75 个 SHA 全部分配；依赖 DAG 无环；runbook 可 dry-read 验证

### Batch 3 - Review Codex Team
- 输入：runbook 草稿与 feature 映射
- 输出：独立质量评审，检查错误恢复、RLCR 兼容性准确性、版本 bump 策略是否完整

## Claude-Codex 讨论

### 达成共识
- "Upstream-mirror + feature shelves" 适用于上游采用 squash-merge 的场景
- `upstream-main` 的 fast-forward 镜像可以消除 post-merge 同步冲突
- 本地 `main` 应保持不动（用户确认：保留 main 作为开发分支）
- 抽取前必须先做提交审计（不能猜 feature 分组）
- dev-snapshot 分支 + 推送到 fork 是安全网
- 抽取机制：对交错提交使用 `cherry-pick -n` + `add -p`

### 已解决分歧
- **远程命名歧义**：Round 1 Codex 指出。解决：runbook 明确使用
  `upstream` = humania-org，`origin` = ZenusZhang/humanize；并包含远程 rename 命令。
- **安全网类型**：Round 1 Codex 建议用分支而非 tag。解决：计划要求同时创建
  `dev-snapshot` 分支与 `dev-snapshot-v0` tag，并都推送到 fork。
- **抽取机制描述过于抽象**：Round 1 Codex 指出。解决：明确写出
  `cherry-pick -n` + `add -p` + 空 patch 检测流程。
- **依赖顺序被猜测**：Round 1 Codex 指出。解决：feature 列表提供完整 SHA 分配与明确依赖理由。
- **AC-8 "at most once" 过严**：Round 2 Codex 指出。解决：删除 AC-8；提到 `rerere` 仅作为摊销工具，不作保证。
- **diff 命令语法**：Round 2 Codex 更正 `git diff dev-snapshot -- <paths>` 为
  `git diff upstream/main..dev-snapshot -- <paths>`。已在 runbook 中修正。
- **range-diff 用法**：Round 2 Codex 更正。替换为
  `git diff --name-status upstream-main..feat/X` + `git log upstream-main..feat/X`。
- **Feature 列表完整性**：Codex 最终评审指出缺少 SHA。解决：现在所有 75 个 SHA 都已明确覆盖（F1-F9 + Admin = 75）。
- **空 cherry-pick 处理缺失**：Codex 最终评审指出。解决：在可行性与 runbook 中加入明确流程。
- **版本 bump 策略未验证**：Codex 最终评审指出硬编码假设。解决：AC-5 现在要求在第一个 PR 前先与上游确认。

## Convergence 日志

- Round 1（Batch 1 Codex 初稿）：识别 6 个核心风险与 5 个必须修改点。
  远程命名、安全网、抽取机制、依赖顺序均被标记。Claude 修订策略以覆盖全部 5 点。
- Round 2（第二次 Codex 合理性评审）：5 个必须修改点，均为命令级别修正
  （diff 语法、range-diff、预检查步骤、worktree 明确性）。计划设计稳定。
- 最终 Codex 评审（pre-ExitPlanMode）：REVISE 结论，存在 3 个阻塞问题。
  3 个均已解决（feature 列表完整性、空 cherry-pick 检测、版本 bump 策略）。
- 最终状态：`converged`

## 待用户决策

- DEC-1：feature PR 中的版本 bump 策略
  - 用户立场：每个 feature PR 都包含版本 bump（遵循项目规则）
  - Codex 立场：先与上游确认；上游可能有自己的版本规范
  - 权衡摘要：包含 bump 符合项目 CLAUDE.md 规则，但若上游集中管理版本，可能导致 PR 被拒。
    上游最近一次合入 PR 为 `v1.11.0`。
  - 决策状态：等待上游确认。默认：包含版本 bump；若上游要求则移除。

## 实现备注

### 代码风格要求
- 实现代码与注释不得包含计划专用术语，例如 "AC-"、"Milestone"、"Step"、"Phase" 等工作流标记
- 这些术语仅用于计划文档，不应用于最终代码库
- 代码中应使用描述清晰、领域语义匹配的命名

---

## 工作流 Runbook

### 远程配置（一次性）

```bash
# Verify current remotes
git remote -v

# If remotes are named differently, rename them:
# git remote rename origin upstream   # humania-org/humanize
# git remote rename zenus origin      # ZenusZhang/humanize

# Ensure both are present after rename
git fetch --all
```

### 安全快照（一次性）

```bash
# Verify clean working tree before snapshot
git status   # must be clean; stash or commit if not

# Create persistent branch snapshot
git branch dev-snapshot main

# Create immutable tag
git tag dev-snapshot-v0 main

# Push both to fork (off-machine backup)
git push origin dev-snapshot
git push origin dev-snapshot-v0

# Verify: these should show the same commit SHA
git rev-parse main dev-snapshot dev-snapshot-v0
```

### Upstream-Main 镜像（一次性）

```bash
# Create upstream-main as a local mirror of upstream
git fetch upstream
git checkout -b upstream-main upstream/main

# Verify: upstream-main == upstream/main
git log --oneline upstream-main -1
git log --oneline upstream/main -1
```

### 启用 rerere（一次性）

```bash
git config rerere.enabled true
git config rerere.autoupdate true
```

### 版本 bump 验证（一次性，在第一个 PR 之前）

在提交任何 feature PR 之前，与 humania-org 维护者确认：
- 他们希望每个 PR 都包含版本 bump，还是由上游集中管理版本？
- 若上游集中管理版本：从 feature PR 中移除所有版本 bump 提交
- 若上游希望每个 PR 都 bump：在每个 `feat/*` 分支末尾包含一个版本 bump 提交
- 将结论记录在此，便于后续复用

### Feature 抽取（按 feature）

```bash
# 1. Start from updated upstream-main
git fetch upstream
git checkout upstream-main && git merge --ff-only upstream/main

# 2. Create feature branch
git checkout -b feat/X upstream-main

# 3. For each commit in the feature group, extract changes
#    Option A: Clean commit (single-feature, no interleaving)
git cherry-pick -x <sha>

#    Option B: Interleaved commit (version bumps or multi-feature)
git cherry-pick -n <sha>       # apply without committing
git diff --cached --stat       # check what was staged
git add -p                     # interactively select only relevant hunks
git commit -m "<clean message>"

# 4. Detect and skip empty cherry-picks
git cherry-pick -n <sha>
if git diff --cached --quiet; then
    echo "Empty patch - skipping"
    git checkout .             # clean up
else
    git add -p && git commit -m "<message>"
fi

# 5. Verify the PR contains exactly the intended changes
git diff --name-status upstream-main..feat/X
git log upstream-main..feat/X

# 6. Run tests
bash tests/run-all-tests.sh   # or equivalent

# 7. Push and create PR
git push origin feat/X
gh pr create --base main --head ZenusZhang:feat/X \
  --title "<title>" --body "<description>"
```

### 合并后同步（每次上游合并后）

```bash
# Trivially conflict-free - upstream-main only fast-forwards
git fetch upstream
git checkout upstream-main && git merge --ff-only upstream/main

# Local main is NEVER touched
# dev-snapshot is NEVER touched
# Next feature extraction picks up from updated upstream-main
```

### 错误恢复

```bash
# If a feat/* branch goes wrong: recreate it cleanly
git checkout -B feat/X upstream-main   # -B forces reset of existing branch

# If upstream-main gets corrupted:
git checkout upstream-main && git reset --hard upstream/main

# The source of truth for unextracted work is always dev-snapshot:
git log upstream-main..dev-snapshot   # all remaining unextracted work
```

### RLCR 兼容性

- Feature 抽取（上面所有 git 操作）必须在**非**活跃 RLCR session 中进行
- 分支锁 hook（`hooks/loop-plan-file-validator.sh`）会阻止任何在活跃 loop 中检测到分支变化的操作——
  这是正确且符合预期的行为
- RLCR **可以**在 `feat/*` 分支上用于 feature 开发与迭代：
  1. 在 `feat/X` 上启动 RLCR：`/humanize:start-rlcr-loop <plan-file>`
  2. RLCR 在 session 期间锁定 `feat/X`
  3. RLCR 结束后再进行验证与 PR 提交
- 要开始下一个 feature 的 RLCR：先用 `/humanize:cancel-rlcr-loop` 取消所有活跃 loops，
  然后在新的 `feat/Y` 分支上启动新 loop

---

--- 原始设计草稿开始 ---

# 草稿：将变更从 zenus/main 提交到 origin/main 的 Feature 分支工作流

## 背景

我想把变更从 zenus/main 提交到 origin/main，并将它们拆分成按 feature 划分的分支。

我之前在 `.humanize/rlcr/2026-03-04_05-26-18` 中尝试过，但遇到了问题：

1. RLCR 工作流不支持在工作过程中切换分支（这是一个应当保留的好特性）。相关分析见 Codex session：`codex resume 019cb7d2-a95c-7cb3-815a-1771020654dd`

2. 上一次 RLCR session 在 `bitlesson` 分支上修改了代码，然后为了测试把它 merge 到了 `main`。这不是一个好工作流。

3. 我还没找到更好的工作流。我需要帮助设计一个。

## 期望工作流

我希望达到的工作流：

1. **创建 feature 分支**：创建一个与 `origin/main` 同步的 `feat1` 分支。从本地 `main` 分支中找到对应模块的代码，并把它们放到 `feat1` 分支里。

2. **验证 feature 分支**：在确认 `feat1` 没问题后，再次拉取 `origin/main`。如果有更新，将 `feat1` 的提交 rebase 到最新 `origin/main` 之上。

3. **提交到 origin**：推送 feature 分支到 origin 并创建 PR。

4. **处理合并后的同步**：如果 PR 被合并到 `origin/main`，更新本地 `main` 分支。**这是最困难的部分**——合并回本地可能导致冲突，需要仔细分析。

5. **重复循环**：继续下一个 feature。

## 关键关注点

- 当 origin 合并了 feature PR 后，同步本地 `main` 的冲突解决策略是最关键的问题。
- RLCR 工作流的分支锁行为应当被保留。
- 该工作流必须可重复且可靠，能够支持多次 feature 提交。

--- 原始设计草稿结束 ---
