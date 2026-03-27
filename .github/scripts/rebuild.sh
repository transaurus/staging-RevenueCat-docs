#!/usr/bin/env bash
set -euo pipefail

# Rebuild script for RevenueCat/docs
# Runs on existing source tree (no clone). Installs deps, runs pre-build steps, builds.

# --- Node version ---
# Docusaurus 3.9.2 requires Node >=18; repo uses Node 22
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
    nvm use 22 2>/dev/null || nvm install 22
fi
echo "[INFO] Using Node $(node --version)"

# --- Package manager: Yarn ---
if ! command -v yarn &>/dev/null; then
    echo "[INFO] Installing yarn..."
    npm install -g yarn
fi

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

# --- Build ---
yarn build

echo "[DONE] Build complete."
