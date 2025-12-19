[CmdletBinding()]
param(
	[string]$ConfigPath,
	[string]$ScriptsDir,
	[switch]$SkipWinUtil
)

# Ensure a reliable script root even if invoked in ways where $PSScriptRoot is empty
$ScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
	$PSScriptRoot
}
else {
	Split-Path -Parent $MyInvocation.MyCommand.Path
}

if (-not $ConfigPath) { $ConfigPath = Join-Path $ScriptRoot "config/winutil.json" }
if (-not $ScriptsDir) { $ScriptsDir = Join-Path $ScriptRoot "scripts" }

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

	Write-Info "Elevation required. Relaunching as Administrator..."
	$args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
	if ($PSBoundParameters.Count -gt 0) {
		foreach ($key in $PSBoundParameters.Keys) {
			$value = $PSBoundParameters[$key]
			$args += " -$key `"$value`""
		}
	}
	Start-Process -FilePath "powershell" -Verb RunAs -ArgumentList $args | Out-Null
	exit
}

function Invoke-WinUtilAutomation {
	param(
		[string]$ResolvedConfig
	)

	Write-Info "Running WinUtil automation using config: $ResolvedConfig"
	$command = "& { $(irm https://christitus.com/win) } -Config `"$ResolvedConfig`" -Run"
	try {
		Invoke-Expression $command
	}
	catch {
		Write-ErrorAndExit "WinUtil automation failed: $($_.Exception.Message)"
	}
}

function Invoke-PostScripts {
	param(
		[string]$Path
	)

	if (-not (Test-Path $Path)) {
		Write-Warn "Scripts directory not found at '$Path'. Skipping post scripts."
		return
	}

	$scripts = Get-ChildItem -Path $Path -Filter *.ps1 -File | Sort-Object Name
	if (-not $scripts) {
		Write-Info "No post scripts found in '$Path'."
		return
	}

	foreach ($script in $scripts) {
		Write-Info "Running post script: $($script.Name)"
		& powershell -NoProfile -ExecutionPolicy Bypass -File $script.FullName
		if ($LASTEXITCODE -ne 0) {
			Write-ErrorAndExit "Post script '$($script.Name)' failed with exit code $LASTEXITCODE."
		}
	}
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Assert-Admin

if (-not (Test-Path $ConfigPath)) {
	Write-ErrorAndExit "Config file not found at '$ConfigPath'."
}

$resolvedConfig = (Resolve-Path $ConfigPath).ProviderPath
if (-not $SkipWinUtil) {
	Invoke-WinUtilAutomation -ResolvedConfig $resolvedConfig
}
else {
	Write-Info "SkipWinUtil flag set. Skipping WinUtil automation."
}
Invoke-PostScripts -Path $ScriptsDir

Write-Info "Setup complete."
