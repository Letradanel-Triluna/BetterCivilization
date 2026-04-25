<#
.SYNOPSIS
  Post-release announce: make Vercel deployment public + post Discord message.

.DESCRIPTION
  Reads secrets from scripts\.env (gitignored).
  Required keys in .env:
    DISCORD_WEBHOOK=https://discord.com/api/webhooks/...
    VERCEL_TOKEN=...
    VERCEL_PROJECT_ID=prj_...
    VERCEL_TEAM_ID=team_...   (optional, leave blank if personal account)

.PARAMETER Version
  Release tag, e.g. "v0.3"  — used to build the GitHub release URL.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root    = Split-Path $PSScriptRoot -Parent
$EnvFile = "$PSScriptRoot\.env"
$Repo    = "Letradanel-Triluna/BetterCivilization"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "    ERROR: $msg" -ForegroundColor Red; exit 1 }

# ── Load .env ─────────────────────────────────────────────────────────────────
if (-not (Test-Path $EnvFile)) {
    Fail "Missing $EnvFile — copy scripts\.env.example to scripts\.env and fill it in."
}
foreach ($line in Get-Content $EnvFile) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $k, $v = $line -split '=', 2
    Set-Variable -Name $k.Trim() -Value $v.Trim() -Scope Script
}

# ── Build release info ────────────────────────────────────────────────────────
$ReleaseUrl  = "https://github.com/$Repo/releases/tag/$Version"
$AssetUrl    = gh release view $Version --repo $Repo --json assets `
                   --jq '.assets[0].browserDownloadUrl'
$ReleaseNotes = gh release view $Version --repo $Repo --json body --jq '.body'

# ── 1. Vercel: set latest deployment public ───────────────────────────────────
Step "Vercel → making latest deployment public"

$vercelBase = "https://api.vercel.com"
$headers    = @{ Authorization = "Bearer $VERCEL_TOKEN"; "Content-Type" = "application/json" }
$teamQuery  = if ($VERCEL_TEAM_ID) { "?teamId=$VERCEL_TEAM_ID" } else { "" }

# Get latest deployment
$deploymentsUrl = "$vercelBase/v6/deployments$teamQuery" +
                  $(if ($teamQuery) { "&" } else { "?" }) +
                  "projectId=$VERCEL_PROJECT_ID&limit=1"
$resp = Invoke-RestMethod $deploymentsUrl -Headers $headers
$deployId = $resp.deployments[0].uid

if (-not $deployId) { Fail "No deployments found for project $VERCEL_PROJECT_ID" }
OK "Deployment: $deployId"

# Set public access (remove password protection / SSO)
$patchUrl  = "$vercelBase/v9/projects/$VERCEL_PROJECT_ID$teamQuery"
$patchBody = @{ passwordProtection = $null; ssoProtection = $null } | ConvertTo-Json
Invoke-RestMethod $patchUrl -Method PATCH -Headers $headers -Body $patchBody | Out-Null
OK "Project access set to public"

# ── 2. Discord webhook ────────────────────────────────────────────────────────
Step "Discord → posting announcement"

$discordBody = @{
    username   = "BetterCiv Bot"
    avatar_url = "https://cdn.discordapp.com/embed/avatars/0.png"
    embeds     = @(
        @{
            title       = "Balance Patch $Version released!"
            url         = $ReleaseUrl
            color       = 0x57F287   # green
            description = $ReleaseNotes
            fields      = @(
                @{
                    name   = "Download"
                    value  = "[BetterCiv_BalancePatch.zip]($AssetUrl)"
                    inline = $false
                },
                @{
                    name   = "Install"
                    value  = "Unzip → run ``install.bat``"
                    inline = $false
                }
            )
            footer      = @{ text = "BetterCivilization Mod · Tournament Mod V12.2a" }
        }
    )
} | ConvertTo-Json -Depth 6

Invoke-RestMethod $DISCORD_WEBHOOK -Method POST `
    -ContentType "application/json" -Body $discordBody | Out-Null
OK "Discord message sent"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Done!  $Version is live and announced." -ForegroundColor Green
Write-Host "  GitHub:  $ReleaseUrl" -ForegroundColor Green
Write-Host "  Archive: $AssetUrl" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
