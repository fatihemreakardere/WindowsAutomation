# WindowsAutomation

Bootstrap and automate a fresh Windows setup using WinUtil plus a few helper scripts. Run everything from an elevated PowerShell.

## Quick start

1. **Bootstrap (first-time on a fresh Windows 11):**

   - Open **PowerShell as Administrator**.
   - Run: `irm "https://raw.githubusercontent.com/fatihemreakardere/WindowsAutomation/main/bootstrap.ps1" | iex`
     - This downloads and runs `bootstrap.ps1` directly (no Git required yet).
   - What it does: installs Git (via winget if needed), clones/updates this repo, and calls `setup.ps1`.
   - Default clone: `%USERPROFILE%\git\WindowsAutomation` (override with `-TargetDir`).
   - If you already cloned the repo, you can also run: `powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -RepoUrl "<your repo url>"`

2. **Setup:** runs WinUtil with the provided config, then executes any scripts in `scripts/`.
   - Example: `powershell -ExecutionPolicy Bypass -File .\setup.ps1 -ConfigPath .\config\winutil.json -ScriptsDir .\scripts`

## Included configs

- `config/winutil.json` — WinUtil automation config (tweaks, features, installs). Edit to your needs.

## Scripts

- `scripts/01_install_wsl_ubuntu.ps1` — Enable WSL + VirtualMachinePlatform, set WSL2 default, install Ubuntu distro (admin; reboot may be required on first enablement).
- `scripts/02_install_python_multi.ps1` — Install Python 3.11/3.12/3.13 via winget if missing (admin).
- `scripts/03_install_pwas.ps1` — Install PWAs (Notion, Discord, WhatsApp, Spotify) via Chromium (Hibbiki.Chromium). Creates Start Menu shortcuts at `%APPDATA%\Microsoft\Windows\Start Menu\Programs\PWA\<App>.lnk`.

Place any additional `.ps1` files in `scripts/`; `setup.ps1` runs them in alphabetical order after WinUtil.

## Requirements

- Run PowerShell as Administrator for installs/WSL/WinUtil.
- `winget` available (install App Installer from Microsoft Store if missing).

## Notes

- WinUtil is fetched directly from GitHub via `irm https://christitus.com/win | iex` inside `setup.ps1`.
- Start menu layout automation has been removed for now.
