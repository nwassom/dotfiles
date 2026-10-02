[CmdletBinding()]
param(
    [string]$DataRoot,
    [string]$DotfilesRef,
    [switch]$ConfirmWipe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$envFile = Join-Path $repoRoot ".env"
$settings = @{}
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$') {
            $settings[$Matches[1]] = $Matches[2].Trim([char[]]@('"', "'"))
        }
    }
}
if (-not $DataRoot -and $settings.ContainsKey("ARCH_QEMU_DATA_ROOT")) { $DataRoot = $settings.ARCH_QEMU_DATA_ROOT }
if (-not $DotfilesRef -and $settings.ContainsKey("ARCH_QEMU_DOTFILES_REF")) { $DotfilesRef = $settings.ARCH_QEMU_DOTFILES_REF }
if (-not $DataRoot) { throw "Set ARCH_QEMU_DATA_ROOT in .env (copy .env.example) or pass -DataRoot." }
if (-not $DotfilesRef) { $DotfilesRef = "main" }
if ($DotfilesRef -notmatch '^[A-Za-z0-9._/-]+$' -or $DotfilesRef.Contains('..')) { throw "DotfilesRef must be a branch, tag, or commit identifier using letters, numbers, '.', '_', '-', and '/'." }

$DataRoot = [System.IO.Path]::GetFullPath($DataRoot).TrimEnd('\')
$complete = Join-Path $DataRoot "vm\install-complete"
$bootstrap = (Resolve-Path (Join-Path $PSScriptRoot "..\guest\install-arch.sh")).Path

& (Join-Path $PSScriptRoot "setup.ps1") -DataRoot $DataRoot
$repoFile = Join-Path $DataRoot "tmp\dotfiles-repo"
$refFile = Join-Path $DataRoot "tmp\dotfiles-ref"
[System.IO.File]::WriteAllText($repoFile, "https://github.com/nwassom/dotfiles.git", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($refFile, $DotfilesRef, [System.Text.UTF8Encoding]::new($false))

if (-not (Test-Path $complete)) {
    & (Join-Path $PSScriptRoot "launch.ps1") `
        -DataRoot $DataRoot `
        -Installer `
        -BootstrapScript $bootstrap `
        -DotfilesRepoFile $repoFile `
        -DotfilesRefFile $refFile

    if ($ConfirmWipe) {
        & (Join-Path $PSScriptRoot "install-guest.ps1") -DataRoot $DataRoot -ConfirmWipe
    }
    else {
        & (Join-Path $PSScriptRoot "install-guest.ps1") -DataRoot $DataRoot
    }
}

& (Join-Path $PSScriptRoot "launch.ps1") -DataRoot $DataRoot
Write-Host "Arch is provisioning itself from $DotfilesRef on first boot; leave QEMU open until Hyprland starts."
