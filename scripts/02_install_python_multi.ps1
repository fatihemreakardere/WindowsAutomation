[CmdletBinding()]
param()

$TargetVersions = @('3.11','3.12','3.13')

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
        [int]$Id = 201
    )
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete -Id $Id
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }
    Write-ErrorAndExit "Run as Administrator (winget installs require elevation)."
}

function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    Write-ErrorAndExit "winget is required. Install from Microsoft Store (App Installer) and retry."
}

function Test-PythonInstalledViaLauncher {
    param([string]$Version)
    $py = Get-Command py -ErrorAction SilentlyContinue
    if (-not $py) { return $false }
    $list = py -0p 2>$null
    return ($list -match "-$([Regex]::Escape($Version))")
}

function Test-PythonInstalledViaWinget {
    param([string]$PackageId)
    $result = winget list --id $PackageId --exact --source winget 2>$null
    return ($result -match [Regex]::Escape($PackageId))
}

function Ensure-PythonVersion {
    param([string]$Version)

    $packageId = "Python.Python.$Version"
    if (Test-PythonInstalledViaLauncher -Version $Version -or Test-PythonInstalledViaWinget -PackageId $packageId) {
        Write-Info "Python $Version already installed."
        Show-Progress -Activity "Python installs" -Status "Python $Version already present" -PercentComplete 100 -Id (202 + [int](10 * $Version.Replace('.',''))) 
        return
    }

    Write-Info "Installing Python $Version via winget..."
    Show-Progress -Activity "Python installs" -Status "Installing $Version" -PercentComplete -1 -Id (202 + [int](10 * $Version.Replace('.','')))
    $args = @(
        'install', '--id', $packageId,
        '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements'
    )
    $proc = Start-Process -FilePath 'winget' -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    if ($proc.ExitCode -ne 0) {
        Write-ErrorAndExit "Python $Version install failed (exit $($proc.ExitCode))."
    }
    Write-Info "Python $Version installed."
    Show-Progress -Activity "Python installs" -Status "Python $Version installed" -PercentComplete 100 -Id (202 + [int](10 * $Version.Replace('.','')))
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Assert-Admin
Ensure-Winget

foreach ($v in $TargetVersions) {
    Ensure-PythonVersion -Version $v
}

Write-Info "Python installation pass complete."