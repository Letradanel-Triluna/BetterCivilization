<#
.SYNOPSIS
  Update the Civ_picker website bundle with new BetterCivilization release info.

.DESCRIPTION
  Patches the DownloadsSection blob inside Civ_picker/index.html:
    - PATCH_NOTES.version  → stripped release tag (e.g. "0.2")
    - PATCH_NOTES.date     → today's date (or -Date override)
    - BetterCiv fileHref   → new GitHub asset download URL

  Then commits and pushes the Civ_picker repo so Vercel auto-deploys.

  The patch notes *sections* content (civ reworks, unit changes, etc.) is NOT
  changed here — update those via Claude Design BEFORE running release.ps1.

.PARAMETER Version
  Release tag, e.g. "v0.2"

.PARAMETER AssetUrl
  GitHub release asset download URL (printed by release.ps1).

.PARAMETER Date
  Date string shown on the site. Default: today formatted as "Month D, YYYY".

.PARAMETER CivPickerDir
  Path to local Civ_picker repository.
  Default: tries common sibling/OneDrive locations automatically.
#>

param(
    [Parameter(Mandatory=$true)]  [string]$Version,
    [Parameter(Mandatory=$true)]  [string]$AssetUrl,
    [string]$Date         = (Get-Date -Format "MMMM d, yyyy"),
    [string]$CivPickerDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "    OK: $msg"    -ForegroundColor Green }
function Fail($msg) { Write-Host "    ERROR: $msg" -ForegroundColor Red; exit 1 }

# ── Resolve Civ_picker path ───────────────────────────────────────────────────
if (-not $CivPickerDir) {
    $candidates = @(
        (Join-Path (Split-Path $PSScriptRoot -Parent) "..\Civ_picker"),
        "$env:USERPROFILE\OneDrive\Документы\GitHub\Civ_picker",
        "$env:USERPROFILE\Documents\GitHub\Civ_picker"
    )
    foreach ($c in $candidates) {
        $resolved = try { (Resolve-Path $c -ErrorAction Stop).Path } catch { $null }
        if ($resolved -and (Test-Path $resolved)) { $CivPickerDir = $resolved; break }
    }
}
if (-not $CivPickerDir -or -not (Test-Path $CivPickerDir)) {
    Fail "Civ_picker directory not found. Pass -CivPickerDir <path> explicitly."
}

$IndexHtml     = Join-Path $CivPickerDir "index.html"
$DownloadsUuid = 'f478b125-2126-412a-8559-86ced485fb2b'
$VersionNum    = $Version.TrimStart('v')   # "v0.2" → "0.2"

if (-not (Test-Path $IndexHtml)) { Fail "index.html not found at $IndexHtml" }

# ── Helpers ───────────────────────────────────────────────────────────────────
function Decode-Blob([string]$b64) {
    $bytes = [Convert]::FromBase64String($b64)
    $ms    = New-Object System.IO.MemoryStream(,$bytes)
    $gz    = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $out   = New-Object System.IO.MemoryStream
    $gz.CopyTo($out); $gz.Close(); $ms.Close()
    return [System.Text.Encoding]::UTF8.GetString($out.ToArray())
}

function Encode-Blob([string]$text) {
    $raw = [System.Text.Encoding]::UTF8.GetBytes($text)
    $ms  = New-Object System.IO.MemoryStream
    $gz  = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress)
    $gz.Write($raw, 0, $raw.Length); $gz.Close()
    return [Convert]::ToBase64String($ms.ToArray())
}

# Replace the content between openMarker and the next occurrence of closeChar.
# Returns the patched string. Throws if openMarker is not found.
function Splice-After([string]$str, [string]$openMarker, [string]$closeChar, [string]$newContent, [int]$startAt = 0) {
    $s = $str.IndexOf($openMarker, $startAt)
    if ($s -lt 0) { throw "Marker not found: $openMarker" }
    $s += $openMarker.Length
    $e  = $str.IndexOf($closeChar, $s)
    if ($e -lt 0) { throw "Close char '$closeChar' not found after marker '$openMarker'" }
    return $str.Substring(0, $s) + $newContent + $str.Substring($e)
}

# ── 1. Read + parse index.html ────────────────────────────────────────────────
Step "Reading $IndexHtml"
$html   = [System.IO.File]::ReadAllText($IndexHtml, [System.Text.Encoding]::UTF8)
$mTag   = '<script type="__bundler/manifest">'
$mStart = $html.IndexOf($mTag)
$mEnd   = $html.IndexOf('</script>', $mStart)
$mJson  = $html.Substring($mStart + $mTag.Length, $mEnd - $mStart - $mTag.Length)
$manifest = $mJson | ConvertFrom-Json
OK "Manifest loaded ($(($manifest | Get-Member -MemberType NoteProperty).Count) entries)"

# ── 2. Decode DownloadsSection blob ──────────────────────────────────────────
Step "Decoding DownloadsSection"
$entry = $manifest.$DownloadsUuid
if (-not $entry) { Fail "UUID $DownloadsUuid not found in manifest" }
$src = Decode-Blob $entry.data
OK "Decoded ($($src.Length) chars)"

# ── 3. Patch PATCH_NOTES version + date ──────────────────────────────────────
Step "Patching version='$VersionNum', date='$Date'"

$pnStart = $src.IndexOf('const PATCH_NOTES = {')
if ($pnStart -lt 0) { Fail "'const PATCH_NOTES' not found in DownloadsSection" }

# Work on the slice from PATCH_NOTES onward to avoid touching PANGAEA_NOTES
$before = $src.Substring(0, $pnStart)
$slice  = $src.Substring($pnStart)

$slice = Splice-After $slice 'version: "' '"' $VersionNum
$slice = Splice-After $slice 'date: "'    '"' $Date
$src   = $before + $slice

OK "version and date patched"

# ── 4. Patch BetterCiv download URL ──────────────────────────────────────────
Step "Patching fileHref → $AssetUrl"

$fhPrefix = 'fileHref="https://github.com/Letradanel-Triluna/BetterCivilization'
$fhS      = $src.IndexOf($fhPrefix)
if ($fhS -lt 0) { Fail "BetterCiv fileHref not found in DownloadsSection" }

# $fhS points to 'f' in fileHref; skip 9 chars to land on opening '"' of the URL
$urlStart = $fhS + 9          # position of the opening "
$urlEnd   = $src.IndexOf('"', $urlStart + 1)   # closing "
$src = $src.Substring(0, $urlStart) + '"' + $AssetUrl + $src.Substring($urlEnd)

OK "fileHref patched"

# ── 5. Re-encode blob ─────────────────────────────────────────────────────────
Step "Re-encoding blob"
$newData   = Encode-Blob $src
OK "Encoded ($($newData.Length) chars)"

# ── 6. Update manifest JSON string (fast string replace) ─────────────────────
Step "Updating manifest"
$oldB64    = $entry.data
$newMJson  = $mJson.Replace("""$oldB64""", """$newData""")
if ($newMJson -eq $mJson) { Fail "Manifest replacement failed — old blob not matched" }
OK "Manifest patched"

# ── 7. Write back index.html ──────────────────────────────────────────────────
Step "Writing index.html"
$newHtml = $html.Substring(0, $mStart + $mTag.Length) + $newMJson + $html.Substring($mEnd)
[System.IO.File]::WriteAllText($IndexHtml, $newHtml, [System.Text.Encoding]::UTF8)
OK "Written ($([math]::Round($newHtml.Length / 1KB, 1)) KB)"

# ── 8. Commit + push Civ_picker ───────────────────────────────────────────────
Step "Committing Civ_picker"
Push-Location $CivPickerDir
try {
    git add index.html
    git commit -m "Release BetterCivilization $Version"
    git push origin main
} finally {
    Pop-Location
}
OK "Pushed → Vercel auto-deploy triggered"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Site updated: v$VersionNum · $Date" -ForegroundColor Green
Write-Host "  Next: .\scripts\announce.ps1 -Version $Version" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
