#!/usr/bin/env bash
# Prints a JSON array of tool names (directories under tools/ with a <name>.containerfile).
#
#   list-tools.sh                  all tools
#   list-tools.sh <base> <head>    tools changed between two commits; all tools if
#                                  .github/workflows or .github/scripts changed, or if
#                                  <base> is missing/unknown (e.g. first push)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

all_tools() {
  for f in tools/*/*.containerfile; do
    [[ -e "$f" ]] || continue
    dir="$(basename "$(dirname "$f")")"
    [[ "$(basename "$f")" == "$dir.containerfile" ]] && echo "$dir"
  done
}

to_json() { sort -u | jq -R . | jq -sc 'map(select(length > 0))'; }

base="${1:-}"
head="${2:-}"

if [[ -z "$base" || "$base" =~ ^0+$ ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  all_tools | to_json
  exit 0
fi

changed="$(git diff --name-only "$base" "$head")"

if grep -qE '^\.github/(workflows|scripts)/' <<<"$changed"; then
  all_tools | to_json
  exit 0
fi

# Only keep changed tools that still exist (a deleted tool has nothing to build).
existing="$(all_tools)"
sed -n 's|^tools/\([^/]*\)/.*|\1|p' <<<"$changed" \
  | { grep -Fxf <(echo "$existing") || true; } \
  | to_json
