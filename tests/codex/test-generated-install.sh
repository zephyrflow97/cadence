#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$(mktemp -d)"

EXPECTED_SKILLS=(
  using-cadence
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
)

BANNED_PATTERNS=(
  "Task tool"
  "TodoWrite"
  "Claude Code"
  "general-purpose"
  "cadence:code-reviewer type"
  "Skill tool"
  "run_in_background"
  "Write tool"
  "Bash tool"
  "Read tool"
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

echo "=== Codex core-native skill pack test ==="

bash "$REPO_ROOT/scripts/install.sh" --codex "$TEST_DIR" >/dev/null
bash "$REPO_ROOT/scripts/install.sh" --codex "$TEST_DIR" >/dev/null

test -f "$TEST_DIR/.codex/.cadence-generated.json"
test -f "$TEST_DIR/AGENTS.md"

for skill in "${EXPECTED_SKILLS[@]}"; do
  test -e "$TEST_DIR/.codex/skills/$skill"
done

assert_not_exists \
  "$TEST_DIR/.codex/skills/writing-skills" \
  "non-core writing-skills directory should not be installed"

assert_not_exists \
  "$TEST_DIR/.codex/skills/using-cadence/references/codex-tools.md" \
  "Codex install should not include the old codex-tools reference page"

python3 - "$TEST_DIR/.codex/.cadence-generated.json" <<'PY'
import json
import sys

expected_skills = [
    "using-cadence",
    "brainstorming",
    "writing-plans",
    "executing-plans",
    "using-git-worktrees",
    "subagent-driven-development",
    "dispatching-parallel-agents",
    "requesting-code-review",
    "receiving-code-review",
    "finishing-a-development-branch",
    "test-driven-development",
    "systematic-debugging",
    "verification-before-completion",
]

data = json.load(open(sys.argv[1]))
assert data["platform"] == "codex", data
assert data["mode"] == "core-native-skill-pack", data
assert data["skills"] == expected_skills, data
assert "writing-skills" not in data["skills"], data
assert data["agents"] == [], data
assert len(data["files"]) >= len(expected_skills), data
PY

assert_contains \
  "$TEST_DIR/.codex/skills/using-cadence/SKILL.md" \
  "description: Use when starting any conversation - establishes how to find and use skills, requiring Skill invocation before ANY response including clarifying questions" \
  "using-cadence should preserve the original description with only the Codex-specific wording adjusted"

assert_contains \
  "$TEST_DIR/.codex/skills/using-cadence/SKILL.md" \
  '**In Codex:** Skills are auto-discovered via `~/.codex/skills/`.' \
  "using-cadence should preserve the original Codex access instructions"

assert_contains \
  "$TEST_DIR/.codex/skills/using-cadence/SKILL.md" \
  "If you think there is even a 1% chance a skill might apply to what you are doing, you ABSOLUTELY MUST invoke the skill." \
  "using-cadence should preserve the original invoke-the-skill instruction"

assert_contains \
  "$TEST_DIR/.codex/skills/requesting-code-review/SKILL.md" \
  'spawn_agent(agent_type="explorer", message=...)' \
  "requesting-code-review should launch an explorer reviewer"

assert_contains \
  "$TEST_DIR/.codex/skills/requesting-code-review/SKILL.md" \
  "## How to Request" \
  "requesting-code-review should preserve the original section structure"

assert_contains \
  "$TEST_DIR/.codex/skills/dispatching-parallel-agents/SKILL.md" \
  'spawn_agent(agent_type="worker", message="Fix agent-tool-abort.test.ts failures")' \
  "dispatching-parallel-agents should show worker-native examples"

assert_contains \
  "$TEST_DIR/.codex/skills/dispatching-parallel-agents/SKILL.md" \
  "## Overview" \
  "dispatching-parallel-agents should preserve the original overview section"

assert_contains \
  "$TEST_DIR/.codex/skills/subagent-driven-development/implementer-prompt.md" \
  'Use this template as the `message` for `spawn_agent(agent_type="worker", ...)`.' \
  "implementer prompt should use worker role"

assert_contains \
  "$TEST_DIR/.codex/skills/subagent-driven-development/implementer-prompt.md" \
  "## Before You Begin" \
  "implementer prompt should preserve the original task guidance structure"

assert_contains \
  "$TEST_DIR/.codex/skills/subagent-driven-development/spec-reviewer-prompt.md" \
  'Use this template as the `message` for `spawn_agent(agent_type="explorer", ...)`.' \
  "spec reviewer prompt should use explorer role"

assert_contains \
  "$TEST_DIR/.codex/skills/subagent-driven-development/spec-reviewer-prompt.md" \
  "## CRITICAL: Do Not Trust the Report" \
  "spec reviewer prompt should preserve the original review guidance"

assert_contains \
  "$TEST_DIR/.codex/skills/subagent-driven-development/code-quality-reviewer-prompt.md" \
  'spawn_agent(agent_type="explorer", message="[filled prompt from requesting-code-review/code-reviewer.md]")' \
  "code-quality reviewer prompt should launch the review explorer via the bundled template"

assert_contains \
  "$TEST_DIR/.codex/skills/brainstorming/spec-document-reviewer-prompt.md" \
  "## Calibration" \
  "spec document reviewer prompt should preserve the original calibration guidance"

assert_contains \
  "$TEST_DIR/.codex/skills/writing-plans/plan-document-reviewer-prompt.md" \
  "## Calibration" \
  "plan document reviewer prompt should preserve the original calibration guidance"

assert_contains \
  "$TEST_DIR/.codex/skills/brainstorming/visual-companion.md" \
  'Create or update each HTML file with `apply_patch`' \
  "visual companion should reference Codex editing guidance"

assert_contains \
  "$TEST_DIR/.codex/skills/using-cadence/SKILL.md" \
  "Skills in this install already use Codex-native tool names. Follow the instructions directly." \
  "using-cadence should adapt the platform section without adding extra workflow content"

assert_contains \
  "$TEST_DIR/.codex/skills/using-cadence/SKILL.md" \
  "Read relevant SKILL.md" \
  "using-cadence should translate skill invocation into Codex-native wording"

assert_contains \
  "$TEST_DIR/.codex/skills/using-cadence/SKILL.md" \
  "Create update_plan item per checklist item" \
  "using-cadence should translate TodoWrite guidance into update_plan wording"

assert_tree_not_contains \
  "$TEST_DIR/.codex/skills/using-cadence" \
  "**In Claude Code:**" \
  "Codex render should drop the Claude-specific access instructions"

assert_tree_not_contains \
  "$TEST_DIR/.codex/skills" \
  "codex-tools.md" \
  "generated Codex skill pack should not reference codex-tools.md"

for pattern in "${BANNED_PATTERNS[@]}"; do
  assert_tree_not_contains \
    "$TEST_DIR/.codex/skills" \
    "$pattern" \
    "generated skill pack should not contain banned phrase: $pattern"
done

bash "$REPO_ROOT/scripts/uninstall.sh" --codex "$TEST_DIR" >/dev/null

test ! -e "$TEST_DIR/.codex"
test ! -e "$TEST_DIR/AGENTS.md"

echo "PASS: Codex install generates a core-native skill pack"
