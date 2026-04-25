#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
PRESERVE_DIR="$TEST_DIR/preserve-existing-agents"

EXPECTED_SKILLS=(
  brainstorming
  writing-plans
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

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if grep -Fq "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "  unexpected pattern: $pattern" >&2
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
  if rg -n -F "$pattern" "$root" --glob '*.md' --glob '*.toml' >/dev/null; then
    echo "FAIL: $message" >&2
    rg -n -F "$pattern" "$root" --glob '*.md' --glob '*.toml' >&2
    exit 1
  fi
}

echo "=== Codex core-native skill pack test ==="

bash "$REPO_ROOT/scripts/install.sh" --codex "$TEST_DIR" >/dev/null
bash "$REPO_ROOT/scripts/install.sh" --codex "$TEST_DIR" >/dev/null

test -f "$TEST_DIR/.codex/.cadence-generated.json"
test ! -e "$TEST_DIR/AGENTS.md"

LEGACY_CODEX_DIR="$TEST_DIR/legacy-codex"
mkdir "$LEGACY_CODEX_DIR"
cat > "$LEGACY_CODEX_DIR/AGENTS.md" <<'MD'
# Existing agent instructions

<!-- BEGIN cadence-block -->
legacy cadence instructions
<!-- END cadence-block -->
MD
bash "$REPO_ROOT/scripts/install.sh" --codex "$LEGACY_CODEX_DIR" >/dev/null
assert_contains \
  "$LEGACY_CODEX_DIR/AGENTS.md" \
  "# Existing agent instructions" \
  "Codex install should preserve existing user AGENTS.md content"
if grep -Fq "cadence-block" "$LEGACY_CODEX_DIR/AGENTS.md"; then
  echo "FAIL: Codex install should remove legacy cadence block without adding a new one" >&2
  exit 1
fi

mkdir -p "$PRESERVE_DIR/.codex/agents"
cat > "$PRESERVE_DIR/.codex/agents/local-reviewer.toml" <<'TOML'
name = "local-reviewer"
description = "Existing local agent"
developer_instructions = "Do local review work."
TOML
bash "$REPO_ROOT/scripts/install.sh" --codex "$PRESERVE_DIR" >/dev/null
test -f "$PRESERVE_DIR/.codex/agents/local-reviewer.toml"
test -f "$PRESERVE_DIR/.codex/agents/code-reviewer.toml"
bash "$REPO_ROOT/scripts/uninstall.sh" --codex "$PRESERVE_DIR" >/dev/null
test -f "$PRESERVE_DIR/.codex/agents/local-reviewer.toml"
test ! -e "$PRESERVE_DIR/.codex/agents/code-reviewer.toml"
test -d "$PRESERVE_DIR/.codex/agents"

ESCAPE_DIR="$TEST_DIR/escape-check"
mkdir -p "$ESCAPE_DIR/.codex" "$ESCAPE_DIR/outside"
touch "$ESCAPE_DIR/outside/keep"
cat > "$ESCAPE_DIR/.codex/.cadence-generated.json" <<'JSON'
{
  "files": ["../outside/keep"]
}
JSON
if python3 "$REPO_ROOT/scripts/remove_generated_package.py" \
    "$ESCAPE_DIR/.codex" \
    "$ESCAPE_DIR/.codex/.cadence-generated.json" 2>/dev/null; then
  echo "FAIL: remove_generated_package should reject parent-directory traversal" >&2
  exit 1
fi
test -f "$ESCAPE_DIR/outside/keep"
test -f "$ESCAPE_DIR/.codex/.cadence-generated.json"

SYMLINK_ESCAPE_DIR="$TEST_DIR/symlink-escape-check"
mkdir -p "$SYMLINK_ESCAPE_DIR/.codex" "$SYMLINK_ESCAPE_DIR/outside"
touch "$SYMLINK_ESCAPE_DIR/outside/keep"
ln -s "$SYMLINK_ESCAPE_DIR/outside" "$SYMLINK_ESCAPE_DIR/.codex/link"
cat > "$SYMLINK_ESCAPE_DIR/.codex/.cadence-generated.json" <<'JSON'
{
  "files": ["link/keep"]
}
JSON
if python3 "$REPO_ROOT/scripts/remove_generated_package.py" \
    "$SYMLINK_ESCAPE_DIR/.codex" \
    "$SYMLINK_ESCAPE_DIR/.codex/.cadence-generated.json" 2>/dev/null; then
  echo "FAIL: remove_generated_package should reject symlink parent traversal" >&2
  exit 1
fi
test -f "$SYMLINK_ESCAPE_DIR/outside/keep"
test -f "$SYMLINK_ESCAPE_DIR/.codex/.cadence-generated.json"

MALFORMED_MARKER_DIR="$TEST_DIR/malformed-marker-check"
mkdir -p "$MALFORMED_MARKER_DIR/.codex"
printf '{not json\n' > "$MALFORMED_MARKER_DIR/.codex/.cadence-generated.json"
if python3 "$REPO_ROOT/scripts/remove_generated_package.py" \
    "$MALFORMED_MARKER_DIR/.codex" \
    "$MALFORMED_MARKER_DIR/.codex/.cadence-generated.json" \
    2>"$MALFORMED_MARKER_DIR/stderr"; then
  echo "FAIL: remove_generated_package should fail on malformed marker JSON" >&2
  exit 1
fi
assert_contains \
  "$MALFORMED_MARKER_DIR/stderr" \
  "error:" \
  "remove_generated_package should print a concise error"
assert_not_contains \
  "$MALFORMED_MARKER_DIR/stderr" \
  "Traceback" \
  "remove_generated_package should not print Python tracebacks"
test -f "$MALFORMED_MARKER_DIR/.codex/.cadence-generated.json"

LEGACY_AGENT_CONFLICT_DIR="$TEST_DIR/legacy-agent-conflict"
mkdir -p "$LEGACY_AGENT_CONFLICT_DIR/.codex/skills" "$LEGACY_AGENT_CONFLICT_DIR/.codex/agents"
cat > "$LEGACY_AGENT_CONFLICT_DIR/.codex/skills/.cadence-generated.json" <<'JSON'
{
  "generated_by": "cadence",
  "files": []
}
JSON
cat > "$LEGACY_AGENT_CONFLICT_DIR/.codex/agents/code-reviewer.toml" <<'TOML'
name = "code-reviewer"
description = "User-owned reviewer"
developer_instructions = "Do not replace me."
TOML
if bash "$REPO_ROOT/scripts/install.sh" --codex "$LEGACY_AGENT_CONFLICT_DIR" >/dev/null 2>&1; then
  echo "FAIL: Codex install should reject user-owned code-reviewer.toml during legacy marker upgrade" >&2
  exit 1
fi
test -f "$LEGACY_AGENT_CONFLICT_DIR/.codex/skills/.cadence-generated.json"
test -f "$LEGACY_AGENT_CONFLICT_DIR/.codex/agents/code-reviewer.toml"

python3 - "$REPO_ROOT/scripts/generate_platform_package.py" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("generate_platform_package", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

frontmatter, body = module.parse_agent_markdown("""---
name: demo-reviewer
description: |-
  Short reviewer description.
model: inherit
---
Body text.
""")
assert frontmatter["description"] == "Short reviewer description.", frontmatter
assert body == "Body text.", body
PY

for skill in "${EXPECTED_SKILLS[@]}"; do
  test -e "$TEST_DIR/.codex/skills/$skill"
done

test -f "$TEST_DIR/.codex/agents/code-reviewer.toml"

assert_not_exists \
  "$TEST_DIR/.codex/skills/writing-skills" \
  "non-core writing-skills directory should not be installed"

assert_not_exists \
  "$TEST_DIR/.codex/skills/using-cadence" \
  "removed using-cadence skill should not be installed"

assert_not_exists \
  "$TEST_DIR/.codex/skills/executing-plans" \
  "removed executing-plans skill should not be installed"

python3 - "$TEST_DIR/.codex/.cadence-generated.json" <<'PY'
import json
import sys

expected_skills = [
    "brainstorming",
    "writing-plans",
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
assert data["agents"] == ["code-reviewer.toml"], data
assert "agents/code-reviewer.toml" in data["files"], data
assert len(data["files"]) >= len(expected_skills), data
PY

assert_contains \
  "$TEST_DIR/.codex/skills/requesting-code-review/SKILL.md" \
  'spawn_agent(agent_type="code-reviewer")' \
  "requesting-code-review should launch the named code-reviewer subagent"

assert_contains \
  "$TEST_DIR/.codex/agents/code-reviewer.toml" \
  'name = "code-reviewer"' \
  "code-reviewer agent should define its Codex subagent name"

assert_contains \
  "$TEST_DIR/.codex/agents/code-reviewer.toml" \
  'sandbox_mode = "read-only"' \
  "code-reviewer agent should run read-only"

assert_not_contains \
  "$TEST_DIR/.codex/agents/code-reviewer.toml" \
  "<example>" \
  "code-reviewer agent description should not include Claude example markup"

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
  'spawn_agent(agent_type="code-reviewer"):' \
  "code-quality reviewer prompt should launch the named reviewer via the bundled template"

assert_contains \
  "$TEST_DIR/.codex/skills/subagent-driven-development/code-quality-reviewer-prompt.md" \
  'Use this template when dispatching the `code-reviewer` subagent.' \
  "code-quality reviewer prompt should name the Codex subagent"

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

assert_tree_not_contains \
  "$TEST_DIR/.codex" \
  "codex-tools.md" \
  "generated Codex skill pack should not reference codex-tools.md"

for pattern in "${BANNED_PATTERNS[@]}"; do
  assert_tree_not_contains \
    "$TEST_DIR/.codex" \
    "$pattern" \
    "generated skill pack should not contain banned phrase: $pattern"
done

bash "$REPO_ROOT/scripts/uninstall.sh" --codex "$TEST_DIR" >/dev/null

test ! -e "$TEST_DIR/.codex"
test ! -e "$TEST_DIR/AGENTS.md"

echo "PASS: Codex install generates a core-native skill pack"
