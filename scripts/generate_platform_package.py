#!/usr/bin/env python3
"""Generate platform-native Cadence install files."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import textwrap
from pathlib import Path


MARKER_FILE = ".cadence-generated.json"

CODEX_CORE_SKILL_FILES: dict[str, list[str]] = {
    "using-cadence": [
        "SKILL.md",
    ],
    "brainstorming": [
        "SKILL.md",
        "visual-companion.md",
        "spec-document-reviewer-prompt.md",
        "scripts/frame-template.html",
        "scripts/helper.js",
        "scripts/server.cjs",
        "scripts/start-server.sh",
        "scripts/stop-server.sh",
    ],
    "writing-plans": [
        "SKILL.md",
        "plan-document-reviewer-prompt.md",
    ],
    "executing-plans": [
        "SKILL.md",
    ],
    "using-git-worktrees": [
        "SKILL.md",
    ],
    "subagent-driven-development": [
        "SKILL.md",
        "implementer-prompt.md",
        "spec-reviewer-prompt.md",
        "code-quality-reviewer-prompt.md",
    ],
    "dispatching-parallel-agents": [
        "SKILL.md",
    ],
    "requesting-code-review": [
        "SKILL.md",
        "code-reviewer.md",
    ],
    "receiving-code-review": [
        "SKILL.md",
    ],
    "finishing-a-development-branch": [
        "SKILL.md",
    ],
    "test-driven-development": [
        "SKILL.md",
        "testing-anti-patterns.md",
    ],
    "systematic-debugging": [
        "SKILL.md",
        "condition-based-waiting.md",
        "condition-based-waiting-example.ts",
        "defense-in-depth.md",
        "root-cause-tracing.md",
        "find-polluter.sh",
    ],
    "verification-before-completion": [
        "SKILL.md",
    ],
}

CLAUDE_EXCLUDED_SKILL_FILES = {
    Path("using-cadence/references/codex-tools.md"),
}


def block(text: str) -> str:
    return textwrap.dedent(text).strip() + "\n"


def tidy_markdown(text: str) -> str:
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.rstrip() + "\n"


def replace_section(text: str, heading: str, replacement: str, next_heading_level: str = "## ") -> str:
    pattern = re.compile(
        rf"^{re.escape(heading)}\n.*?(?=^{re.escape(next_heading_level)}|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    return pattern.sub(block(replacement) + "\n", text, count=1)


def remove_section(text: str, heading: str, next_heading_level: str = "## ") -> str:
    pattern = re.compile(
        rf"^{re.escape(heading)}\n.*?(?=^{re.escape(next_heading_level)}|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    return tidy_markdown(pattern.sub("", text, count=1))


def render_claude_using_cadence(source_text: str) -> str:
    text = replace_section(
        source_text,
        "## How to Access Skills",
        """
        ## How to Access Skills

        **In Claude Code:** Use the `Skill` tool. When you invoke a skill, its content is loaded and presented to you—follow it directly. Never use the Read tool on skill files.
        """,
        next_heading_level="## Platform Adaptation",
    )
    text = remove_section(text, "## Platform Adaptation", next_heading_level="# Using Skills")
    return tidy_markdown(text)


def render_codex_using_cadence(source_text: str) -> str:
    text = source_text

    text = text.replace(
        "requiring Skill tool invocation before ANY response including clarifying questions",
        "requiring Skill invocation before ANY response including clarifying questions",
    )
    text = replace_section(
        text,
        "## How to Access Skills",
        """
        ## How to Access Skills

        **In Codex:** Skills are auto-discovered via `~/.codex/skills/`. Invocation is native — read the SKILL.md content and follow it directly.
        """,
        next_heading_level="## Platform Adaptation",
    )
    text = replace_section(
        text,
        "## Platform Adaptation",
        """
        ## Platform Adaptation

        Skills in this install already use Codex-native tool names. Follow the instructions directly.
        """,
        next_heading_level="# Using Skills",
    )
    replacements = [
        ("Invoke Skill tool", "Read relevant SKILL.md"),
        ("Create TodoWrite todo per item", "Create update_plan item per checklist item"),
        (
            "**Invoke relevant or requested skills BEFORE any response or action.** Even a 1% chance a skill might apply means that you should invoke the skill to check. If an invoked skill turns out to be wrong for the situation, you don't need to use it.",
            "**Invoke relevant or requested skills BEFORE any response or action.** Even a 1% chance a skill might apply means that you should read the skill to check. If that skill turns out to be wrong for the situation, you don't need to use it.",
        ),
    ]
    for old, new in replacements:
        text = text.replace(old, new)
    return tidy_markdown(text)

def render_requesting_code_review(source_text: str) -> str:
    text = source_text
    text = text.replace(
        "Dispatch cadence:code-reviewer subagent to catch issues before they cascade.",
        "Dispatch a read-only code review explorer to catch issues before they cascade.",
    )
    text = text.replace(
        "Use Task tool with cadence:code-reviewer type, fill template at `code-reviewer.md`",
        'Use `spawn_agent(agent_type="explorer", message=...)` with the filled template at `code-reviewer.md`',
    )
    text = text.replace(
        "[Dispatch cadence:code-reviewer subagent]",
        'spawn_agent(agent_type="explorer", message="[filled prompt from requesting-code-review/code-reviewer.md]")',
    )
    return tidy_markdown(text)


def render_code_reviewer_prompt(source_text: str) -> str:
    return source_text.replace(
        "# Code Review Agent\n\nYou are reviewing code changes for production readiness.\n",
        (
            "# Code Review Explorer Prompt\n\n"
            "Use this file as the `message` for `spawn_agent(agent_type=\"explorer\", ...)`.\n\n"
            "You are a read-only code review explorer. Review code changes for production readiness. Do not edit files.\n"
        ),
        1,
    )


def render_dispatching_parallel_agents(source_text: str) -> str:
    text = cleanup_codex_generic(source_text)
    text = text.replace("// In Codex / AI environment", "// In Codex")
    return tidy_markdown(text)


def render_subagent_driven_development(source_text: str) -> str:
    text = cleanup_codex_generic(source_text)
    text = text.replace("[Dispatch final code-reviewer]", "[Dispatch final code review explorer]")
    return tidy_markdown(text)


def convert_task_prompt_block(text: str) -> str:
    start = text.find("```\nTask tool (")
    if start == -1:
        return text

    prompt_marker = "  prompt: |\n"
    prompt_start = text.find(prompt_marker, start)
    if prompt_start == -1:
        return text

    end = text.find("\n```", prompt_start)
    if end == -1:
        return text

    header = text[start:prompt_start]
    body = text[prompt_start + len(prompt_marker) : end]

    description_match = re.search(r'  description: "([^"]+)"', header)
    description = description_match.group(1) if description_match else None

    lines = []
    for line in body.splitlines():
        if line.startswith("    "):
            lines.append(line[4:])
        else:
            lines.append(line)
    prompt_body = "\n".join(lines).rstrip()

    parts = []
    if description:
        parts.append(description)
    parts.append(prompt_body)
    replacement = "```text\n" + "\n\n".join(parts).rstrip() + "\n```"
    return text[:start] + replacement + text[end + 4 :]


def render_implementer_prompt(source_text: str) -> str:
    text = source_text.replace(
        "Use this template when dispatching an implementer subagent.",
        'Use this template as the `message` for `spawn_agent(agent_type="worker", ...)`.',
        1,
    )
    return tidy_markdown(convert_task_prompt_block(text))


def render_spec_reviewer_prompt(source_text: str) -> str:
    text = source_text.replace(
        "Use this template when dispatching a spec compliance reviewer subagent.",
        'Use this template as the `message` for `spawn_agent(agent_type="explorer", ...)`.',
        1,
    )
    return tidy_markdown(convert_task_prompt_block(text))


def render_code_quality_reviewer_prompt(source_text: str) -> str:
    text = source_text.replace(
        "Use this template when dispatching a code quality reviewer subagent.",
        "Use this template when launching a code quality review explorer.",
        1,
    )
    old_block = block(
        """
        ```
        Task tool (cadence:code-reviewer):
          Use template at requesting-code-review/code-reviewer.md

          WHAT_WAS_IMPLEMENTED: [from implementer's report]
          PLAN_OR_REQUIREMENTS: Task N from [plan-file]
          BASE_SHA: [commit before task]
          HEAD_SHA: [current commit]
          DESCRIPTION: [task summary]
        ```
        """
    ).strip()
    new_block = block(
        """
        Fill the placeholders in `requesting-code-review/code-reviewer.md`, then launch:

        ```text
        spawn_agent(agent_type="explorer", message="[filled prompt from requesting-code-review/code-reviewer.md]")
        ```

        Use these placeholder values:
        - `WHAT_WAS_IMPLEMENTED`: [from implementer's report]
        - `PLAN_OR_REQUIREMENTS`: Task N from [plan-file]
        - `BASE_SHA`: [commit before task]
        - `HEAD_SHA`: [current commit]
        - `DESCRIPTION`: [task summary]
        """
    ).strip()
    text = text.replace(old_block, new_block, 1)
    return tidy_markdown(text)


def render_spec_document_reviewer_prompt(source_text: str) -> str:
    text = source_text.replace(
        "Use this template when dispatching a spec document reviewer subagent.",
        'Use this template as the `message` for `spawn_agent(agent_type="explorer", ...)`.',
        1,
    )
    return tidy_markdown(convert_task_prompt_block(text))


def render_plan_document_reviewer_prompt(source_text: str) -> str:
    text = source_text.replace(
        "Use this template when dispatching a plan document reviewer subagent.",
        'Use this template as the `message` for `spawn_agent(agent_type="explorer", ...)`.',
        1,
    )
    return tidy_markdown(convert_task_prompt_block(text))


def transform_visual_companion_claude(text: str) -> str:
    return replace_section(
        text,
        "**Launching the server by platform:**",
        """
        **Launching the server in Claude Code:**

        **macOS / Linux:**
        ```bash
        scripts/start-server.sh --project-dir /path/to/project
        ```

        **Windows:**
        ```bash
        scripts/start-server.sh --project-dir /path/to/project
        ```
        Windows auto-detects foreground mode, which blocks the tool call.
        When launching this with the Bash tool, set `run_in_background: true`.
        Then read `$STATE_DIR/server-info` on the next turn to get the URL and port.
        """,
        next_heading_level="If the URL is unreachable from your browser (common in remote/containerized setups), bind a non-loopback host:",
    )


def transform_visual_companion_codex(text: str) -> str:
    text = replace_section(
        text,
        "**Launching the server by platform:**",
        """
        **Launching the server in Codex:**

        ```bash
        scripts/start-server.sh --project-dir /path/to/project
        ```

        Codex reaps detached background processes. The script auto-detects `CODEX_CI`
        and switches to foreground mode automatically, so no extra flags are needed.

        If your environment also reaps detached processes, use `--foreground` and rely
        on the harness to keep the process alive.
        """,
        next_heading_level="If the URL is unreachable from your browser (common in remote/containerized setups), bind a non-loopback host:",
    )
    text = text.replace(
        "- Use Write tool — **never use cat/heredoc** (dumps noise into terminal)",
        "- Create or update each HTML file with `apply_patch` — **never use cat/heredoc** (dumps noise into terminal)",
    )
    text = text.replace(
        "- Read `$STATE_DIR/events` if it exists — this contains the user's browser interactions (clicks, selections) as JSON lines",
        "- Use `exec_command` to read `$STATE_DIR/events` if it exists — this contains the user's browser interactions (clicks, selections) as JSON lines",
    )
    text = text.replace(
        "**Finding connection info:** The server writes its startup JSON to `$STATE_DIR/server-info`. If you launched the server in the background and didn't capture stdout, read that file to get the URL and port. When using `--project-dir`, check `<project>/.cadence/brainstorm/` for the session directory.",
        "**Finding connection info:** The server writes its startup JSON to `$STATE_DIR/server-info`. Use `exec_command` to read that file if you need the URL or port again. When using `--project-dir`, check `<project>/.cadence/brainstorm/` for the session directory.",
    )
    return text


def transform_executing_plans_claude(text: str) -> str:
    return text.replace(
        "**Note:** Tell your human partner that Cadence works much better with access to subagents. The quality of its work will be significantly higher if run on a platform with subagent support (such as Claude Code or Codex). If subagents are available, use cadence:subagent-driven-development instead of this skill.",
        "**Note:** Tell your human partner that Cadence works much better with access to Claude Code subagents. If subagents are available, use cadence:subagent-driven-development instead of this skill.",
    )


def transform_executing_plans_codex(text: str) -> str:
    return text.replace(
        "**Note:** Tell your human partner that Cadence works much better with access to subagents. The quality of its work will be significantly higher if run on a platform with subagent support (such as Claude Code or Codex). If subagents are available, use cadence:subagent-driven-development instead of this skill.",
        "**Note:** If your Codex environment has multi-agent support, prefer `subagent-driven-development` over this skill.",
    )


def transform_writing_skills_claude(text: str) -> str:
    return text.replace(
        "**Personal skills live in agent-specific directories (`~/.claude/skills` for Claude Code, `~/.codex/skills/` for Codex)** ",
        "**Personal skills live in `~/.claude/skills`** ",
    )


def cleanup_codex_generic(text: str) -> str:
    replacements = [
        ("cadence:", ""),
        ("TodoWrite", "update_plan"),
        ("Task tool", "spawn_agent"),
        ("Task returns result", "Subagent returns result"),
        ("Task completes automatically", "Close the subagent when you no longer need it"),
        ("Skill tool", "skill file"),
        ("Read tool", "read files directly"),
        ("Write tool", "apply_patch"),
        ("Edit tool", "apply_patch"),
        ("Bash tool", "exec_command"),
        ("Claude Code", "Codex"),
        ("CLAUDE.md", "AGENTS.md"),
    ]
    for old, new in replacements:
        text = text.replace(old, new)

    text = re.sub(
        r'\bTask\("([^"]+)"\)',
        r'spawn_agent(agent_type="worker", message="\1")',
        text,
    )
    return text


CODEX_FULL_RENDERERS = {
    "using-cadence/SKILL.md": render_codex_using_cadence,
    "requesting-code-review/SKILL.md": render_requesting_code_review,
    "requesting-code-review/code-reviewer.md": render_code_reviewer_prompt,
    "dispatching-parallel-agents/SKILL.md": render_dispatching_parallel_agents,
    "subagent-driven-development/SKILL.md": render_subagent_driven_development,
    "subagent-driven-development/implementer-prompt.md": render_implementer_prompt,
    "subagent-driven-development/spec-reviewer-prompt.md": render_spec_reviewer_prompt,
    "subagent-driven-development/code-quality-reviewer-prompt.md": render_code_quality_reviewer_prompt,
    "brainstorming/spec-document-reviewer-prompt.md": render_spec_document_reviewer_prompt,
    "writing-plans/plan-document-reviewer-prompt.md": render_plan_document_reviewer_prompt,
}


def transform_codex_skill_markdown(rel_path: Path, text: str) -> str:
    rel_str = rel_path.as_posix()
    if rel_str in CODEX_FULL_RENDERERS:
        return CODEX_FULL_RENDERERS[rel_str](text)

    if rel_str == "brainstorming/visual-companion.md":
        text = transform_visual_companion_codex(text)
    elif rel_str == "using-git-worktrees/SKILL.md":
        text = text.replace("CLAUDE.md", "AGENTS.md")
    elif rel_str == "receiving-code-review/SKILL.md":
        text = text.replace("CLAUDE.md", "AGENTS.md")
    elif rel_str == "executing-plans/SKILL.md":
        text = transform_executing_plans_codex(text)

    return cleanup_codex_generic(text)


def transform_claude_skill_markdown(rel_path: Path, text: str) -> str:
    rel_str = rel_path.as_posix()

    if rel_str == "using-cadence/SKILL.md":
        return render_claude_using_cadence(text)
    if rel_str == "brainstorming/visual-companion.md":
        return transform_visual_companion_claude(text)
    if rel_str == "executing-plans/SKILL.md":
        return transform_executing_plans_claude(text)
    if rel_str == "writing-skills/SKILL.md":
        return transform_writing_skills_claude(text)
    if rel_str == "dispatching-parallel-agents/SKILL.md":
        return text.replace("// In Claude Code / AI environment", "// In Claude Code")

    return text


def iter_files(root: Path) -> list[Path]:
    return sorted(path for path in root.rglob("*") if path.is_file())


def selected_codex_items(repo_root: Path) -> list[tuple[Path, Path, str, Path]]:
    items: list[tuple[Path, Path, str, Path]] = []
    skills_root = repo_root / "skills"
    for skill, rel_paths in CODEX_CORE_SKILL_FILES.items():
        for rel_path in rel_paths:
            logical_rel = Path(skill) / rel_path
            items.append((skills_root / logical_rel, Path("skills") / logical_rel, "skills", logical_rel))
    return items


def selected_claude_items(repo_root: Path) -> list[tuple[Path, Path, str, Path]]:
    items: list[tuple[Path, Path, str, Path]] = []
    skills_root = repo_root / "skills"
    for src in iter_files(skills_root):
        logical_rel = src.relative_to(skills_root)
        if logical_rel in CLAUDE_EXCLUDED_SKILL_FILES:
            continue
        items.append((src, Path("skills") / logical_rel, "skills", logical_rel))

    agents_root = repo_root / "agents"
    for src in iter_files(agents_root):
        logical_rel = src.relative_to(agents_root)
        items.append((src, Path("agents") / logical_rel, "agents", logical_rel))

    return items


def cadence_version(repo_root: Path) -> str | None:
    package_json = repo_root / "package.json"
    if not package_json.exists():
        return None
    data = json.loads(package_json.read_text(encoding="utf-8"))
    return data.get("version")


def generate(repo_root: Path, target_root: Path, platform: str) -> None:
    target_root.mkdir(parents=True, exist_ok=True)

    if platform == "codex":
        items = selected_codex_items(repo_root)
        skills = list(CODEX_CORE_SKILL_FILES)
        agents: list[str] = []
        mode = "core-native-skill-pack"
    else:
        items = selected_claude_items(repo_root)
        skills = sorted(path.name for path in (repo_root / "skills").iterdir() if path.is_dir())
        agents = sorted(path.relative_to(repo_root / "agents").as_posix() for path in iter_files(repo_root / "agents"))
        mode = "full-native-install"

    generated_paths: list[str] = []

    for src, dst_rel, namespace, logical_rel in items:
        if not src.exists():
            raise FileNotFoundError(f"Missing source file: {src}")

        dst = target_root / dst_rel
        dst.parent.mkdir(parents=True, exist_ok=True)

        if src.suffix == ".md":
            text = src.read_text(encoding="utf-8")
            if platform == "codex" and namespace == "skills":
                text = transform_codex_skill_markdown(logical_rel, text)
            elif platform == "claude-code" and namespace == "skills":
                text = transform_claude_skill_markdown(logical_rel, text)
            dst.write_text(text, encoding="utf-8")
        else:
            shutil.copy2(src, dst)

        generated_paths.append(dst_rel.as_posix())

    marker = {
        "generated_by": "cadence",
        "platform": platform,
        "mode": mode,
        "version": cadence_version(repo_root),
        "source": str(repo_root),
        "skills": skills,
        "agents": agents,
        "files": generated_paths,
    }
    (target_root / MARKER_FILE).write_text(json.dumps(marker, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("claude-code", "codex"), required=True)
    parser.add_argument("repo_root", type=Path)
    parser.add_argument("target_root", type=Path)
    args = parser.parse_args()

    generate(args.repo_root.resolve(), args.target_root.resolve(), args.platform)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
