<#
.SYNOPSIS
    Sync this KytyPS5 fork's main branch with upstream KytyPS5.

.DESCRIPTION
    KytyPS5-only. Fast-forwards fork main to upstream main when the fork has no
    unique commits, and otherwise reports the divergence instead of guessing.

    It never force-pushes and never discards commits: if fork main has commits
    that upstream does not, it stops and tells you so.

.PARAMETER Remote
    Name of the upstream remote. Added automatically when missing.
    Default: upstream

.PARAMETER Url
    Upstream repository URL.
    Default: https://github.com/KytyPS5/KytyPS5.git

.PARAMETER Branch
    Branch to sync. Default: main

.PARAMETER Push
    Push the fast-forward to the fork when it succeeds.

.EXAMPLE
    .\sync-fork.ps1 -Push
#>
[CmdletBinding()]
param(
    [string]$Remote = 'upstream',
    [string]$Url = 'https://github.com/KytyPS5/KytyPS5.git',
    [string]$Branch = 'main',
    [switch]$Push
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step([string]$text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Info([string]$text) { Write-Host "  $text" }
function Write-Warn2([string]$text) { Write-Host "  $text" -ForegroundColor Yellow }

if (-not (Test-Path -LiteralPath '.git')) { throw 'Run this from the KytyPS5 checkout root.' }

$remotes = @(git remote)
if ($remotes -notcontains $Remote) {
    Write-Info "Adding remote $Remote -> $Url"
    git remote add $Remote $Url
}

Write-Step "Fetching $Remote"
git fetch $Remote $Branch
if ($LASTEXITCODE -ne 0) { throw "git fetch failed (exit $LASTEXITCODE)." }

$forkTip     = (git rev-parse $Branch).Trim()
$upstreamTip = (git rev-parse "$Remote/$Branch").Trim()
Write-Info "$Branch          : $forkTip"
Write-Info "$Remote/$Branch : $upstreamTip"

if ($forkTip -eq $upstreamTip) {
    Write-Host "`nAlready in sync." -ForegroundColor Green
    return
}

git merge-base --is-ancestor $Branch "$Remote/$Branch"
$forkIsAncestor = ($LASTEXITCODE -eq 0)

if ($forkIsAncestor) {
    Write-Step 'Fast-forwarding'
    $behind = (git rev-list --count "$Branch..$Remote/$Branch").Trim()
    Write-Info "$behind commit(s) to bring in"
    git checkout $Branch
    git merge --ff-only "$Remote/$Branch"
    if ($LASTEXITCODE -ne 0) { throw "fast-forward failed (exit $LASTEXITCODE)." }
    git submodule update --init --recursive
    Write-Info "now at $((git rev-parse $Branch).Trim())"

    if ($Push) {
        Write-Step 'Pushing'
        git push origin $Branch
        if ($LASTEXITCODE -ne 0) { throw "git push failed (exit $LASTEXITCODE)." }
    } else {
        Write-Warn2 'Not pushed; re-run with -Push to update the fork.'
    }
} else {
    $unique = (git rev-list --count "$Remote/$Branch..$Branch").Trim()
    Write-Warn2 "Fork $Branch has $unique commit(s) upstream does not."
    Write-Warn2 'Not fast-forwarding. Rebase or merge manually:'
    Write-Warn2 "    git rebase $Remote/$Branch"
    git log --oneline "$Remote/$Branch..$Branch" | ForEach-Object { Write-Warn2 "      $_" }
    throw 'Fork has diverged; resolve manually.'
}
