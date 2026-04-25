#!/usr/bin/env python3
"""Remove files listed in a Cadence generated-package marker safely."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def path_is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def marker_paths(marker: Path) -> list[Path]:
    if not marker.exists():
        return []

    with marker.open(encoding="utf-8") as f:
        data = json.load(f)

    paths: list[Path] = []
    for raw_path in data.get("files", []):
        rel = Path(raw_path)
        if rel.is_absolute() or ".." in rel.parts:
            raise ValueError(f"Refusing unsafe generated path in marker: {raw_path!r}")
        paths.append(rel)
    return paths


def remove_generated_package(root: Path, marker: Path) -> None:
    if not marker.exists():
        return

    root_resolved = root.resolve()
    marker_resolved = marker.resolve()
    if not path_is_relative_to(marker_resolved, root_resolved):
        raise ValueError(f"Refusing marker outside package root: {marker}")

    files = marker_paths(marker)

    for rel in sorted(files, key=lambda path: len(path.parts), reverse=True):
        path = root / rel
        parent_resolved = path.parent.resolve()
        if not path_is_relative_to(parent_resolved, root_resolved):
            raise ValueError(f"Refusing generated path outside package root: {rel}")

        try:
            if path.is_file() or path.is_symlink():
                path.unlink()
        except FileNotFoundError:
            pass

    dirs = set()
    for rel in files:
        current = (root / rel).parent
        while current != root:
            current_resolved = current.resolve()
            if not path_is_relative_to(current_resolved, root_resolved):
                raise ValueError(f"Refusing generated directory outside package root: {current}")
            dirs.add(current)
            current = current.parent

    for directory in sorted(dirs, key=lambda path: len(path.parts), reverse=True):
        try:
            directory.rmdir()
        except OSError:
            pass

    marker.unlink()


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: remove_generated_package.py <package-root> <marker-file>",
            file=sys.stderr,
        )
        return 2

    try:
        remove_generated_package(Path(sys.argv[1]), Path(sys.argv[2]))
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
