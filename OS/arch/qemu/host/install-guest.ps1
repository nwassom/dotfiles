[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DataRoot,

    [Parameter(Mandatory)]
    [string]$VmName,

    [Parameter(Mandatory)]
    [string]$IsoName,

    [ValidateRange(1, 900)]
    [int]$InstallerBootSeconds = 90,

    [ValidateRange(300, 3600)]
    [int]$InstallTimeoutSeconds = 1800,

    [switch]$ConfirmWipe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DataRoot = [System.IO.Path]::GetFullPath($DataRoot).TrimEnd('\')
$qmpPortFile = Join-Path $DataRoot "tmp\qmp-port"
$log = Join-Path $DataRoot "logs\serial.log"
$disk = Join-Path $DataRoot "vm\$($VmName).qcow2"
$qemuInfo = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64w.exe'" |
    Where-Object {
        $_.CommandLine -and
        $_.CommandLine.IndexOf($disk, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $_.CommandLine.IndexOf($IsoName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    } |
    Select-Object -First 1
if (-not $qemuInfo) { throw "QEMU is not running $VmName from the Arch ISO; run host\install.ps1." }
$qemu = Get-Process -Id $qemuInfo.ProcessId -ErrorAction Stop

if (-not (Test-Path $qmpPortFile)) { throw "QEMU did not prepare its QMP port file under $DataRoot\tmp." }

Write-Host "Waiting $InstallerBootSeconds seconds for the Arch ISO live shell (QEMU PID $($qemu.Id))."
Start-Sleep -Seconds $InstallerBootSeconds
if (-not (Get-Process -Id $qemu.Id -ErrorAction SilentlyContinue)) {
    if (Test-Path (Join-Path $DataRoot "logs\qemu.log")) { Get-Content (Join-Path $DataRoot "logs\qemu.log") -Tail 80 }
    throw "QEMU exited while the Arch ISO was booting; no disk install was started."
}

if (-not (Test-Path $qmpPortFile)) { throw "QEMU did not publish its localhost QMP port." }
$qmpPort = [int](Get-Content -LiteralPath $qmpPortFile -Raw)
$client = $null
$connectError = "connection timed out"
for ($attempt = 0; $attempt -lt 15; $attempt++) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $client.Connect([System.Net.IPAddress]::Loopback, $qmpPort)
        break
    }
    catch {
        $connectError = $_.Exception.Message
        $client.Dispose()
        $client = $null
        if (-not (Get-Process -Id $qemu.Id -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Seconds 1
    }
}
if (-not $client -or -not $client.Connected) {
    throw "Could not connect to QEMU QMP on 127.0.0.1:$qmpPort ($connectError). Check $DataRoot\logs\qemu.log."
}
$stream = $client.GetStream()
$reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
$writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
$writer.NewLine = "`r`n"
$writer.AutoFlush = $true

function Read-QmpLine {
    $line = $reader.ReadLine()
    if ($null -eq $line) {
        $client.Dispose()
        throw "QEMU QMP disconnected."
    }
    return $line
}

function Send-Qmp {
    param([hashtable]$Message)
    $json = $Message | ConvertTo-Json -Depth 8 -Compress
    $writer.WriteLine($json)
    do { $reply = Read-QmpLine } while ($reply -match '"event"')
    if ($reply -match '"error"') {
        $client.Dispose()
        throw "QEMU QMP error: $reply"
    }
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
        elseif ($key -eq "&") {
            $keys = @(@{ type = "qcode"; data = "shift" }, @{ type = "qcode"; data = "7" })
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

Send-Qmp @{ execute = "send-key"; arguments = @{ keys = @(@{ type = "qcode"; data = "ctrl" }, @{ type = "qcode"; data = "u" }); "hold-time" = 35 } }
Send-QmpText "modprobe qemu_fw_cfg && bash /sys/firmware/qemu_fw_cfg/by_name/install-arch/raw"
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
        if ($logText -match "Initial Arch base guest installed") { break }
    }
    Start-Sleep -Seconds 2
}

if (-not (Test-Path $log) -or (Get-Content $log -Raw) -notmatch "Initial Arch base guest installed") {
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
if (-not (Test-Path $log) -or (Get-Content $log -Raw) -notmatch "Initial Arch base guest installed") {
    throw "QEMU exited without reporting a successful install; inspect $log before retrying."
}

Write-Host "Arch install finished. Guest install log: $log"
if (Test-Path $log) { Get-Content $log -Tail 80 }
Set-Content -Path (Join-Path $DataRoot "vm\install-complete") -Value "base-installed" -NoNewline
$client.Dispose()
