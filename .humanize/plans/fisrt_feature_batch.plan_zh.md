# F2 Feature 抽取：feat-gen-plan-convergence

## 语言格式
默认：仅英文。
当 `.humanize/config.json` 中 `chinese_plan=true` 时，会生成单独的 `_zh` 仅中文版本。
在两个文件中保持标识符（`AC-1`、task IDs、文件路径、API 名称、命令行 flags）不变。

## 目标描述

从本地 `main` 抽取 F2（`feat-gen-plan-convergence`）特性集，将其功能记录到独立分析文档
`docs/f2-gen-plan-convergence-analysis.md`，基于 `origin/main` 创建本地 feature 分支
`feat/gen-plan-convergence`，并为后续提交 PR 准备好 cherry-pick 的提交，但不向任何 remote
push。

F2 由 9 个提交组成（SHAs：`c283a92`、`9c0eef7`、`5156a05`、`002308a`、`8ba3a57`、
`437567b`、`3c8caf5`、`4a57429`、`821f225`），它们为 `gen-plan` 命令加入了 Claude-Codex
辩论与收敛工作流。其中的 revert 成对提交（`5156a05` + `002308a`）净效果为 0，通过
`cherry-pick -n` 方式处理。

## 验收标准

遵循 TDD 思路，每条标准都包含正向与反向测试，便于确定性验证。

- AC-1：分析文档存在于 `docs/f2-gen-plan-convergence-analysis.md`
  - 正向测试（预期 PASS）：
    - 指定路径存在该文件
    - 文件仅英文（不包含 CJK 字符）
    - 文件覆盖 F2 的全部 5 个子特性：(a) Claude-Codex 辩论流程，(b) Codex 优先的规划与收敛
      循环，(c) task-tag 路由（`coding`/`analyze`），(d) 收敛循环最多 3 轮，(e) `_zh` 输出且
      默认仅英文
    - 文件在 `feat/gen-plan-convergence` 上已提交
  - 反向测试（预期 FAIL）：
    - 缺少任一子特性的文件应在内容评审中失败
    - 含有 CJK 字符的文件违反项目规则
    - 文件未提交或缺失将同时导致 AC-5 与 AC-1 失败

- AC-2：本地存在 feature 分支 `feat/gen-plan-convergence`，且基于 `origin/main`
  - 正向测试（预期 PASS）：
    - `git branch --list feat/gen-plan-convergence` 返回该分支名
    - `git merge-base --is-ancestor 7e0c3ae feat/gen-plan-convergence` 以 0 退出
      （确认 base 固定为当前 `origin/main` HEAD）
  - 反向测试（预期 FAIL）：
    - 本地分支列表中不存在该分支
    - 分支基于本地 `main` 或错误的提交

- AC-3：从 `origin/main` 到 `feat/gen-plan-convergence` 的净 diff 是允许列表的子集
  - 允许列表：
    - `commands/gen-plan.md`
    - `prompt-template/plan/gen-plan-template.md`
    - `scripts/validate-gen-plan-io.sh`
    - `tests/test-gen-plan.sh`
    - `commands/start-rlcr-loop.md`
    - `hooks/loop-codex-stop-hook.sh`
    - `scripts/setup-rlcr-loop.sh`
    - `tests/run-all-tests.sh`
    - `tests/test-task-tag-routing.sh`
    - `.claude-plugin/plugin.json`
    - `.claude-plugin/marketplace.json`
    - `README.md`
    - `docs/f2-gen-plan-convergence-analysis.md`
  - 正向测试（预期 PASS）：
    - `git diff --stat origin/main...feat/gen-plan-convergence` 仅列出允许列表内的文件
    - `hooks/lib/loop-common.sh` 与 `tests/test-plan-type-routing.sh` 不出现
      （确认 revert pair 的净效应为 0）
  - 反向测试（预期 FAIL）：
    - diff 中出现任何允许列表之外的文件，说明泄露了无关改动
    - 出现 `hooks/lib/loop-common.sh` 表示 revert pair 未被正确处理

- AC-4：未执行任何 remote push（用户显式覆盖 `AGENTS.md` 的默认自动 push 行为）
  - 正向测试（预期 PASS）：
    - `git ls-remote zenus feat/gen-plan-convergence` 返回空（无远程 ref）
    - `git ls-remote origin feat/gen-plan-convergence` 返回空
  - 反向测试（预期 FAIL）：
    - 在 `zenus` 或 `origin` 任一 remote 上发现该分支 ref

- AC-5：所有操作完成后工作区干净
  - 正向测试（预期 PASS）：
    - 在 `feat/gen-plan-convergence` 上执行 `git status` 显示 "nothing to commit, working tree clean"
  - 反向测试（预期 FAIL）：
    - 仍残留与 F2 相关的未暂存改动或未跟踪文件

- AC-6：版本策略被明确延后决策
  - 正向测试（预期 PASS）：
    - `docs/f2-gen-plan-convergence-analysis.md` 注明：版本 bump 的对齐延后，等待上游维护者决策
      （对应 runbook 4.5）
    - `feat/gen-plan-convergence` 上的版本文件与 `origin/main` 一致（而非 F2 bump 后的值），因为
      cherry-pick 冲突通过接受 `origin/main` 版本解决
  - 反向测试（预期 FAIL）：
    - 版本文件彼此不一致，且没有显式文档说明

## 边界范围

边界范围定义了可接受的实现质量与取舍空间。

### 上界（最大可接受范围）

应用全部 9 个 SHA，并在 `feat/gen-plan-convergence` 上形成 2 个提交：一个提交包含经过整理的 F2
代码变更（版本冲突通过保留 `origin/main` 的值解决），另一个提交包含分析文档。分析文档提供逐提交
拆解，按子特性描述实现细节并引用相关测试用例。所有 `tests/test-gen-plan.sh` 用例通过。

### 下界（最小可接受范围）

通过 `cherry-pick -n` 应用全部 9 个 SHA；版本文件冲突通过接受 `origin/main` 的值解决；最终作为一个
合并后的代码提交。分析文档用简洁文字覆盖全部 5 个子特性。`tests/test-gen-plan.sh` 通过。diff 在允许列表内。

### 允许/禁止项

- 可用：`cherry-pick -n`（批量不提交）或逐个 SHA `cherry-pick`
- 可用：在 cherry-pick 期间用 `git checkout --ours` 解决版本文件冲突
- 可用：对任何空 pick 使用 `git cherry-pick --skip`（提交已在 base 中）
- 可用：抽取分支上形成 1 或 2 个提交
- 禁止：对任何 remote 执行 `git push`（`origin`、`zenus` 或其他）
- 禁止：对 `origin/main` 进行 force-push 或 rebase
- 禁止：在分析文档中出现 CJK 字符

> **关于确定性约束的说明**：不 push 要求、base commit（`7e0c3ae`）、分支名（`feat/gen-plan-convergence`）、
> 以及分析文档路径都是固定的。提交粒度可在 1–2 个提交范围内自由选择。

## 可行性提示与建议

> **注意**：本节仅用于参考与理解。它们是概念性建议，不是强制要求。

### 概念方案

```bash
# 1. Verify environment
git fetch origin
for sha in c283a92 9c0eef7 5156a05 002308a 8ba3a57 437567b 3c8caf5 4a57429 821f225; do
  git cat-file -e "${sha}^{commit}" || echo "MISSING $sha"
done

# 2. Create branch pinned to current origin/main
git switch -c feat/gen-plan-convergence 7e0c3ae

# 3. Cherry-pick all 9 SHAs with no-commit
git cherry-pick -n \
  c283a92 9c0eef7 5156a05 002308a 8ba3a57 437567b 3c8caf5 4a57429 821f225

# 4. Resolve version-file conflicts: keep origin/main values
# (If git stops with conflicts on plugin.json, marketplace.json, README.md)
git checkout --ours \
  .claude-plugin/plugin.json \
  .claude-plugin/marketplace.json \
  README.md
git add \
  .claude-plugin/plugin.json \
  .claude-plugin/marketplace.json \
  README.md

# 5. Handle empty picks if any
# git cherry-pick --skip  (for any SHAs that are already in base)

# 6. Verify non-empty result
if git diff --quiet && git diff --cached --quiet; then
  echo "Empty cherry-pick result. Stop and re-check SHA assignment."
  exit 1
fi

# 7. Curate and commit code changes
git add -p  # or add specific allowlisted files
git commit -m "feat: extract F2 gen-plan-convergence changes

Cherry-picked from SHAs: c283a92 9c0eef7 8ba3a57 437567b 3c8caf5 4a57429 821f225
Revert pair 5156a05+002308a included (net-zero; hooks/lib/loop-common.sh not in diff)
Version files kept at origin/main values; version bump deferred per runbook 4.5"

# 8. Write and commit analysis document
# ... write docs/f2-gen-plan-convergence-analysis.md ...
git add docs/f2-gen-plan-convergence-analysis.md
git commit -m "docs: add F2 gen-plan-convergence feature analysis"

# 9. Verify
git diff --stat origin/main...HEAD
./tests/test-gen-plan.sh
git status
```

### 相关参考

- `docs/feature-commit-map.md` - F2 的规范 SHA 列表（F2 小节，9 个提交）
- `docs/feature-pr-workflow.md` - 抽取 runbook（完整流程见 4.1–4.5）
- `commands/gen-plan.md` - F2 修改的主要文件（覆盖全部 5 个子特性）
- `prompt-template/plan/gen-plan-template.md` - 与 gen-plan.md 保持同步的模板
- `scripts/validate-gen-plan-io.sh` - 在提交 6（`437567b`）中修改了 IO 校验
- `tests/test-gen-plan.sh` - 主要验证套件（随 F2 提交逐步扩展）
- `tests/test-task-tag-routing.sh` - 在提交 5（`8ba3a57`）中新增，用于 tag 路由测试

## 依赖与顺序

### 里程碑

1. 里程碑 1：环境验证
   - Phase A：拉取上游（`git fetch origin`），验证 `origin/main` HEAD 为 `7e0c3ae`
   - Phase B：用 `git cat-file -e` 验证全部 9 个 F2 SHA 存在

2. 里程碑 2：分支创建与 cherry-pick
   - Phase A：从 `7e0c3ae` 创建 `feat/gen-plan-convergence`
   - Phase B：对全部 9 个 SHA 执行 `cherry-pick -n`；跳过任何空 pick
   - Phase C：通过接受 `origin/main` 的值解决版本文件冲突
   - Phase D：验证结果非空；整理并提交代码变更

3. 里程碑 3：分析文档
   - Phase A：分析净 diff，理解全部 5 个子特性
   - Phase B：编写 `docs/f2-gen-plan-convergence-analysis.md`（仅英文）
   - Phase C：将分析文档作为分支上的第二个提交

4. 里程碑 4：验证
   - Phase A：运行 `./tests/test-gen-plan.sh`
   - Phase B：验证 `git diff --stat origin/main...HEAD` 为允许列表子集
   - Phase C：确认 `git status` 干净，且该分支不存在任何远程 ref

里程碑 2 与里程碑 3 部分重叠：里程碑 3 的分析文档需要基于里程碑 2 Phase B 的 cherry-pick 暂存结果进行检查。
但分析文档的提交顺序在代码提交之后。

## 任务拆解

每个任务都恰好包含一个路由 tag：
- `coding`：由 Codex worker 实现（`/humanize:codex-worker`）
- `analyze`：通过 Codex analyzer 执行（`/humanize:ask-codex`）

| Task ID | 描述 | 目标 AC | Tag | 依赖 |
|---------|-------------|-----------|-----|------------|
| task1 | 拉取 origin；用 `git cat-file -e` 验证全部 9 个 F2 SHA 存在 | AC-2 | coding | - |
| task2 | 从 `origin/main` 的 `7e0c3ae` 创建 `feat/gen-plan-convergence` 分支 | AC-2 | coding | task1 |
| task3 | 对全部 9 个 SHA 执行 `cherry-pick -n`；用 `--ours` 解决版本文件冲突；跳过空 pick | AC-3 | coding | task2 |
| task4 | 通过 `add -p` 整理暂存变更；验证非空；提交代码变更（commit 1） | AC-3, AC-5 | coding | task3 |
| task5 | 分析净 diff；编写并提交 `docs/f2-gen-plan-convergence-analysis.md`（commit 2） | AC-1, AC-5, AC-6 | analyze | task4 |
| task6 | 在 feature 分支上运行 `./tests/test-gen-plan.sh` | AC-3 | coding | task4 |
| task7 | 验证 diff 为允许列表子集；确认版本延后策略已文档化 | AC-3, AC-6 | analyze | task4, task5 |
| task8 | 最终检查：工作区干净、未远程 push、分支存在且 base 正确 | AC-2, AC-4, AC-5 | coding | task5, task6, task7 |

## Codex 团队工作流

### Batch 1 - Planning Codex
- 输入：原始草稿 + 仓库上下文（feature-commit-map.md、feature-pr-workflow.md）
- 输出：风险图（RLCR loop 冲突——通过“无活跃状态”缓解；remote 命名不匹配——通过适配命令缓解；
  revert pair；版本 bump 冲突；upstream-main 缺失——通过直接使用 `origin/main` 缓解），缺失
  要求（输出位置、提交策略、版本策略、push 意图）

### Batch 2 - Implementation Codex Team
- 输入：本收敛后的计划 + 下方精简的实现交接摘要
- 输出：分支创建、cherry-pick 执行、冲突解决、分析文档、测试执行
- 交接摘要：
  - 范围：将 9 个 F2 SHA 抽取到 `feat/gen-plan-convergence`；编写分析文档；不 push
  - 关键约束：仅英文输出、不向任何 remote push、通过接受 `origin/main` 的值解决版本文件冲突、
    跳过空 pick
  - 高风险点：版本文件冲突（`.claude-plugin/plugin.json`、`.claude-plugin/marketplace.json`、
    `README.md`），因为 F2 将版本从 v1.10.x bump 到 v1.11.1 base；revert pair（通过
    `cherry-pick -n` 处理；`hooks/lib/loop-common.sh` 净效应为 0）
  - 必要验证：SHA 存在性检查、非空 patch 检查、diff 允许列表检查、`tests/test-gen-plan.sh` 通过、
    版本延后策略已文档化

### Batch 3 - Review Codex Team
- 输入：实现总结、变更文件、测试结果
- 输出：独立质量评审，验证 F2 完整性、未泄露无关文件、未远程 push、分析文档正确性

## Claude-Codex 讨论

### 共识
- `cherry-pick -n`（批量不提交）在存在 revert pair 的情况下是正确做法
- `origin/main` 的 `7e0c3ae` 是正确的 base（因为 `origin` = upstream `humania-org`）
- `docs/f2-gen-plan-convergence-analysis.md` 是分析文档的合适路径
- `tests/test-gen-plan.sh` 是主要验证命令（确认存在）
- 版本 bump 对齐延后（对应 runbook 4.5，版本策略 gate）
- 不 push 是用户对 `AGENTS.md` 默认自动 push 行为的显式覆盖

### 已解决分歧
- Push 策略 vs AGENTS.md：Codex 提出了冲突；通过注意到用户草稿明确写了 “don't push, just prepare locally”
  而解决——任务级指令覆盖 AGENTS.md 默认值。
- AC-3 允许列表缺少分析文档：Codex 指出缺口；Claude 将 `docs/f2-gen-plan-convergence-analysis.md`
  加入允许列表。
- 任务顺序（1 个提交 vs 文档创建）：Codex 指出不一致；Claude 明确 2 个提交（先代码后文档），并将
  task5 调整到 task4 之后。
- AC-3 语义：从“必须包含所有列出文件”改为“不出现允许列表之外的文件”（子集检查），以适配 revert pair
  的净效应文件。
- 冲突解决策略：Codex 要求明确策略；Claude 指定对版本文件使用 `git checkout --ours`
  （接受 `origin/main` 的值）。
- 空 pick 处理：Codex 要求显式处理；Claude 添加 `git cherry-pick --skip`，用于跳过 base 中已存在的提交。

## 收敛日志

- Round 1：Codex 提出了 push 策略冲突（AGENTS.md）、SHA 描述不充分、测试脚本不确定性、版本文件描述模糊、
  分析文档路径未定。Claude 解决了全部 5 项。
- Round 2：Codex 提出了 AC-3 允许列表遗漏分析文档、任务顺序不一致（1 个提交 vs 文档创建顺序）、AC-3
  “必需文件”语义过严。Claude 解决了全部 3 项（将文档加入允许列表、引入 2 提交方案、改为子集检查语义）。
- Round 3：Codex 提出了 cherry-pick 冲突解决（版本文件）与空 pick 处理。达到最大轮数。Claude 在最终计划中
  解决两项：版本冲突使用 `git checkout --ours`；空 pick 使用 `--skip`。
- 最终状态：`partially_converged`（达到最大 3 轮；Round 3 的问题已在最终计划中由 Claude 解决；无用户决策待定）

## 待用户决定

无。所有 Claude/Codex 分歧均已技术性解决。原始中文草稿中的歧义（“不用提交”=“不提交/不 push”）通过阅读完整句子解决：
“这次loop不用提交，只需要在本地做好提交的准备” = “不 push/提交这个 loop，只需要在本地把提交准备好”。
本地 git commit 是预期行为；不进行远程 push。

## 实现说明

### 代码风格要求
- 实现代码与注释中不得出现计划专用术语，例如 "AC-"、"Milestone"、"Step"、"Phase" 等工作流标记
- 这些术语仅用于计划文档，不应进入最终代码库
- 改用语义清晰、贴合领域的命名

---

## 原始设计草稿

<!-- 以下保留用户原始草稿以供参考，请勿修改。 -->

--- 原始设计草稿开始 ---

请你根据@/home/dyzhang/projects/pytorch_qemu/humanize/docs/feature-pr-workflow.md的内容，分析F2的功能和内容。
分析的结果要写成一个md文件.

然后你要在本地创建F2 的branch分支，把相关的功能摘到里面去。

这次loop不用提交，只需要在本地做好提交的准备。


--- 原始设计草稿结束 ---
