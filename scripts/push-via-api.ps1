# 用 GitHub Git Database API 推送，绕开 git 的 TLS 传输层。
#
# 为什么需要它：本机存在 TLS 中间代理，
#   - schannel 后端报 CRYPT_E_NO_REVOCATION_CHECK
#   - openssl 后端报 unable to get local issuer certificate
# 而 gh（Go 自带证书栈）能正常访问 GitHub。所以改用 gh api 直接建 blob/tree/commit/ref。
#
# 用法： pwsh -File scripts/push-via-api.ps1 -Owner <用户> -Repo <仓库>

param(
    [Parameter(Mandatory = $true)][string]$Owner,
    [Parameter(Mandatory = $true)][string]$Repo,
    [string]$Branch = "main",
    [string]$Message = "chore: 用 API 推送"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $RepoRoot

function Invoke-Gh {
    # 注意：参数名不能叫 $Args —— 那是 PowerShell 自动变量，会让脚本解析失败。
    param([string[]]$GhArgs)
    $json = & gh api @GhArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gh api 失败: $($GhArgs -join ' ')`n$json"
    }
    return ($json -join "`n")
}

# gh api 的 -f 会把值当字符串、-F 会做类型推断；文件内容必须当字符串传，
# 且不能经过 shell 转义 —— 所以走 stdin。
function New-Blob {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $b64 = [Convert]::ToBase64String($bytes)

    # 用 --input - 从 stdin 读 JSON body，避免命令行长度与转义问题
    $body = @{ content = $b64; encoding = "base64" } | ConvertTo-Json -Compress
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $body, [System.Text.UTF8Encoding]::new($false))
        $out = & gh api "repos/$Owner/$Repo/git/blobs" --method POST -H "Content-Type: application/json" --input $tmp 2>&1
        if ($LASTEXITCODE -ne 0) { throw "建 blob 失败 ($Path): $out" }
        return (($out -join "`n") | ConvertFrom-Json).sha
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "==> 读取远端当前状态" -ForegroundColor Cyan
$repoInfo = (Invoke-Gh @("repos/$Owner/$Repo")) | ConvertFrom-Json
$branchName = $repoInfo.default_branch
Write-Host "  默认分支: $branchName"

$parentSha = $null
try {
    $ref = (Invoke-Gh @("repos/$Owner/$Repo/git/ref/heads/$branchName")) | ConvertFrom-Json
    $parentSha = $ref.object.sha
    Write-Host "  当前 HEAD: $parentSha"
} catch {
    Write-Host "  分支还不存在（空仓库），走首次提交" -ForegroundColor Yellow
}

# 收集所有被 git 跟踪的文件
Write-Host "==> 收集文件" -ForegroundColor Cyan
$tracked = & git ls-files
if (-not $tracked) { throw "git ls-files 为空，先在本地 git add / commit" }
Write-Host "  $($tracked.Count) 个文件"

Write-Host "==> 上传 blobs" -ForegroundColor Cyan
$tree = @()
$i = 0
foreach ($rel in $tracked) {
    $i++
    $full = Join-Path $RepoRoot ($rel -replace '/', '\')
    if (-not (Test-Path $full)) { Write-Host "  跳过（不存在）: $rel" -ForegroundColor Yellow; continue }

    $sha = New-Blob -Path $full
    # mode 100755 给 .sh，其余 100644
    $mode = if ($rel -like "*.sh") { "100755" } else { "100644" }
    $tree += @{ path = $rel; mode = $mode; type = "blob"; sha = $sha }
    Write-Host ("  [{0,2}/{1}] {2}" -f $i, $tracked.Count, $rel)
}

Write-Host "==> 建 tree" -ForegroundColor Cyan
$treeBody = @{ tree = $tree } | ConvertTo-Json -Depth 6 -Compress
$tmpTree = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($tmpTree, $treeBody, [System.Text.UTF8Encoding]::new($false))
$treeOut = & gh api "repos/$Owner/$Repo/git/trees" --method POST -H "Content-Type: application/json" --input $tmpTree 2>&1
Remove-Item $tmpTree -Force -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) { throw "建 tree 失败: $treeOut" }
$treeSha = (($treeOut -join "`n") | ConvertFrom-Json).sha
Write-Host "  tree: $treeSha"

Write-Host "==> 建 commit" -ForegroundColor Cyan
$commitObj = @{ message = $Message; tree = $treeSha }
if ($parentSha) { $commitObj.parents = @($parentSha) }
$commitBody = $commitObj | ConvertTo-Json -Depth 5 -Compress
$tmpCommit = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($tmpCommit, $commitBody, [System.Text.UTF8Encoding]::new($false))
$commitOut = & gh api "repos/$Owner/$Repo/git/commits" --method POST -H "Content-Type: application/json" --input $tmpCommit 2>&1
Remove-Item $tmpCommit -Force -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) { throw "建 commit 失败: $commitOut" }
$commitSha = (($commitOut -join "`n") | ConvertFrom-Json).sha
Write-Host "  commit: $commitSha"

Write-Host "==> 更新分支引用" -ForegroundColor Cyan
$refBody = @{ sha = $commitSha; force = $true } | ConvertTo-Json -Compress
$tmpRef = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($tmpRef, $refBody, [System.Text.UTF8Encoding]::new($false))
if ($parentSha) {
    $refOut = & gh api "repos/$Owner/$Repo/git/refs/heads/$branchName" --method PATCH -H "Content-Type: application/json" --input $tmpRef 2>&1
} else {
    $createBody = @{ ref = "refs/heads/$branchName"; sha = $commitSha } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($tmpRef, $createBody, [System.Text.UTF8Encoding]::new($false))
    $refOut = & gh api "repos/$Owner/$Repo/git/refs" --method POST -H "Content-Type: application/json" --input $tmpRef 2>&1
}
Remove-Item $tmpRef -Force -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) { throw "更新引用失败: $refOut" }

Write-Host ""
Write-Host "✅ 推送完成: https://github.com/$Owner/$Repo" -ForegroundColor Green
