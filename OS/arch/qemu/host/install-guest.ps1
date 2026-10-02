[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DataRoot,

    [ValidateRange(1, 900)]
    [int]$InstallerBootSeconds = 90,

    [ValidateRange(300, 3600)]
    [int]$InstallTimeoutSeconds = 1800,

    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$DotfilesRef = "main",

    [switch]$ConfirmWipe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DataRoot = [System.IO.Path]::GetFullPath($DataRoot).TrimEnd('\')
if ([System.IO.Path]::GetPathRoot($DataRoot).Substring(0, 1) -eq "C") {
    throw "VM and installer files must remain on a non-C: drive."
}

$qmpPath = Join-Path $DataRoot "tmp\qmp.sock"
$log = Join-Path $DataRoot "logs\serial.log"
if (-not (Test-Path $qmpPath)) { throw "QEMU is not running with the Arch ISO; start launch.ps1 -Installer first." }

$qemu = Get-Process qemu-system-x86_64w -ErrorAction Stop | Select-Object -First 1
$qemuInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$($qemu.Id)"
if ($qemuInfo.CommandLine -notmatch '-cdrom\s+.*archlinux-2026\.10\.01-x86_64\.iso' -or
    $qemuInfo.CommandLine -notmatch '-boot\s+order=d') {
    throw "The active QEMU process is not booted into this project's Arch ISO installer."
}
Write-Host "Waiting $InstallerBootSeconds seconds for the Arch ISO live shell (QEMU PID $($qemu.Id))."
Start-Sleep -Seconds $InstallerBootSeconds

# QEMU's Windows AF_UNIX QMP socket lets setup type only the live-ISO commands.
$source = @"
using System;
using System.Runtime.InteropServices;
public static class ArchQmpSocket {
    [DllImport("Ws2_32.dll", SetLastError=true)] public static extern int WSAStartup(ushort version, IntPtr data);
    [DllImport("Ws2_32.dll", SetLastError=true)] public static extern IntPtr socket(int af, int type, int protocol);
    [DllImport("Ws2_32.dll", SetLastError=true)] public static extern int connect(IntPtr socket, IntPtr address, int length);
    [DllImport("Ws2_32.dll", SetLastError=true)] public static extern int send(IntPtr socket, byte[] data, int length, int flags);
    [DllImport("Ws2_32.dll", SetLastError=true)] public static extern int recv(IntPtr socket, byte[] data, int length, int flags);
    [DllImport("Ws2_32.dll")] public static extern int closesocket(IntPtr socket);
    [DllImport("Ws2_32.dll")] public static extern int WSACleanup();
    [DllImport("Ws2_32.dll")] public static extern int WSAGetLastError();
}
"@
Add-Type -TypeDefinition $source

$wsa = [Runtime.InteropServices.Marshal]::AllocHGlobal(512)
[void][ArchQmpSocket]::WSAStartup(514, $wsa)
$socketPath = Join-Path $DataRoot "tmp\qmp.sock"
$pathBytes = [Text.Encoding]::ASCII.GetBytes($socketPath)
if ($pathBytes.Length -gt 106) { throw "QMP socket path is too long." }
$address = [Runtime.InteropServices.Marshal]::AllocHGlobal(110)
for ($i = 0; $i -lt 110; $i++) { [Runtime.InteropServices.Marshal]::WriteByte($address, $i, 0) }
[Runtime.InteropServices.Marshal]::WriteInt16($address, 0, [int16]1)
[Runtime.InteropServices.Marshal]::Copy($pathBytes, 0, [IntPtr]::Add($address, 2), $pathBytes.Length)
$socket = [ArchQmpSocket]::socket(1, 1, 0)
if ([ArchQmpSocket]::connect($socket, $address, $pathBytes.Length + 3) -ne 0) {
    throw "Could not connect to QEMU QMP (Winsock $([ArchQmpSocket]::WSAGetLastError()))."
}

function Read-QmpLine {
    $line = New-Object System.Text.StringBuilder
    $byte = New-Object byte[] 1
    do {
        $count = [ArchQmpSocket]::recv($socket, $byte, 1, 0)
        if ($count -ne 1) { throw "QEMU QMP disconnected." }
        $character = [char]$byte[0]
        if ($character -ne "`n") { [void]$line.Append($character) }
    } while ($character -ne "`n")
    return $line.ToString()
}

function Send-Qmp {
    param([hashtable]$Message)
    $json = $Message | ConvertTo-Json -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json + "`r`n")
    if ([ArchQmpSocket]::send($socket, $bytes, $bytes.Length, 0) -ne $bytes.Length) {
        throw "Could not send QEMU QMP request."
    }
    do { $reply = Read-QmpLine } while ($reply -match '"event"')
    if ($reply -match '"error"') { throw "QEMU QMP error: $reply" }
}

[void](Read-QmpLine) # greeting
Send-Qmp @{ execute = "qmp_capabilities" }

$keyMap = @{
    " " = "spc"; "-" = "minus"; "=" = "equal"; "." = "dot"; "/" = "slash"; "," = "comma"
}
function Send-QmpText {
    param([Parameter(Mandatory)][string]$Text)
    foreach ($character in $Text.ToCharArray()) {
        $key = $character.ToString()
        if ($key -cmatch "^[A-Z]$") {
            $keys = @(@{ type = "qcode"; data = "shift" }, @{ type = "qcode"; data = $key.ToLowerInvariant() })
        }
        elseif ($key -eq ":") {
            $keys = @(@{ type = "qcode"; data = "shift" }, @{ type = "qcode"; data = "semicolon" })
        }
        elseif ($key -eq "_") {
            $keys = @(@{ type = "qcode"; data = "shift" }, @{ type = "qcode"; data = "minus" })
        }
        elseif ($key -eq "|") {
            $keys = @(@{ type = "qcode"; data = "shift" }, @{ type = "qcode"; data = "backslash" })
        }
        elseif ($keyMap.ContainsKey($key)) {
            $keys = @(@{ type = "qcode"; data = $keyMap[$key] })
        }
        else {
            $keys = @(@{ type = "qcode"; data = $key })
        }
        Send-Qmp @{ execute = "send-key"; arguments = @{ keys = $keys; "hold-time" = 35 } }
        Start-Sleep -Milliseconds 45
    }
    Send-Qmp @{ execute = "send-key"; arguments = @{ keys = @(@{ type = "qcode"; data = "ret" }); "hold-time" = 35 } }
}

Send-QmpText "DOTFILES_REF=$DotfilesRef curl -fsSL https://raw.githubusercontent.com/nwassom/dotfiles/$DotfilesRef/OS/arch/qemu/guest/install-arch.sh | DOTFILES_REF=$DotfilesRef bash"
$confirmation = "Type WIPE-ARCH-GUEST"
$installDeadline = (Get-Date).AddSeconds($InstallTimeoutSeconds)
while ((Get-Date) -lt $installDeadline) {
    if (-not (Get-Process -Id $qemu.Id -ErrorAction SilentlyContinue)) {
        if (Test-Path $log) { Get-Content $log -Tail 100 }
        throw "QEMU exited before the Arch installer completed."
    }
    if (Test-Path $log) {
        $logText = Get-Content $log -Raw
    if ($logText -match [regex]::Escape($confirmation)) { break }
        if ($logText -match "Initial Arch \+ Hyprland guest installed") { break }
    }
    Start-Sleep -Seconds 2
}

if (-not (Test-Path $log) -or (Get-Content $log -Raw) -notmatch "Initial Arch \+ Hyprland guest installed") {
    $logText = if (Test-Path $log) { Get-Content $log -Raw } else { "" }
    if ($logText -notmatch [regex]::Escape($confirmation)) {
        if ($logText) { Write-Host $logText }
        throw "Installer did not reach its disk confirmation prompt before timeout."
    }
    if (-not $ConfirmWipe) {
        $answer = Read-Host "The installer will format the new VM disk at /dev/vda. Type WIPE-ARCH-GUEST to confirm"
        if ($answer -cne "WIPE-ARCH-GUEST") { throw "Disk formatting was not confirmed; the installer remains paused." }
    }
    Write-Host "Confirming format of the isolated, newly-created QEMU disk /dev/vda."
    Send-QmpText "WIPE-ARCH-GUEST"
}

while ((Get-Date) -lt $installDeadline -and (Get-Process -Id $qemu.Id -ErrorAction SilentlyContinue)) {
    Start-Sleep -Seconds 3
}
if (Get-Process -Id $qemu.Id -ErrorAction SilentlyContinue) {
    throw "Arch install is still running; inspect $log before taking any action."
}
if (-not (Test-Path $log) -or (Get-Content $log -Raw) -notmatch "Initial Arch \+ Hyprland guest installed") {
    throw "QEMU exited without reporting a successful install; inspect $log before retrying."
}

Write-Host "Arch install finished. Guest install log: $log"
if (Test-Path $log) { Get-Content $log -Tail 80 }
Set-Content -Path (Join-Path $DataRoot "vm\install-complete") -Value $DotfilesRef -NoNewline
