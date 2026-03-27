#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/RevenueCat/docs"
BRANCH="main"
REPO_DIR="source-repo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Clone (skip if already exists) ---
if [ ! -d "$REPO_DIR" ]; then
    # RevenueCat/docs is a private repository — requires GITHUB_PAT
    if [ -z "${GITHUB_PAT:-}" ]; then
        echo "[ERROR] GITHUB_PAT is not set. RevenueCat/docs is a private repository."
        exit 1
    fi
    CLONE_URL="https://x-access-token:${GITHUB_PAT}@github.com/RevenueCat/docs.git"
    git clone --depth 1 --branch "$BRANCH" "$CLONE_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

# --- Node version ---
# Docusaurus 3.9.2 requires Node >=18; repo uses Node 22
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
    nvm use 22 2>/dev/null || nvm install 22
fi
NODE_MAJOR=$(node --version | sed 's/v//' | cut -d. -f1)
echo "[INFO] Using Node $(node --version)"
if [ "$NODE_MAJOR" -lt 18 ]; then
    echo "[ERROR] Node $NODE_MAJOR is too old; Docusaurus 3.x requires Node >=18"
    exit 1
fi

# --- Package manager: Yarn ---
# Ensure Yarn is available
if ! command -v yarn &>/dev/null; then
    echo "[INFO] Installing yarn..."
    npm install -g yarn
fi
echo "[INFO] Yarn version: $(yarn --version)"

# Handle Yarn 4+ (Berry) if packageManager field is present
if grep -q '"packageManager"' package.json 2>/dev/null; then
    PM_FIELD=$(node -e "try{const p=require('./package.json');console.log(p.packageManager||'')}catch(e){}" 2>/dev/null)
    if echo "$PM_FIELD" | grep -qE "yarn@[4-9]"; then
        echo "[INFO] Detected Yarn 4+ (Berry): $PM_FIELD"
        if ! command -v corepack &>/dev/null; then
            npm install -g corepack
        fi
        corepack enable
        corepack prepare --activate 2>/dev/null || true
    fi
fi

# --- Dependencies ---
yarn install --frozen-lockfile 2>/dev/null || yarn install

# --- Apply fixes.json if present ---
FIXES_JSON="$SCRIPT_DIR/fixes.json"
if [ -f "$FIXES_JSON" ]; then
    echo "[INFO] Applying content fixes..."
    node -e "
    const fs = require('fs');
    const path = require('path');
    const fixes = JSON.parse(fs.readFileSync('$FIXES_JSON', 'utf8'));
    for (const [file, ops] of Object.entries(fixes.fixes || {})) {
        if (!fs.existsSync(file)) { console.log('  skip (not found):', file); continue; }
        let content = fs.readFileSync(file, 'utf8');
        for (const op of ops) {
            if (op.type === 'replace' && content.includes(op.find)) {
                content = content.split(op.find).join(op.replace || '');
                console.log('  fixed:', file, '-', op.comment || '');
            }
        }
        fs.writeFileSync(file, content);
    }
    for (const [file, cfg] of Object.entries(fixes.newFiles || {})) {
        const c = typeof cfg === 'string' ? cfg : cfg.content;
        fs.mkdirSync(path.dirname(file), {recursive: true});
        fs.writeFileSync(file, c);
        console.log('  created:', file);
    }
    "
fi

echo "[DONE] Repository is ready for docusaurus commands."
