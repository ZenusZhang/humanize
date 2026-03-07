# 当前工作区 + `feat/rlcr-loop-improvements` 相比 `origin/main` 的差异说明

## 1. 对比范围

本文档比较的是两部分内容相对于 `origin/main` 的差异：

1. **当前工作区状态**：当前 `main` 分支的已提交历史 + 当前未提交修改。
2. **`feat/rlcr-loop-improvements` 分支**：单独抽出来看的 RLCR Loop 改进特性集。

> 结论先行：
>
> - 当前工作区相对 `origin/main` 不是一个“纯增量超集”，而是**大幅领先 + 部分分叉**。
> - `feat/rlcr-loop-improvements` 代表的是一个比较清晰的 **F1 / RLCR Loop 核心能力增强包**。
> - 当前未提交修改本身的“feature”比较集中，核心是 **把 worker / analyzer / reviewer 的默认 Codex 模型统一到 `gpt-5.4:xhigh`，并同步文档、提示词、技能和测试**。

## 2. 基线快照

### 2.1 参考提交

- `origin/main`: `a19fcf1` - `Add dev branch install option for experimental features`
- 当前 `main` HEAD: `dbf5f16` - `docs: add _zh translation for fisrt_feature_batch plan`
- `feat/rlcr-loop-improvements`: `e5bc7a7` - `refactor: simplify WORKTREE_ROOT_SAFE guard and remove unused local in loop marker`

### 2.2 分叉关系

- 当前 `main` 相对 `origin/main`：**79 个本地提交 / 10 个 upstream 提交分叉**
- `feat/rlcr-loop-improvements` 相对 `origin/main`：**6 个本地提交 / 3 个 upstream 提交分叉**

### 2.3 差异规模（按当前实际工作区统计）

- 当前工作区 vs `origin/main`：**80 个文件改动，`+11310 / -865`**
- `feat/rlcr-loop-improvements` vs `origin/main`：**43 个文件改动，`+2476 / -103`**
- 当前未提交修改 vs 当前 `HEAD`：**42 个文件改动，`+121 / -137`**

## 3. 总体差异：当前工作区相比 `origin/main` 多了哪些 feature

结合现有提交映射文档（`docs/feature-commit-map_zh.md`）和当前分支状态，当前工作区相对 `origin/main` 可以概括为以下几组能力增强：

| Feature 组 | 核心能力 | 价值 |
|---|---|---|
| F1 `feat-rlcr-loop-improvements` | RLCR Loop 连续执行、Codex worker 拆分、角色/模型策略梳理 | 让 RLCR 主循环更可持续、更清晰、更稳定 |
| F2 `feat-gen-plan-convergence` | `gen-plan` 的辩论式生成、收敛循环、任务路由标签 | 让计划生成从“一次性产出”升级为“可收敛迭代” |
| F3 `feat-task-graph` | `task-graph.py` DAG、循环检测、ready-set、reconcile | 让任务依赖和可执行性具备机器可读基础 |
| F4 `feat-gen-batch-prompt` | 从 worktree matrix 生成 batch prompt，并接入 readiness 过滤 | 支撑并行任务分发 |
| F5 `feat-delegation-enforcement` | worker 调用标记、stop hook 检查、委托约束强化 | 防止 leader 自己下场写代码，强化流程纪律 |
| F6 `feat-worktree-teams` | worktree team 编排、setup 命令、doc-first 多工协作 | 支撑多人/多 worktree 并行执行 |
| F7 `feat-bitlesson-rlcr-integration` | BitLesson 模板、选择器、delta 校验、loop 集成 | 把经验回流纳入 RLCR 闭环 |
| F9 `feat-misc` | 本地安装更新、计划模板研究、配套文档 | 提升可维护性和本地开发体验 |

### 3.1 F1: `feat/rlcr-loop-improvements`

这是当前请求里最明确的一组 feature，核心能力包括：

1. **新增 `/humanize:continue-rlcr-loop` 命令**
   - 支持 RLCR 会话中断后继续执行。
   - 让 loop 从“单次启动”变成“可恢复流程”。

2. **新增 `/humanize:codex-worker` 与独立 worker 脚本**
   - 把实现执行器从泛化描述变成明确入口。
   - worker / analyzer / reviewer 的职责边界更清晰。

3. **引入任务标签路由的默认执行语义**
   - `coding` → `codex-worker`
   - `analyze` → `ask-codex`
   - 这让计划里的 task tag 真正变成可执行调度信息。

4. **明确 Codex worker / analyzer / reviewer 的角色与模型策略**
   - 相关提示词、命令文档、skill 文档都进行了同步。
   - 降低调用者理解成本，减少提示不一致。

5. **修复 loop 执行中的目录/路径问题**
   - 用 `WORKDIR_ABS` 传给 `codex exec -C`
   - 用 `LOOP_DIR` 放置 marker
   - 修正 `--workdir` 帮助文本
   - 提升 hook 与 worker 在不同运行目录下的稳定性。

6. **简化路径安全判断和 loop marker 逻辑**
   - 清理无用局部变量。
   - 减少 guard 逻辑复杂度。

### 3.2 F2: `feat-gen-plan-convergence`

这组 feature 把 `gen-plan` 从“静态计划生成器”升级成“带收敛机制的计划生成流程”：

- 引入 Claude / Codex debate flow
- 让 `gen-plan` 变成 codex-first 的收敛式循环
- 为任务添加 `coding` / `analyze` 路由标签
- 增加 ultrathink / converged auto-start 等策略
- 支持 `_zh` 变体输出，并进一步收敛到英文默认、中文可选

### 3.3 F3 + F4: 任务图与并行分发基础设施

这两组 feature 共同补上了“任务依赖建模 + 批量分发”能力：

- `scripts/task-graph.py` 提供 DAG 构建、循环检测、状态读写、reconcile、ready-set 计算
- `gen-batch-prompt` 可以根据 worktree matrix 和 readiness 结果生成可执行批量任务
- 这使得并行执行不再只靠人工拆分，而具备程序化支撑

### 3.4 F5 + F6: 委托纪律与 worktree 团队协作

这是“RLCR 从单人串行向多 lane 协作”演进的关键层：

- 用 marker file 和 stop hook 警告来检查是否真的委托给 worker
- 提供更强的 delegation enforcement 语义与环境开关
- 新增 worktree teams 命令、脚本、prompt template、skill
- 强化 doc-first / cross-review / ownership boundary 等团队执行规范

### 3.5 F7: BitLesson 闭环集成

这一组 feature 主要解决“经验如何沉淀并反馈回流程”的问题：

- 引入 `bitlesson.md` / `templates/bitlesson.md`
- 增加 `bitlesson-select.sh` 和 `bitlesson-validate-delta.sh`
- 在 stop hook / loop 中接入 BitLesson delta 校验
- 让每轮执行产生的经验可以变成显式知识资产

### 3.6 F9: 杂项但有价值的增强

- `update_human` / `scripts/update_human.sh`：提升本地安装刷新体验
- `docs/feature-commit-map*.md` / `docs/feature-pr-workflow*.md`：为功能抽取和 PR 工作流提供操作手册
- `docs/plan-template-investigation.md`：补充计划模板研究背景

## 4. 单独看 `feat/rlcr-loop-improvements`：相比 `origin/main` 到底新增了什么

当前分支上可见的 6 个提交（相对 `origin/main`）是：

1. `3c70584` `feat: add continue-rlcr-loop command`
2. `c99e6ea` `feat: add codex-worker and split worker/reviewer models`
3. `f68a750` `feat: clarify role/model policy for Codex worker and review`
4. `6d65dab` `fix: use WORKDIR_ABS for codex exec -C and portable sed -E in stop hook`
5. `87a0605` `fix: use LOOP_DIR for marker placement and correct --workdir help text`
6. `e5bc7a7` `refactor: simplify WORKTREE_ROOT_SAFE guard and remove unused local in loop marker`

### 4.1 这个分支的 feature 定位

如果只看这一支，它本质上是在做三件事：

- **补齐 RLCR 的可恢复执行入口**：continue loop
- **把执行角色拆清楚**：worker / analyzer / reviewer
- **把 loop 的运行时细节修稳**：路径、marker、帮助文本、安全 guard

### 4.2 它与当前 `main` 的关系

`feat/rlcr-loop-improvements` 并不是一组与当前 `main` 完全独立的新 feature；相反，它对应的是当前本地历史里的 **F1 功能桶**。

也就是说：

- 如果你的目的是“抽出一个最小、可单独提 PR 的 RLCR 核心改进包”，这个分支是合适的。
- 如果你的目的是“理解当前整体改了哪些能力”，那它只是当前总变更中的一个子集，而不是全部。

## 5. 当前未提交修改都有哪些 feature

当前未提交修改的 feature 非常集中，基本可以归成 **一个主 feature + 一组同步性改动**。

### 5.1 主 feature：统一默认 Codex 模型到 `gpt-5.4:xhigh`

当前未提交修改最核心的变化是：

- 把 worker 默认模型从 `gpt-5.3-codex:xhigh` 改成 `gpt-5.4:xhigh`
- 把 analyzer / reviewer 默认模型从 `gpt-5.2:xhigh` 改成 `gpt-5.4:xhigh`
- 去掉 plugin runtime / skill runtime 之间的 worker 默认模型分叉逻辑
- 在 `hooks/lib/loop-common.sh` 中收敛为统一默认值：
  - `DEFAULT_CODEX_MODEL=gpt-5.4`
  - `DEFAULT_CODEX_WORKER_MODEL=gpt-5.4`

这意味着：

- **角色还在，但默认模型不再分裂**
- **运行时判定逻辑更简单**
- **文档、提示词、skill、脚本帮助文本、测试 fixture 都围绕同一默认值同步**

### 5.2 同步性改动

围绕这个主 feature，当前未提交修改还做了几类同步：

1. **元数据与版本描述同步**
   - `.claude-plugin/plugin.json`
   - `.claude-plugin/marketplace.json`
   - `README.md`
   - 版本号从 `1.11.3` 更新到 `1.11.4`

2. **命令帮助文本同步**
   - `scripts/ask-codex.sh`
   - `scripts/codex-worker.sh`
   - `scripts/setup-pr-loop.sh`
   - `scripts/setup-rlcr-loop.sh`
   - `commands/*.md`

3. **提示词与 skill 文档同步**
   - `prompt-template/claude/*`
   - `prompt-template/codex/*`
   - `prompt-template/plan/*`
   - `skills/ask-codex/SKILL.md`
   - `skills/codex-worker/SKILL.md`
   - `skills/humanize*.md`

4. **测试样例同步**
   - 多个 shell test 中的默认 `codex_model` fixture 改为 `gpt-5.4`
   - skill monitor 测试的默认模型字符串同步为 `gpt-5.4`

### 5.3 这些未提交修改相对 `origin/main` 的定位

这一点很重要：

**这些未提交修改大部分不是“额外新增一个全新 feature 分支”，而是在当前本地分叉历史上，进一步把模型默认值统一到 `gpt-5.4`。**

由于 `origin/main` 本身已经包含 `Upgrade default model to gpt-5.4 (v1.14.0)`，所以从“纯粹新增功能”的角度看：

- 当前未提交修改更多是在**追平 / 对齐 / 收敛**模型默认值和文档描述
- 而不是在 `origin/main` 之上再引入一条完全独立的新工作流

## 6. 与 `origin/main` 的关键分歧点

为了避免误判，必须明确：当前工作区不是 `origin/main` 的严格超集。

### 6.1 当前工作区新增很多 feature

这部分主要是上文列出的 F1 / F2 / F3 / F4 / F5 / F6 / F7 / F9。

### 6.2 但当前工作区也没有完全跟上 `origin/main`

`origin/main` 上还有一些当前本地状态未完整吸收的内容，例如：

- `Add dev branch install option for experimental features`
- PR version bump check 相关调整
- upstream 的 README / docs 收敛结果
- 一些安装与 usage 文档、图片资源在当前本地状态中已经被重构、替换或删除

因此，如果后续要做“对外 PR”或“功能抽取”，建议把问题拆成两层看：

1. **功能层**：当前本地到底比 `origin/main` 多了哪些能力（本文件第 3 节）
2. **同步层**：当前本地与 `origin/main` 之间还存在多少 rebase / merge / 文档收敛问题

## 7. 最终总结

如果把“当前工作区 + `feat/rlcr-loop-improvements`”合在一起看，相比 `origin/main` 的核心结论是：

1. **当前最大的新增价值不是单点功能，而是一整套 RLCR 工作流增强包**
   - 包括 loop continuation、worker 拆分、plan convergence、task graph、batch prompt、delegation enforcement、worktree teams、BitLesson integration。

2. **`feat/rlcr-loop-improvements` 是这套增强包里最核心、最适合独立理解的一层**
   - 它回答的是：RLCR Loop 本身如何更可恢复、更清晰、更稳定。

3. **当前未提交修改的 feature 很集中**
   - 主线就是：**统一默认 Codex 模型到 `gpt-5.4:xhigh` 并同步全仓描述与测试**。

4. **当前状态相对 `origin/main` 是“功能领先很多，但并非完全同步”**
   - 后续如果要整理 PR，最好按 feature bucket 拆分，而不是直接把当前整个 `main` 当成单个提交面向 upstream。
