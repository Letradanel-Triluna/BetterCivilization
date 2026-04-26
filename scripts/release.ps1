<#
.SYNOPSIS
  Creates a BetterCivilization patch release on GitHub.

.DESCRIPTION
  1. Copies the compiled DLL from BuildOutput into Patch/Files/
  2. Rebuilds BetterCiv_BalancePatch.zip from Patch/
  3. Prepends the release notes to CHANGELOG.txt
  4. Commits and pushes all changes to git
  5. Creates a GitHub release and uploads the archive
  6. Prints the asset download URL (for the website button)

.PARAMETER Version
  Release tag, e.g. "v0.3"

.PARAMETER Notes
  Patch notes as a plain string (Markdown OK).
  Example:
    $n = @"
### Bug Fixes
- Fixed Huns pasture bonus
- Fixed Indonesia happiness
"@
    .\scripts\release.ps1 -Version v0.3 -Notes $n

.PARAMETER SkipBuild
  Pass -SkipBuild to skip copying the DLL (use if you already synced it).
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,

    [Parameter(Mandatory=$true)]
    [string]$Notes,

    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root    = Split-Path $PSScriptRoot -Parent
$DllSrc  = "$Root\CvGameCoreDLL_Expansion2\BuildOutput\VS2013_ModWin32\CvGameCoreDLL_Expansion2Win32Mod.dll"
$DllDst  = "$Root\Patch\Files\CvGameCore_Expansion2.dll"
$PatchDir  = "$Root\Patch"
$Archive   = "$Root\BetterCiv_BalancePatch.zip"
$Changelog = "$Root\Patch\CHANGELOG.txt"
$Repo    = "Letradanel-Triluna/BetterCivilization"

# ── helpers ──────────────────────────────────────────────────────────────────
function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "    ERROR: $msg" -ForegroundColor Red; exit 1 }

# ── 0. Pre-flight ─────────────────────────────────────────────────────────────
Step "Pre-flight checks"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Fail "GitHub CLI (gh) not found. Install from https://cli.github.com/"
}
$ghAuth = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) { Fail "Not logged in to gh. Run: gh auth login" }
OK "gh CLI ready"

if (-not (Test-Path $DllSrc)) { Fail "DLL not found at: $DllSrc" }

# ── 1. Sync DLL ───────────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Step "Copying DLL  →  Patch/Files/"
    Copy-Item $DllSrc $DllDst -Force
    OK (Get-Item $DllDst).Length.ToString() + " bytes"
} else {
    Step "SkipBuild: using existing DLL in Patch/Files/"
}

# ── 2. Rebuild archive ────────────────────────────────────────────────────────
Step "Rebuilding $Archive"
if (Test-Path $Archive) { Remove-Item $Archive -Force }

Compress-Archive -Path @(
    "$PatchDir\Files",
    "$PatchDir\INSTALL.txt",
    "$PatchDir\CHANGELOG.txt",
    "$PatchDir\install.bat"
) -DestinationPath $Archive

$sz = [math]::Round((Get-Item $Archive).Length / 1MB, 2)
OK "$sz MB"

# ── 3. Update CHANGELOG.txt ───────────────────────────────────────────────────
Step "Prepending $Version to CHANGELOG.txt"
$date    = Get-Date -Format "yyyy-MM-dd"
$header  = "## $Version - $date`r`n`r`n$Notes`r`n`r`n"
$old     = Get-Content $Changelog -Raw -Encoding UTF8
Set-Content $Changelog -Value ($header + $old) -Encoding UTF8
OK "CHANGELOG updated"

# ── 4. Git commit + push ──────────────────────────────────────────────────────
Step "Committing and pushing"
Push-Location $Root
try {
    git add BetterCiv_BalancePatch.zip Patch/CHANGELOG.txt Patch/Files/CvGameCore_Expansion2.dll
    git commit -m "Release $Version" --allow-empty
    git push origin main
} finally {
    Pop-Location
}
OK "Pushed to origin/main"

# ── 5. GitHub release ─────────────────────────────────────────────────────────
Step "Creating GitHub release $Version"

# Build release body with standard header
$installLine1 = "**Installation:** Unzip -> run ``install.bat`` (auto-detects Steam path)."
$installLine2 = "Manual: copy ``Files\`` into ``...\Steam\steamapps\common\Sid Meier's Civilization V\Assets\DLC\Tournament Mod V12.2a\``"
$releaseBody = "## Balance Patch $Version`r`n`r`n$Notes`r`n`r`n---`r`n$installLine1`r`n$installLine2"

gh release create $Version `
    --repo $Repo `
    --title "Balance Patch $Version" `
    --notes $releaseBody `
    $Archive

if ($LASTEXITCODE -ne 0) { Fail "gh release create failed" }
OK "Release created"

# ── 6. Print asset URL ────────────────────────────────────────────────────────
Step "Fetching asset download URL"
$AssetUrl = gh release view $Version --repo $Repo --json assets `
    --jq '.assets[0].browserDownloadUrl'

Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  Release:  https://github.com/$Repo/releases/tag/$Version" -ForegroundColor Yellow
Write-Host "  Archive:  $AssetUrl" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Update website download button with the archive URL above."
Write-Host "  2. Run  .\scripts\announce.ps1 -Version $Version  to post to Discord."
Write-Host ""
