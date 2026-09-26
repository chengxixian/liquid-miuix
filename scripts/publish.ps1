# 一键建库并推送
#
# 前置：git 与 gh 已装好，且已 `gh auth login`。
# 用法：在 PowerShell 里执行
#     pwsh -File scripts/publish.ps1
# 或在 bash / Git Bash 里执行
#     bash scripts/publish.sh
#
# 只想建库不推送 / 换个仓库名，改下面的 $RepoName 即可。

$ErrorActionPreference = "Stop"

$RepoName   = "liquid-miuix"
$Visibility = "--public"     # 想先私有就改成 --private
$Description = "MIUI/HyperOS style + true liquid glass (with refraction) for Jetpack Compose"

# 这个脚本放在 <repo>/scripts/ 下，所以仓库根是它的上一级
$RepoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $RepoRoot

Write-Host "==> 检查登录状态" -ForegroundColor Cyan
gh auth status
if ($LASTEXITCODE -ne 0) {
    Write-Host "还没登录。先执行： gh auth login" -ForegroundColor Yellow
    exit 1
}

Write-Host "==> 确认工作区干净" -ForegroundColor Cyan
$dirty = git status --porcelain
if ($dirty) {
    Write-Host "有未提交的改动，先提交：" -ForegroundColor Yellow
    git status --short
    exit 1
}

Write-Host "==> 创建仓库 $RepoName" -ForegroundColor Cyan
# 已存在时会报错，忽略即可（下面照常推送）
gh repo create $RepoName $Visibility --source=. --description=$Description 2>$null

Write-Host "==> 推送" -ForegroundColor Cyan
$owner = gh api user --jq .login
git remote remove origin 2>$null
git remote add origin "https://github.com/$owner/$RepoName.git"
git push -u origin main

Write-Host ""
Write-Host "完成： https://github.com/$owner/$RepoName" -ForegroundColor Green
