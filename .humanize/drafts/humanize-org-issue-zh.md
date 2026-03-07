# [Proposal] 基于运行日志增加一个低成本的 scaffold review workflow

## 背景

随着 `humanize` 这类真实项目型 agent scaffold 逐渐变大，会有越来越多的贡献者尝试增加新 feature、角色分工或 workflow。问题是：这些改动到底有没有真正提升系统效果，往往很难评估。

一个很自然的方向是把这类改动放进类似 CI 的评测流程里，在一些“真实开发场景”上跑对比。但这里有两个现实问题：

1. 很难挑选真正有代表性的“真实 workload”；
2. 如果直接跑较大的真实任务，token 成本会很高，难以高频执行。

我最近有一个想法：也许不应该只把 scaffold 改动看成“prompt/agent 能力优化”，而应该把它看成一种**组织设计（organizational design）**问题。

换句话说，我们真正想知道的不是“这个 scaffold 看起来更复杂了吗”，而是：

- 它是否更匹配当前任务分布；
- 它是否让信息流和决策流更顺畅；
- 它是否降低了重复搜索、重复 review、重复试错等协调摩擦；
- 它是否让失败更早暴露、成功经验更容易复用。

我觉得可以把这个评估框架压缩成四个维度：

- **Fit**：scaffold 是否匹配真实任务分布；
- **Flow**：信息流 / 决策流 / handoff 是否顺畅；
- **Friction**：哪里在空转、排队、重复劳动；
- **Feedback**：失败是否被及时发现，经验是否能沉淀。

这个视角的好处是，它不要求我们每次都用一个超大的“真实 benchmark”来判断 scaffold，而是允许我们从已有运行日志里提取证据，持续诊断系统设计是否合理。

## 修改建议

我建议在 `humanize` 现有日志/trace 基础上，加一个**低成本的周期性 scaffold review workflow**，优先做一个很轻量的 v1：

### 1. 先把运行日志和 scaffold 版本关联起来

每次 run 至少保留这些字段：

- `session_id`
- `scaffold_version`
- `model_version`
- `task_id`
- `task_slice`
- `budget`
- `events[]`（例如 plan / search / read / edit / test / review / stop / handoff）
- `outcome`（success / failure / false finish / human takeover）
- `artifacts`（diff / test result / review comments）

最关键的是：**日志必须能映射到具体 scaffold 版本**。否则后续分析只能“吐槽现象”，无法归因到具体改动。

### 2. 每天只跑便宜的指标预审

全量日志不直接喂给大模型，而是先做程序统计，例如：

- `success@budget`
- `tokens_per_success`
- `false_finish_rate`
- `human_takeover_rate`
- `search_steps_before_first_edit`
- `review_loop_count`
- 重复读同一文件 / 重复跑同一失败命令的次数

这一步的目的不是给建议，而是先定位：**到底是 scaffold 变坏了，还是任务分布变了。**

### 3. 每周只抽样，不看全量原始日志

为了控制 token 消耗，可以按结果和任务类型做分层采样，例如抽 20–40 个 session，覆盖：

- 便宜成功
- 昂贵成功
- 便宜失败
- 昂贵失败
- false finish
- human takeover

这样比“把一周日志全塞进模型”更便宜，也通常更稳。

### 4. 先生成 Trace Card，再做高级 review

先用便宜模型或本地模型，把每个 session 压成一张结构化 `Trace Card`，只保留：

- 任务是什么
- scaffold 经过了哪些阶段
- 哪一步开始偏航
- 哪些动作高价值
- 哪些动作纯浪费
- 验证是否充分
- 最可能的 failure tag
- 证据片段引用

然后再让强模型只看：

- 指标摘要
- Trace Cards
- 当前 scaffold spec
- 上一轮 review 结果

而不是直接看原始长日志。

### 5. review 的输出必须约束成“可证伪的实验建议”

建议每周最多产出 1–3 条修改建议，而且每条建议都必须显式映射到：

- 一个 failure mode
- 一个 scaffold 模块
- 一个预期改善指标
- 一个低成本证伪实验

例如：

- 对 `small-fix` 跳过 reviewer
- 目标模块：`review_trigger_policy`
- 预期收益：降低 `tokens_per_success` 和 latency
- 风险：漏掉边界回归
- 验证方式：A/B 一周，guardrail 为 `false_finish_rate` 不显著上升

如果一条建议不能写成这种格式，那它更像“观察”，还不应该进入 action list。

## 为什么这件事值得做

我觉得这个 workflow 对 `humanize` 的价值在于：

1. **更贴近真实系统演化**：不是只测模型能力，而是测整个 scaffold 的组织效果；
2. **更可扩展**：随着贡献者变多，能够更系统地评估 feature 改动是否真的带来收益；
3. **更省 token**：全量日志只做程序统计，强模型只看压缩后的证据包；
4. **更容易形成闭环**：每周只认领少量实验，逐步验证哪些 scaffold 设计真的有效。

## 一个可落地的最小版本

如果要从很小的改动开始，我建议优先落 3 个东西：

1. 给日志补齐 `scaffold_version`、`task_slice`、`outcome`、`budget`、`events`；
2. 增加一个每周生成 `weekly_scaffold_review.md` 的脚本或 workflow；
3. 统一一版最小 `failure taxonomy` 和 `Trace Card` schema。

这样就已经能把“是否值得改 scaffold”从主观讨论，往“基于证据的低成本组织诊断”推进一步。

如果 maintainer 觉得这个方向有价值，我很愿意继续补一个更具体的 v1 草案，比如：

- `Trace Card` schema
- `failure taxonomy` 初版
- `weekly_scaffold_review.md` 模板
- reviewer prompt 的结构约束
