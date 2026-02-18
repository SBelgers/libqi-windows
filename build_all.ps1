<#
.SYNOPSIS
    Build libqi and libqi-python from source on Windows with MSVC.

.DESCRIPTION
    This script clones the upstream repos, applies the Windows/MSVC patches,
    and builds everything using Conan 2 + CMake + Ninja.

    Run this from a "Developer PowerShell for VS 2022" (or any shell where
    cl.exe is on the PATH).

.PARAMETER PythonVenv
    Path to the Python virtual-environment to install into.
    Defaults to the currently active venv ($env:VIRTUAL_ENV).
#>
param(
    [string]$PythonVenv = $env:VIRTUAL_ENV
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helpers ───────────────────────────────────────────────────────────────
function Bail([string]$msg) { Write-Error $msg; exit 1 }

function Test-Command([string]$cmd) {
    $null = Get-Command $cmd -ErrorAction SilentlyContinue
    return $?
}

# ── Pre-flight checks ────────────────────────────────────────────────────
if (-not (Test-Command "cl"))    { Bail "cl.exe not found. Run this from a VS Developer PowerShell." }
if (-not (Test-Command "cmake")) { Bail "cmake not found. Install CMake." }
if (-not (Test-Command "conan")) { Bail "conan not found. Install Conan 2 (pip install conan)." }
if (-not (Test-Command "git"))   { Bail "git not found." }
if (-not (Test-Command "ninja")) { Bail "ninja not found. Install Ninja (pip install ninja)." }

if (-not $PythonVenv) {
    Bail "No active virtualenv detected. Activate one or pass -PythonVenv <path>."
}
Write-Host "Using Python venv: $PythonVenv" -ForegroundColor Cyan

$RepoRoot = $PSScriptRoot          # libqi-windows/
$WorkDir  = Split-Path $RepoRoot   # parent directory where libqi/ and libqi-python/ will be cloned

# ── 1. Clone & patch libqi ────────────────────────────────────────────────
Write-Host "`n=== Cloning libqi ===" -ForegroundColor Green
Push-Location $WorkDir
if (Test-Path "libqi") {
    Write-Host "  libqi/ already exists — skipping clone."
} else {
    git clone --depth 1 --branch qi-framework-v4.0.1 https://github.com/aldebaran/libqi.git
}
Set-Location libqi

# Apply patches (skip any that are already applied)
$patches = Get-ChildItem "$RepoRoot\patches\libqi\*.patch" | Sort-Object Name
foreach ($p in $patches) {
    Write-Host "  Applying $($p.Name) ..."
    git am $p.FullName 2>$null
    if ($LASTEXITCODE -ne 0) {
        git am --abort 2>$null
        Write-Host "    (already applied or conflict — skipped)" -ForegroundColor Yellow
    }
}
Pop-Location

# ── 2. Clone & patch libqi-python ─────────────────────────────────────────
Write-Host "`n=== Cloning libqi-python ===" -ForegroundColor Green
Push-Location $WorkDir
if (Test-Path "libqi-python") {
    Write-Host "  libqi-python/ already exists — skipping clone."
} else {
    git clone --depth 1 --branch qi-python-v3.1.5 https://github.com/aldebaran/libqi-python.git
}
Set-Location libqi-python

$patches = Get-ChildItem "$RepoRoot\patches\libqi-python\*.patch" | Sort-Object Name
foreach ($p in $patches) {
    Write-Host "  Applying $($p.Name) ..."
    git am $p.FullName 2>$null
    if ($LASTEXITCODE -ne 0) {
        git am --abort 2>$null
        Write-Host "    (already applied or conflict — skipped)" -ForegroundColor Yellow
    }
}
Pop-Location

# ── 3. Build libqi ────────────────────────────────────────────────────────
Write-Host "`n=== Building libqi ===" -ForegroundColor Green
Push-Location "$WorkDir\libqi"

# Do NOT pass "-of build/release" — cmake_layout() already creates that.
conan install . -s build_type=Release --build=missing
cmake --preset conan-release
cmake --build --preset conan-release

Pop-Location

# ── 4. Build libqi-python ─────────────────────────────────────────────────
Write-Host "`n=== Building libqi-python ===" -ForegroundColor Green
Push-Location "$WorkDir\libqi-python"

conan install . -s build_type=Release --build=missing
cmake --preset conan-release
cmake --build --preset conan-release

Pop-Location

# ── 5. Install into venv ──────────────────────────────────────────────────
Write-Host "`n=== Installing qi into venv ===" -ForegroundColor Green
Push-Location "$WorkDir\libqi-python"
& "$PythonVenv\Scripts\python.exe" install_local.py
Pop-Location

# ── 6. Smoke test ─────────────────────────────────────────────────────────
Write-Host "`n=== Smoke test ===" -ForegroundColor Green
& "$PythonVenv\Scripts\python.exe" -c "import qi; print(f'qi {qi.__version__} loaded successfully')"
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nBuild complete! qi is ready to use." -ForegroundColor Green
} else {
    Bail "Smoke test failed."
}
