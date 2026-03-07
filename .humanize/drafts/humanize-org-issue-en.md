# [Proposal] Consider adding a low-cost scaffold review workflow based on run logs

## Background

As projects like `humanize` grow into real-world agent scaffolds, more contributors will naturally add new features, roles, and workflows. A related challenge is that it becomes harder to tell whether those changes are actually improving the system.

One natural idea is to add a CI-like check that compares scaffold changes on “real” development workloads. But there are two practical issues:

1. It is hard to choose workloads that are genuinely representative.
2. If the workloads are large and realistic, the token cost can become too high for frequent evaluation.

I have been wondering whether scaffold changes could be framed not only as “prompt/agent capability tweaks,” but also as an **organizational design** problem.

In other words, the question may not just be “is this scaffold more sophisticated?”, but also:

- Does it fit the actual task distribution?
- Does it improve information flow and decision flow?
- Does it reduce coordination friction such as repeated search, repeated review, and repeated trial-and-error?
- Does it help the system surface failures earlier and reuse successful patterns more reliably?

If I compress that evaluation lens a bit, it seems to fall into four dimensions:

- **Fit**: does the scaffold match the real task mix?
- **Flow**: are information flow, decision flow, and handoffs working well?
- **Friction**: where are we wasting effort through loops, queues, or duplicate work?
- **Feedback**: are failures caught early, and are wins made reusable?

One benefit of this framing is that it does not require a giant “real benchmark” every time. It allows us to use existing run logs as evidence and continuously observe whether the scaffold design is moving in a good direction.

## A possible direction

If this seems useful, I would like to suggest adding a **low-cost periodic scaffold review workflow** on top of the existing logging / trace system, starting with a lightweight v1.

### 1. Make runs traceable to scaffold versions

Each run should retain at least:

- `session_id`
- `scaffold_version`
- `model_version`
- `task_id`
- `task_slice`
- `budget`
- `events[]` (for example plan / search / read / edit / test / review / stop / handoff)
- `outcome` (success / failure / false finish / human takeover)
- `artifacts` (diff / test result / review comments)

The most important point, in my view, is that **logs should ideally be attributable to a specific scaffold version**. Otherwise the analysis may describe symptoms, but it becomes much harder to attribute them to a concrete change.

### 2. Run cheap metric screening daily

Instead of sending full logs to a strong model by default, first run programmatic metrics over all runs, for example:

- `success@budget`
- `tokens_per_success`
- `false_finish_rate`
- `human_takeover_rate`
- `search_steps_before_first_edit`
- `review_loop_count`
- repeated reads of the same file / repeated execution of the same failing command

The goal here is not necessarily to generate recommendations immediately. It is first to help answer: **did the scaffold actually get worse, or did the task mix change?**

### 3. Sample weekly instead of reviewing all raw logs

To control cost, it may be enough to do stratified sampling over outcomes and task types — for example 20–40 sessions covering:

- cheap successes
- expensive successes
- cheap failures
- expensive failures
- false finishes
- human takeovers

This is usually much cheaper than feeding an entire week of raw logs into a model, and it may also lead to a more stable review rhythm.

### 4. Generate Trace Cards before higher-level review

A cheap or local model could first compress each sampled session into a structured `Trace Card`, keeping only:

- what the task was
- which scaffold phases were used
- where the run started to drift
- which actions added value
- which actions were pure waste
- whether verification was sufficient
- the most likely failure tag
- short evidence references

Then a stronger model would review only:

- metric summaries
- Trace Cards
- the current scaffold spec
- the previous review report

instead of full raw logs.

### 5. Keep review output close to falsifiable experiment proposals

If this workflow were adopted, I think it could be helpful for each weekly review to produce at most 1–3 proposed changes, and for each proposal to map as explicitly as possible to:

- one failure mode
- one scaffold module
- one expected improvement metric
- one low-cost falsification test

For example:

- skip reviewer for `small-fix`
- target module: `review_trigger_policy`
- expected gain: lower `tokens_per_success` and latency
- risk: missing subtle regressions
- validation: one-week A/B test with `false_finish_rate` as guardrail

If a recommendation cannot yet be written in this format, it may be better treated as an observation rather than an immediate action item.

## Why this might be worth discussing

I think this workflow could potentially help `humanize` in a few ways:

1. **It evaluates the whole scaffold, not just model capability.**
2. **It scales better as more contributors propose changes.**
3. **It controls token cost by reviewing compressed evidence instead of raw logs.**
4. **It creates a tighter learning loop by turning suggestions into small experiments.**

## A minimal first version

If this should start small, I would suggest beginning with just three things:

1. add `scaffold_version`, `task_slice`, `outcome`, `budget`, and `events` to the log schema;
2. add a script or workflow that generates `weekly_scaffold_review.md`;
3. define a minimal `failure taxonomy` and `Trace Card` schema.

Even that alone could already move the discussion from subjective impressions toward low-cost, evidence-based scaffold diagnosis.

If the maintainers think this direction is worthwhile, I would also be happy to help sketch a more concrete v1, such as:

- a `Trace Card` schema
- a first-pass `failure taxonomy`
- a `weekly_scaffold_review.md` template
- a constrained reviewer prompt structure
