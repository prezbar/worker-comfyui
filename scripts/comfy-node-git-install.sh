#!/usr/bin/env bash
# comfy-node-git-install: clone a custom ComfyUI node at a pinned commit
# Usage: comfy-node-git-install <repo-url> <commit> [<node-name>]
set -euo pipefail

REPO_URL="${1:?repo URL required}"
COMMIT="${2:?commit hash required}"
NODE_NAME="${3:-$(basename "$REPO_URL" .git)}"
DEST="/comfyui/custom_nodes/${NODE_NAME}"

git clone "$REPO_URL" --no-checkout "$DEST"
git -C "$DEST" checkout --quiet "$COMMIT"

if [[ -f "$DEST/requirements.txt" ]]; then
    pip install --no-cache-dir -r "$DEST/requirements.txt"
fi

rm -rf "$DEST/.git"
