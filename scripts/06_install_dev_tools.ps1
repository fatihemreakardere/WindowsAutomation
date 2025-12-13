[CmdletBinding()]
param()

function Write-Info($Message) { Write-Host "[INFO]  $Message"  -ForegroundColor Cyan }
function Write-Warn($Message) { Write-Host "[WARN]  $Message"  -ForegroundColor Yellow }
function Write-ErrorAndExit($Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

function Show-Progress {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete = -1,
        [int]$Id = 1
    )
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete -Id $Id
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }
    Write-ErrorAndExit "Run as Administrator (winget installs require elevation)."
}

function Invoke-ChildScript {
    param([string]$RelativePath, [int]$ProgressId, [string]$Label)
    $scriptPath = Join-Path $PSScriptRoot $RelativePath
    if (-not (Test-Path $scriptPath)) {
        Write-Warn "Child script '$RelativePath' not found; skipping."
        return
    }

    Write-Info "Running $RelativePath$Label..."
    Show-Progress -Activity "Dev tools" -Status "Running $RelativePath" -PercentComplete -1 -Id $ProgressId
    & $scriptPath
    $exit = $LASTEXITCODE
    Show-Progress -Activity "Dev tools" -Status "$RelativePath done" -PercentComplete 100 -Id $ProgressId

    if ($exit -ne 0) {
        Write-ErrorAndExit "$RelativePath exited with code $exit."
    }
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Assert-Admin

# Ensure winget availability up-front
Invoke-ChildScript '00_ensure_winget.ps1' 1 ' (winget ensure)'

# Core developer CLIs (extend this list as needed)
Invoke-ChildScript 'devtools/install_heroku_cli.ps1' 6 ' (Heroku CLI)'
Invoke-ChildScript 'devtools/install_aws_cli.ps1' 7 ' (AWS CLI)'

# Future: add additional dev tools here (e.g., Azure CLI, gh CLI, kubectl, terraform)
