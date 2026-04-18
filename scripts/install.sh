#!/usr/bin/env bash
# Install Cadence into a project's local .claude/ and .agents/ (not globally).
# Creates symlinks back to this checkout so updates flow automatically.
#
# Usage: bash scripts/install.sh [target-project-path]
#   If no path given, installs into $PWD.

set -euo pipefail

CADENCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-$PWD}"

[[ -d "$TARGET" ]] || { echo "error: '$TARGET' is not a directory" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

[[ "$TARGET" != "$CADENCE_ROOT" ]] || {
  echo "error: cannot install cadence into itself ($CADENCE_ROOT)" >&2; exit 1;
}

command -v python3 >/dev/null || {
  echo "error: python3 required (used to merge settings.json / AGENTS.md)" >&2; exit 1;
}

echo "Installing Cadence"
echo "  from: $CADENCE_ROOT"
echo "  into: $TARGET"

link() {
  local src="$1" dst="$2"
  if [[ -L "$dst" ]]; then
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    echo "error: $dst exists and is not a symlink; move or remove it first" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  echo "  linked $dst -> $src"
}

# --- Claude Code ---
link "$CADENCE_ROOT/skills" "$TARGET/.claude/skills"
link "$CADENCE_ROOT/agents" "$TARGET/.claude/agents"

python3 - "$TARGET/.claude/settings.json" "$CADENCE_ROOT/hooks/run-hook.cmd" <<'PY'
import json, os, sys
path, hook_cmd = sys.argv[1], sys.argv[2]
command_line = f'"{hook_cmd}" session-start'

data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)

hooks = data.setdefault("hooks", {})
entries = hooks.get("SessionStart", [])
# Strip any prior cadence SessionStart entries so re-running is idempotent.
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

# --- Codex ---
link "$CADENCE_ROOT/skills" "$TARGET/.agents/skills"

python3 - "$TARGET/AGENTS.md" <<'PY'
import os, re, sys
path = sys.argv[1]
begin = "<!-- BEGIN cadence-block -->"
end = "<!-- END cadence-block -->"
block = f"""{begin}
## Cadence skills

This project uses Cadence. Skills live at `.agents/skills/`. Before any task,
read `.agents/skills/using-cadence/SKILL.md` and follow it.
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

echo
echo "Done. Start a new Claude Code or Codex session in $TARGET."
