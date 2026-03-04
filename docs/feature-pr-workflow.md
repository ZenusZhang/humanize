# Feature PR Workflow Runbook

This runbook defines how to extract feature branches from a diverged local `main` and submit clean PRs to upstream.

## Scope and Rules

- This is a documentation-only workflow for feature extraction and PR submission.
- Do not disable or bypass `hooks/loop-plan-file-validator.sh`.
- Do not switch branches inside an active RLCR session.
- Never force-push `main`.
- Never use local `main` as the sync branch after setup; use `upstream-main` only.

## 1) Setup Milestone (One-Time, Mandatory)

### 1.1 Remote rename (must be the first setup step)

```bash
git remote rename origin upstream
git remote rename zenus origin
git remote -v
```

Expected mapping after rename:

- `upstream` -> `https://github.com/humania-org/humanize.git`
- `origin` -> `https://github.com/ZenusZhang/humanize.git`

### 1.2 Create safety snapshot of current local main

```bash
SNAPSHOT_BRANCH="dev/main-snapshot-$(date +%Y%m%d)"
git switch main
git switch -c "$SNAPSHOT_BRANCH"
git push -u origin "$SNAPSHOT_BRANCH"
```

### 1.3 Create and maintain `upstream-main` tracking branch

```bash
git fetch upstream --prune
if git show-ref --verify --quiet refs/heads/upstream-main; then
  git switch upstream-main
  git merge --ff-only upstream/main
else
  git switch -c upstream-main --track upstream/main
fi
```

### 1.4 Enable rerere for repeated conflict reuse

```bash
git config rerere.enabled true
git config rerere.autoupdate true
git config --get rerere.enabled
git config --get rerere.autoupdate
```

## 2) Commit Audit Milestone

### 2.1 Validate divergence and review ahead commits

```bash
git fetch upstream --prune
git rev-list --count upstream/main..main
git log --oneline --decorate upstream/main..main
```

Expected count for this context: `66`.

### 2.2 Validate SHA assignment source of truth

- Use [docs/feature-commit-map.md](/home/dyzhang/projects/pytorch_qemu/humanize/docs/feature-commit-map.md) as the canonical map.
- Confirm every listed SHA exists before extraction:

```bash
cat <<'EOF' >/tmp/feature-shas.txt
61e45a1
c5378a6
0a7b4fe
5678449
bc1c135
09b1134
07d67bf
c283a92
9c0eef7
5156a05
002308a
8ba3a57
437567b
3c8caf5
4a57429
821f225
ca96484
9920412
81e617b
fed29d9
60dadca
b0747b3
e8e3255
1abe1e4
2685897
cf5725b
97b280e
0c0716b
fdc5132
ac570d5
b0f9aaa
ebcd1f0
d9138d5
96ce1f5
766e619
1a57574
ae2c56b
6e86b65
a5f94fc
c8d484a
7c128c4
f8e4bb5
df534b2
0504e25
ee70f4d
111bfde
857878e
e81f3ab
d5143d7
6618a53
4b5a1ff
dfbc525
a4942a8
a0fb925
b6de551
3e6be9c
f34d79c
a92dc71
4fc73c3
99d04d8
ccc0ef5
4d0cc7b
8892c39
4410871
dbf6a6a
14544de
EOF

while read -r sha; do
  git cat-file -e "${sha}^{commit}" || echo "MISSING $sha"
done </tmp/feature-shas.txt
```

## 3) Dependency DAG and Submission Order

Dependency DAG:

- `F1 -> F5 -> F6`
- `F1 -> F7`
- `F3 -> F4`
- `F2` and `F9` are independent

Recommended PR order:

1. `F2` (`feat-gen-plan-convergence`)
2. `F1` (`feat-rlcr-loop-improvements`)
3. `F3` (`feat-task-graph`)
4. `F9` (`feat-misc`)
5. `F4` (`feat-gen-batch-prompt`, after F3)
6. `F5` (`feat-delegation-enforcement`, after F1)
7. `F6` (`feat-worktree-teams`, after F1+F5)
8. `F7` (`feat-bitlesson-rlcr-integration`, after F1)

Suggested extraction branch names and bases:

| Feature | Branch Name | Base Branch |
|---|---|---|
| F2 | `feat/gen-plan-convergence` | `upstream-main` |
| F1 | `feat/rlcr-loop-improvements` | `upstream-main` |
| F3 | `feat/task-graph` | `upstream-main` |
| F9 | `feat/misc` | `upstream-main` |
| F4 | `feat/gen-batch-prompt` | `feat/task-graph` |
| F5 | `feat/delegation-enforcement` | `feat/rlcr-loop-improvements` |
| F6 | `feat/worktree-teams` | `feat/delegation-enforcement` |
| F7 | `feat/bitlesson-rlcr-integration` | `feat/rlcr-loop-improvements` |

## 4) Extraction Cycle (Per Feature)

Repeat this cycle for each feature from the map.

### 4.1 Choose base branch and create feature branch

Use `upstream-main` for independent features. Use the dependency feature branch for dependent features.

```bash
BASE_BRANCH="upstream-main"
FEATURE_BRANCH="feat/gen-plan-convergence"

git switch "$BASE_BRANCH"
git switch -c "$FEATURE_BRANCH"
```

### 4.2 Cherry-pick candidate commits without auto-commit

Use ordered SHAs from the feature group in [docs/feature-commit-map.md](/home/dyzhang/projects/pytorch_qemu/humanize/docs/feature-commit-map.md).

```bash
SHA_LIST=(c283a92 9c0eef7 5156a05)
git cherry-pick -n "${SHA_LIST[@]}"
```

If conflicts happen:

```bash
git status
# resolve files
git add path/to/resolved-file1 path/to/resolved-file2
git cherry-pick --continue
```

Abort only when needed:

```bash
git cherry-pick --abort
```

### 4.3 Empty patch detection (required)

Run immediately after cherry-pick and again after interactive staging.

```bash
if git diff --quiet && git diff --cached --quiet; then
  echo "Empty cherry-pick result. Stop and re-check SHA assignment."
  exit 1
fi
```

### 4.4 Curate change set (`add -p`) and commit

```bash
git add -p
if git diff --cached --quiet; then
  echo "Nothing staged. Do not create an empty commit."
  exit 1
fi
git commit -m "feat: extract scoped feature changes"
```

Split into multiple clean commits if one cherry-pick batch contains unrelated changes.

### 4.5 Version bump policy gate (confirm before first PR)

Before opening the first feature PR, ask upstream maintainer which strategy to use:

- Option A: Contributor-managed per PR version bumps
- Option B: Maintainer-managed central bumping (no bump in feature PRs)
- Option C: Deferred bumping on release branches

Version invariant (must always hold if a bump is included):

- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `README.md` `Current Version:` line

Invariant check command:

```bash
v_plugin="$(jq -r '.version' .claude-plugin/plugin.json)"
v_market="$(jq -r '.version' .claude-plugin/marketplace.json)"
v_readme="$(sed -n 's/^Current Version:[[:space:]]*//p' README.md | head -n1)"
printf "plugin=%s\nmarketplace=%s\nreadme=%s\n" "$v_plugin" "$v_market" "$v_readme"
test "$v_plugin" = "$v_market" && test "$v_market" = "$v_readme"
```

Concurrent PR conflict avoidance:

- Prefer Option B or C when multiple feature PRs are open at the same time.
- If Option A is required, keep version bump as the final commit in each branch and re-sync before pushing.

### 4.6 Verify diff and run relevant tests

```bash
git log --oneline "$BASE_BRANCH"..HEAD
git diff --stat "$BASE_BRANCH"...HEAD
```

Run tests relevant to the feature. Examples:

```bash
pytest -q tests/test_task_graph.py
./tests/test-gen-plan.sh
./tests/test-gen-batch-prompt.sh
```

Optional full suite:

```bash
./tests/run-all-tests.sh
```

### 4.7 Push branch and open PR

```bash
git push -u origin "$FEATURE_BRANCH"
gh pr create \
  --repo humania-org/humanize \
  --base main \
  --head "ZenusZhang:$FEATURE_BRANCH" \
  --fill
```

PR checklist:

- Description references feature ID and exact SHAs extracted.
- Dependency links are explicit (for F4/F5/F6/F7).
- Version policy choice is stated.

## 5) Post-Merge Sync (Never Touch Local `main`)

After each upstream merge:

```bash
git fetch upstream --prune
git switch upstream-main
git merge --ff-only upstream/main
git push origin upstream-main
```

Rules:

- Run post-merge sync on `upstream-main` only.
- Keep local `main` as the frozen source branch for historical extraction.
- Do not force-push `main`.

## 6) RLCR Compatibility

`hooks/loop-plan-file-validator.sh` enforces branch consistency during active RLCR loops.

Inside active RLCR:

- Allowed: edit/commit on the RLCR start branch.
- Forbidden: branch switching and feature extraction.

Outside active RLCR:

- Full extraction workflow is allowed.

Required policy:

- Perform all feature extraction work outside RLCR sessions.
- RLCR can be used normally on `feat/*` branches for feature implementation and iteration.

## 7) Error Recovery and rerere Usage

Conflict recovery:

```bash
git status
git cherry-pick --abort
```

Discard unstaged and staged working changes on current branch:

```bash
git restore --staged :/
git restore :/
```

Recover branch tip from reflog:

```bash
git reflog --date=iso
GOOD_SHA="61e45a1"
git reset --hard "$GOOD_SHA"
```

rerere behavior:

- First conflict resolution is manual.
- Repeated conflict patterns are auto-reapplied when `rerere.enabled=true`.
- Re-run tests after rerere-assisted resolutions.
