#!/usr/bin/env bash
# Install Cadence into a project's local .claude/ and .codex/ (not globally).
# Both Claude Code and Codex receive generated, platform-native install files.
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
  echo "error: python3 required (used to generate install files and merge settings)" >&2
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

  python3 - "$claude_root/settings.json" "$CADENCE_ROOT/hooks/run-hook.cmd" <<'PY'
import json, os, sys
path, hook_cmd = sys.argv[1], sys.argv[2]
command_line = f'"{hook_cmd}" session-start'

data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)

hooks = data.setdefault("hooks", {})
entries = hooks.get("SessionStart", [])
entries = [
    e for e in entries
    if not any("run-hook.cmd" in h.get("command", "") for h in e.get("hooks", []))
]
entries.append({
    "matcher": "startup|clear|compact",
    "hooks": [{"type": "command", "command": command_line, "async": False}],
})
hooks["SessionStart"] = entries
data["hooks"] = hooks

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"  wrote {path}")
PY
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

  python3 - "$TARGET/AGENTS.md" <<'PY'
import os, re, sys
path = sys.argv[1]
begin = "<!-- BEGIN cadence-block -->"
end = "<!-- END cadence-block -->"
block = f"""{begin}
## Cadence skills

This project uses Cadence's Codex-native skill pack. Skills live at
`.codex/skills/`. Before any task, read
`.codex/skills/using-cadence/SKILL.md` and follow it.
{end}"""

text = open(path).read() if os.path.exists(path) else ""
if begin in text:
    text = re.sub(
        re.escape(begin) + r".*?" + re.escape(end),
        block,
        text,
        flags=re.DOTALL,
    )
    action = "updated cadence block in"
else:
    text = (text.rstrip() + "\n\n" if text else "") + block + "\n"
    action = "appended cadence block to"

with open(path, "w") as f:
    f.write(text)
print(f"  {action} {path}")
PY
fi

echo
echo "Done. Start a new session in $TARGET."
