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

function Ensure-WingetPresent {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    Write-ErrorAndExit "winget not found. Run scripts/00_ensure_winget.ps1 first."
}

function Get-HerokuCommand {
    return Get-Command heroku -ErrorAction SilentlyContinue
}

function Add-ToUserPathIfMissing {
    param([string]$Directory)
    if (-not $Directory) { return }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = ($userPath -split ';') | Where-Object { $_ -ne '' }
    if ($parts -contains $Directory) { return }

    $newPath = ($parts + $Directory) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    $env:PATH = "$Directory;$($env:PATH)"
    Write-Info "Added '$Directory' to User PATH. Restart shells to pick up globally."
}

function Find-HerokuCliPath {
    $cmd = Get-HerokuCommand
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'heroku\bin\heroku.cmd'),
        (Join-Path $env:ProgramFiles 'Heroku\bin\heroku.cmd'),
        (Join-Path ${env:ProgramFiles(x86)} 'Heroku\bin\heroku.cmd')
    )

    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    try {
        $list = winget list --id 'Heroku.HerokuCLI' --source winget 2>$null
        if ($LASTEXITCODE -eq 0 -and $list -match 'HerokuCLI') { return $null }
    }
    catch { }

    return $null
}

function Install-HerokuCli {
    $id = 'Heroku.HerokuCLI'
    Write-Info "Installing Heroku CLI via winget ($id)..."
    Show-Progress -Activity "Heroku CLI" -Status "winget install" -PercentComplete -1 -Id 10
    $args = @('install', '--id', $id, '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements')
    $proc = Start-Process -FilePath 'winget' -ArgumentList $args -PassThru -Wait -WindowStyle Hidden
    Show-Progress -Activity "Heroku CLI" -Status "winget attempt complete" -PercentComplete 100 -Id 10
    return ($proc.ExitCode -eq 0)
}

function Ensure-HerokuCliInstalled {
    $herokuPath = Find-HerokuCliPath
    if ($herokuPath) {
        Write-Info "Heroku CLI already available at '$herokuPath'. Skipping install."
        Add-ToUserPathIfMissing (Split-Path $herokuPath -Parent)
        return
    }

    $installed = Install-HerokuCli

    $herokuPath = Find-HerokuCliPath
    if ($herokuPath) {
        if (-not $installed) { Write-Warn "winget reported a failure but Heroku CLI was detected at '$herokuPath'." }
        Add-ToUserPathIfMissing (Split-Path $herokuPath -Parent)
        Write-Info "Heroku CLI available at '$herokuPath'."
        return
    }

    Write-ErrorAndExit "Unable to install Heroku CLI via winget. Ensure winget sources are available or install manually, then rerun."
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Assert-Admin
Ensure-WingetPresent
Ensure-HerokuCliInstalled
