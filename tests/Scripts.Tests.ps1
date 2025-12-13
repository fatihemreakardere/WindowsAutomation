<#
  Pester tests for repo PowerShell scripts.
  Safe tests only: syntax/parse validation (no external installs, no elevation required).
#>

# Ensure Pester 5+ (needed for these assertions)
if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 5 })) {
    throw "Pester 5+ is required. Install with: Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber"
}
Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop

Describe 'PowerShell scripts parse cleanly' {
    BeforeAll {
        $here = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }
        $repoRoot = Split-Path -Parent $here
        $scriptsDir = Join-Path $repoRoot 'scripts'

        $scriptPaths = @(Get-ChildItem -Path $scriptsDir -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        Set-Variable -Name scriptPaths -Value $scriptPaths -Scope Script

        Write-Host "Discovered $($scriptPaths.Count) scripts under $scriptsDir" -ForegroundColor Cyan
    }

    It 'found scripts to test' {
        $scriptPaths.Count | Should -BeGreaterThan 0
    }

    It 'parses without errors' -ForEach $scriptPaths {
        param($scriptPath)

        $tokens = [System.Collections.ObjectModel.Collection[System.Management.Automation.Language.Token]]::new()
        $errors = [System.Collections.ObjectModel.Collection[System.Management.Automation.Language.ParseError]]::new()

        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath,
            [ref]$tokens,
            [ref]$errors
        )

        if ($errors.Count -gt 0) {
            foreach ($err in $errors) {
                $path = if ($scriptPath) { $scriptPath } else { '<unknown>' }
                Write-Host "Parse error in ${path}: $($err.Message) (line $($err.Extent.StartLineNumber), col $($err.Extent.StartColumnNumber))" -ForegroundColor Red
            }
        }

        $errors.Count | Should -Be 0 -Because "Scripts must parse without errors"
    }
}