# WindowsAutomation

Bootstrap and automate a fresh Windows setup using WinUtil plus a few helper scripts. Run everything from an elevated PowerShell.

## Quick start

1. **Bootstrap (first-time on a fresh Windows 11):**

   - Open **PowerShell as Administrator**.
   - Run: `irm "https://raw.githubusercontent.com/fatihemreakardere/WindowsAutomation/main/bootstrap.ps1" | iex`
     - This downloads and runs `bootstrap.ps1` directly (no Git required yet).
   - What it does: installs Git (via winget if needed), clones/updates this repo, and calls `setup.ps1`.
   - Default clone: `%USERPROFILE%\git\WindowsAutomation` (override with `-TargetDir`).
   - Modes:
     - **WinUtil (default):** clone + run `setup.ps1` (WinUtil + post scripts).
     - **Scripts only:** clone + run `setup.ps1 -SkipWinUtil` (runs `scripts/*.ps1`, skips WinUtil).
   - Non-interactive examples:
     - Full (WinUtil): `powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Mode winutil -Silent`
     - Scripts only: `powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Mode scripts -Silent`
   - If you already cloned the repo, you can also run: `powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -RepoUrl "<your repo url>"`

2. **Setup:** runs WinUtil with the provided config, then executes any scripts in `scripts/`.
   - Example: `powershell -ExecutionPolicy Bypass -File .\setup.ps1 -ConfigPath .\config\winutil.json -ScriptsDir .\scripts`
   - To skip WinUtil but still run post scripts: `powershell -ExecutionPolicy Bypass -File .\setup.ps1 -SkipWinUtil`

## Included configs

- `config/winutil.json` — WinUtil automation config (tweaks, features, installs). Edit to your needs.

## Scripts

- `scripts/00_ensure_winget.ps1` — Run once to confirm `winget` is installed/enabled and refresh sources (requires admin).
- `scripts/01_install_wsl_ubuntu.ps1` — Enable WSL + VirtualMachinePlatform, set WSL2 default, install Ubuntu distro (admin; reboot may be required on first enablement). Shows progress during feature/WSL/distro steps.
- `scripts/02_install_python_multi.ps1` — Install Python 3.11/3.12/3.13 via winget if missing (admin). Shows per-version progress.
- `scripts/03_install_pwas.ps1` — Install PWAs (Notion, Discord, WhatsApp) via Chromium (Hibbiki.Chromium). Creates Start Menu shortcuts at `%APPDATA%\Microsoft\Windows\Start Menu\Programs\PWA\<App>.lnk`. Shows progress for Chromium install/profile init/shortcuts.
- `scripts/04_install_ncspot.ps1` — Install ncspot (tries winget → scoop → cargo → GitHub release), writes an opinionated `config.toml` at `%APPDATA%\ncspot\config.toml`, and adds ncspot to PATH.
- `scripts/05_install_nerd_fonts.ps1` — Install a Nerd Font (FiraCode/Cascadia/Hack via winget, with GitHub fallback for FiraCode NF) so ncspot icons render correctly.
- `scripts/06_install_dev_tools.ps1` — Convenience runner that ensures winget, then installs core dev CLIs (Heroku CLI, AWS CLI). Extend here for future dev tooling.
- `scripts/07_install_lightshot.ps1` — Install Lightshot, remove Snipping Tool/Snip & Sketch Appx packages, disable Snipping Tool's Print Screen binding, and autostart Lightshot so the Print Screen key launches it.
- `scripts/devtools/install_heroku_cli.ps1` — Install the Heroku CLI via winget if missing (invoked by 06_install_dev_tools.ps1).
- `scripts/devtools/install_aws_cli.ps1` — Install the AWS CLI via winget if missing (invoked by 06_install_dev_tools.ps1).

`setup.ps1` executes all scripts in `scripts/` alphabetically after (or instead of, when `-SkipWinUtil`) running WinUtil.

Place any additional `.ps1` files in `scripts/`; `setup.ps1` runs them in alphabetical order after WinUtil.

## CI

- GitHub Actions workflow: PowerShell lint via PSScriptAnalyzer runs on pushes/PRs to `main` for files under `scripts/`.
- GitHub Actions workflow: Pester tests (syntax/parse checks for all `scripts/*.ps1`) run on pushes/PRs to `main`.

### Run tests locally

Install Pester (v5+) once per machine, then run:

```pwsh
pwsh -NoLogo -NoProfile -Command "Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber; Invoke-Pester -Path tests"
```

If you already have Pester 5+ installed, you can shorten to:

```pwsh
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests"
```

## Requirements

- Run PowerShell as Administrator for installs/WSL/WinUtil.
- `winget` available (install App Installer from Microsoft Store if missing).

## Notes

- WinUtil is fetched directly from GitHub via `irm https://christitus.com/win | iex` inside `setup.ps1`.
- Start menu layout automation has been removed for now.
