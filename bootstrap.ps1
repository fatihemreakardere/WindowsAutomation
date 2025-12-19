[CmdletBinding()]
param(
	[string]$RepoUrl = "https://github.com/fatihemreakardere/WindowsAutomation.git",
	[string]$TargetDir = (Join-Path $env:USERPROFILE "git/WindowsAutomation"),
	[ValidateSet("winutil", "scripts")]
	[string]$Mode = "winutil",
	[switch]$Silent
)

function Write-Info($Message) { Write-Host "[INFO]  $Message"  -ForegroundColor Cyan }
function Write-Warn($Message) { Write-Host "[WARN]  $Message"  -ForegroundColor Yellow }
function Write-ErrorAndExit($Message) {
	Write-Host "[ERROR] $Message" -ForegroundColor Red
	exit 1
}

function Ensure-Winget {
	if (Get-Command winget -ErrorAction SilentlyContinue) { return }
	Write-ErrorAndExit "winget is required to install Git automatically. Install winget from the Microsoft Store and re-run this script."
}

function Ensure-GitInstalled {
	if (Get-Command git -ErrorAction SilentlyContinue) {
		Write-Info "Git already installed: $(git --version)"
		return
	}

	Write-Info "Installing Git via winget..."
	Ensure-Winget
	$installArgs = @(
		"install",
		"--id", "Git.Git",
		"--source", "winget",
		"--exact",
		"--accept-package-agreements",
		"--accept-source-agreements"
	)

	$process = Start-Process -FilePath "winget" -ArgumentList $installArgs -Wait -PassThru -WindowStyle Hidden
	if ($process.ExitCode -ne 0) {
		Write-ErrorAndExit "Git installation failed (exit code $($process.ExitCode))."
	}

	if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
		Write-ErrorAndExit "Git did not become available after installation. Please check winget logs and retry."
	}

	Write-Info "Git installation complete: $(git --version)"
}

function Prompt-Mode {
	param([string]$CurrentMode)

	if ($Silent) { return $CurrentMode }

	Write-Host "Choose run mode:" -ForegroundColor Cyan
	Write-Host "  [W] WinUtil (clone + run setup.ps1)" -ForegroundColor Gray
	Write-Host "  [S] Scripts only (clone repo, do not run setup)" -ForegroundColor Gray
	$choice = Read-Host "Enter W/S or press Enter for default [$CurrentMode]"

	switch -Regex ($choice) {
		'^(?i)w' { return "winutil" }
		'^(?i)s' { return "scripts" }
		'' { return $CurrentMode }
		default { Write-Warn "Unrecognized choice '$choice'. Using default '$CurrentMode'."; return $CurrentMode }
	}
}

function Ensure-Repo {
	param(
		[string]$Url,
		[string]$Path
	)

	if (-not (Test-Path $Path)) {
		Write-Info "Cloning repository to '$Path'..."
		git clone $Url $Path | Out-Null
		return
	}

	# If the directory exists and is a git repo, pull latest; otherwise, stop.
	$gitDir = Join-Path $Path ".git"
	if (-not (Test-Path $gitDir)) {
		Write-ErrorAndExit "Target directory '$Path' exists but is not a git repository. Move or delete it, or update -TargetDir."
	}

	Write-Info "Repository already present. Pulling latest changes..."
	git -C $Path pull --ff-only | Out-Null
}

function Run-SetupScript {
	param(
		[string]$RepoPath,
		[switch]$SkipWinUtil
	)

	$setupPath = Join-Path $RepoPath "setup.ps1"
	if (-not (Test-Path $setupPath)) {
		Write-Warn "setup.ps1 not found at '$setupPath'. Skipping setup execution."
		return
	}

	Write-Info "Running setup script..."
	$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $setupPath)
	if ($SkipWinUtil) { $argList += '-SkipWinUtil' }
	& powershell @argList
	if ($LASTEXITCODE -ne 0) {
		Write-ErrorAndExit "Setup script failed with exit code $LASTEXITCODE."
	}
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null

try {
	Write-Info "Bootstrap starting..."

	$selectedMode = Prompt-Mode -CurrentMode $Mode
	Write-Info "Selected mode: $selectedMode"

	Ensure-GitInstalled
	Ensure-Repo -Url $RepoUrl -Path $TargetDir

	if ($selectedMode -eq "winutil") {
		Run-SetupScript -RepoPath $TargetDir
		Write-Host "All done! (WinUtil setup completed)" -ForegroundColor Green
	}
	else {
		Run-SetupScript -RepoPath $TargetDir -SkipWinUtil
		Write-Host "All done! (Scripts-only mode: post scripts executed, WinUtil skipped)" -ForegroundColor Green
	}
}
catch {
	Write-ErrorAndExit $_.Exception.Message
}
