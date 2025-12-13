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

function Get-AwsCliCommand {
    return Get-Command aws -ErrorAction SilentlyContinue
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

function Find-AwsCliPath {
    $cmd = Get-AwsCliCommand
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Amazon\AWSCLIV2\aws.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Amazon\AWSCLIV2\aws.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Amazon\AWSCLIV2\aws.exe')
    )

    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    try {
        $list = winget list --id 'Amazon.AWSCLI' --source winget 2>$null
        if ($LASTEXITCODE -eq 0 -and $list -match 'Amazon\.AWSCLI') { return $null }
    }
    catch { }

    return $null
}

function Install-AwsCli {
    $id = 'Amazon.AWSCLI'
    Write-Info "Installing AWS CLI via winget ($id)..."
    Show-Progress -Activity "AWS CLI" -Status "winget install" -PercentComplete -1 -Id 20
    $args = @('install', '--id', $id, '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements')
    $proc = Start-Process -FilePath 'winget' -ArgumentList $args -PassThru -Wait -WindowStyle Hidden
    Show-Progress -Activity "AWS CLI" -Status "winget attempt complete" -PercentComplete 100 -Id 20
    return ($proc.ExitCode -eq 0)
}

function Ensure-AwsCliInstalled {
    $awsPath = Find-AwsCliPath
    if ($awsPath) {
        Write-Info "AWS CLI already available at '$awsPath'. Skipping install."
        Add-ToUserPathIfMissing (Split-Path $awsPath -Parent)
        return
    }

    $installed = Install-AwsCli

    $awsPath = Find-AwsCliPath
    if ($awsPath) {
        if (-not $installed) { Write-Warn "winget reported a failure but AWS CLI was detected at '$awsPath'." }
        Add-ToUserPathIfMissing (Split-Path $awsPath -Parent)
        Write-Info "AWS CLI available at '$awsPath'."
        return
    }

    Write-ErrorAndExit "Unable to install AWS CLI via winget. Ensure winget sources are available or install manually, then rerun."
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Assert-Admin
Ensure-WingetPresent
Ensure-AwsCliInstalled
