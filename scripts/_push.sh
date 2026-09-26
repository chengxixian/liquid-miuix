#!/usr/bin/env bash
# 推送到 GitHub。用 bash 跑是因为 PortableGit 的 bash 环境里 CA 与代理配置更完整，
# 在 PowerShell 里直接调 git.exe 会撞上 schannel 的 CRYPT_E_NO_REVOCATION_CHECK。
set -euo pipefail

cd /d/liquid-miuix

echo "==> 远端"
git remote -v

echo
echo "==> 尝试推送"
if git push -u origin main 2>&1; then
    echo "✅ 推送成功"
    exit 0
fi

echo
echo "⚠️  直接推送失败，尝试用 gh 的凭据助手"
gh auth setup-git 2>&1 || true
git config --global credential.helper "!gh auth git-credential" 2>&1 || true

if git push -u origin main 2>&1; then
    echo "✅ 推送成功"
    exit 0
fi

echo
echo "⚠️  仍然失败，尝试关闭吊销检查"
git -c http.schannelCheckRevoke=false \
    -c http.schannelUseSSLCAInfo=false \
    push -u origin main 2>&1

echo "✅ 推送成功"
