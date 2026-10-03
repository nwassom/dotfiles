[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$settings = Get-QemuSettings -EnvPath (Join-Path $repoRoot ".env")
$complete = Join-Path $settings.DataRoot "vm\install-complete"
$bootstrapTemplate = (Resolve-Path (Join-Path $PSScriptRoot "..\guest\install-arch.sh")).Path
$guestSettings = Join-Path $settings.DataRoot "tmp\guest-settings"
$bootstrap = Join-Path $settings.DataRoot "tmp\install-arch-bootstrap.sh"

& (Join-Path $PSScriptRoot "setup.ps1") `
    -DataRoot $settings.DataRoot `
    -VmName $settings.VmName `
    -DiskGiB $settings.DiskGiB

if (-not (Test-Path $complete)) {
    Write-QemuGuestSettings -Settings $settings -Path $guestSettings
    $installerText = [System.IO.File]::ReadAllText($guestSettings) + [System.IO.File]::ReadAllText($bootstrapTemplate)
    [System.IO.File]::WriteAllText($bootstrap, $installerText, [System.Text.UTF8Encoding]::new($false))

    & (Join-Path $PSScriptRoot "launch.ps1") `
        -DataRoot $settings.DataRoot `
        -VmName $settings.VmName `
        -Installer `
        -BootstrapScript $bootstrap `
        -Cpus $settings.Cpus `
        -MemoryMiB $settings.MemoryMiB `
        -GPUHostMemoryGiB $settings.GPUHostMemoryGiB `
        -VideoMode $settings.VideoMode `
        -DotfilesRef $settings.DotfilesRef `
        -HyprlandScale $settings.Scale `
        -Fullscreen $settings.Fullscreen

    $isoName = (Get-Content (Join-Path $PSScriptRoot "..\versions.json") -Raw | ConvertFrom-Json).arch.iso
    & (Join-Path $PSScriptRoot "install-guest.ps1") `
        -DataRoot $settings.DataRoot `
        -VmName $settings.VmName `
        -IsoName $isoName
}

$shortcutRoot = switch ($settings.Shortcut) {
    "desktop" { [Environment]::GetFolderPath("Desktop") }
    "start-menu" { [Environment]::GetFolderPath("Programs") }
}
if ($shortcutRoot) {
    New-QemuShortcut -Path (Join-Path $shortcutRoot "$($settings.VmName).lnk") -ScriptPath (Join-Path $PSScriptRoot "start.ps1")
    New-QemuShortcut -Path (Join-Path $shortcutRoot "$($settings.VmName) - Reconfigure.lnk") -ScriptPath (Join-Path $PSScriptRoot "start.ps1") -Reconfigure
}

& (Join-Path $PSScriptRoot "start.ps1")
