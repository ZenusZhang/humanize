# 完整委派器：提供方无关的角色配置与委派移植

## 语言格式
默认：仅英语。

## 目标说明

将委派器工作流模式从 `main` 移植到一个基于 `origin/dev` 的新 `full-delegation` 分支，并将当前的 `(builder <-> reviewer) <-> reviewer` 工作流替换为 `delegator <-> ((builder <-> reviewer) <-> reviewer)` 模式。通过配置系统使三个代理角色（worker、analyzer、reviewer）都可按提供方配置，而不是将它们硬编码为 Codex。引入提供方无关的命令名（`/humanize:worker`、`/humanize:analyze`），并将其构建为独立架构，而不是保持与 `main` 的一致性。

核心转换：
- **当前 `origin/dev`**：Claude 直接实现；Codex 负责审查。角色是硬编码的。
- **目标 `full-delegation`**：Claude 作为团队负责人进行委派；可配置的 worker 负责实现；可配置的 reviewer 负责审查。角色由配置驱动。

## 验收标准

遵循 TDD 哲学，每条标准都包含正向测试和反向测试，以便进行确定性的验证。

- AC-1：存在基于 `origin/dev` 的 `full-delegation` 分支，并包含委派器工作流
  - 正向测试（预期通过）：
    - `git log full-delegation --oneline` 显示了从 `main` 移植过来的委派功能提交
    - 该分支相对于 `origin/dev` 发生了分叉（而不是相对于 `main`）
  - 反向测试（预期失败）：
    - 运行 `git merge-base --is-ancestor main full-delegation` 返回 false（该分支不是基于 `main`）

- AC-2：通过配置系统支持按角色配置提供方
  - 正向测试（预期通过）：
    - 在 `.humanize/config.json` 中设置 `"roles": { "worker": { "provider": "codex", "model": "gpt-5.4", "effort": "xhigh" } }`，能够将 worker 任务正确路由到 Codex
    - 为 analyzer 设置不同的 provider 时，analyzer 任务会相应路由
    - 当按角色配置缺失时，旧版 `codex_model`/`codex_effort` 键仍可作为回退方案使用
    - 按角色配置可在 default/user/project 三层中正确合并
  - 反向测试（预期失败）：
    - 设置 `"roles": { "worker": { "provider": "nonexistent" } }` 会导致 setup 以清晰错误信息失败
    - 设置 `"roles": { "reviewer": { "provider": "unsupported_provider" } }` 且没有注册适配器时，会导致 setup 失败
  - AC-2.1：配置优先级遵循 CLI 标志 > 按角色配置 > 旧版 `codex_*` > 硬编码默认值
    - 正向：CLI `--worker-model gpt-5.4:xhigh` 会覆盖配置文件中的 `roles.worker.model`
    - 反向：配置文件的值不会覆盖显式给出的 CLI 标志

- AC-3：`full-delegation` 分支上的委派强制钩子可正常工作
  - 正向测试（预期通过）：
    - 当 `delegation_enforcement: strict` 且 `agent_teams: true` 时，Claude 对源文件执行的 Write/Edit/Bash 操作会被阻止，并给出清晰提示
    - 在严格模式下，对 `.humanize/` 协调文件的操作是允许的
    - 在审查阶段（`review_started: true`）会放宽委派强制规则
  - 反向测试（预期失败）：
    - 在严格委派模式下，Claude 直接编辑 `scripts/some-file.sh` 会触发强制阻止（退出码 2）

- AC-4：提供方无关的 worker 命令（`/humanize:worker`）通过配置的 provider 执行任务
  - 正向测试（预期通过）：
    - 当 provider=codex 时，`/humanize:worker` 使用配置好的 model/effort 调用 `codex exec`
    - Worker 成功时会创建 `.worker-invoked-round-N` 标记文件
    - Worker 状态会持久化到 loop `state.md` 的 frontmatter 中
  - 反向测试（预期失败）：
    - 当配置的 provider CLI 未安装时，运行 `/humanize:worker` 会在调用时以清晰错误失败

- AC-5：提供方无关的 analyzer 命令（`/humanize:analyze`）通过配置的 provider 执行分析
  - 正向测试（预期通过）：
    - 当 provider=codex 时，`/humanize:analyze` 调用 `codex exec` 执行一次性分析
    - 分析结果按预期格式返回
  - 反向测试（预期失败）：
    - 当 provider CLI 缺失时，`/humanize:analyze` 会以清晰错误失败

- AC-6：审查输出适配器接口支持可配置的代码审查
  - 正向测试（预期通过）：
    - 当 provider=codex 时，审查使用 `codex review --base <branch>`，并解析 `[P0-9]` 严重级别标记
    - 适配器接口定义了稳定契约：输入（branch/diff 上下文）与输出（带严重级别的结构化问题）
    - 存在 Codex 适配器实现，并通过所有审查测试
  - 反向测试（预期失败）：
    - 如果为 reviewer 配置了一个没有已注册适配器实现的 provider，会在 setup 阶段被拒绝

- AC-7：RLCR 循环在 `full-delegation` 分支上可在委派模式下端到端运行
  - 正向测试（预期通过）：
    - `/humanize:start-rlcr-loop plan.md --agent-teams` 能完成实现和审查阶段
    - Claude 只充当协调者；所有编码工作都委派给已配置的 worker
    - 审查阶段通过适配器接口使用已配置的 reviewer
    - 状态切换（轮次递增、`review_started` 标记）工作正常
  - 反向测试（预期失败）：
    - 在 `full-delegation` 分支上不带 `--agent-teams` 运行 RLCR 时，仍使用旧版直接实现流程（委派默认开启，但该标志仍控制它）

- AC-8：与旧版配置和状态文件保持向后兼容
  - 正向测试（预期通过）：
    - `.humanize/config.json` 仅包含 `codex_model`/`codex_effort`（没有 `roles` 键）时，仍能正常工作，并将旧版键映射到所有角色
    - 现有来自 `origin/dev` 的 loop 状态文件可以无错误解析
    - `tests/test-unified-codex-config.sh` 通过（或已更新以覆盖新 schema）
  - 反向测试（预期失败）：
    - 当配置同时包含 `roles.worker.model` 和旧版 `codex_model` 时，应使用按角色配置的值（旧版值不会覆盖按角色配置）

- AC-9：在 setup 阶段对无效或不可用的 provider 配置进行拒绝
  - 正向测试（预期通过）：
    - `setup-rlcr-loop.sh` 在启动循环前验证 provider 是否可用
    - 缺失 provider CLI 时会输出明确的错误信息，并指出缺失的工具名
    - 无效 provider 名称会被拒绝，并给出受支持 provider 列表
  - 反向测试（预期失败）：
    - 当配置的 provider 不可用时，setup 悄悄继续执行（这种情况绝不能发生）

## 路径边界

路径边界定义了实现质量和实现选择的可接受范围。

### 上界（最大可接受范围）
实现包含：
- 完整委派器工作流移植，并包含三层强制钩子（write/edit/bash validators）
- 按角色配置的 schema，支持 worker、analyzer、reviewer 的 provider/model/effort/timeout
- 审查输出适配器接口，以及 Codex 适配器实现
- 提供方无关的命令 `/humanize:worker` 和 `/humanize:analyze` 作为主要入口
- 从 `main` 移植过来的 worktree-teams 基础设施
- 配置优先级解析（CLI > 按角色 > 旧版 > 默认），并包含完整状态持久化
- 对旧版 `codex_model`/`codex_effort` 配置的向后兼容映射
- Shell 测试，覆盖角色配置校验、状态序列化、委派强制和适配器选择

### 下界（最小可接受范围）
实现包含：
- 从 `main` 移植过来的带严格强制钩子的委派器工作流
- 按角色配置的 schema，至少包含 provider 和 model 字段
- Codex 审查适配器（最小可行版本只要求这一种适配器）
- 提供方无关的包装脚本，通过它们分发到特定 provider 的实现
- 在 setup 阶段验证 provider 是否可用
- 对旧版 `codex_model`/`codex_effort` 的回退支持

### 允许的选择
- 可使用：bash 脚本、`jq` 进行 JSON 处理、现有 `config-loader.sh` 模式、现有 `model-router.sh` 作为 provider 路由基础
- 可使用：审查输出的适配器模式（基于函数或基于脚本的分发）
- 可使用：YAML frontmatter 进行状态持久化（现有模式）
- 不可使用：超出 bash/jq 之外的外部包管理器或运行时依赖
- 不可使用：对现有 `origin/dev` 流程进行超出范围的破坏性修改（PR loop、monitor）

## 可行性提示与建议

> **说明**：本节仅供参考与理解。这些是概念性建议，而不是强制要求。

### 概念性方案

1. **分支设置**：从 `origin/dev` 创建 `full-delegation`。为 `main` 创建一个 git worktree，用于参考其委派代码。

2. **扩展配置 schema**：为 `config/default_config.json` 增加一个 `roles` 对象：
   ```json
   {
     "codex_model": "gpt-5.4",
     "codex_effort": "high",
     "roles": {
       "worker":   { "provider": "codex", "model": "gpt-5.4", "effort": "xhigh", "timeout": 3600 },
       "analyzer": { "provider": "codex", "model": "gpt-5.4", "effort": "high",  "timeout": 3600 },
       "reviewer": { "provider": "codex", "model": "gpt-5.4", "effort": "high",  "timeout": 3600 }
     }
   }
   ```

3. **Provider Router**：将 `scripts/lib/model-router.sh` 扩展为一个 provider 分发器，把 `provider` 字段映射到正确的 CLI 工具及调用模式。

4. **Review Adapter**：创建 `scripts/lib/review-adapter.sh`，并提供一个分发函数：
   ```
   review_dispatch(provider, model, effort, base_branch) -> structured_findings
   ```
   Codex 适配器调用 `codex review --base $base_branch` 并解析 `[P0-9]` 输出。其他适配器也实现同样的问题契约。

5. **中立命令**：创建 `scripts/worker.sh` 和 `scripts/analyze.sh` 作为提供方无关的入口点，它们读取角色配置并通过 provider router 进行分发。

6. **强制逻辑移植**：从 `main` 挑拣或改造 write/edit/bash validator 钩子，并将其连接到 `loop-common.sh` 中的委派状态字段。

### 相关参考
- `config/default_config.json` - 当前需要扩展的配置 schema
- `scripts/lib/config-loader.sh` - 配置合并逻辑（三层层级）
- `scripts/lib/model-router.sh` - 需要扩展的 provider 检测逻辑
- `scripts/codex-worker.sh` - 当前的 Codex worker 实现，需要做抽象
- `scripts/ask-codex.sh` - 当前的 Codex analyzer，需要做抽象
- `hooks/loop-codex-stop-hook.sh` - 含有 `codex review` 调用的审查逻辑
- `hooks/lib/loop-common.sh` - 状态管理、委派模式检查
- `hooks/loop-write-validator.sh` - `main` 上的 Write 强制钩子
- `hooks/loop-edit-validator.sh` - `main` 上的 Edit 强制钩子
- `hooks/loop-bash-validator.sh` - `main` 上的 Bash 强制钩子
- `prompt-template/claude/agent-teams-core.md` - `main` 上的团队负责人说明
- `prompt-template/claude/worktree-teams-instructions.md` - `main` 上的 worktree 协议
- `prompt-template/block/strict-delegation-required.md` - `main` 上的阻止消息模板
- `scripts/setup-rlcr-loop.sh` - 带委派字段的循环 setup
- `tests/test-unified-codex-config.sh` - 现有配置校验测试

## 依赖与顺序

### 里程碑

1. **里程碑 1：分支与配置基础**
   - 阶段 A：从 `origin/dev` 创建 `full-delegation` 分支；设置 `main` worktree 以供参考
   - 阶段 B：用 `roles` 对象扩展配置 schema；更新 config-loader 校验逻辑
   - 阶段 C：实现配置优先级解析（CLI > 按角色 > 旧版 > 默认）

2. **里程碑 2：Provider 抽象层**
   - 阶段 A：将 `model-router.sh` 扩展为 provider 分发器
   - 阶段 B：创建提供方无关的 `scripts/worker.sh`（作为主要入口替代 `codex-worker.sh`）
   - 阶段 C：创建提供方无关的 `scripts/analyze.sh`（作为主要入口替代 `ask-codex.sh`）
   - 阶段 D：构建审查适配器接口和 Codex 适配器实现

3. **里程碑 3：委派强制逻辑移植**
   - 阶段 A：将委派状态字段和 `strict_delegation_mode_active()` 移植到 `loop-common.sh`
   - 阶段 B：从 `main` 移植 write/edit/bash validator 钩子
   - 阶段 C：移植 `agent-teams-core.md` 和阻止模板
   - 阶段 D：增加 `.worker-invoked-round-N` 标记文件支持

4. **里程碑 4：RLCR 集成**
   - 阶段 A：更新 `setup-rlcr-loop.sh`，支持角色配置解析和状态持久化
   - 阶段 B：更新 `hooks/loop-codex-stop-hook.sh`，使其通过审查适配器工作
   - 阶段 C：移植 worktree-teams 基础设施
   - 阶段 D：在委派模式下进行端到端 RLCR 循环验证

5. **里程碑 5：测试与向后兼容**
   - 阶段 A：更新或创建 shell 测试，覆盖角色配置校验
   - 阶段 B：增加委派强制钩子测试
   - 阶段 C：增加审查适配器测试
   - 阶段 D：验证与旧版配置/状态的向后兼容性

里程碑 1 是基础；完成里程碑 1 后，里程碑 2 和 3 可以并行推进。里程碑 4 依赖里程碑 2 和 3。里程碑 5 与里程碑 2 到 4 并行进行（测试驱动）。

## 任务拆解

每个任务必须且只能包含一个路由标签：
- `coding`：由 Claude 实现
- `analyze`：通过 Codex 执行（`/humanize:ask-codex`）

| Task ID | 描述 | 目标 AC | 标签（`coding`/`analyze`） | 依赖项 |
|---------|------|---------|----------------------------|--------|
| task1 | 从 `origin/dev` 创建 `full-delegation` 分支，并设置 `main` worktree 以供参考 | AC-1 | coding | - |
| task2 | 分析 `main` 分支的委派代码，识别所有需要移植的文件和模式 | AC-1 | analyze | task1 |
| task3 | 用 `roles` schema 扩展 `config/default_config.json`（worker/analyzer/reviewer 均包含 provider/model/effort/timeout） | AC-2 | coding | task1 |
| task4 | 更新 `scripts/lib/config-loader.sh` 的校验逻辑，以支持新的 `roles` schema，并向后兼容旧版 `codex_*` 键 | AC-2, AC-8 | coding | task3 |
| task5 | 在 `hooks/lib/loop-common.sh` 中实现配置优先级解析（CLI > 按角色 > 旧版 > 默认） | AC-2.1 | coding | task4 |
| task6 | 将 `scripts/lib/model-router.sh` 扩展为支持多个后端的通用 provider 分发器 | AC-4, AC-5 | coding | task3 |
| task7 | 创建 `scripts/worker.sh` 作为提供方无关的 worker 命令 | AC-4 | coding | task6 |
| task8 | 创建 `scripts/analyze.sh` 作为提供方无关的 analyzer 命令 | AC-5 | coding | task6 |
| task9 | 在 `scripts/lib/review-adapter.sh` 中构建带分发函数的审查适配器接口 | AC-6 | coding | task6 |
| task10 | 实现 Codex 审查适配器（包装 `codex review --base` 并解析 `[P0-9]`） | AC-6 | coding | task9 |
| task11 | 将委派状态字段移植到 `hooks/lib/loop-common.sh`（`agent_teams`、`delegation_enforcement`、`worktree_teams` 等） | AC-3 | coding | task2, task5 |
| task12 | 从 `main` 移植带委派强制逻辑的 write/edit/bash validator 钩子 | AC-3 | coding | task11 |
| task13 | 移植 `prompt-template/claude/agent-teams-core.md` 和 `prompt-template/block/strict-delegation-required.md` | AC-3 | coding | task11 |
| task14 | 在 `scripts/worker.sh` 中增加 `.worker-invoked-round-N` 标记文件的创建逻辑 | AC-4, AC-7 | coding | task7, task11 |
| task15 | 更新 `scripts/setup-rlcr-loop.sh`，支持角色配置解析、provider 校验和状态持久化 | AC-7, AC-9 | coding | task5, task6 |
| task16 | 更新 `hooks/loop-codex-stop-hook.sh`，改为使用审查适配器，而不是硬编码 `codex review` | AC-6, AC-7 | coding | task10, task15 |
| task17 | 移植 worktree-teams 基础设施（setup 脚本、说明模板） | AC-7 | coding | task11, task13 |
| task18 | 为 `/humanize:worker` 和 `/humanize:analyze` 命令创建或更新 skill 定义 | AC-4, AC-5 | coding | task7, task8 |
| task19 | 在所有组件移植完成后，分析端到端 RLCR 流程中的集成缺口 | AC-7 | analyze | task16, task17 |
| task20 | 编写 shell 测试，覆盖角色配置校验和 provider 分发 | AC-2, AC-9 | coding | task4, task6 |
| task21 | 编写 shell 测试，覆盖委派强制钩子 | AC-3 | coding | task12 |
| task22 | 编写 shell 测试，覆盖审查适配器接口和 Codex 适配器 | AC-6 | coding | task10 |
| task23 | 验证向后兼容性：旧版配置文件、现有状态文件、`test-unified-codex-config.sh` | AC-8 | coding | task15 |
| task24 | 在 `full-delegation` 分支上对委派模式进行端到端 RLCR 验证 | AC-7 | analyze | task19 |

## Claude-Codex 审议

### 已达成一致
- 从 `origin/dev` 创建 `full-delegation` 是正确的分支策略
- 这是一次功能移植，而不是简单的配置重构；需要移植提示模板、强制钩子、状态 schema 和 worker 脚本
- 按用户要求，三个角色（worker、analyzer、reviewer）都必须可配置
- 按角色配置的 schema 需要 provider/model/effort/timeout 字段（而不仅仅是 backend 名称）
- 将工作拆分为“从 `main` 移植”和“新抽象层”两个里程碑是合理的做法
- 对于 `full-delegation` 分支，委派应默认开启（按草案要求替换当前工作流）
- 为了向后兼容，必须保留旧版 `codex_model`/`codex_effort` 作为回退
- 对不受支持或不可用的 provider，必须在 setup 阶段拒绝（默认关闭，失败即停止）
- analyzer 相关接入点（`ask-codex.sh` 及相关 prompts）必须纳入范围
- 现有测试如 `test-unified-codex-config.sh` 需要更新以适配新 schema

### 已解决分歧
- **Reviewer 范围**：Claude 最初提出为了简化实现，将 reviewer 保持为仅 Codex。Codex 认为这与用户明确要求 builder 和 reviewer 都可配置相矛盾。结论：用户确认需要构建 review adapter，因此三个角色都必须完全可配置。
- **配置 schema 深度**：Claude 最初只提出 `worker_backend` 字段。Codex 要求按角色提供 model/effort/timeout，并定义明确的优先级规则。结论：采用完整的按角色 schema，优先级为 CLI > 按角色 > 旧版 > 默认。
- **状态字段准确性**：Claude 曾将 `agent_teams` 列为需要新增的字段。Codex 指出它在 `origin/dev` 中已经存在。结论：已更正；只需要新增委派相关字段。
