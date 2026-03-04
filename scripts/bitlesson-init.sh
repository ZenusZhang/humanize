#!/bin/bash

set -euo pipefail

usage() {
    cat <<'USAGE_EOF' >&2
Usage:
  bitlesson-init.sh --project-root <dir> --template <path> [--bitlesson-relpath <relpath>]

Behavior:
  - Default bitlesson-relpath: bitlesson.md
  - Creates <project-root>/<bitlesson-relpath> from template if missing
  - Does not overwrite existing file
  - Falls back to inline template if --template does not exist
  - Prints the resolved bitlesson file path to stdout on success
USAGE_EOF
}

PROJECT_ROOT=""
TEMPLATE_PATH=""
BITLESSON_RELPATH="bitlesson.md"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --project-root)
            PROJECT_ROOT="${2:-}"
            shift 2
            ;;
        --template)
            TEMPLATE_PATH="${2:-}"
            shift 2
            ;;
        --bitlesson-relpath)
            BITLESSON_RELPATH="${2:-}"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "Error: --project-root is required" >&2
    usage
    exit 1
fi

if [[ -z "$TEMPLATE_PATH" ]]; then
    echo "Error: --template is required" >&2
    usage
    exit 1
fi

if [[ ! -d "$PROJECT_ROOT" ]]; then
    echo "Error: --project-root must be an existing directory: $PROJECT_ROOT" >&2
    exit 1
fi

PROJECT_ROOT_ABS="$(cd "$PROJECT_ROOT" && pwd -P)"
BITLESSON_FILE="$PROJECT_ROOT_ABS/$BITLESSON_RELPATH"

if [[ -e "$BITLESSON_FILE" && ! -f "$BITLESSON_FILE" ]]; then
    echo "Error: BitLesson path exists but is not a regular file: $BITLESSON_FILE" >&2
    exit 1
fi

if [[ ! -f "$BITLESSON_FILE" ]]; then
    mkdir -p "$(dirname "$BITLESSON_FILE")"
    if [[ -f "$TEMPLATE_PATH" ]]; then
        cp "$TEMPLATE_PATH" "$BITLESSON_FILE"
    else
        cat > "$BITLESSON_FILE" << 'BITLESSON_EOF'
# BitLesson Knowledge Base

This file is project-specific. Keep entries precise and reusable for future rounds.

## Entry Template (Strict)

Use this exact field order for every entry:

```markdown
## Lesson: <unique-id>
Lesson ID: <BL-YYYYMMDD-short-name>
Scope: <component/subsystem/files>
Problem Description: <specific failure mode with trigger conditions>
Root Cause: <direct technical cause>
Solution: <exact fix that resolved the problem>
Constraints: <limits, assumptions, non-goals>
Validation Evidence: <tests/commands/logs/PR evidence>
Source Rounds: <round numbers where problem appeared and was solved>
```

## Entries

<!-- Add lessons below using the strict template. -->
BITLESSON_EOF
    fi
fi

printf '%s\n' "$BITLESSON_FILE"
