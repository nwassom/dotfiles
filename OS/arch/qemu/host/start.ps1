[CmdletBinding()]
param([switch]$Reconfigure)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$settings = Get-QemuSettings -EnvPath (Join-Path $repoRoot ".env")
$complete = Join-Path $settings.DataRoot "vm\install-complete"
if (-not (Test-Path $complete)) { throw "Run host\install.ps1 once to create and install $($settings.VmName)." }

$oldTokenFile = Join-Path $settings.DataRoot "tmp\github-token"
if (Test-Path $oldTokenFile) { Remove-Item -LiteralPath $oldTokenFile -Force }
$refreshFile = Join-Path $settings.DataRoot "tmp\provision-refresh"
if ($Reconfigure) {
    [System.IO.File]::WriteAllText($refreshFile, "1", [System.Text.UTF8Encoding]::new($false))
}
elseif (Test-Path $refreshFile) {
    Remove-Item -LiteralPath $refreshFile -Force
}

$launch = @{
    DataRoot = $settings.DataRoot
    VmName = $settings.VmName
    Cpus = $settings.Cpus
    MemoryMiB = $settings.MemoryMiB
    GPUHostMemoryGiB = $settings.GPUHostMemoryGiB
    VideoMode = $settings.VideoMode
    DotfilesRef = $settings.DotfilesRef
    HyprlandScale = $settings.Scale
    Fullscreen = $settings.Fullscreen
}
if ($Reconfigure) { $launch.ReconfigureFile = $refreshFile }
& (Join-Path $PSScriptRoot "launch.ps1") @launch
