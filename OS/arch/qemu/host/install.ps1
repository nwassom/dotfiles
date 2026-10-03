[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$settings = Get-QemuSettings -EnvPath (Join-Path $repoRoot ".env")
$complete = Join-Path $settings.DataRoot "vm\install-complete"
$bootstrap = (Resolve-Path (Join-Path $PSScriptRoot "..\guest\install-arch.sh")).Path
$guestSettings = Join-Path $settings.DataRoot "tmp\guest-settings"

& (Join-Path $PSScriptRoot "setup.ps1") `
    -DataRoot $settings.DataRoot `
    -VmName $settings.VmName `
    -DiskGiB $settings.DiskGiB

if (-not (Test-Path $complete)) {
    Write-QemuGuestSettings -Settings $settings -Path $guestSettings

    & (Join-Path $PSScriptRoot "launch.ps1") `
        -DataRoot $settings.DataRoot `
        -VmName $settings.VmName `
        -GuestSettingsFile $guestSettings `
        -Installer `
        -BootstrapScript $bootstrap `
        -Cpus $settings.Cpus `
        -MemoryMiB $settings.MemoryMiB `
        -GPUHostMemoryGiB $settings.GPUHostMemoryGiB `
        -VideoMode $settings.VideoMode `
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
