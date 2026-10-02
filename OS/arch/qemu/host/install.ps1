[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DataRoot,

    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$DotfilesRef = "main",

    [switch]$ConfirmWipe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DataRoot = [System.IO.Path]::GetFullPath($DataRoot).TrimEnd('\')
$complete = Join-Path $DataRoot "vm\install-complete"

if (Test-Path $complete) {
    & (Join-Path $PSScriptRoot "launch.ps1") -DataRoot $DataRoot
    return
}

& (Join-Path $PSScriptRoot "setup.ps1") -DataRoot $DataRoot
& (Join-Path $PSScriptRoot "launch.ps1") -DataRoot $DataRoot -Installer

$installArgs = @{
    DataRoot = $DataRoot
    DotfilesRef = $DotfilesRef
}
if ($ConfirmWipe) { $installArgs.ConfirmWipe = $true }
& (Join-Path $PSScriptRoot "install-guest.ps1") @installArgs

& (Join-Path $PSScriptRoot "launch.ps1") -DataRoot $DataRoot
