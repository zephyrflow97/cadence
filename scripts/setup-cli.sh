#!/usr/bin/env bash
# One-shot bootstrap: expose `cadence` on PATH so you can run it from anywhere.
# Safe to re-run — updates the symlink, appends to rc only when missing.
#
# Usage: bash scripts/setup-cli.sh

set -euo pipefail

CADENCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY="$CADENCE_ROOT/bin/cadence"

[[ -x "$ENTRY" ]] || { echo "error: $ENTRY missing or not executable" >&2; exit 1; }

# 1. Pick a PATH directory. Prefer one that's already in PATH; otherwise default
#    to ~/.local/bin and append it to the user's shell rc.
BIN_DIR=""
for cand in "$HOME/.local/bin" "$HOME/bin"; do
  if [[ ":$PATH:" == *":$cand:"* ]]; then
    BIN_DIR="$cand"
    break
  fi
done

ADDED_RC=""
if [[ -z "$BIN_DIR" ]]; then
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"

  case "$(basename "${SHELL:-bash}")" in
    zsh)  rc="$HOME/.zshrc" ;;
    bash) [[ "$(uname)" == "Darwin" ]] && rc="$HOME/.bash_profile" || rc="$HOME/.bashrc" ;;
    fish)
      # fish uses a different PATH syntax; write to its conf.d
      mkdir -p "$HOME/.config/fish/conf.d"
      rc="$HOME/.config/fish/conf.d/cadence.fish"
      ;;
    *)    rc="$HOME/.profile" ;;
  esac
  touch "$rc"

  marker="# cadence CLI setup"
  if ! grep -qF "$marker" "$rc"; then
    {
      printf '\n%s\n' "$marker"
      if [[ "$rc" == *".fish" ]]; then
        echo 'fish_add_path -g "$HOME/.local/bin"'
      else
        echo 'export PATH="$HOME/.local/bin:$PATH"'
      fi
    } >> "$rc"
    ADDED_RC="$rc"
  fi
fi

# 2. (Re)create the symlink.
link="$BIN_DIR/cadence"
if [[ -L "$link" ]]; then
  rm "$link"
elif [[ -e "$link" ]]; then
  echo "error: $link exists and is not a symlink; move or remove it first" >&2
  exit 1
fi
ln -s "$ENTRY" "$link"
echo "linked $link -> $ENTRY"

if [[ -n "$ADDED_RC" ]]; then
  echo "added PATH line to $ADDED_RC"
  echo
  echo "open a new terminal, or run:"
  echo "  source $ADDED_RC"
else
  echo "$BIN_DIR already on PATH — nothing else to do."
fi

echo
echo "try: cadence --help"
