# Install Humanize for Claude Code

## Prerequisites

- [codex](https://github.com/openai/codex) -- OpenAI Codex CLI (for review). Verify with `codex --version`.
- `jq` -- JSON processor. Verify with `jq --version`.
- `git` -- Git version control. Verify with `git --version`.

## Option 1: Git Marketplace (Recommended)

Start Claude Code and run:

```bash
# Add the marketplace
/plugin marketplace add git@github.com:humania-org/humanize.git

# Install the plugin
/plugin install humanize@humania
```

## Option 2: Local Development

If you have the plugin cloned locally:

```bash
claude --plugin-dir /path/to/humanize
```

### Recommended Branch Workflow

If you actively switch between `main` and feature branches, do not keep reinstalling the plugin.
Use branch-specific git worktrees and launch Claude with the matching plugin directory instead:

```bash
# Ensure a dedicated plugin worktree for a branch
scripts/humanize-plugin-worktree.sh ensure --branch main
scripts/humanize-plugin-worktree.sh ensure --branch feat/refine-plan

# Launch Claude against a target project with the selected plugin branch
scripts/humanize-plugin-worktree.sh launch --branch main --project /path/to/target-project
scripts/humanize-plugin-worktree.sh launch --branch feat/refine-plan --project /path/to/target-project
```

Why this is better:

- No repeated `/plugin install` step when switching plugin branches
- Each branch gets a stable, dedicated plugin path
- The bundled `statusline.sh` now shows `Plugin: <branch>@<commit>` so you can immediately tell which Humanize branch Claude is running

Useful helpers:

```bash
# Show all Humanize repo worktrees
scripts/humanize-plugin-worktree.sh list

# Inspect the plugin identity for a worktree or install copy
scripts/humanize-plugin-worktree.sh info --plugin-dir ~/.claude/plugin-sources/humanize-worktrees/feat_refine-plan
```

## Option 3: Try Experimental Features (dev branch)

The `dev` branch contains experimental features that are not yet released to `main`. To try them locally:

```bash
git clone https://github.com/humania-org/humanize.git
cd humanize
git checkout dev
```

Then start Claude Code with the local plugin directory:

```bash
claude --plugin-dir /path/to/humanize
```

Note: The `dev` branch may contain unstable or incomplete features. For production use, stick with Option 1 (Git Marketplace) which tracks the stable `main` branch.

## Verify Installation

After installing, you should see Humanize commands available:

```
/humanize:start-rlcr-loop
/humanize:gen-plan
/humanize:refine-plan
/humanize:ask-codex
```

## Monitor Setup (Optional)

Add the monitoring helper to your shell for real-time progress tracking:

```bash
# Add to your .bashrc or .zshrc
source ~/.claude/plugins/cache/humania/humanize/<LATEST.VERSION>/scripts/humanize.sh
```

Then use:

```bash
humanize monitor rlcr   # Monitor RLCR loop
humanize monitor pr     # Monitor PR loop
```

## Other Install Guides

- [Install for Codex](install-for-codex.md)
- [Install for Kimi](install-for-kimi.md)

## Next Steps

See the [Usage Guide](usage.md) for detailed command reference and configuration options.
