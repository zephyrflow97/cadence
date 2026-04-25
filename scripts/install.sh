#!/usr/bin/env bash
# Install Cadence into a project's local .claude/ and .codex/ (not globally).
# Both Claude Code and Codex receive generated, platform-native install files.
# The installer does not inject Cadence instructions into AGENTS.md or Claude hooks.
#
# Usage: bash scripts/install.sh [--claude-code] [--codex] [target-project-path]
#   If neither --claude-code nor --codex is given, installs both.
#   If no path is given, installs into $PWD.

set -euo pipefail

CADENCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

do_claude=0
do_codex=0
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --claude-code) do_claude=1 ;;
    --codex)       do_codex=1 ;;
    -h|--help)
      sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --*)
      echo "error: unknown flag '$arg'" >&2
      exit 1
      ;;
    *)
      [[ -z "$TARGET" ]] || { echo "error: multiple target paths given" >&2; exit 1; }
      TARGET="$arg"
      ;;
  esac
done

if [[ $do_claude -eq 0 && $do_codex -eq 0 ]]; then
  do_claude=1
  do_codex=1
fi

TARGET="${TARGET:-$PWD}"

[[ -d "$TARGET" ]] || { echo "error: '$TARGET' is not a directory" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

[[ "$TARGET" != "$CADENCE_ROOT" ]] || {
  echo "error: cannot install cadence into itself ($CADENCE_ROOT)" >&2
  exit 1
}

command -v python3 >/dev/null || {
  echo "error: python3 required (used to generate install files)" >&2
  exit 1
}

platforms=()
(( do_claude )) && platforms+=("Claude Code")
(( do_codex )) && platforms+=("Codex")

echo "Installing Cadence"
echo "  from:      $CADENCE_ROOT"
echo "  into:      $TARGET"
echo "  platforms: ${platforms[*]}"

remove_legacy_symlink() {
  local dst="$1" expected="$2"
  if [[ ! -L "$dst" ]]; then
    return 1
  fi

  local target
  target="$(readlink "$dst")"
  if [[ "$target" != "$expected" ]]; then
    echo "error: $dst points to $target, not $expected; move or remove it first" >&2
    exit 1
  fi

  rm "$dst"
  echo "  removed legacy link $dst"
}

clean_claude_hook() {
  python3 - "$1" <<'PY'
import json, os, sys
path = sys.argv[1]
if not os.path.exists(path):
    sys.exit(0)

with open(path) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"  skip {path} (unparseable: {e})")
        sys.exit(0)

hooks = data.get("hooks") or {}
entries = hooks.get("SessionStart") or []
kept = [
    e for e in entries
    if not any("run-hook.cmd" in h.get("command", "") for h in e.get("hooks", []))
]
removed = len(entries) - len(kept)
if removed == 0:
    sys.exit(0)

if kept:
    hooks["SessionStart"] = kept
elif "SessionStart" in hooks:
    del hooks["SessionStart"]

if hooks:
    data["hooks"] = hooks
elif "hooks" in data:
    del data["hooks"]

if data:
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"  removed legacy cadence hook from {path}")
else:
    os.remove(path)
    print(f"  removed {path} (empty after legacy cadence hook cleanup)")
PY
}

clean_codex_agents_block() {
  python3 - "$1" <<'PY'
import os, re, sys
path = sys.argv[1]
if not os.path.exists(path):
    sys.exit(0)

begin = "<!-- BEGIN cadence-block -->"
end = "<!-- END cadence-block -->"
with open(path) as f:
    text = f.read()

if begin not in text:
    sys.exit(0)

new = re.sub(
    r"\n*" + re.escape(begin) + r".*?" + re.escape(end) + r"\n*",
    "\n",
    text,
    flags=re.DOTALL,
).strip()

if new:
    with open(path, "w") as f:
        f.write(new + "\n")
    print(f"  removed legacy cadence block from {path}")
else:
    os.remove(path)
    print(f"  removed {path} (empty after legacy cadence block cleanup)")
PY
}

if (( do_claude )); then
  claude_root="$TARGET/.claude"
  claude_marker="$claude_root/.cadence-generated.json"

  if [[ -f "$claude_marker" ]]; then
    rm -rf "$claude_root/skills" "$claude_root/agents"
    rm -f "$claude_marker"
  else
    remove_legacy_symlink "$claude_root/skills" "$CADENCE_ROOT/skills" || true
    remove_legacy_symlink "$claude_root/agents" "$CADENCE_ROOT/agents" || true

    if [[ -e "$claude_root/skills" ]]; then
      echo "error: $claude_root/skills exists and is not managed by this installer; move or remove it first" >&2
      exit 1
    fi
    if [[ -e "$claude_root/agents" ]]; then
      echo "error: $claude_root/agents exists and is not managed by this installer; move or remove it first" >&2
      exit 1
    fi
  fi

  mkdir -p "$claude_root"
  python3 "$CADENCE_ROOT/scripts/generate_platform_package.py" \
    --platform claude-code \
    "$CADENCE_ROOT" \
    "$claude_root"
  echo "  generated $claude_root/skills and $claude_root/agents from $CADENCE_ROOT"

  clean_claude_hook "$claude_root/settings.json"
fi

if (( do_codex )); then
  codex_root="$TARGET/.codex"
  codex_skills_dir="$codex_root/skills"
  codex_marker="$codex_root/.cadence-generated.json"
  codex_legacy_marker="$codex_skills_dir/.cadence-generated.json"
  legacy_codex_root="$TARGET/.agents"
  legacy_codex_skills_dir="$legacy_codex_root/skills"
  legacy_codex_marker="$legacy_codex_root/.cadence-generated.json"
  legacy_codex_skills_marker="$legacy_codex_skills_dir/.cadence-generated.json"

  if [[ -f "$codex_marker" ]]; then
    rm -rf "$codex_skills_dir"
    rm -f "$codex_marker"
  elif [[ -f "$codex_legacy_marker" ]]; then
    rm -rf "$codex_skills_dir"
  elif remove_legacy_symlink "$codex_skills_dir" "$CADENCE_ROOT/skills"; then
    :
  elif [[ -e "$codex_skills_dir" ]]; then
    echo "error: $codex_skills_dir exists and is not managed by this installer; move or remove it first" >&2
    exit 1
  fi

  if [[ -f "$legacy_codex_marker" ]]; then
    rm -rf "$legacy_codex_skills_dir"
    rm -f "$legacy_codex_marker"
  elif [[ -f "$legacy_codex_skills_marker" ]]; then
    rm -rf "$legacy_codex_skills_dir"
  elif remove_legacy_symlink "$legacy_codex_skills_dir" "$CADENCE_ROOT/skills"; then
    :
  fi

  mkdir -p "$codex_root"
  python3 "$CADENCE_ROOT/scripts/generate_platform_package.py" \
    --platform codex \
    "$CADENCE_ROOT" \
    "$codex_root"
  echo "  generated $codex_skills_dir from $CADENCE_ROOT/skills"

  clean_codex_agents_block "$TARGET/AGENTS.md"
fi

echo
echo "Done. Start a new session in $TARGET."
