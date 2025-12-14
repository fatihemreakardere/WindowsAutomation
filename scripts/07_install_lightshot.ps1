[CmdletBinding()]
param(
    [string]$LightshotPath
)

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
        [int]$Id = 60
    )
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete -Id $Id
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }
    Write-ErrorAndExit "Run as Administrator (winget installs and app removals require elevation)."
}

function Invoke-ChildScript {
    param([string]$RelativePath, [int]$ProgressId = 60, [string]$Label = '')
    $scriptPath = Join-Path $PSScriptRoot $RelativePath
    if (-not (Test-Path $scriptPath)) {
        Write-Warn "Child script '$RelativePath' not found; skipping."
        return
    }
    Write-Info "Running $RelativePath$Label..."
    Show-Progress -Activity "Lightshot" -Status "Running $RelativePath" -PercentComplete -1 -Id $ProgressId
    & $scriptPath
    $exit = $LASTEXITCODE
    Show-Progress -Activity "Lightshot" -Status "$RelativePath done" -PercentComplete 100 -Id $ProgressId
    if ($exit -ne 0) {
        Write-ErrorAndExit "$RelativePath exited with code $exit."
    }
}

function Get-LightshotExecutable {
    param([string]$OverridePath)

    # If user provided a path, respect it first
    if ($OverridePath) {
        if (Test-Path $OverridePath) { return (Resolve-Path $OverridePath).Path }
        Write-Warn "Provided LightshotPath '$OverridePath' not found. Falling back to auto-discovery."
    }

    # Direct well-known locations (include static paths to avoid env var quirks)
    $directPaths = @(
        "$Env:ProgramFiles(x86)\Skillbrains\lightshot\lightshot.exe",
        "$Env:ProgramFiles\Skillbrains\lightshot\lightshot.exe",
        "$Env:LOCALAPPDATA\Programs\Skillbrains\lightshot\lightshot.exe",
        "$Env:LOCALAPPDATA\Skillbrains\lightshot\lightshot.exe",
        "$Env:ProgramFiles(x86)\Lightshot\lightshot.exe",
        "$Env:ProgramFiles\Lightshot\lightshot.exe",
        'C:\\Program Files (x86)\\Skillbrains\\lightshot\\lightshot.exe',
        'C:\\Program Files\\Skillbrains\\lightshot\\lightshot.exe'
    ) | Where-Object { $_ }

    $candidate = $directPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($candidate) { return $candidate }

    # Fallback: shallow recursive search in expected vendor folders to handle versioned subfolders
    $searchRoots = @(
        "$Env:ProgramFiles(x86)\Skillbrains",
        "$Env:ProgramFiles\Skillbrains",
        "$Env:LOCALAPPDATA\Programs\Skillbrains",
        "$Env:LOCALAPPDATA\Skillbrains",
        "$Env:ProgramFiles(x86)\Lightshot",
        "$Env:ProgramFiles\Lightshot",
        'C:\\Program Files (x86)\\Skillbrains',
        'C:\\Program Files\\Skillbrains'
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $searchRoots) {
        $found = Get-ChildItem -Path $root -Filter 'lightshot*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
        $foundPrtScr = Get-ChildItem -Path $root -Filter 'prtscr*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundPrtScr) { return $foundPrtScr.FullName }
    }

    return $null
}

function Ensure-LightshotInstalled {
    param([string]$OverridePath)

    $existing = Get-LightshotExecutable -OverridePath $OverridePath
    if ($existing) {
        Write-Info "Lightshot already present at $existing. Skipping install."
        return $existing
    }

    Write-Info "Installing Lightshot via winget..."
    Show-Progress -Activity "Lightshot" -Status "winget install" -PercentComplete -1 -Id 61
    $args = @(
        'install', '--id', 'Skillbrains.Lightshot', '--exact', '--source', 'winget',
        '--silent', '--accept-package-agreements', '--accept-source-agreements'
    )
    $process = Start-Process -FilePath 'winget' -ArgumentList $args -Wait -PassThru -NoNewWindow
    Show-Progress -Activity "Lightshot" -Status "winget complete" -PercentComplete 100 -Id 61

    if ($process.ExitCode -ne 0) {
        Write-Warn "winget returned exit code $($process.ExitCode). Checking if Lightshot is present anyway..."
    }

    $installedPath = Get-LightshotExecutable -OverridePath $OverridePath
    if (-not $installedPath) {
        Write-ErrorAndExit "Lightshot not found after winget attempt (exit code $($process.ExitCode))."
    }

    Write-Info "Lightshot available at $installedPath."
    return $installedPath
}

function Remove-SnippingTools {
    Write-Info "Removing Microsoft Snipping/Snip & Sketch apps..."
    Show-Progress -Activity "Lightshot" -Status "Removing Snipping Tool" -PercentComplete -1 -Id 62
    $packageIds = @('Microsoft.ScreenSketch', 'Microsoft.WindowsSnippingTool')
    foreach ($pkg in $packageIds) {
        $instances = Get-AppxPackage -AllUsers $pkg -ErrorAction SilentlyContinue
        if (-not $instances) {
            Write-Info "No package '$pkg' present; skipping."
            continue
        }
        foreach ($instance in $instances) {
            Write-Info "Removing $($instance.Name) ($($instance.PackageFullName))..."
            try {
                Remove-AppxPackage -AllUsers -Package $instance.PackageFullName -ErrorAction Stop
            }
            catch {
                Write-Warn "Failed to remove $($instance.PackageFullName): $($_.Exception.Message)"
            }
        }
    }
    Show-Progress -Activity "Lightshot" -Status "Removal attempt complete" -PercentComplete 100 -Id 62
}

function Disable-PrintScreenForSnippingTool {
    $keyPath = 'HKCU:\Control Panel\Keyboard'
    if (-not (Test-Path $keyPath)) { New-Item -Path $keyPath -Force | Out-Null }
    Set-ItemProperty -Path $keyPath -Name 'PrintScreenKeyForSnippingEnabled' -Value 0 -Type DWord
    Write-Info "Disabled Snipping Tool binding for the Print Screen key."
}

function Enable-LightshotStartup {
    param([string]$ExePath)

    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path $runKey)) { New-Item -Path $runKey -Force | Out-Null }
    Set-ItemProperty -Path $runKey -Name 'Lightshot' -Value "`"$ExePath`"" -Type String
    Write-Info "Configured Lightshot to launch at logon and handle Print Screen (path: $ExePath)."
}

function Bind-PrintScreenToLightshot {
    param([string]$ExePath)

    if (-not (Test-Path $ExePath)) {
        Write-Warn "Cannot bind Print Screen: Lightshot path '$ExePath' missing."
        return
    }

    $appKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AppKey\44'
    if (-not (Test-Path $appKeyPath)) { New-Item -Path $appKeyPath -Force | Out-Null }

    # ShellExecute tells Explorer what to launch when the Print Screen virtual key (VK 0x2C / 44) is pressed
    Set-ItemProperty -Path $appKeyPath -Name 'ShellExecute' -Value "`"$ExePath`"" -Type String

    # Association is not strictly required, but ensures the key is treated as app-launch instead of the built-in handler
    Set-ItemProperty -Path $appKeyPath -Name 'Association' -Value 'Lightshot' -Type String

    Write-Info "Bound Print Screen (VK 44) to Lightshot via Explorer AppKey (path: $ExePath)."
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Assert-Admin

# Ensure winget availability up-front
Invoke-ChildScript '00_ensure_winget.ps1' 60 ' (winget ensure)'

$lightshotPath = Ensure-LightshotInstalled -OverridePath $LightshotPath
Remove-SnippingTools
Disable-PrintScreenForSnippingTool

if ($lightshotPath) {
    Enable-LightshotStartup -ExePath $lightshotPath
    Bind-PrintScreenToLightshot -ExePath $lightshotPath
}
else {
    Write-Warn "Lightshot path not detected; startup entry not created."
}

Show-Progress -Activity "Lightshot" -Status "Done" -PercentComplete 100 -Id 60
Write-Info "Lightshot ready. If Print Screen is not handled immediately, log off/on (or reboot) to ensure startup entry is applied."
