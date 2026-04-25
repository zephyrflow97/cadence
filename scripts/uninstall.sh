#!/usr/bin/env bash
# Reverse install.sh: remove generated Cadence files, legacy symlinks, legacy
# hook entries, and legacy Codex AGENTS.md blocks. Safe/idempotent.
#
# Usage: bash scripts/uninstall.sh [--claude-code] [--codex] [target-project-path]
#   If neither --claude-code nor --codex is given, uninstalls both.
#   If no path is given, uninstalls from $PWD.

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
      sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
  echo "error: cannot uninstall from cadence itself" >&2
  exit 1
}

command -v python3 >/dev/null || {
  echo "error: python3 required" >&2
  exit 1
}

platforms=()
(( do_claude )) && platforms+=("Claude Code")
(( do_codex )) && platforms+=("Codex")

echo "Uninstalling Cadence"
echo "  cadence:   $CADENCE_ROOT"
echo "  from:      $TARGET"
echo "  platforms: ${platforms[*]}"

unlink_if_cadence() {
  local dst="$1" expected="$2"
  if [[ ! -e "$dst" && ! -L "$dst" ]]; then
    return 0
  fi
  if [[ ! -L "$dst" ]]; then
    echo "  skip $dst (not a symlink; leaving alone)"
    return 0
  fi

  local target
  target="$(readlink "$dst")"
  if [[ "$target" == "$expected" ]]; then
    rm "$dst"
    echo "  removed $dst"
  else
    echo "  skip $dst (points to $target, not $expected)"
  fi
}

if (( do_claude )); then
  claude_root="$TARGET/.claude"
  claude_marker="$claude_root/.cadence-generated.json"

  if [[ -f "$claude_marker" ]]; then
    rm -rf "$claude_root/skills" "$claude_root/agents"
    rm -f "$claude_marker"
    echo "  removed generated $claude_root/skills and $claude_root/agents"
  else
    unlink_if_cadence "$claude_root/skills" "$CADENCE_ROOT/skills"
    unlink_if_cadence "$claude_root/agents" "$CADENCE_ROOT/agents"
  fi

  python3 - "$claude_root/settings.json" <<'PY'
import json, os, sys
path = sys.argv[1]
if not os.path.exists(path):
    print(f"  skip {path} (not present)")
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
    print(f"  cleaned {path} (dropped {removed} cadence hook entr{'y' if removed == 1 else 'ies'})")
else:
    os.remove(path)
    print(f"  removed {path} (empty after cleanup)")
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
    echo "  removed generated $codex_skills_dir"
  elif [[ -f "$codex_legacy_marker" ]]; then
    rm -rf "$codex_skills_dir"
    echo "  removed legacy generated $codex_skills_dir"
  else
    unlink_if_cadence "$codex_skills_dir" "$CADENCE_ROOT/skills"
  fi

  if [[ -f "$legacy_codex_marker" ]]; then
    rm -rf "$legacy_codex_skills_dir"
    rm -f "$legacy_codex_marker"
    echo "  removed legacy generated $legacy_codex_skills_dir"
  elif [[ -f "$legacy_codex_skills_marker" ]]; then
    rm -rf "$legacy_codex_skills_dir"
    echo "  removed legacy generated $legacy_codex_skills_dir"
  else
    unlink_if_cadence "$legacy_codex_skills_dir" "$CADENCE_ROOT/skills"
  fi

  python3 - "$TARGET/AGENTS.md" <<'PY'
import os, re, sys
path = sys.argv[1]
if not os.path.exists(path):
    print(f"  skip {path} (not present)")
    sys.exit(0)

begin = "<!-- BEGIN cadence-block -->"
end = "<!-- END cadence-block -->"
with open(path) as f:
    text = f.read()

if begin not in text:
    print(f"  skip {path} (no cadence block)")
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
    print(f"  cleaned cadence block from {path}")
else:
    os.remove(path)
    print(f"  removed {path} (empty after cleanup)")
PY
fi

for d in "$TARGET/.claude" "$TARGET/.codex" "$TARGET/.agents"; do
  if [[ -d "$d" ]] && [[ -z "$(ls -A "$d")" ]]; then
    rmdir "$d"
    echo "  removed empty $d"
  fi
done

echo
echo "Done."
