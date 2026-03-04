# 功能 PR 工作流操作手册

本手册定义了如何从发生分叉的本地 `main` 中提取功能分支，并向 upstream 提交干净的 PR。

## 范围与规则

- 这是一套仅用于文档说明的工作流，用于功能提取与 PR 提交。
- 不要禁用或绕过 `hooks/loop-plan-file-validator.sh`。
- 在活跃的 RLCR 会话中不要切换分支。
- 永远不要对 `main` 进行强制推送（force-push）。
- 在完成一次性设置后，永远不要再用本地 `main` 作为同步分支；只使用 `upstream-main`。

## 1) Setup Milestone（一次性，强制）

### 1.1 Remote 重命名（必须是第一步）

```bash
git remote rename origin upstream
git remote rename zenus origin
git remote -v
```

重命名后的期望映射：

- `upstream` -> `https://github.com/humania-org/humanize.git`
- `origin` -> `https://github.com/ZenusZhang/humanize.git`

### 1.2 为当前本地 main 创建安全快照

```bash
SNAPSHOT_BRANCH="dev/main-snapshot-$(date +%Y%m%d)"
git switch main
git switch -c "$SNAPSHOT_BRANCH"
git push -u origin "$SNAPSHOT_BRANCH"
```

### 1.3 创建并维护 `upstream-main` 跟踪分支

```bash
git fetch upstream --prune
if git show-ref --verify --quiet refs/heads/upstream-main; then
  git switch upstream-main
  git merge --ff-only upstream/main
else
  git switch -c upstream-main --track upstream/main
fi
```

### 1.4 启用 rerere 以复用重复冲突的解决方案

```bash
git config rerere.enabled true
git config rerere.autoupdate true
git config --get rerere.enabled
git config --get rerere.autoupdate
```

## 2) 提交审计里程碑

### 2.1 验证分叉并查看 ahead 提交

```bash
git fetch upstream --prune
git rev-list --count upstream/main..main
git log --oneline --decorate upstream/main..main
```

在当前上下文中期望的计数：`66`。

### 2.2 验证 SHA 分配的权威来源

- 以 `docs/feature-commit-map.md` 作为 canonical map。
- 在提取前确认每个列出的 SHA 都存在：

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

## 3) 依赖 DAG 与提交顺序

依赖 DAG：

- `F1 -> F5 -> F6`
- `F1 -> F7`
- `F3 -> F4`
- `F2` 和 `F9` 相互独立

推荐 PR 顺序：

1. `F2`（`feat-gen-plan-convergence`）
2. `F1`（`feat-rlcr-loop-improvements`）
3. `F3`（`feat-task-graph`）
4. `F9`（`feat-misc`）
5. `F4`（`feat-gen-batch-prompt`，在 F3 之后）
6. `F5`（`feat-delegation-enforcement`，在 F1 之后）
7. `F6`（`feat-worktree-teams`，在 F1+F5 之后）
8. `F7`（`feat-bitlesson-rlcr-integration`，在 F1 之后）

建议的提取分支名与 base：

| 功能 | 分支名 | Base 分支 |
|---|---|---|
| F2 | `feat/gen-plan-convergence` | `upstream-main` |
| F1 | `feat/rlcr-loop-improvements` | `upstream-main` |
| F3 | `feat/task-graph` | `upstream-main` |
| F9 | `feat/misc` | `upstream-main` |
| F4 | `feat/gen-batch-prompt` | `feat/task-graph` |
| F5 | `feat/delegation-enforcement` | `feat/rlcr-loop-improvements` |
| F6 | `feat/worktree-teams` | `feat/delegation-enforcement` |
| F7 | `feat/bitlesson-rlcr-integration` | `feat/rlcr-loop-improvements` |

## 4) 提取循环（每个功能）

对映射表中的每个功能重复该循环。

### 4.1 选择 base 分支并创建功能分支

对独立功能使用 `upstream-main`。对有依赖的功能使用依赖的功能分支。

```bash
BASE_BRANCH="upstream-main"
FEATURE_BRANCH="feat/gen-plan-convergence"

git switch "$BASE_BRANCH"
git switch -c "$FEATURE_BRANCH"
```

### 4.2 Cherry-pick 候选提交（不自动提交）

使用 `docs/feature-commit-map.md` 中该功能分组的有序 SHA。

```bash
SHA_LIST=(c283a92 9c0eef7 5156a05)
git cherry-pick -n "${SHA_LIST[@]}"
```

如果发生冲突：

```bash
git status
# 解决冲突文件
git add path/to/resolved-file1 path/to/resolved-file2
git cherry-pick --continue
```

仅在需要时中止：

```bash
git cherry-pick --abort
```

### 4.3 空补丁检测（必需）

在 cherry-pick 之后立即运行，并在交互式暂存后再次运行。

```bash
if git diff --quiet && git diff --cached --quiet; then
  echo "Empty cherry-pick result. Stop and re-check SHA assignment."
  exit 1
fi
```

### 4.4 精选变更集（`add -p`）并提交

```bash
git add -p
if git diff --cached --quiet; then
  echo "Nothing staged. Do not create an empty commit."
  exit 1
fi
git commit -m "feat: extract scoped feature changes"
```

如果一次 cherry-pick 批次包含无关改动，请拆分成多个干净的提交。

### 4.5 版本号 bump 策略门（首个 PR 前确认）

在打开第一个功能 PR 之前，询问 upstream 维护者选择哪种策略：

- 选项 A：由贡献者在每个 PR 中管理版本 bump
- 选项 B：由维护者集中管理 bump（功能 PR 不做 bump）
- 选项 C：在发布分支上延后 bump

版本不变式（如果包含 bump，则必须始终成立）：

- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `README.md` 的 `Current Version:` 行

不变式检查命令：

```bash
v_plugin="$(jq -r '.version' .claude-plugin/plugin.json)"
v_market="$(jq -r '.version' .claude-plugin/marketplace.json)"
v_readme="$(sed -n 's/^Current Version:[[:space:]]*//p' README.md | head -n1)"
printf "plugin=%s\nmarketplace=%s\nreadme=%s\n" "$v_plugin" "$v_market" "$v_readme"
test "$v_plugin" = "$v_market" && test "$v_market" = "$v_readme"
```

避免并行 PR 冲突：

- 多个功能 PR 并行打开时，优先选项 B 或 C。
- 如果必须选项 A，将版本 bump 作为每个分支的最后一个提交，并在 push 前重新同步。

### 4.6 验证 diff 并运行相关测试

```bash
git log --oneline "$BASE_BRANCH"..HEAD
git diff --stat "$BASE_BRANCH"...HEAD
```

运行与功能相关的测试。示例：

```bash
pytest -q tests/test_task_graph.py
./tests/test-gen-plan.sh
./tests/test-gen-batch-prompt.sh
```

可选：运行完整套件：

```bash
./tests/run-all-tests.sh
```

### 4.7 Push 分支并创建 PR

```bash
git push -u origin "$FEATURE_BRANCH"
gh pr create \
  --repo humania-org/humanize \
  --base main \
  --head "ZenusZhang:$FEATURE_BRANCH" \
  --fill
```

PR 检查清单：

- 描述中引用功能 ID 与被提取的精确 SHA。
- 依赖链接清晰（适用于 F4/F5/F6/F7）。
- 说明版本策略选择。

## 5) 合并后同步（不要碰本地 `main`）

每次 upstream 合并后执行：

```bash
git fetch upstream --prune
git switch upstream-main
git merge --ff-only upstream/main
git push origin upstream-main
```

规则：

- 只在 `upstream-main` 上做合并后同步。
- 保持本地 `main` 冻结，作为历史提取的源分支。
- 不要 force-push `main`。

## 6) RLCR 兼容性

`hooks/loop-plan-file-validator.sh` 会在活跃的 RLCR 循环中强制分支一致性。

在活跃 RLCR 内：

- 允许：在 RLCR 启动分支上编辑/提交。
- 禁止：切换分支与功能提取。

在非活跃 RLCR 外：

- 允许完整的提取工作流。

必需策略：

- 在 RLCR 会话之外执行所有功能提取工作。
- 可以在 `feat/*` 分支上正常使用 RLCR 进行功能实现与迭代。

## 7) 错误恢复与 rerere 用法

冲突恢复：

```bash
git status
git cherry-pick --abort
```

丢弃当前分支上的未暂存与已暂存工作更改：

```bash
git restore --staged :/
git restore :/
```

从 reflog 恢复分支 tip：

```bash
git reflog --date=iso
GOOD_SHA="61e45a1"
git reset --hard "$GOOD_SHA"
```

rerere 行为：

- 第一次冲突解决需要手动完成。
- 重复出现的冲突模式会在 `rerere.enabled=true` 时自动复用应用。
- 在 rerere 辅助解决后重新运行测试。

