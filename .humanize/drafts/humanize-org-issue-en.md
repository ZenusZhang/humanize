# [Proposal] Consider adding a low-cost scaffold review workflow based on run logs

> Note: this write-up is based on a prior Chinese discussion and is being shared here, per the original framing, as a "GPT-5.4 Pro proposal" for discussion.

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

## Workflow details

### 0. Prepare the inputs

Each run should keep at least these fields:

- `session_id`
- `scaffold_version`
- `model_version`
- `task_id`
- `task_slice`
- `repo / language / task_size`
- `events[]`: plan, search, read, edit, test, review, refine, stop, handoff
- `artifacts`: diff, test results, review comments
- `outcome`: success / failure / false finish / human takeover
- `cost`: tokens, latency, number of turns
- `budget`: the token / time budget given to the agent for that run

There are also two useful static inputs:

- **current scaffold spec**: planner, search, builder, reviewer, refiner, stop policy, escalation rule, memory policy
- **task taxonomy**: for example `small-fix / multifile / debug / review-only / resume / refactor`

The most important point is: **logs need to be connected to scaffold versions**. Otherwise reviewers can describe symptoms, but they cannot attribute them.

### 1. Clean, redact, and normalize

It probably makes sense not to feed raw logs directly into a strong model.

First do three things:

- redact sensitive data such as secrets, paths, customer data, and internal URLs
- normalize different agent / event formats into a single schema
- segment the data by session, task, and review loop

A natural output artifact could be `normalized_sessions.jsonl`.

### 2. Run a cheap metric pre-screen

This layer does not need a strong model. Programmatic analysis is likely enough.

Some useful metrics might be:

**Fit**

- success rate by task slice
- `tokens_per_success` by slice
- human takeover rate by slice

**Flow**

- `time_to_first_read`
- `time_to_first_useful_edit`
- `search_steps_before_first_edit`
- `review_loop_count`

**Friction**

- repeated reads of the same file
- repeated execution of the same failing command
- similar unproductive searches
- diff rollback / rewrite count

**Feedback**

- `false_finish_rate`
- rate of “claimed done, but tests still failed”
- rate of critical issues only found in the second review round
- frequency of repeated failure patterns

At this stage the main question is simple:

**what actually got worse this week, and what was just task-mix drift?**

### 3. Use stratified sampling instead of reading all logs

This seems like the key cost-control step.

Rather than letting a reviewer consume all logs, sample only **representative cases**. One useful first pass might be six buckets:

- cheap success
- expensive success
- cheap failure
- expensive failure
- false finish
- human takeover

Then do a second layer of sampling by `task_slice`, for example:

- single-file fixes
- multi-file changes
- debugging / test repair
- resume-from-partial
- tasks with heavy reviewer / refiner involvement

A weekly sample of roughly 24–40 sessions may already be enough. Coverage across categories likely matters more than raw volume.

### 4. Generate a Trace Card for each sampled session

A cheap model, ideally a local one, could first generate a short card for each session.

Each `Trace Card` could include:

- what the task was
- which scaffold stages were used
- where the run started to drift
- which actions created value
- which actions were pure waste
- whether verification was sufficient
- the most likely failure tags
- short evidence references

For example:

```yaml
session_id: xxx
task_slice: multifile-debug
outcome: false_finish
summary: >
  The agent located module A quickly, but repeated search on module B six times;
  the reviewer pointed out missing test coverage, but the refiner did not add new verification;
  the stop rule triggered too early.
failure_tags:
  - SEARCH_THRASH
  - VERIFICATION_GAP
  - EARLY_STOP
evidence:
  - turn_14: repeated grep on same path
  - turn_27: reviewer requests missing edge-case test
  - turn_31: stop without rerun of failing suite
```

This step feels especially important because the stronger reviewer should ideally read **Trace Cards + metrics + scaffold spec**, not raw long logs.

### 5. Session Reviewer: score one session at a time

At this layer, the reviewer only looks at a single session and does not try to make global conclusions.

It does two things:

**A. Score the session with a rubric**

- Fit: was this scaffold too heavy or too light for the task?
- Flow: were the handoffs smooth?
- Friction: was there obvious mechanical waste?
- Feedback: were errors detected and corrected?
- Governance: were stop / escalate / review permissions placed appropriately?

**B. Apply failure taxonomy tags**

A fixed taxonomy might include labels like:

- `OVER_PLANNING`
- `UNDER_PLANNING`
- `SEARCH_THRASH`
- `CONTEXT_AMNESIA`
- `VERIFICATION_GAP`
- `REVIEW_THEATER`
- `EARLY_STOP`
- `LATE_ESCALATION`
- `TOOL_MISMATCH`
- `BAD_ROLE_BOUNDARY`

One useful guardrail here is that the Session Reviewer should not jump straight to “change the prompt.” It should stay focused on symptoms and evidence.

### 6. Scaffold Reviewer: diagnose mechanisms across sessions

This is the core layer.

Instead of looking at one session, it looks across:

- weekly metrics
- distribution by slice
- 24–40 Trace Cards
- the current scaffold spec
- the previous review report

Then it produces three kinds of output.

**1. Repeated patterns**

For example:

- small tasks still go through the full build-review-refine path and waste cycles
- the reviewer often flags insufficient verification, but the refiner cannot actually add verification
- search works reasonably well on multi-file tasks, but the stop policy is too aggressive

**2. Attribution to scaffold components**

For example:

- the issue is not necessarily weak model capability, but loss of actionable requirements in the `reviewer -> refiner` handoff
- the issue is not necessarily poor search, but over-fragmented planning that breaks context apart
- the issue is not necessarily that reviewer adds no value, but that trivial tasks should not always invoke reviewer

**3. No more than 3 change proposals**

Each proposal should include five fields:

- which module to change
- which failure mode it addresses
- which metric it aims to improve
- possible side effects
- how to falsify it cheaply

For example:

```yaml
proposal:
  title: "Skip reviewer for single-file fixes"
  target_module: review_trigger_policy
  expected_gain:
    - lower tokens_per_success on small-fix
    - lower latency
  risk:
    - miss subtle regression on edge cases
  falsification_test:
    - A/B on small-fix slice for 1 week
    - guardrail: false_finish_rate must not increase > 1pp
```

### 7. Counter Reviewer: a structured dissent pass

This layer feels important because AI reviewers can otherwise sound persuasive while still drifting toward weak recommendations.

The Counter Reviewer does one job:

**try to refute the previous reviewer’s conclusion.**

In particular, it checks for confounders such as:

- task distribution changed, not scaffold quality
- model version changed, not scaffold quality
- infra / sandbox / timeout noise
- weak labels causing model-capability problems to be mistaken for scaffold problems

Only recommendations that still stand after this pass should move into the action list.

### 8. Human Triage: maintainers choose a small number of experiments

This layer probably does not need a large review meeting.

The goal is simple: **pick only 1–2 experiments at a time.**

The meeting output could be limited to:

- what not to change this week
- what to change this week
- how success will be judged

It may be better not to let AI propose six changes at once, because then it becomes hard to know which one actually worked.

### 9. Run experiments and close the loop

Each accepted proposal can be turned into a small experiment with:

- the target task slice
- the affected scaffold module
- primary metrics
- guardrail metrics
- experiment duration
- whether gradual rollout / shadow run is needed

After the experiment, write the result back into the review archive:

- was the proposal confirmed or falsified?
- did a new failure mode appear?
- does the taxonomy need to expand?

That is what would allow the reviewer workflow to gradually learn the system, instead of starting from zero every week.

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
