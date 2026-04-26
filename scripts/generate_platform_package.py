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

# Skills excluded from default installs on every platform.
# These are author-facing meta tools (e.g. writing-skills, which teaches
# agents how to author new skills). They live in the cadence repository
# for maintainers; users who want them should read the source tree directly.
META_SKILLS: frozenset[str] = frozenset({"writing-skills"})

CODEX_CORE_SKILL_FILES: dict[str, list[str]] = {
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

CODEX_AGENT_FILES = [
    "code-reviewer.md",
]


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


def render_requesting_code_review(source_text: str) -> str:
    text = source_text
    text = text.replace(
        "Dispatch code-reviewer subagent to catch issues before they cascade.",
        "Dispatch the `code-reviewer` custom subagent to catch issues before they cascade.",
    )
    text = text.replace(
        "Use Agent tool with subagent_type: code-reviewer, fill template at `code-reviewer.md`",
        'Use `spawn_agent(agent_type="code-reviewer")`, filling the template at `code-reviewer.md`',
    )
    text = text.replace(
        "[Dispatch code-reviewer subagent]",
        'spawn_agent(agent_type="code-reviewer"):',
    )
    return tidy_markdown(text)


def render_code_reviewer_prompt(source_text: str) -> str:
    return source_text.replace(
        "# Code Review Agent\n\nYou are reviewing code changes for production readiness.\n",
        (
            "# Code Review Prompt\n\n"
            "Use this file as the `message` for `spawn_agent(agent_type=\"code-reviewer\", ...)`.\n\n"
            "The named `code-reviewer` subagent supplies the reviewer persona. This prompt supplies the specific scope, diff range, and output format.\n"
        ),
        1,
    )


def render_dispatching_parallel_agents(source_text: str) -> str:
    text = cleanup_codex_generic(source_text)
    text = text.replace("// In Codex / AI environment", "// In Codex")
    return tidy_markdown(text)


def render_subagent_driven_development(source_text: str) -> str:
    text = cleanup_codex_generic(source_text)
    text = text.replace("[Dispatch final code-reviewer]", "[Dispatch final code-reviewer subagent]")
    return tidy_markdown(text)


def convert_task_prompt_block(text: str) -> str:
    start = text.find("```\nAgent tool (")
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
        "Use this template when dispatching the `code-reviewer` subagent.",
        1,
    )
    text = text.replace(
        "Agent tool (subagent_type: code-reviewer):",
        'spawn_agent(agent_type="code-reviewer"):',
        1,
    )
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


def cleanup_codex_generic(text: str) -> str:
    replacements = [
        ("TodoWrite", "update_plan"),
        ("Agent tool", "spawn_agent"),
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
        r'\bAgent\(\{[^}]*prompt:\s*"([^"]+)"[^}]*\}\)',
        r'spawn_agent(agent_type="worker", message="\1")',
        text,
    )
    return text


def parse_agent_markdown(source_text: str) -> tuple[dict[str, str], str]:
    match = re.match(r"\A---\n(.*?)\n---\n(.*)\Z", source_text, re.DOTALL)
    if not match:
        raise ValueError("Agent markdown must start with YAML frontmatter")

    frontmatter, body = match.groups()
    data: dict[str, str] = {}
    lines = frontmatter.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if ":" not in line:
            raise ValueError(f"Unsupported frontmatter line: {line!r}")

        key, value = line.split(":", 1)
        key = key.strip()
        value = value.lstrip()

        if value.rstrip() in {"|", "|-", "|+"}:
            i += 1
            block_lines: list[str] = []
            while i < len(lines):
                block_line = lines[i]
                if block_line.startswith("  "):
                    block_lines.append(block_line[2:])
                    i += 1
                    continue
                if not block_line.strip():
                    block_lines.append("")
                    i += 1
                    continue
                break
            data[key] = "\n".join(block_lines).rstrip()
            continue

        data[key] = value.strip().strip('"').strip("'")
        i += 1

    return data, body.strip()


def toml_basic_string(value: str) -> str:
    return json.dumps(value)


def toml_multiline_literal(value: str) -> str:
    if "'''" in value:
        return json.dumps(value)
    return "'''\n" + value.rstrip() + "\n'''"


def codex_agent_description(frontmatter: dict[str, str]) -> str:
    description = frontmatter.get("codex_description") or frontmatter.get("description")
    if not description:
        raise ValueError("Agent markdown must provide description")

    description = re.split(r"\bExamples?:", description, maxsplit=1)[0].strip()
    description = re.sub(r"<[^>]+>", "", description).strip()
    return description


def transform_codex_agent_markdown(logical_rel: Path, source_text: str) -> str:
    frontmatter, body = parse_agent_markdown(source_text)
    name = frontmatter.get("name")
    if not name:
        raise ValueError("Agent markdown must provide name")
    description = codex_agent_description(frontmatter)

    developer_instructions = tidy_markdown(body)

    return (
        f"name = {toml_basic_string(name)}\n"
        f"description = {toml_basic_string(description)}\n"
        'sandbox_mode = "read-only"\n'
        f"developer_instructions = {toml_multiline_literal(developer_instructions)}\n"
    )


CODEX_FULL_RENDERERS = {
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

    return cleanup_codex_generic(text)


def transform_claude_skill_markdown(rel_path: Path, text: str) -> str:
    rel_str = rel_path.as_posix()

    if rel_str == "brainstorming/visual-companion.md":
        return transform_visual_companion_claude(text)
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

    agents_root = repo_root / "agents"
    for rel_path in CODEX_AGENT_FILES:
        logical_rel = Path(rel_path)
        dst_rel = Path("agents") / logical_rel.with_suffix(".toml")
        items.append((agents_root / logical_rel, dst_rel, "agents", logical_rel))

    return items


def selected_claude_items(repo_root: Path) -> list[tuple[Path, Path, str, Path]]:
    items: list[tuple[Path, Path, str, Path]] = []
    skills_root = repo_root / "skills"
    for src in iter_files(skills_root):
        logical_rel = src.relative_to(skills_root)
        if logical_rel.parts[0] in META_SKILLS:
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

    existing_skills = {p.name for p in (repo_root / "skills").iterdir() if p.is_dir()}
    unknown_meta = META_SKILLS - existing_skills
    if unknown_meta:
        raise ValueError(
            f"META_SKILLS references unknown skills (typo or rename?): {sorted(unknown_meta)}"
        )

    if platform == "codex":
        items = selected_codex_items(repo_root)
        skills = list(CODEX_CORE_SKILL_FILES)
        agents = [Path(path).with_suffix(".toml").as_posix() for path in CODEX_AGENT_FILES]
        mode = "core-native-skill-pack"
    else:
        items = selected_claude_items(repo_root)
        skills = sorted(
            path.name
            for path in (repo_root / "skills").iterdir()
            if path.is_dir() and path.name not in META_SKILLS
        )
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
            elif platform == "codex" and namespace == "agents":
                text = transform_codex_agent_markdown(logical_rel, text)
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
