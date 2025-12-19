[CmdletBinding()]
param()

$TargetVersions = @('3.11', '3.12', '3.13')

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

function Ensure-WingetPresent {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    Write-ErrorAndExit "winget not found. Run scripts/00_ensure_winget.ps1 first."
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

function Test-PythonFunctional {
    param([string]$Version)
    try {
        $proc = Start-Process -FilePath 'py' -ArgumentList "-$Version", '-c', 'exit()' -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        return $proc.ExitCode -eq 0
    }
    catch { return $false }
}

function Test-PythonCmdVersionMatch {
    param([string]$Version)
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { return $false }
    try {
        $out = python --version 2>$null
        if (-not $out) { return $false }
        # Expect something like "Python 3.11.9"
        $parts = $out -split '\s+'
        if ($parts.Count -lt 2) { return $false }
        $detected = $parts[1]
        return $detected.StartsWith($Version)
    }
    catch { return $false }
}

function Ensure-PythonVersion {
    param([string]$Version)

    $packageId = "Python.Python.$Version"
    $alreadyInstalled = Test-PythonInstalledViaLauncher -Version $Version -or
    Test-PythonInstalledViaWinget   -PackageId $packageId -or
    Test-PythonFunctional           -Version $Version -or
    Test-PythonCmdVersionMatch      -Version $Version

    if ($alreadyInstalled) {
        Write-Info "Python $Version already installed."
        Show-Progress -Activity "Python installs" -Status "Python $Version already present" -PercentComplete 100 -Id (202 + [int](10 * $Version.Replace('.', ''))) 
        return
    }

    Write-Info "Installing Python $Version via winget..."
    Show-Progress -Activity "Python installs" -Status "Installing $Version" -PercentComplete -1 -Id (202 + [int](10 * $Version.Replace('.', '')))
    $args = @(
        'install', '--id', $packageId,
        '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements'
    )
    $proc = Start-Process -FilePath 'winget' -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    if ($proc.ExitCode -ne 0) {
        Write-Warn "winget reported a non-zero exit ($($proc.ExitCode)) for Python $Version. Skipping error and continuing; verify Python is usable."
        return
    }
    Write-Info "Python $Version installed."
    Show-Progress -Activity "Python installs" -Status "Python $Version installed" -PercentComplete 100 -Id (202 + [int](10 * $Version.Replace('.', '')))
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Assert-Admin
Ensure-WingetPresent

foreach ($v in $TargetVersions) {
    Ensure-PythonVersion -Version $v
}

Write-Info "Python installation pass complete."