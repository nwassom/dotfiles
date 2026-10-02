[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DataRoot,
    [Parameter(Mandatory)][string]$VmName,
    [Parameter(Mandatory)][string]$GuestSettingsFile,
    [switch]$Installer,
    [string]$BootstrapScript,
    [string]$ReconfigureFile,
    [ValidateRange(2, 16)][int]$Cpus = 8,
    [ValidateRange(4096, 16384)][int]$MemoryMiB = 6144,
    [ValidateRange(1, 8)][int]$GPUHostMemoryGiB = 4,
    [bool]$Fullscreen = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DataRoot = [System.IO.Path]::GetFullPath($DataRoot).TrimEnd('\')
$runtime = Join-Path $DataRoot "runtime"
$provisioner = Join-Path $PSScriptRoot "..\guest\provision-arch-hyprland.sh"
$qemu = Get-ChildItem $runtime -Filter "qemu-system-x86_64w.exe" -Recurse | Select-Object -First 1
if (-not $qemu) { throw "Run host\install.ps1 first; WINQ-EMU was not found under $runtime." }
if (-not (Test-Path $provisioner) -or -not (Test-Path $GuestSettingsFile)) { throw "Guest settings or provisioner file is missing." }
if ($Installer -and -not (Test-Path $BootstrapScript)) { throw "Installer mode requires guest\install-arch.sh." }

$disk = Join-Path $DataRoot "vm\$($VmName).qcow2"
$iso = Get-ChildItem (Join-Path $DataRoot "iso") -Filter "archlinux-*.iso" | Select-Object -First 1
$logs = Join-Path $DataRoot "logs"
$temp = Join-Path $DataRoot "tmp"
foreach ($path in @($disk, $logs, $temp)) {
    if (-not (Test-Path $path)) { throw "Missing setup path: $path. Run host\install.ps1 first." }
}
if ($Installer -and -not $iso) { throw "The pinned Arch ISO is missing; run host\install.ps1 first." }
if ($ReconfigureFile -and -not (Test-Path $ReconfigureFile)) { throw "The reconfigure marker is missing: $ReconfigureFile" }

$running = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64w.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($disk, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 } |
    Select-Object -First 1
if ($running) {
    if ($ReconfigureFile) { throw "$VmName is already running; shut it down before reconfiguring." }
    Write-Host "$VmName is already running (QEMU PID $($running.ProcessId))."
    return
}

$arguments = @(
    "-machine", "q35,accel=whpx",
    "-cpu", "host",
    "-smp", "$Cpus",
    "-m", "${MemoryMiB}M",
    "-device", "virtio-vga-gl,blob=on,hostmem=${GPUHostMemoryGiB}G",
    "-display", "sdl,gl=on,show-cursor=off,window-close=off",
    "-drive", "file=$disk,format=qcow2,if=virtio",
    "-device", "virtio-keyboard-pci",
    "-device", "virtio-tablet-pci",
    "-device", "virtio-rng-pci",
    "-netdev", "user,id=n0",
    "-device", "virtio-net-pci,netdev=n0",
    "-serial", "file:$(Join-Path $logs 'serial.log')",
    "-D", (Join-Path $logs "qemu.log"),
    "-qmp", "unix:$(Join-Path $temp 'qmp.sock'),server=on,wait=off",
    "-rtc", "base=localtime,clock=host",
    "-no-reboot",
    "-name", $VmName
)
if ($Fullscreen) { $arguments += "-full-screen" }
$arguments += @(
    "-fw_cfg", "name=provision-arch-hyprland,file=$provisioner",
    "-fw_cfg", "name=guest-settings,file=$GuestSettingsFile"
)
if ($ReconfigureFile) { $arguments += @("-fw_cfg", "name=provision-refresh,file=$ReconfigureFile") }

if ($Installer) {
    $arguments += @(
        "-cdrom", $iso.FullName,
        "-boot", "order=d",
        "-fw_cfg", "name=install-arch,file=$BootstrapScript"
    )
}
else {
    $arguments += @("-boot", "order=c")
}

$env:TEMP = $temp
$env:TMP = $temp
$env:TMPDIR = $temp
$commandLine = ($arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' '
Write-Host "Starting $VmName with WHPX and virtio-GPU/VirGL."
$process = Start-Process -FilePath $qemu.FullName -ArgumentList $commandLine -WorkingDirectory $qemu.DirectoryName -PassThru
Write-Host "$VmName QEMU PID: $($process.Id)"
