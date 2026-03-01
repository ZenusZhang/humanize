#!/bin/bash
#
# Update installed Claude humanize plugin(s) and sync cache to current development copy.
#
# Usage:
#   scripts/update_human.sh
#   scripts/update_human.sh --source /path/to/humanize
#

set -euo pipefail

PLUGIN_ID="humanize@humania"
CLAUDE_PLUGINS_DIR="${HOME}/.claude/plugins"
INSTALLED_JSON="${CLAUDE_PLUGINS_DIR}/installed_plugins.json"
KNOWN_MARKETPLACES_JSON="${CLAUDE_PLUGINS_DIR}/known_marketplaces.json"

log() {
    echo "[update_human] $*"
}

warn() {
    echo "[update_human] WARNING: $*" >&2
}

die() {
    echo "[update_human] ERROR: $*" >&2
    exit 1
}

SOURCE_ROOT="${UPDATE_HUMAN_SOURCE_ROOT:-}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            [[ $# -ge 2 ]] || die "--source requires a path"
            SOURCE_ROOT="$2"
            shift 2
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

command -v claude >/dev/null 2>&1 || die "'claude' CLI is not in PATH"

if [[ -z "$SOURCE_ROOT" && -f "$KNOWN_MARKETPLACES_JSON" ]]; then
    if command -v python3 >/dev/null 2>&1; then
        SOURCE_ROOT=$(python3 - "$KNOWN_MARKETPLACES_JSON" <<'PY'
import json
import os
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print("")
    raise SystemExit(0)

entry = data.get("humania", {})
source = entry.get("source", {})
if source.get("source") != "file":
    print("")
    raise SystemExit(0)

marketplace_json = source.get("path", "")
if not marketplace_json:
    print("")
    raise SystemExit(0)

root = os.path.dirname(os.path.dirname(os.path.abspath(marketplace_json)))
print(root)
PY
)
    fi
fi

if [[ -z "$SOURCE_ROOT" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    SOURCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

SOURCE_ROOT="$(cd "$SOURCE_ROOT" && pwd)"
PLUGIN_JSON="${SOURCE_ROOT}/.claude-plugin/plugin.json"
[[ -f "$PLUGIN_JSON" ]] || die "Cannot find plugin manifest: $PLUGIN_JSON"

if ! command -v python3 >/dev/null 2>&1; then
    die "python3 is required to parse plugin metadata JSON"
fi

PLUGIN_VERSION=$(python3 - "$PLUGIN_JSON" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
print(data.get("version", ""))
PY
)
[[ -n "$PLUGIN_VERSION" ]] || die "Failed to read plugin version from $PLUGIN_JSON"

log "Source root: ${SOURCE_ROOT}"
log "Target version: ${PLUGIN_VERSION}"

log "Updating user-scope plugin via Claude CLI..."
if ! claude plugin update "$PLUGIN_ID" -s user; then
    warn "User-scope update failed; continuing with cache sync"
fi

PROJECT_PATHS=()
if [[ -f "$INSTALLED_JSON" ]]; then
    mapfile -t PROJECT_PATHS < <(python3 - "$INSTALLED_JSON" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    raise SystemExit(0)

for item in data.get("plugins", {}).get("humanize@humania", []):
    if item.get("scope") == "project":
        p = item.get("projectPath")
        if p:
            print(p)
PY
)
fi

if [[ ${#PROJECT_PATHS[@]} -gt 0 ]]; then
    declare -A SEEN=()
    for project_path in "${PROJECT_PATHS[@]}"; do
        [[ -n "$project_path" ]] || continue
        if [[ -n "${SEEN[$project_path]:-}" ]]; then
            continue
        fi
        SEEN[$project_path]=1
        if [[ ! -d "$project_path" ]]; then
            warn "Skipping missing project path: $project_path"
            continue
        fi
        log "Updating project-scope plugin in: $project_path"
        if ! (cd "$project_path" && claude plugin update "$PLUGIN_ID" -s project); then
            warn "Project-scope update failed in: $project_path"
        fi
    done
fi

CACHE_DIR="${HOME}/.claude/plugins/cache/humania/humanize/${PLUGIN_VERSION}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log "Syncing source tree to cache: $CACHE_DIR"
mkdir -p "$TMP_DIR/src"
tar \
    --exclude='.git' \
    --exclude='.humanize' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    -cf - -C "$SOURCE_ROOT" . | tar -xf - -C "$TMP_DIR/src"

mkdir -p "$CACHE_DIR"
find "$CACHE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a "$TMP_DIR/src"/. "$CACHE_DIR"/

log "Update complete."
claude plugin list | sed -n '/humanize@humania/,+3p'
