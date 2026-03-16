#!/bin/bash
#
# Manage branch-specific Humanize plugin worktrees and launch Claude with them.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
DEFAULT_SOURCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_WORKTREE_ROOT="${HUMANIZE_PLUGIN_WORKTREE_ROOT:-$HOME/.claude/plugin-sources/humanize-worktrees}"

log() {
    echo "[${SCRIPT_NAME}] $*" >&2
}

die() {
    echo "[${SCRIPT_NAME}] ERROR: $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage:
  ${SCRIPT_NAME} ensure --branch <branch> [--source <repo>] [--worktree-root <dir>]
  ${SCRIPT_NAME} path --branch <branch> [--worktree-root <dir>]
  ${SCRIPT_NAME} info [--plugin-dir <dir>]
  ${SCRIPT_NAME} list [--source <repo>]
  ${SCRIPT_NAME} launch --branch <branch> [--project <dir>] [--source <repo>] [--worktree-root <dir>] [--print-only] [-- <claude args>]

Commands:
  ensure     Create or reuse a dedicated plugin worktree for the target branch.
  path       Print the managed worktree path for the target branch.
  info       Print plugin identity details for a plugin directory.
  list       List Humanize repo worktrees with branch and path.
  launch     Launch Claude with the branch-specific plugin worktree via --plugin-dir.

Defaults:
  --source         ${DEFAULT_SOURCE_ROOT}
  --worktree-root  ${DEFAULT_WORKTREE_ROOT}
  --project        current working directory

Examples:
  ${SCRIPT_NAME} ensure --branch main
  ${SCRIPT_NAME} ensure --branch feat/refine-plan --worktree-root ~/wt/humanize
  ${SCRIPT_NAME} launch --branch main --project ~/projects/app
  ${SCRIPT_NAME} launch --branch feat/refine-plan --project ~/projects/app -- --model sonnet
EOF
}

sanitize_branch_name() {
    local branch="$1"
    branch="${branch//\//_}"
    branch="${branch//@/_}"
    branch="${branch//:/_}"
    branch="${branch// /_}"
    printf '%s' "$branch" | sed 's/[^A-Za-z0-9._-]/_/g'
}

resolve_dir() {
    local path="$1"
    [[ -n "$path" ]] || die "Expected a non-empty path"
    if [[ ! -d "$path" ]]; then
        die "Directory does not exist: $path"
    fi
    (cd "$path" && pwd)
}

resolve_source_root() {
    local source_root="${1:-$DEFAULT_SOURCE_ROOT}"
    source_root="$(resolve_dir "$source_root")"
    if ! git -C "$source_root" rev-parse --show-toplevel >/dev/null 2>&1; then
        die "Not a git repository: $source_root"
    fi
    git -C "$source_root" rev-parse --show-toplevel
}

read_plugin_version() {
    local plugin_dir="$1"
    local manifest="$plugin_dir/.claude-plugin/plugin.json"

    if [[ ! -f "$manifest" ]]; then
        echo ""
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$manifest" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print("")
    raise SystemExit(0)

print(data.get("version", ""))
PY
        return 0
    fi

    sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -1
}

worktree_path_for_branch() {
    local worktree_root="$1"
    local branch="$2"
    printf '%s/%s\n' "$worktree_root" "$(sanitize_branch_name "$branch")"
}

find_existing_worktree_for_branch() {
    local source_root="$1"
    local branch="$2"

    git -C "$source_root" worktree list --porcelain | awk -v target="refs/heads/${branch}" '
        $1 == "worktree" {
            path = $2
            next
        }
        $1 == "branch" && $2 == target {
            print path
            exit
        }
    '
}

resolve_tracking_ref() {
    local source_root="$1"
    local branch="$2"
    local remote_ref=""
    local refs=()

    mapfile -t refs < <(git -C "$source_root" for-each-ref --format='%(refname:short)' "refs/remotes/*/${branch}")

    if [[ ${#refs[@]} -eq 0 ]]; then
        echo ""
        return 0
    fi

    for remote_ref in "${refs[@]}"; do
        if [[ "$remote_ref" == "origin/${branch}" ]]; then
            echo "$remote_ref"
            return 0
        fi
    done

    if [[ ${#refs[@]} -eq 1 ]]; then
        echo "${refs[0]}"
        return 0
    fi

    die "Branch '$branch' is ambiguous across remotes: ${refs[*]}"
}

ensure_worktree() {
    local branch="$1"
    local source_root="$2"
    local worktree_root="$3"
    local existing=""
    local target_path=""
    local current_branch=""
    local tracking_ref=""

    [[ -n "$branch" ]] || die "--branch is required"
    source_root="$(resolve_source_root "$source_root")"
    mkdir -p "$worktree_root"
    worktree_root="$(resolve_dir "$worktree_root")"

    existing="$(find_existing_worktree_for_branch "$source_root" "$branch")"
    if [[ -n "$existing" ]]; then
        printf '%s\n' "$existing"
        return 0
    fi

    target_path="$(worktree_path_for_branch "$worktree_root" "$branch")"
    if [[ -e "$target_path" ]]; then
        if git -C "$target_path" rev-parse --show-toplevel >/dev/null 2>&1; then
            current_branch="$(git -C "$target_path" branch --show-current 2>/dev/null || true)"
            if [[ "$current_branch" == "$branch" ]]; then
                printf '%s\n' "$(resolve_dir "$target_path")"
                return 0
            fi
            die "Existing path uses another branch: $target_path ($current_branch)"
        fi
        die "Target path already exists and is not a git worktree: $target_path"
    fi

    if git -C "$source_root" show-ref --verify --quiet "refs/heads/${branch}"; then
        log "Creating worktree for local branch '$branch' at $target_path"
        git -C "$source_root" worktree add "$target_path" "$branch" >/dev/null
    else
        tracking_ref="$(resolve_tracking_ref "$source_root" "$branch")"
        [[ -n "$tracking_ref" ]] || die "Branch '$branch' not found locally or on remotes"
        log "Creating worktree for remote branch '$tracking_ref' at $target_path"
        git -C "$source_root" worktree add -b "$branch" "$target_path" "$tracking_ref" >/dev/null
    fi

    printf '%s\n' "$(resolve_dir "$target_path")"
}

print_plugin_info() {
    local plugin_dir="$1"
    local version=""
    local branch=""
    local commit=""
    local dirty="false"

    plugin_dir="$(resolve_dir "$plugin_dir")"
    version="$(read_plugin_version "$plugin_dir")"

    if git -C "$plugin_dir" rev-parse --show-toplevel >/dev/null 2>&1; then
        branch="$(git -C "$plugin_dir" branch --show-current 2>/dev/null || true)"
        commit="$(git -C "$plugin_dir" rev-parse --short HEAD 2>/dev/null || true)"
        if [[ -n "$(git -C "$plugin_dir" status --porcelain 2>/dev/null || true)" ]]; then
            dirty="true"
        fi
    fi

    printf 'plugin_dir=%s\n' "$plugin_dir"
    printf 'plugin_version=%s\n' "$version"
    printf 'plugin_branch=%s\n' "$branch"
    printf 'plugin_commit=%s\n' "$commit"
    printf 'plugin_dirty=%s\n' "$dirty"
}

list_worktrees() {
    local source_root="$1"

    source_root="$(resolve_source_root "$source_root")"
    git -C "$source_root" worktree list --porcelain | awk '
        $1 == "worktree" {
            path = $2
            branch = "(detached)"
            next
        }
        $1 == "branch" {
            branch = $2
            sub(/^refs\/heads\//, "", branch)
            next
        }
        /^$/ {
            if (path != "") {
                printf "%-24s %s\n", branch, path
            }
            path = ""
            branch = "(detached)"
        }
        END {
            if (path != "") {
                printf "%-24s %s\n", branch, path
            }
        }
    '
}

launch_claude() {
    local branch=""
    local source_root="$DEFAULT_SOURCE_ROOT"
    local worktree_root="$DEFAULT_WORKTREE_ROOT"
    local project_dir="$(pwd)"
    local print_only="false"
    local plugin_dir=""
    local version=""
    local commit=""
    local dirty=""
    local claude_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --branch)
                [[ $# -ge 2 ]] || die "--branch requires a value"
                branch="$2"
                shift 2
                ;;
            --source)
                [[ $# -ge 2 ]] || die "--source requires a value"
                source_root="$2"
                shift 2
                ;;
            --worktree-root)
                [[ $# -ge 2 ]] || die "--worktree-root requires a value"
                worktree_root="$2"
                shift 2
                ;;
            --project)
                [[ $# -ge 2 ]] || die "--project requires a value"
                project_dir="$2"
                shift 2
                ;;
            --print-only)
                print_only="true"
                shift
                ;;
            --)
                shift
                claude_args=("$@")
                break
                ;;
            *)
                die "Unknown launch option: $1"
                ;;
        esac
    done

    [[ -n "$branch" ]] || die "--branch is required for launch"
    plugin_dir="$(ensure_worktree "$branch" "$source_root" "$worktree_root")"
    project_dir="$(resolve_dir "$project_dir")"

    version="$(read_plugin_version "$plugin_dir")"
    if git -C "$plugin_dir" rev-parse --show-toplevel >/dev/null 2>&1; then
        commit="$(git -C "$plugin_dir" rev-parse --short HEAD 2>/dev/null || true)"
        dirty="false"
        if [[ -n "$(git -C "$plugin_dir" status --porcelain 2>/dev/null || true)" ]]; then
            dirty="true"
        fi
    else
        commit=""
        dirty="false"
    fi

    if [[ "$print_only" == "true" ]]; then
        printf 'project_dir=%s\n' "$project_dir"
        printf 'plugin_dir=%s\n' "$plugin_dir"
        printf 'plugin_branch=%s\n' "$branch"
        printf 'plugin_version=%s\n' "$version"
        printf 'plugin_commit=%s\n' "$commit"
        printf 'plugin_dirty=%s\n' "$dirty"
        return 0
    fi

    command -v claude >/dev/null 2>&1 || die "'claude' CLI is not in PATH"

    log "Project: ${project_dir}"
    log "Plugin: ${plugin_dir}"
    log "Plugin branch: ${branch}"
    if [[ -n "$version" ]]; then
        log "Plugin version: ${version}"
    fi
    if [[ -n "$commit" ]]; then
        log "Plugin commit: ${commit}"
    fi

    (
        cd "$project_dir"
        export HUMANIZE_PLUGIN_DIR="$plugin_dir"
        export HUMANIZE_PLUGIN_BRANCH="$branch"
        export HUMANIZE_PLUGIN_VERSION="$version"
        exec claude --plugin-dir "$plugin_dir" "${claude_args[@]}"
    )
}

main() {
    local command="${1:-}"
    local branch=""
    local source_root="$DEFAULT_SOURCE_ROOT"
    local worktree_root="$DEFAULT_WORKTREE_ROOT"
    local plugin_dir=""

    case "$command" in
        ensure)
            shift
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --branch)
                        [[ $# -ge 2 ]] || die "--branch requires a value"
                        branch="$2"
                        shift 2
                        ;;
                    --source)
                        [[ $# -ge 2 ]] || die "--source requires a value"
                        source_root="$2"
                        shift 2
                        ;;
                    --worktree-root)
                        [[ $# -ge 2 ]] || die "--worktree-root requires a value"
                        worktree_root="$2"
                        shift 2
                        ;;
                    *)
                        die "Unknown ensure option: $1"
                        ;;
                esac
            done
            ensure_worktree "$branch" "$source_root" "$worktree_root"
            ;;
        path)
            shift
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --branch)
                        [[ $# -ge 2 ]] || die "--branch requires a value"
                        branch="$2"
                        shift 2
                        ;;
                    --worktree-root)
                        [[ $# -ge 2 ]] || die "--worktree-root requires a value"
                        worktree_root="$2"
                        shift 2
                        ;;
                    *)
                        die "Unknown path option: $1"
                        ;;
                esac
            done
            [[ -n "$branch" ]] || die "--branch is required"
            worktree_root="$(resolve_dir "$(mkdir -p "$worktree_root" && printf '%s' "$worktree_root")")"
            worktree_path_for_branch "$worktree_root" "$branch"
            ;;
        info)
            shift
            plugin_dir="${DEFAULT_SOURCE_ROOT}"
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --plugin-dir)
                        [[ $# -ge 2 ]] || die "--plugin-dir requires a value"
                        plugin_dir="$2"
                        shift 2
                        ;;
                    *)
                        die "Unknown info option: $1"
                        ;;
                esac
            done
            print_plugin_info "$plugin_dir"
            ;;
        list)
            shift
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --source)
                        [[ $# -ge 2 ]] || die "--source requires a value"
                        source_root="$2"
                        shift 2
                        ;;
                    *)
                        die "Unknown list option: $1"
                        ;;
                esac
            done
            list_worktrees "$source_root"
            ;;
        launch)
            shift
            launch_claude "$@"
            ;;
        -h|--help|help|"")
            usage
            ;;
        *)
            die "Unknown command: $command"
            ;;
    esac
}

main "$@"
