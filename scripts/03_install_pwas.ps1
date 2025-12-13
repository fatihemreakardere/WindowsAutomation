[CmdletBinding()]
param()

$Apps = @(
    @{ Name = 'Notion'; Url = 'https://www.notion.so' },
    @{ Name = 'Discord'; Url = 'https://discord.com/app' },
    @{ Name = 'WhatsApp'; Url = 'https://web.whatsapp.com' }
)

# Global Chromium flags to apply to every PWA shortcut
$GlobalFlags = @(
    '--ignore-gpu-blocklist',
    '--enable-accelerated-video-decode',
    # Media / GPU / HDR / controls / file-handling
    '--enable-features=PlatformHEVCDecoderSupport,PlatformVP9Decoder,WebRTCHWDecoding,HardwareMediaKeyHandling,GlobalMediaControls,UseWindowsHDR,FileHandlingAPI'
)

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
        [int]$Id = 301
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

function Ensure-ChromiumInstalled {
    if (Get-ChromiumPath) { return }

    Write-Info "Installing Chromium via winget (Hibbiki.Chromium)..."
    Show-Progress -Activity "PWA install" -Status "Installing Chromium" -PercentComplete -1 -Id 301
    $args = @(
        'install', '--id', 'Hibbiki.Chromium',
        '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements'
    )
    $proc = Start-Process -FilePath 'winget' -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    if ($proc.ExitCode -ne 0) {
        Write-ErrorAndExit "Chromium install failed (exit $($proc.ExitCode))."
    }
    Show-Progress -Activity "PWA install" -Status "Chromium installed" -PercentComplete 100 -Id 301
}

function Get-ChromiumPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Chromium\Application\chrome.exe'),
        'C:\Program Files\Chromium\Application\chrome.exe',
        'C:\Program Files (x86)\Chromium\Application\chrome.exe'
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function New-PwaShortcut {
    param(
        [string]$Name,
        [string]$Url,
        [string]$BrowserPath,
        [string[]]$Flags = @()
    )

    $shortcutDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PWA'
    if (-not (Test-Path $shortcutDir)) { New-Item -ItemType Directory -Path $shortcutDir -Force | Out-Null }
    $shortcutPath = Join-Path $shortcutDir "$Name.lnk"

    $baseArgs = @(
        '--no-first-run',
        '--no-default-browser-check',
        '--profile-directory=Default',
        "--app=$Url"
    )

    $allArgs = @($baseArgs + $Flags + $GlobalFlags)

    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($shortcutPath)
    $sc.TargetPath = $BrowserPath
    $sc.Arguments = ($allArgs -join ' ')
    $sc.WorkingDirectory = Split-Path $BrowserPath -Parent
    $sc.IconLocation = "$BrowserPath,0"
    $sc.Save()

    return $shortcutPath
}

function Ensure-ChromiumProfileInitialized {
    param([string]$BrowserPath)
    # Launch a lightweight run to create Default profile if it doesn't exist.
    $profileDir = Join-Path $env:LOCALAPPDATA 'Chromium\User Data\Default'
    if (Test-Path $profileDir) { return }
    Write-Info "Initializing Chromium profile (Default)..."
    Show-Progress -Activity "PWA install" -Status "Initializing Chromium profile" -PercentComplete -1 -Id 302
    Start-Process -FilePath $BrowserPath -ArgumentList @('--no-first-run', '--no-default-browser-check', 'about:blank') -WindowStyle Minimized -Wait | Out-Null
    Show-Progress -Activity "PWA install" -Status "Profile initialized" -PercentComplete 100 -Id 302
}

function Install-Pwa {
    param(
        [string]$BrowserPath,
        [string]$Name,
        [string]$Url,
        [string[]]$Flags = @()
    )

    $shortcutPath = Join-Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PWA') "$Name.lnk"
    if (Test-Path $shortcutPath) {
        Write-Info "PWA '$Name' shortcut present; recreating with current flags/settings..."
        Remove-Item $shortcutPath -ErrorAction SilentlyContinue
    }

    Ensure-ChromiumProfileInitialized -BrowserPath $BrowserPath

    Write-Info "Creating PWA shortcut for '$Name'..."
    Show-Progress -Activity "PWA install" -Status "Creating shortcut for $Name" -PercentComplete -1 -Id 303
    $created = New-PwaShortcut -Name $Name -Url $Url -BrowserPath $BrowserPath -Flags $Flags
    if (-not (Test-Path $created)) {
        Write-Warn "Shortcut creation for '$Name' may have failed. Verify manually."
    }
    Show-Progress -Activity "PWA install" -Status "$Name shortcut done" -PercentComplete 100 -Id 303
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Assert-Admin
Ensure-WingetPresent
Ensure-ChromiumInstalled

$chromium = Get-ChromiumPath
if (-not $chromium) {
    Write-ErrorAndExit "Chromium not found after install. Adjust Get-ChromiumPath paths or install manually."
}

foreach ($app in $Apps) {
    $flags = @()
    if ($app.ContainsKey('Flags')) { $flags = $app.Flags }
    Install-Pwa -BrowserPath $chromium -Name $app.Name -Url $app.Url -Flags $flags
}

Write-Info "PWA installation pass complete."
Write-Warn "If shortcuts didn't appear, launch Chromium once so it initializes the profile, then rerun this script."