# 用 Contents API 逐文件推送。
#
# 为什么不用更"正规"的 Git Database API（blob -> tree -> commit -> ref）：
# 本机 gh 在 POST /git/trees 上稳定返回 404（body 是合法 JSON，原因未查明）。
# Contents API 每次 PUT 一个文件、自动建一个提交，笨但可靠。
#
# 两个必须处理的坑：
#  1. **Contents API 不会自动创建父目录** —— 直接 PUT `.github/workflows/build.yml`
#     会 404，因为 `.github/` 还不存在。GitHub 也没有"建目录"接口，
#     目录是靠其中出现文件而隐式存在的，所以要先往目录里放一个 .gitkeep。
#  2. **$ErrorActionPreference = "Stop" 会把 gh 的 stderr 升级成终止错误**。
#     gh 在非 2xx 时往 stderr 写，而 404 在本脚本里是**正常信号**（文件/目录还不存在），
#     所以每次调用 gh 前后都要临时放宽它。
#
# 用法： powershell -File scripts/push-via-contents.ps1 -Owner <用户> -Repo <仓库>

param(
    [Parameter(Mandatory = $true)][string]$Owner,
    [Parameter(Mandatory = $true)][string]$Repo,
    [string]$Branch = "main",
    [string]$Message = "sync"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $RepoRoot

# 统一封装：临时放宽 ErrorActionPreference 再调 gh
function Invoke-Gh {
    param([string[]]$GhArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = & gh api @GhArgs 2>&1
        return @{ ok = ($LASTEXITCODE -eq 0); out = ($out -join "`n") }
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Get-FileSha {
    param([string]$Path)
    $r = Invoke-Gh @("repos/$Owner/$Repo/contents/$Path`?ref=$Branch")
    if (-not $r.ok) { return $null }     # 404 = 不存在，正常
    try { return ($r.out | ConvertFrom-Json).sha } catch { return $null }
}

function Put-File {
    param([string]$Path, [string]$LocalPath, [string]$CommitMessage)
    $body = @{
        message = $CommitMessage
        content = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($LocalPath))
        branch  = $Branch
    }
    $ex = Get-FileSha -Path $Path
    if ($ex) { $body.sha = $ex }

    $tf = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tf, ($body | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
        return (Invoke-Gh @(
            "repos/$Owner/$Repo/contents/$Path", "--method", "PUT",
            "-H", "Content-Type: application/json", "--input", $tf
        ))
    } finally {
        Remove-Item $tf -Force -ErrorAction SilentlyContinue
    }
}

$tracked = & git ls-files
if (-not $tracked) { throw "git ls-files 为空" }
$tracked = $tracked | Sort-Object { ($_ -split '/').Count }, { $_ }
$total = $tracked.Count
Write-Host "==> 共 $total 个文件" -ForegroundColor Cyan

$ensured = @{}

# 先拉一次远端树，把**已存在**的目录记下来。
# 否则脚本每次运行都会重新建 .gitkeep —— 明明目录早就在了，还平白多出一堆占位文件。
Write-Host "==> 读取远端已有的目录" -ForegroundColor Cyan
$remoteTree = Invoke-Gh @("repos/$Owner/$Repo/git/trees/$Branch`?recursive=1")
$existingDirs = @{}
if ($remoteTree.ok) {
    try {
        $parsed = $remoteTree.out | ConvertFrom-Json
        foreach ($entry in $parsed.tree) {
            if ($entry.type -ne "blob") { continue }
            $dir = Split-Path $entry.path -Parent
            while (-not [string]::IsNullOrEmpty($dir)) {
                $dir = $dir -replace '\\', '/'
                $existingDirs[$dir] = $true
                $dir = Split-Path $dir -Parent
            }
        }
    } catch { }
}
Write-Host "  远端已有 $($existingDirs.Count) 个目录" -ForegroundColor Cyan

function Ensure-Dir {
    param([string]$Dir)
    if ([string]::IsNullOrEmpty($Dir)) { return }
    $parts = $Dir -split '/'
    for ($d = 0; $d -lt $parts.Count; $d++) {
        $sub = ($parts[0..$d] -join '/')
        if ($ensured.ContainsKey($sub)) { continue }
        if ($existingDirs.ContainsKey($sub)) {     # 远端已有，不用建
            $ensured[$sub] = $true
            continue
        }
        $keep = "$sub/.gitkeep"
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllText($tmp, "", [System.Text.UTF8Encoding]::new($false))
            $r = Put-File -Path $keep -LocalPath $tmp -CommitMessage "chore: create dir $sub"
            if (-not $r.ok) {
                Write-Host "  建目录 $sub 失败: $($r.out)" -ForegroundColor DarkYellow
            }
        } finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
        $ensured[$sub] = $true
    }
}

$i = 0
$failed = @()
foreach ($rel in $tracked) {
    $i++
    $full = Join-Path $RepoRoot ($rel -replace '/', '\')
    if (-not (Test-Path $full)) { continue }

    # 先保证父目录存在
    $parent = Split-Path $rel -Parent
    if ($parent) { Ensure-Dir -Dir ($parent -replace '\\', '/') }

    $r = Put-File -Path $rel -LocalPath $full -CommitMessage $Message
    if ($r.ok) {
        Write-Host ("  [{0,2}/{1}] OK   {2}" -f $i, $total, $rel)
    } else {
        $failed += $rel
        Write-Host ("  [{0,2}/{1}] FAIL {2}" -f $i, $total, $rel) -ForegroundColor Red
        Write-Host "         $($r.out)" -ForegroundColor DarkGray
    }
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) 个文件失败：" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "   $_" }
    exit 1
}
Write-Host "全部推送完成: https://github.com/$Owner/$Repo" -ForegroundColor Green
