# [Proposal] Add a low-cost scaffold review workflow based on run logs

## Background

As projects like `humanize` grow into real-world agent scaffolds, more contributors will naturally add new features, roles, and workflows. The hard part is not making changes — it is evaluating whether those changes actually improve the system.

One natural idea is to build a CI-like check that runs scaffold changes against “real” development workloads. But there are two practical issues:

1. It is hard to choose workloads that are genuinely representative.
2. If the workloads are large and realistic, the token cost becomes too high for frequent evaluation.

I think there is a useful reframing here: instead of treating scaffold changes purely as “prompt/agent capability tweaks,” we can evaluate them as an **organizational design** problem.

In other words, the key question is not just “is this scaffold more sophisticated?” but:

- Does it fit the actual task distribution?
- Does it improve information flow and decision flow?
- Does it reduce coordination friction such as repeated search, repeated review, and repeated trial-and-error?
- Does it help the system surface failures earlier and reuse successful patterns more reliably?

I would summarize this evaluation lens into four dimensions:

- **Fit**: does the scaffold match the real task mix?
- **Flow**: are information flow, decision flow, and handoffs working well?
- **Friction**: where are we wasting effort through loops, queues, or duplicate work?
- **Feedback**: are failures caught early, and are wins made reusable?

The benefit of this framing is that it does not require a giant “real benchmark” every time. It lets us use existing run logs as evidence to continuously diagnose whether the scaffold design is improving or regressing.

## Proposed change

I would suggest adding a **low-cost periodic scaffold review workflow** on top of the existing logging / trace system, starting with a lightweight v1.

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

The most important point is: **logs must be attributable to a specific scaffold version**. Otherwise the analysis can describe symptoms, but not attribute them to a concrete change.

### 2. Run cheap metric screening daily

Do not send full logs to a strong model by default. First run programmatic metrics over all runs, for example:

- `success@budget`
- `tokens_per_success`
- `false_finish_rate`
- `human_takeover_rate`
- `search_steps_before_first_edit`
- `review_loop_count`
- repeated reads of the same file / repeated execution of the same failing command

The goal here is not to generate recommendations yet. It is to answer: **did the scaffold actually get worse, or did the task mix change?**

### 3. Sample weekly instead of reviewing all raw logs

To control cost, do stratified sampling over outcomes and task types — for example 20–40 sessions covering:

- cheap successes
- expensive successes
- cheap failures
- expensive failures
- false finishes
- human takeovers

This is much cheaper and usually more stable than feeding an entire week of raw logs into a model.

### 4. Generate Trace Cards before higher-level review

Use a cheap or local model to compress each sampled session into a structured `Trace Card`, keeping only:

- what the task was
- which scaffold phases were used
- where the run started to drift
- which actions added value
- which actions were pure waste
- whether verification was sufficient
- the most likely failure tag
- short evidence references

Then let a stronger model review only:

- metric summaries
- Trace Cards
- the current scaffold spec
- the previous review report

instead of full raw logs.

### 5. Constrain review output into falsifiable experiment proposals

Each weekly review should produce at most 1–3 proposed changes, and every proposal should map explicitly to:

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

If a recommendation cannot be written in this format, it is probably still an observation rather than an actionable change.

## Why this seems useful

I think this workflow would help `humanize` in four ways:

1. **It evaluates the whole scaffold, not just model capability.**
2. **It scales better as more contributors propose changes.**
3. **It controls token cost by reviewing compressed evidence instead of raw logs.**
4. **It creates a tighter learning loop by turning suggestions into small experiments.**

## A minimal first version

If this should start small, I would begin with just three things:

1. add `scaffold_version`, `task_slice`, `outcome`, `budget`, and `events` to the log schema;
2. add a script or workflow that generates `weekly_scaffold_review.md`;
3. define a minimal `failure taxonomy` and `Trace Card` schema.

That alone would already move the discussion from subjective impressions toward low-cost, evidence-based scaffold diagnosis.

If this direction sounds useful, I would be happy to help sketch a more concrete v1, such as:

- a `Trace Card` schema
- a first-pass `failure taxonomy`
- a `weekly_scaffold_review.md` template
- a constrained reviewer prompt structure
