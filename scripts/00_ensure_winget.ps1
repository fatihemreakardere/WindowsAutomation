[CmdletBinding()]
param()

function Write-Info($Message) { Write-Host "[INFO]  $Message" -ForegroundColor Cyan }
function Write-Warn($Message) { Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-ErrorAndExit($Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

function Show-Progress {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete = -1,
        [int]$Id = 10
    )
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete -Id $Id
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }
    Write-ErrorAndExit "Run as Administrator (winget/app installer setup may require elevation)."
}

function Ensure-WingetPresent {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info "winget is available."
        return $true
    }

    Write-Warn "winget not found. Install 'App Installer' from Microsoft Store (ProductId: 9NBLGGH4NNS1) then rerun."
    $storeUri = 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1'
    Write-Info "Store link: $storeUri"
    return $false
}

function Refresh-WingetSources {
    try {
        Show-Progress -Activity "winget ensure" -Status "Updating sources" -PercentComplete -1 -Id 11
        # Suppress winget's ANSI progress noise for cleaner logs
        winget source update --disable-interactivity 1>$null 2>$null
        Show-Progress -Activity "winget ensure" -Status "Sources updated" -PercentComplete 100 -Id 11
    }
    catch {
        Write-Warn "winget source update failed: $($_.Exception.Message)"
    }
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Assert-Admin

if (-not (Ensure-WingetPresent)) {
    Write-ErrorAndExit "winget unavailable. Install App Installer, then rerun this script."
}

Refresh-WingetSources
Write-Info "winget readiness check complete."