[CmdletBinding()]
param()

function Write-Info($Message) { Write-Host "[INFO]  $Message"  -ForegroundColor Cyan }
function Write-Warn($Message) { Write-Host "[WARN]  $Message"  -ForegroundColor Yellow }
function Write-ErrorAndExit($Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
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

function Get-NcspotCommand {
    return Get-Command ncspot -ErrorAction SilentlyContinue
}

function Get-CargoCommand {
    return Get-Command cargo -ErrorAction SilentlyContinue
}

function Get-7ZipCommand {
    return Get-Command 7z -ErrorAction SilentlyContinue
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

function Find-NcspotExe {
    $cmd = Get-NcspotCommand
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:USERPROFILE '.cargo\bin\ncspot.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\ncspot\ncspot.exe'),
        'C:\Program Files\ncspot\ncspot.exe',
        'C:\Program Files (x86)\ncspot\ncspot.exe'
    )

    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    $probeDir = Join-Path $env:LOCALAPPDATA 'Programs\ncspot'
    if (Test-Path $probeDir) {
        $exe = Get-ChildItem -Path $probeDir -Recurse -Filter 'ncspot.exe' | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }

    return $null
}

function Ensure-NcspotOnPath {
    $exe = Find-NcspotExe
    if (-not $exe) {
        Write-Warn "ncspot was installed but not located; add its install directory to PATH manually if needed."
        return
    }
    Add-ToUserPathIfMissing (Split-Path $exe -Parent)
}

function Install-NcspotViaWinget {
    $candidates = @(
        'NeeshY.ncspot',    # common community package id
        'NeeshY.NCSpot',
        'ncspot.ncspot'     # fallback if id casing/owner changes
    )

    foreach ($id in $candidates) {
        Write-Info "Trying winget package id '$id'..."
        $args = @('install', '--id', $id, '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements')
        $proc = Start-Process -FilePath 'winget' -ArgumentList $args -PassThru -Wait -WindowStyle Hidden
        if ($proc.ExitCode -eq 0) { return $true }
        Write-Warn "winget install for '$id' returned exit code $($proc.ExitCode)."
    }

    return $false
}

function Install-NcspotViaScoop {
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { return $false }
    Write-Info "Trying scoop install ncspot (bucket: extras)..."
    $proc = Start-Process -FilePath 'scoop' -ArgumentList @('install', 'ncspot') -PassThru -Wait -WindowStyle Hidden
    if ($proc.ExitCode -eq 0) { return $true }
    Write-Warn "scoop install returned exit code $($proc.ExitCode)."
    return $false
}

function Ensure-RustupInstalled {
    if (Get-CargoCommand) { return $true }

    $rustupIds = @('Rustlang.Rustup', 'Rustlang.Rustup.MSVC')
    foreach ($id in $rustupIds) {
        Write-Info "Trying winget install rustup with id '$id'..."
        $args = @('install', '--id', $id, '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements')
        $proc = Start-Process -FilePath 'winget' -ArgumentList $args -PassThru -Wait -WindowStyle Hidden
        if ($proc.ExitCode -eq 0) {
            $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
            if (Test-Path $cargoBin) { $env:PATH = "$cargoBin;$($env:PATH)" }
            return $true
        }
        Write-Warn "rustup install via winget ($id) exit code $($proc.ExitCode)."
    }

    return $false
}

function Install-NcspotViaCargo {
    if (-not (Ensure-RustupInstalled)) { return $false }
    if (-not (Get-CargoCommand)) {
        Write-Warn "Cargo not found even after rustup attempt; skipping cargo fallback."
        return $false
    }

    Write-Info "Trying cargo install ncspot (may take a few minutes)..."
    $logOut = Join-Path $env:TEMP 'ncspot_cargo_install.log'
    $logErr = Join-Path $env:TEMP 'ncspot_cargo_install.err.log'
    $psiArgs = @('install', 'ncspot', '--locked')
    $proc = Start-Process -FilePath (Get-CargoCommand).Source -ArgumentList $psiArgs -PassThru -Wait -WindowStyle Hidden -RedirectStandardError $logErr -RedirectStandardOutput $logOut
    if ($proc.ExitCode -eq 0) { return $true }
    Write-Warn "cargo install ncspot returned exit code $($proc.ExitCode). See $logOut and $logErr for details (common causes: missing MSVC build tools, OpenSSL headers, or git)."
    return $false
}

function Install-NcspotFromRelease {
    $releaseApi = 'https://api.github.com/repos/hrkfdn/ncspot/releases/latest'
    $tmp = Join-Path $env:TEMP 'ncspot_latest.zip'
    $targetDir = Join-Path $env:LOCALAPPDATA 'Programs\ncspot'
    $expectedPattern = 'windows.*zip|x86_64-pc-windows-msvc.*zip'

    try {
        Write-Info "Querying GitHub for latest ncspot release..."
        $rel = Invoke-RestMethod -Uri $releaseApi -Headers @{ 'User-Agent' = 'ncspot-installer' }
    }
    catch {
        Write-Warn "Could not query GitHub releases: $($_.Exception.Message)"
        return $false
    }

    $asset = $rel.assets | Where-Object { $_.name -match $expectedPattern } | Select-Object -First 1
    if (-not $asset) {
        Write-Warn "No Windows/MSVC asset found in latest release payload."
        return $false
    }

    Write-Info "Downloading release asset '$($asset.name)'..."
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing
    }
    catch {
        Write-Warn "Download failed: $($_.Exception.Message)"
        return $false
    }

    if (-not (Test-Path $tmp)) { Write-Warn "Download temp file missing."; return $false }

    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

    try {
        Expand-Archive -Path $tmp -DestinationPath $targetDir -Force
    }
    catch {
        # fallback to 7zip if available
        $seven = Get-7ZipCommand
        if ($seven) {
            Write-Warn "Expand-Archive failed, trying 7z..."
            & $seven x $tmp "-o$targetDir" -y | Out-Null
        }
        else {
            Write-Warn "Expand-Archive failed and 7z not available: $($_.Exception.Message)"
            return $false
        }
    }

    $exe = Get-ChildItem -Path $targetDir -Recurse -Filter 'ncspot.exe' | Select-Object -First 1
    if (-not $exe) { Write-Warn "ncspot.exe not found after extraction."; return $false }

    # add to PATH for current session
    $env:PATH = "$($exe.DirectoryName);$($env:PATH)"
    Write-Info "ncspot extracted to $($exe.DirectoryName) and added to PATH for this session. Add it to your user PATH to persist."
    return $true
}

function Ensure-NcspotInstalled {
    if (Get-NcspotCommand) {
        Write-Info "ncspot already available. Skipping install."
        return
    }

    Ensure-Winget

    $installed = Install-NcspotViaWinget
    if (-not $installed) {
        $installed = Install-NcspotViaScoop
    }

    if (-not $installed) {
        $installed = Install-NcspotViaCargo
    }

    if (-not $installed) {
        $installed = Install-NcspotFromRelease
    }

    if (-not $installed) {
        Write-ErrorAndExit "Unable to install ncspot via winget/scoop/cargo. Check winget sources (may be disabled in enterprise), ensure network access, or install manually then rerun to apply config."
    }
}

function Write-NcspotConfig {
    $configDir = Join-Path $env:APPDATA 'ncspot'
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }

    $configPath = Join-Path $configDir 'config.toml'
    if (Test-Path $configPath) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupPath = "$configPath.bak_$timestamp"
        Copy-Item $configPath $backupPath -Force
        Write-Info "Existing config backed up to $backupPath"
    }

    $config = @'
## ncspot configuration generated by WindowsAutomation (04_install_ncspot.ps1)
## Edit to taste; rerun this script to regenerate with defaults.

[playback]
bitrate = 320
gapless = true
notify = true
volume_step = 5

[ui]
use_nerdfont = true
status_bar_format = "{track} — {artist} ({album})"
show_cover_in_playback = true

[theme]
background = "#0f1115"
primary = "#8be9fd"
secondary = "#50fa7b"
title = "#bd93f9"
playing = "#f1fa8c"
highlight = "#ffb86c"

[keybindings]
"Space"           = "playpause"
"MediaPlayPause"  = "playpause"
"MediaNextTrack"  = "next"
"MediaPreviousTrack" = "previous"
"Ctrl+Right"      = "seek +5s"
"Ctrl+Left"       = "seek -5s"
"Ctrl+Up"         = "volume +5%"
"Ctrl+Down"       = "volume -5%"
"Alt+Up"          = "focus queue"
"Alt+Down"        = "focus library"
"g"               = "shuffle"
"r"               = "repeat"
"q"               = "quit"
'@

    $config | Set-Content -Encoding UTF8 -Path $configPath
    Write-Info "ncspot config written to $configPath"
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Assert-Admin
Ensure-NcspotInstalled
Ensure-NcspotOnPath
Write-NcspotConfig

Write-Info "ncspot install/config complete. First launch will prompt Spotify login (ncspot uses the Spotify API)."
Write-Warn "Run 'ncspot' from a new terminal to start the client; media keys are mapped and Nerd Font glyphs are enabled."