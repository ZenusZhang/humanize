# [Proposal] 考虑基于运行日志增加一个低成本的 scaffold review workflow

## 背景

随着 `humanize` 这类真实项目型 agent scaffold 逐渐变大，会有越来越多的贡献者尝试增加新 feature、角色分工或 workflow。一个随之而来的问题是：这些改动是否真的提升了系统效果，往往并不容易判断。

一个很自然的方向，是把这类改动放进类似 CI 的评测流程里，在一些“真实开发场景”上做对比。不过这里有两个现实问题：

1. 很难挑选真正有代表性的“真实 workload”；
2. 如果直接跑较大的真实任务，token 成本会比较高，不太适合高频执行。

最近我在想，也许不一定只把 scaffold 改动看成“prompt/agent 能力优化”，也可以把它视作一种**组织设计（organizational design）**问题来评估。

换句话说，我们想知道的也许不只是“这个 scaffold 看起来是不是更复杂了”，而是：

- 它是否更匹配当前任务分布；
- 它是否让信息流和决策流更顺畅；
- 它是否降低了重复搜索、重复 review、重复试错等协调摩擦；
- 它是否让失败更早暴露、成功经验更容易复用。

如果把这个评估视角再压缩一下，我觉得可以落在四个维度上：

- **Fit**：scaffold 是否匹配真实任务分布；
- **Flow**：信息流 / 决策流 / handoff 是否顺畅；
- **Friction**：哪里在空转、排队、重复劳动；
- **Feedback**：失败是否被及时发现，经验是否能沉淀。

这个视角的一个好处是，它不要求我们每次都依赖一个超大的“真实 benchmark”来判断 scaffold，而是允许我们从已有运行日志里提取证据，持续观察系统设计是否合理。

## 一个可能的修改方向

如果这个方向有参考价值，我想建议在 `humanize` 现有日志/trace 基础上，尝试增加一个**低成本的周期性 scaffold review workflow**，先从一个轻量 v1 开始。

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

这里我觉得最关键的是：**日志最好能映射到具体 scaffold 版本**。否则后续分析可能只能描述现象，比较难归因到具体改动。

### 2. 每天只跑便宜的指标预审

全量日志不直接喂给大模型，而是先做程序统计，例如：

- `success@budget`
- `tokens_per_success`
- `false_finish_rate`
- `human_takeover_rate`
- `search_steps_before_first_edit`
- `review_loop_count`
- 重复读同一文件 / 重复跑同一失败命令的次数

这一步的目的不一定是立刻给建议，而是先帮助回答：**到底是 scaffold 变坏了，还是只是任务分布变了。**

### 3. 每周只抽样，不看全量原始日志

为了控制 token 消耗，可以按结果和任务类型做分层采样，例如抽 20–40 个 session，覆盖：

- 便宜成功
- 昂贵成功
- 便宜失败
- 昂贵失败
- false finish
- human takeover

这样通常会比“把一周日志全塞进模型”更便宜，也更容易维持稳定的 review 节奏。

### 4. 先生成 Trace Card，再做高级 review

可以先用便宜模型或本地模型，把每个 session 压成一张结构化 `Trace Card`，只保留：

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

### 5. review 的输出尽量约束成“可证伪的实验建议”

如果后面真的采用这种 workflow，我会比较倾向于让每周 review 最多产出 1–3 条修改建议，而且每条建议都尽量显式映射到：

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

如果一条建议还不能写成这种格式，也许更适合作为“观察”，而不是立即进入 action list。

## 为什么我觉得这件事值得讨论

我觉得这个 workflow 对 `humanize` 可能有几个潜在价值：

1. **更贴近真实系统演化**：不是只测模型能力，而是测整个 scaffold 的组织效果；
2. **更可扩展**：随着贡献者变多，能够更系统地评估 feature 改动是否真的带来收益；
3. **更省 token**：全量日志只做程序统计，强模型只看压缩后的证据包；
4. **更容易形成闭环**：每周只认领少量实验，逐步验证哪些 scaffold 设计真正有效。

## 一个可落地的最小版本

如果要从很小的改动开始，我会建议优先补 3 个东西：

1. 给日志补齐 `scaffold_version`、`task_slice`、`outcome`、`budget`、`events`；
2. 增加一个每周生成 `weekly_scaffold_review.md` 的脚本或 workflow；
3. 统一一版最小 `failure taxonomy` 和 `Trace Card` schema。

这样也许就已经能把“是否值得改 scaffold”从主观讨论，往“基于证据的低成本组织诊断”推进一步。

如果 maintainer 觉得这个方向有意义，我也很愿意继续补一个更具体的 v1 草案，比如：

- `Trace Card` schema
- `failure taxonomy` 初版
- `weekly_scaffold_review.md` 模板
- reviewer prompt 的结构约束
