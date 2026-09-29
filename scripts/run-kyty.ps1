<#
.SYNOPSIS
    Run a game on a KytyPS5 build, or build this KytyPS5 checkout and run it.

.DESCRIPTION
    KytyPS5-only. No AnyPS5 paths, no relinker, no payload staging: Kyty loads
    the game folder itself.

    With no -Build it uses a downloaded release build and auto-detects
    kyty_emulator.exe in the usual extraction folders. With -Build it compiles
    the checkout and runs the result.

    Kyty writes its logs (_kyty.txt, _Shaders, _PipelineCache) relative to the
    working directory, so this runs from the emulator's folder and reports where
    they landed.

.PARAMETER Game
    Game directory (the folder holding eboot.bin), an ELF, or a .zar archive.

.PARAMETER Emulator
    Path to kyty_emulator.exe, or to the folder containing it. Skips
    auto-detection.

.PARAMETER RepoPath
    KytyPS5 source checkout, used only with -Build. Defaults to the folder
    containing this script when it looks like a checkout, so the script works
    whether it sits in a git clone or in a folder of downloaded scripts.

.PARAMETER Build
    Configure and build this checkout instead of using a release binary.
    Needs clang-cl, Ninja, glslang and the MSVC toolchain (see notes).

.PARAMETER Clean
    Delete the build directory before configuring (implies -Build).

.PARAMETER ExtraArgs
    Extra arguments for kyty_emulator.exe, e.g. @('--present-mode','Fifo').

.PARAMETER VulkanValidation
    Pass --vulkan-validation true. Off by default: Kyty treats any Vulkan
    validation error as fatal and aborts on benign swapchain issues.

.EXAMPLE
    .\run-kyty.ps1 -Game 'D:\Games\SAROS-PPSA07631'

.EXAMPLE
    .\run-kyty.ps1 -Game 'D:\Games\SAROS-PPSA07631' -Emulator 'C:\Users\me\Downloads\KytyPS5-latest-Windows-x64'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Game,

    [string]$Emulator,
    [string]$RepoPath,
    [switch]$Build,
    [switch]$Clean,
    [string[]]$ExtraArgs = @(),
    [switch]$VulkanValidation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step([string]$text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Info([string]$text) { Write-Host "  $text" }
function Write-Warn2([string]$text) { Write-Host "  $text" -ForegroundColor Yellow }

function Find-KytyEmulator {
    $candidates = @(
        (Join-Path $env:USERPROFILE 'KytyPS5-latest'),
        (Join-Path $env:USERPROFILE 'KytyPS5'),
        (Join-Path $env:USERPROFILE 'Downloads\KytyPS5-latest-Windows-x64'),
        (Join-Path $env:USERPROFILE 'Downloads\KytyPS5-Windows-x64'),
        (Join-Path $env:USERPROFILE 'Downloads')
    )
    foreach ($dir in $candidates) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        $direct = Join-Path $dir 'kyty_emulator.exe'
        if (Test-Path -LiteralPath $direct -PathType Leaf) { return $direct }
        $nested = Get-ChildItem -LiteralPath $dir -Recurse -Depth 2 -File -Filter 'kyty_emulator.exe' -ErrorAction SilentlyContinue |
                  Select-Object -First 1 -ExpandProperty FullName
        if ($nested) { return $nested }
    }
    return $null
}

try {
    $gameExists = Test-Path -LiteralPath $Game
} catch {
    # Test-Path throws rather than returning false for paths with characters
    # Windows forbids, such as the angle brackets in documentation examples.
    throw "Game path is not a valid Windows path: $Game`n$($_.Exception.Message)"
}
if (-not $gameExists) { throw "Game not found: $Game" }
$Game = (Resolve-Path -LiteralPath $Game).Path

if ($Clean) { $Build = $true }

# Kyty wants the directory that directly contains eboot.bin. PS5 dumps often
# nest it (for example <game>\<titleid>-app0\eboot.bin), so look a few
# levels down rather than making the caller find the exact folder.
function Resolve-GameDir([string]$path) {
    if (Test-Path -LiteralPath (Join-Path $path 'eboot.bin') -PathType Leaf) { return $path }
    $found = Get-ChildItem -LiteralPath $path -Recurse -Depth 3 -File -Filter 'eboot.bin' -ErrorAction SilentlyContinue |
              Select-Object -First 1 -ExpandProperty FullName
    if ($found) { return (Split-Path -Parent $found) }
    return $path
}

if (Test-Path -LiteralPath $Game -PathType Container) {
    $resolved = Resolve-GameDir $Game
    if ($resolved -ne $Game) {
        Write-Info "Using nested game folder: $resolved"
        $Game = $resolved
    }
}

# Default RepoPath to the folder holding this script, but only when it is a
# real checkout. Scripts copied into an arbitrary folder must not be mistaken
# for one.
if (-not $RepoPath) {
    $scriptDir = Split-Path -Parent $PSCommandPath
    $RepoPath  = if (Test-Path -LiteralPath (Join-Path $scriptDir 'CMakeLists.txt')) {
        $scriptDir
    } else {
        # In a clone this script lives in <repo>\scripts, so try one level up.
        Split-Path -Parent $scriptDir
    }
}
if ($Build -and -not (Test-Path -LiteralPath (Join-Path $RepoPath 'CMakeLists.txt'))) {
    Write-Warn2 "No CMakeLists.txt in $RepoPath"
    Write-Warn2 'Point -RepoPath at the KytyPS5 git clone, or clone it first:'
    Write-Warn2 "    git clone --recurse-submodules https://github.com/nahshongraham97/KytyPS5.git $RepoPath"
    throw "Not a KytyPS5 checkout: $RepoPath"
}

$exe = $null

if ($Build) {
    Write-Step 'Building KytyPS5'
    foreach ($tool in @('cmake', 'ninja', 'clang-cl', 'glslangValidator')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Write-Warn2 "missing $tool on PATH (run from an x64 Native Tools / Developer PowerShell)"
        }
    }

    $buildDir = Join-Path $RepoPath '_Build\windows'
    if ($Clean -and (Test-Path -LiteralPath $buildDir)) {
        Remove-Item -LiteralPath $buildDir -Recurse -Force
    }
    Push-Location $RepoPath
    try {
        # KYTY_BUILD_LAUNCHER=OFF skips the Qt launcher, so Qt is not needed.
        # Kyty requires clang-cl; cl.exe and MinGW g++ are rejected.
        cmake -S . -B _Build/windows -G Ninja -DCMAKE_BUILD_TYPE=Release `
            -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl `
            -DKYTY_BUILD_LAUNCHER=OFF
        if ($LASTEXITCODE -ne 0) { throw "cmake configure failed (exit $LASTEXITCODE)." }
        cmake --build _Build/windows --target kyty_emulator --parallel
        if ($LASTEXITCODE -ne 0) { throw "cmake build failed (exit $LASTEXITCODE)." }
    } finally { Pop-Location }

    $exe = Get-ChildItem -LiteralPath $buildDir -Recurse -File -Filter 'kyty_emulator.exe' -ErrorAction SilentlyContinue |
           Select-Object -First 1 -ExpandProperty FullName
    if (-not $exe) { throw "kyty_emulator.exe not found under $buildDir after the build." }
} elseif ($Emulator) {
    if (Test-Path -LiteralPath $Emulator -PathType Container) {
        $exe = Join-Path $Emulator 'kyty_emulator.exe'
    } else {
        $exe = $Emulator
    }
} else {
    $exe = Find-KytyEmulator
}

if (-not $exe -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    Write-Warn2 'kyty_emulator.exe not found. Download a release and pass -Emulator:'
    Write-Warn2 '  https://github.com/KytyPS5/KytyPS5/releases/latest'
    throw "KytyPS5 not found: $exe"
}

$arguments = @('--game', $Game)
if (-not $VulkanValidation) { $arguments += @('--vulkan-validation', 'false') }
if ($ExtraArgs.Count -gt 0) { $arguments += $ExtraArgs }

Write-Host "KytyPS5 runner" -ForegroundColor Green
Write-Info "Emulator : $exe"
Write-Info "Game     : $Game"

Write-Step 'Running'
Write-Info ("kyty_emulator.exe " + ($arguments -join ' '))
$runDir = Split-Path -Parent $exe
Push-Location $runDir
try { & $exe @arguments } finally { Pop-Location }

Write-Step 'Logs'
Write-Info "Kyty wrote its logs next to the emulator: $runDir"
foreach ($name in @('_kyty.txt', '_Shaders', '_PipelineCache', '_Textures')) {
    $path = Join-Path $runDir $name
    if (Test-Path -LiteralPath $path) { Write-Info "  $path" }
}
