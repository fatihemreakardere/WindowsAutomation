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
        [int]$Id = 50
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

function Install-NerdFont {
    param([string[]]$Ids)

    foreach ($id in $Ids) {
        Write-Info "Trying winget install '$id'..."
        Show-Progress -Activity "Nerd Font install" -Status "winget: $id" -PercentComplete -1 -Id 51
        $args = @('install', '--id', $id, '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements')
        $proc = Start-Process -FilePath 'winget' -ArgumentList $args -PassThru -Wait -WindowStyle Hidden
        if ($proc.ExitCode -eq 0) { return $true }
        Write-Warn "winget install for '$id' exited $($proc.ExitCode)."
    }

    Show-Progress -Activity "Nerd Font install" -Status "winget attempts complete" -PercentComplete 100 -Id 51

    return $false
}

function Install-NerdFontFromRelease {
    param(
        [string]$FontName = 'FiraCode',
        [string]$AssetPattern = '^FiraCode\.zip$'
    )

    $api = 'https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest'
    $tmpZip = Join-Path $env:TEMP "${FontName}_NF.zip"
    $extractDir = Join-Path $env:TEMP "${FontName}_NF_extract"
    $userFonts = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'

    try {
        Write-Info "Querying Nerd Fonts latest release for $FontName..."
        $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'nerd-font-installer' }
    }
    catch {
        Write-Warn "Failed to query releases: $($_.Exception.Message)"
        return $false
    }

    $asset = $rel.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
    if (-not $asset) {
        Write-Warn "Could not find asset matching $AssetPattern"
        return $false
    }

    Write-Info "Downloading $($asset.name)..."
    Show-Progress -Activity "Nerd Font install" -Status "Downloading $($asset.name)" -PercentComplete -1 -Id 52
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip -UseBasicParsing
    }
    catch {
        Write-Warn "Download failed: $($_.Exception.Message)"
        return $false
    }

    Show-Progress -Activity "Nerd Font install" -Status "Download complete" -PercentComplete 50 -Id 52

    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    try {
        Show-Progress -Activity "Nerd Font install" -Status "Extracting archive" -PercentComplete -1 -Id 52
        Expand-Archive -Path $tmpZip -DestinationPath $extractDir -Force
    }
    catch {
        Write-Warn "Extract failed: $($_.Exception.Message)"
        return $false
    }

    Show-Progress -Activity "Nerd Font install" -Status "Installing fonts" -PercentComplete 70 -Id 52

    if (-not (Test-Path $userFonts)) { New-Item -ItemType Directory -Path $userFonts -Force | Out-Null }

    $ttfFiles = Get-ChildItem -Path $extractDir -Filter '*.ttf' -Recurse
    if (-not $ttfFiles) {
        Write-Warn "No TTF files found in extracted package."
        return $false
    }

    $addFontSig = @'
using System;
using System.Runtime.InteropServices;
public class FontUtil {
    [DllImport("gdi32.dll", SetLastError=true)]
    public static extern int AddFontResourceEx(string lpszFilename, uint fl, IntPtr pdv);
}
'@
    Add-Type -TypeDefinition $addFontSig -ErrorAction SilentlyContinue

    foreach ($ttf in $ttfFiles) {
        $dest = Join-Path $userFonts $ttf.Name
        Copy-Item $ttf.FullName $dest -Force
        [void][FontUtil]::AddFontResourceEx($dest, 0, [IntPtr]::Zero)
    }

    Show-Progress -Activity "Nerd Font install" -Status "Font install complete" -PercentComplete 100 -Id 52
    Write-Info "Installed $FontName Nerd Font to $userFonts. Restart terminal/apps to pick it up; select the font (e.g., '${FontName} NF')."
    return $true
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Assert-Admin
Ensure-Winget

$fontIds = @(
    'NerdFonts.FiraCode',
    'NerdFonts.CascadiaCode',
    'NerdFonts.Hack'
)

$installed = Install-NerdFont -Ids $fontIds
if (-not $installed) {
    Write-Warn "winget font install failed with your sources. Trying direct GitHub release..."
    $installed = Install-NerdFontFromRelease -FontName 'FiraCode' -AssetPattern '^FiraCode\.zip$'
}

if (-not $installed) {
    Write-ErrorAndExit "Could not install a Nerd Font via winget or GitHub release. Install manually from https://www.nerdfonts.com/ (e.g., FiraCode Nerd Font) and rerun ncspot for best icons."
}

Write-Info "Nerd Font installed. You may need to set your terminal font to the installed Nerd Font (e.g., FiraCode NF) and restart the terminal."