[CmdletBinding()]
param()

function Write-Info($Message)  { Write-Host "[INFO]  $Message"  -ForegroundColor Cyan }
function Write-Warn($Message)  { Write-Host "[WARN]  $Message"  -ForegroundColor Yellow }
function Write-ErrorAndExit($Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

function Show-Progress {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete = -1,
        [int]$Id = 101
    )
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete -Id $Id
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }
    Write-ErrorAndExit "This script must be run as Administrator (needed for WSL enablement)."
}

function Ensure-FeatureEnabled {
    param(
        [Parameter(Mandatory)] [string]$Name
    )
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction SilentlyContinue
    if ($feature -and $feature.State -eq 'Enabled') { return }

    Write-Info "Enabling Windows optional feature: $Name"
    Show-Progress -Activity "WSL setup" -Status "Enabling feature $Name" -PercentComplete -1 -Id 101
    Enable-WindowsOptionalFeature -Online -FeatureName $Name -All -NoRestart -ErrorAction Stop | Out-Null
}

function Ensure-WSLCore {
    Write-Info "Checking WSL core status..."
    try {
        $status = wsl.exe --status 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Info "WSL is already installed."
            Show-Progress -Activity "WSL setup" -Status "WSL core already installed" -PercentComplete 100 -Id 102
            return
        }
    }
    catch {
        Write-Warn "wsl.exe --status not available; proceeding to ensure features are enabled."
    }

    Write-Info "Installing WSL (core)."
    Show-Progress -Activity "WSL setup" -Status "Installing WSL core" -PercentComplete -1 -Id 102
    # For Win10/11 modern builds, this triggers the new single-command install.
    wsl.exe --install 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "WSL install returned exit code $LASTEXITCODE. Continuing after enabling features manually."
    }
    Show-Progress -Activity "WSL setup" -Status "WSL core install step complete" -PercentComplete 100 -Id 102
}

function Ensure-WSLFeatures {
    Show-Progress -Activity "WSL setup" -Status "Ensuring optional features" -PercentComplete -1 -Id 103
    Ensure-FeatureEnabled -Name "Microsoft-Windows-Subsystem-Linux"
    Ensure-FeatureEnabled -Name "VirtualMachinePlatform"
    Show-Progress -Activity "WSL setup" -Status "Optional features ensured" -PercentComplete 100 -Id 103
}

function Ensure-DefaultVersion2 {
    Write-Info "Setting WSL default version to 2..."
    Show-Progress -Activity "WSL setup" -Status "Setting default version to 2" -PercentComplete -1 -Id 104
    wsl.exe --set-default-version 2 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Could not set default version to 2 (exit $LASTEXITCODE). If this is an older OS build, update Windows and retry."
    }
    Show-Progress -Activity "WSL setup" -Status "Default version step complete" -PercentComplete 100 -Id 104
}

function Ensure-UbuntuDistro {
    $existing = (wsl.exe -l -q 2>$null) -split "`n" | Where-Object { $_ -and ($_ -eq 'Ubuntu' -or $_ -like 'Ubuntu*') }
    if ($existing) {
        Write-Info "Ubuntu distribution already present: $($existing -join ', ')"
        Show-Progress -Activity "WSL setup" -Status "Ubuntu already installed" -PercentComplete 100 -Id 105
        return
    }

    Write-Info "Installing Ubuntu distribution..."
    Show-Progress -Activity "WSL setup" -Status "Installing Ubuntu" -PercentComplete -1 -Id 105
    wsl.exe --install -d Ubuntu 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit "Failed to install Ubuntu (exit code $LASTEXITCODE). Reboot may be required; rerun afterward."
    }
    Show-Progress -Activity "WSL setup" -Status "Ubuntu install complete" -PercentComplete 100 -Id 105
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Assert-Admin

Ensure-WSLFeatures
Ensure-WSLCore
Ensure-DefaultVersion2
Ensure-UbuntuDistro

Write-Info "WSL2 with Ubuntu setup completed. If this was the first enablement, reboot may still be required."