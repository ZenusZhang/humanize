# Swarm Backend 接口草案 + PoC 文件清单（委派版）

> 统筹说明：本草案由 **Codex-Backend（被委派执行）** 产出，我负责整合落库。

## 1) 目标与边界

- 在不替换现有 RLCR 主循环的前提下，引入可插拔编排后端：`native | openai_agents | claude_swarm`。
- 第一阶段只接管 `analyze` 路由（低风险），`coding` 路由和最终 `codex review` gate 保持不变。
- 保证状态文件、日志与回退策略统一，避免“双编排器并存”造成状态分裂。

---

## 2) 接口草案（v0）

### 2.1 CLI/配置层

在 `start-rlcr-loop` 增加参数：

- `--swarm-backend <native|openai_agents|claude_swarm>`（默认 `native`）
- `--swarm-config <path>`（可选，后端特定配置）
- `--swarm-failover <native|abort>`（默认 `native`）

可选环境变量（优先级低于 CLI）：

- `HUMANIZE_SWARM_BACKEND`
- `HUMANIZE_SWARM_CONFIG`
- `HUMANIZE_SWARM_FAILOVER`

### 2.2 状态文件扩展（frontmatter）

在 loop 状态中新增字段：

- `swarm_backend: native|openai_agents|claude_swarm`
- `swarm_enabled: true|false`
- `swarm_config_path: <path|empty>`
- `swarm_failover: native|abort`
- `swarm_session_id: <string|empty>`（后端会话标识）
- `swarm_last_error: <string|empty>`

### 2.3 适配器契约（脚本函数）

新增统一入口（建议放在 `scripts/lib/swarm-backend.sh`）：

```bash
# 初始化后端（读取配置、预检依赖、创建运行上下文）
swarm_backend_init <loop_dir> <backend> <config_path> <failover>
# 返回: 0 成功；非0失败（由调用方按 failover 处理）

# 每轮开始前的准备（可选）
swarm_backend_prepare_round <loop_dir> <round>

# 执行 analyze 任务（MVP 核心）
# 输入: task_id, prompt_file, output_file, timeout
swarm_backend_run_analyze <loop_dir> <task_id> <prompt_file> <output_file> <timeout>
# 返回: 0 成功；非0失败

# 轮次结束钩子（记录统计/trace）
swarm_backend_finalize_round <loop_dir> <round>

# 释放资源
swarm_backend_shutdown <loop_dir>
```

### 2.4 结果与错误约定

- `swarm_backend_run_analyze` 成功时，必须写出标准 Markdown 结果到 `output_file`。
- 失败时必须：
  - 写 stderr 到 `.humanize/rlcr/<id>/swarm/round-<n>-<task>-error.log`
  - 更新 `swarm_last_error`
  - 按 `swarm_failover` 执行：
    - `native`: 回退到 `/humanize:ask-codex` 路径
    - `abort`: 阻断本轮并提示人工处理

### 2.5 观测与审计

统一目录（每个 loop）：

- `.humanize/rlcr/<id>/swarm/backend.json`（后端元信息）
- `.humanize/rlcr/<id>/swarm/events.ndjson`（事件流）
- `.humanize/rlcr/<id>/swarm/round-*-*.log`（运行日志）

事件最小字段：

- `ts`, `round`, `task_id`, `backend`, `phase`, `status`, `duration_ms`, `fallback_used`

---

## 3) 后端实现轮廓（MVP）

### 3.1 native（基线）

- 直接复用现有 `/humanize:ask-codex` 行为。
- 作为默认后端与 failover 目标。

### 3.2 openai_agents（一期）

- 仅替换 `analyze` 执行器：
  - 读任务 prompt
  - 调 Python runner（Agents SDK）
  - 输出 Markdown 结果
- 保留现有 review phase（`codex review --base`）不变。

### 3.3 claude_swarm（二期可选）

- 暂不接管全流程，仅用于并行 analyze 或特定协作任务。
- 与 `worktree-teams` 的 lane 机制做映射（避免文件所有权冲突）。

---

## 4) PoC 文件清单（最小改动集）

## A. 新增文件

1. `scripts/lib/swarm-backend.sh`
   - 后端分发器与统一契约实现（native/openai_agents/claude_swarm stub）。
2. `scripts/swarm/openai_agents_runner.py`
   - OpenAI Agents SDK 最小执行器（读取 prompt，写 markdown）。
3. `scripts/swarm/claude_swarm_runner.sh`
   - Claude Swarm 预留执行器（先返回明确“not implemented”并产生日志）。
4. `docs/swarm-backend.md`
   - 用户文档：参数、配置、回退、故障排查。
5. `tests/test-swarm-backend.sh`
   - 适配器分发、回退、状态字段、日志产物测试。

## B. 修改文件

1. `scripts/setup-rlcr-loop.sh`
   - 增加新参数解析、状态字段写入、初始化调用。
2. `hooks/loop-codex-stop-hook.sh`
   - 在 `analyze` 路由点调用 `swarm_backend_run_analyze`。
3. `commands/start-rlcr-loop.md`
   - 暴露新参数与用法说明。
4. `README.md`
   - 补充 Swarm backend 开关与 MVP 行为说明。
5. `tests/run-all-tests.sh`
   - 纳入 `test-swarm-backend.sh`。

## C. 非目标（PoC 不做）

- 不改 review phase 判定逻辑。
- 不重写 `worktree-teams` 协议。
- 不引入跨 loop 的全局状态中心。

---

## 5) PoC 分阶段实施

### Phase 0（接口落地）

- 落地 CLI 参数 + 状态字段 + `swarm-backend.sh` 分发骨架。
- `native` 路径行为与当前一致。

### Phase 1（openai_agents 接入）

- 打通 analyze 执行链路。
- 打通 failover 到 native。
- 增加事件日志与基本时延统计。

### Phase 2（claude_swarm 预集成）

- 先给 stub + 配置验证 + 错误信息完整化。
- 仅在实验开关下启用。

---

## 6) PoC 验收标准

- `--swarm-backend native` 与当前行为一致（回归通过）。
- `--swarm-backend openai_agents` 可成功执行至少一个 `analyze` 任务并落盘结果。
- 后端失败时，`swarm_failover=native` 能自动回退并完成任务。
- `events.ndjson` 与错误日志可用于复盘一次失败。

---

## 7) 任务委派（Codex 执行分工）

### 7.1 角色与负责人

- **Codex-1（接口与状态）**
  - 负责 `scripts/setup-rlcr-loop.sh`：新增 `--swarm-backend/--swarm-config/--swarm-failover` 参数解析与状态字段写入。
  - 同步更新 `commands/start-rlcr-loop.md` 的参数说明。
- **Codex-2（后端分发骨架）**
  - 负责新增 `scripts/lib/swarm-backend.sh`：统一契约、backend dispatch、failover 决策入口。
  - 落地 `native` 基线路径，保证行为与当前一致。
- **Codex-3（analyze 路由接线）**
  - 负责修改 `hooks/loop-codex-stop-hook.sh`：在 analyze 路由调用 `swarm_backend_run_analyze`。
  - 衔接失败日志与 `swarm_last_error` 更新流程。
- **Codex-4（openai_agents 执行器）**
  - 负责新增 `scripts/swarm/openai_agents_runner.py`：读取 prompt、调用 Agents SDK、输出标准 Markdown。
  - 与 Codex-2 对齐 runner 入参/出参约定。
- **Codex-5（claude_swarm 预集成）**
  - 负责新增 `scripts/swarm/claude_swarm_runner.sh` stub：返回 not implemented、输出可审计日志。
  - 加入实验开关与基础配置校验（不接管全流程）。
- **Codex-6（文档）**
  - 负责新增 `docs/swarm-backend.md`（参数、配置、故障排查）。
  - 更新 `README.md` 中 Swarm backend MVP 行为说明。
- **Codex-7（测试）**
  - 负责新增 `tests/test-swarm-backend.sh`（分发、回退、状态字段、日志产物）。
  - 修改 `tests/run-all-tests.sh`，纳入新测试并保证默认测试入口可执行。

### 7.2 执行顺序（依赖）

1. Codex-1 与 Codex-2 并行起步（接口参数 + 分发骨架）。
2. Codex-3 在 Codex-2 的函数契约稳定后接线 analyze 路由。
3. Codex-4/Codex-5 分别接入 openai_agents 与 claude_swarm stub。
4. Codex-6 在参数与行为基本稳定后补全文档。
5. Codex-7 最后收敛测试并补回归。

### 7.3 Reviewer 指派

- **Codex-Reviewer（最终审阅负责人）**
  - 独立于上述 7 个执行 Codex，不直接提交实现代码。
  - 审查范围：接口契约一致性、failover 安全性、日志与状态完整性、测试覆盖和文档一致性。
  - 合并前 gate：`tests/run-all-tests.sh` 必须通过，且 openai_agents 失败回退场景有可复盘日志。
