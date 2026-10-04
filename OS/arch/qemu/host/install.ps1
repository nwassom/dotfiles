[CmdletBinding()]
param([switch]$Reset)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$settings = Get-QemuSettings -EnvPath (Join-Path $repoRoot ".env")
$vmDisk = Join-Path $settings.DataRoot "vm\$($settings.VmName).qcow2"
if ($Reset) {
    $running = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64w.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($vmDisk, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 } |
        Select-Object -First 1
    if ($running) { throw "$($settings.VmName) is running. Shut it down before resetting its disk." }
    foreach ($path in @("vm", "logs", "tmp")) {
        Remove-Item -LiteralPath (Join-Path $settings.DataRoot $path) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Reset the $($settings.VmName) guest disk and logs; kept the QEMU runtime and Arch ISO."
}
$complete = Join-Path $settings.DataRoot "vm\install-complete"
$bootstrapTemplate = (Resolve-Path (Join-Path $PSScriptRoot "..\guest\install-arch.sh")).Path
$guestSettings = Join-Path $settings.DataRoot "tmp\guest-settings"
$bootstrap = Join-Path $settings.DataRoot "tmp\install-arch-bootstrap.sh"

& (Join-Path $PSScriptRoot "setup.ps1") `
    -DataRoot $settings.DataRoot `
    -VmName $settings.VmName `
    -DiskGiB $settings.DiskGiB

if (-not (Test-Path $complete)) {
    $disk = Join-Path $settings.DataRoot "vm\$($settings.VmName).qcow2"
    $serialLog = Join-Path $settings.DataRoot "logs\serial.log"
    if ((Test-Path $disk) -and (Test-Path $serialLog) -and
        (Get-Item -LiteralPath $disk).Length -gt 1GB -and
        (Get-Content -LiteralPath $serialLog -Raw) -match "Initial Arch base guest installed") {
        [System.IO.File]::WriteAllText($complete, "base-installed", [System.Text.UTF8Encoding]::new($false))
        Write-Host "Recovered the completed Arch install marker from the guest serial log."
    }
}

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
        -IsoName $isoName `
        -ConfirmWipe:$Reset
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
