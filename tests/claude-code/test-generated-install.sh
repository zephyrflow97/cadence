#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$(mktemp -d)"

EXPECTED_SKILLS=(
  brainstorming
  writing-plans
  executing-plans
  using-git-worktrees
  subagent-driven-development
  dispatching-parallel-agents
  requesting-code-review
  receiving-code-review
  finishing-a-development-branch
  test-driven-development
  systematic-debugging
  verification-before-completion
  writing-skills
)

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Fq "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "  missing pattern: $pattern" >&2
    exit 1
  fi
}

assert_not_exists() {
  local path="$1"
  local message="$2"
  if [[ -e "$path" ]]; then
    echo "FAIL: $message" >&2
    echo "  unexpected path: $path" >&2
    exit 1
  fi
}

assert_tree_not_contains() {
  local root="$1"
  local pattern="$2"
  local message="$3"
  if rg -n -F "$pattern" "$root" --glob '*.md' >/dev/null; then
    echo "FAIL: $message" >&2
    rg -n -F "$pattern" "$root" --glob '*.md' >&2
    exit 1
  fi
}

echo "=== Claude Code native install test ==="

bash "$REPO_ROOT/scripts/install.sh" --claude-code "$TEST_DIR" >/dev/null
bash "$REPO_ROOT/scripts/install.sh" --claude-code "$TEST_DIR" >/dev/null

test -f "$TEST_DIR/.claude/.cadence-generated.json"
test ! -e "$TEST_DIR/.claude/settings.json"
test -f "$TEST_DIR/.claude/agents/code-reviewer.md"

LEGACY_CLAUDE_DIR="$TEST_DIR/legacy-claude"
mkdir -p "$LEGACY_CLAUDE_DIR/.claude"
cat > "$LEGACY_CLAUDE_DIR/.claude/settings.json" <<'JSON'
{
  "keep": true,
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "\"/tmp/cadence/hooks/run-hook.cmd\" session-start",
            "async": false
          }
        ]
      }
    ]
  }
}
JSON
bash "$REPO_ROOT/scripts/install.sh" --claude-code "$LEGACY_CLAUDE_DIR" >/dev/null
python3 - "$LEGACY_CLAUDE_DIR/.claude/settings.json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
assert data == {"keep": True}, data
PY

for skill in "${EXPECTED_SKILLS[@]}"; do
  test -e "$TEST_DIR/.claude/skills/$skill"
done

assert_not_exists \
  "$TEST_DIR/.claude/skills/using-cadence" \
  "removed using-cadence skill should not be installed"

python3 - "$TEST_DIR/.claude/.cadence-generated.json" <<'PY'
import json
import sys

expected_skills = [
    "brainstorming",
    "dispatching-parallel-agents",
    "executing-plans",
    "finishing-a-development-branch",
    "receiving-code-review",
    "requesting-code-review",
    "subagent-driven-development",
    "systematic-debugging",
    "test-driven-development",
    "using-git-worktrees",
    "verification-before-completion",
    "writing-plans",
    "writing-skills",
]

data = json.load(open(sys.argv[1]))
assert data["platform"] == "claude-code", data
assert data["mode"] == "full-native-install", data
assert data["skills"] == expected_skills, data
assert data["agents"] == ["code-reviewer.md"], data
assert "agents/code-reviewer.md" in data["files"], data
PY

assert_contains \
  "$TEST_DIR/.claude/skills/writing-skills/SKILL.md" \
  '`~/.claude/skills`' \
  "writing-skills should point at Claude's native skills directory"

assert_tree_not_contains \
  "$TEST_DIR/.claude" \
  "Codex" \
  "generated Claude install should not mention Codex in markdown files"

assert_tree_not_contains \
  "$TEST_DIR/.claude" \
  "~/.codex/skills" \
  "generated Claude install should not mention Codex skill paths"

bash "$REPO_ROOT/scripts/uninstall.sh" --claude-code "$TEST_DIR" >/dev/null

test ! -e "$TEST_DIR/.claude"

echo "PASS: Claude install generates a native skill and agent pack"
