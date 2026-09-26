#!/usr/bin/env bash
# 一键建库并推送（bash / Git Bash）
#
# 前置：git 与 gh 已装好，且已 `gh auth login`。
# 用法： bash scripts/publish.sh
#
# 只想建库不推送 / 换个仓库名，改下面的 REPO_NAME 即可。

set -euo pipefail

REPO_NAME="liquid-miuix"
VISIBILITY="--public"     # 想先私有就改成 --private
DESCRIPTION="MIUI/HyperOS style + true liquid glass (with refraction) for Jetpack Compose"

# 这个脚本放在 <repo>/scripts/ 下，所以仓库根是它的上一级
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> 检查登录状态"
if ! gh auth status; then
    echo "还没登录。先执行： gh auth login"
    exit 1
fi

echo "==> 确认工作区干净"
if [ -n "$(git status --porcelain)" ]; then
    echo "有未提交的改动，先提交："
    git status --short
    exit 1
fi

echo "==> 创建仓库 $REPO_NAME"
# 已存在时会报错，忽略即可（下面照常推送）
gh repo create "$REPO_NAME" $VISIBILITY --source=. --description="$DESCRIPTION" 2>/dev/null || true

echo "==> 推送"
OWNER="$(gh api user --jq .login)"
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$OWNER/$REPO_NAME.git"
git push -u origin main

echo
echo "完成： https://github.com/$OWNER/$REPO_NAME"
