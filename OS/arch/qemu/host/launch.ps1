[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DataRoot,

    [switch]$Installer,

    [string]$BootstrapScript,

    [string]$DotfilesRepoFile,

    [string]$DotfilesRefFile,

    [ValidateRange(2, 16)]
    [int]$Cpus = 8,

    [ValidateRange(4096, 16384)]
    [int]$MemoryMiB = 6144
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DataRoot = [System.IO.Path]::GetFullPath($DataRoot).TrimEnd('\')
if ([System.IO.Path]::GetPathRoot($DataRoot).Substring(0, 1) -eq "C") {
    throw "VM data must remain on a non-C: drive."
}
if ($DataRoot -match '\s') { throw "Choose a data path without spaces to keep QEMU arguments simple." }

$runtime = Join-Path $DataRoot "runtime"
$qemu = Get-ChildItem $runtime -Filter "qemu-system-x86_64w.exe" -Recurse | Select-Object -First 1
if (-not $qemu) { throw "Run setup.ps1 first; WINQ-EMU was not found under $runtime." }

$disk = Join-Path $DataRoot "vm\arch.qcow2"
$iso = Get-ChildItem (Join-Path $DataRoot "iso") -Filter "archlinux-*.iso" | Select-Object -First 1
$logs = Join-Path $DataRoot "logs"
$temp = Join-Path $DataRoot "tmp"
foreach ($path in @($disk, $logs, $temp)) {
    if (-not (Test-Path $path)) { throw "Missing setup path: $path. Run setup.ps1 first." }
}
if ($Installer -and -not $iso) { throw "The pinned Arch ISO is missing; run setup.ps1 first." }
if ($Installer -and (-not (Test-Path $BootstrapScript) -or -not (Test-Path $DotfilesRepoFile) -or -not (Test-Path $DotfilesRefFile))) {
    throw "Installer mode requires the bootstrap script and dotfiles repo/ref settings."
}

# The trial host OS stays usable; the defaults mirror the tested balanced profile.
$arguments = @(
    "-machine", "q35,accel=whpx",
    "-cpu", "host",
    "-smp", "$Cpus",
    "-m", "${MemoryMiB}M",
    "-device", "virtio-vga-gl,blob=on,hostmem=4G,venus=on",
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
    "-name", "ArchHyprland",
    "-full-screen"
)

if ($Installer) {
    $arguments += @("-cdrom", $iso.FullName, "-boot", "order=d")
    $arguments += @(
        "-fw_cfg", "name=install-arch,file=$BootstrapScript",
        "-fw_cfg", "name=dotfiles-repo,file=$DotfilesRepoFile",
        "-fw_cfg", "name=dotfiles-ref,file=$DotfilesRefFile"
    )
}
else {
    $arguments += @("-boot", "order=c")
}

$env:TEMP = $temp
$env:TMP = $temp
$env:TMPDIR = $temp

Write-Host "Starting QEMU/WHPX. Guest files and logs: $DataRoot"
Write-Host "Renderer: virtio-gpu + VirGL; Venus is enabled but not required."
$process = Start-Process -FilePath $qemu.FullName -ArgumentList $arguments -WorkingDirectory $qemu.DirectoryName -PassThru
Write-Host "QEMU PID: $($process.Id)"
