[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DataRoot,

    [Parameter(Mandatory)]
    [string]$VmName,

    [ValidateRange(32, 1024)]
    [int]$DiskGiB = 64
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DataRoot = [System.IO.Path]::GetFullPath($DataRoot).TrimEnd('\')
$driveLetter = [System.IO.Path]::GetPathRoot($DataRoot).Substring(0, 1)

$volume = Get-Volume -DriveLetter $driveLetter
if ($volume.DriveType -ne "Fixed" -or $volume.FileSystem -notin @("NTFS", "ReFS")) {
    throw "Choose a local NTFS or ReFS drive for sparse QCOW2 storage."
}
if ($volume.SizeRemaining -lt 25GB) { throw "At least 25 GiB must be free on $driveLetter`: ." }

$manifest = Get-Content (Join-Path $PSScriptRoot "..\versions.json") -Raw | ConvertFrom-Json

function Get-VerifiedDownload {
    param([string]$Url, [string]$Path, [string]$Sha256)

    if (Test-Path $Path) {
        $existing = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($existing -ne $Sha256.ToLowerInvariant()) {
            throw "Existing file failed SHA-256 verification: $Path. Move it aside before retrying."
        }
        return
    }

    $partial = "$Path.download"
    $curl = Get-Command curl.exe -ErrorAction Stop
    & $curl.Source --fail --location --retry 5 --retry-delay 2 --continue-at - --output $partial $Url
    if ($LASTEXITCODE -ne 0) { throw "Download failed for $Url (curl exit $LASTEXITCODE). Partial data is retained on the selected data drive." }
    $actual = (Get-FileHash -Path $partial -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Sha256.ToLowerInvariant()) {
        Remove-Item -LiteralPath $partial -Force
        throw "SHA-256 mismatch for $Url (got $actual)."
    }
    Move-Item -LiteralPath $partial -Destination $Path
}

$directories = @("downloads", "runtime", "iso", "vm", "logs", "tmp")
foreach ($directory in $directories) {
    New-Item -ItemType Directory -Path (Join-Path $DataRoot $directory) -Force | Out-Null
}

$runtimeZip = Join-Path $DataRoot "downloads\winq-emu-alpha10-portable.zip"
$isoPath = Join-Path $DataRoot "iso\$($manifest.arch.iso)"
Get-VerifiedDownload -Url $manifest.runtime.url -Path $runtimeZip -Sha256 $manifest.runtime.sha256
Get-VerifiedDownload -Url $manifest.arch.isoUrl -Path $isoPath -Sha256 $manifest.arch.isoSha256

$qemu = Get-ChildItem (Join-Path $DataRoot "runtime") -Filter "qemu-system-x86_64w.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $qemu) {
    Expand-Archive -LiteralPath $runtimeZip -DestinationPath (Join-Path $DataRoot "runtime") -Force
    $qemu = Get-ChildItem (Join-Path $DataRoot "runtime") -Filter "qemu-system-x86_64w.exe" -Recurse | Select-Object -First 1
}
$qemuImg = Get-ChildItem (Join-Path $DataRoot "runtime") -Filter "qemu-img.exe" -Recurse | Select-Object -First 1
if (-not $qemu -or -not $qemuImg) { throw "WINQ-EMU QEMU binaries were not found after extraction." }

$disk = Join-Path $DataRoot "vm\$($VmName).qcow2"
$legacyDisk = Join-Path $DataRoot "vm\arch.qcow2"
if (-not (Test-Path $disk) -and (Test-Path $legacyDisk)) {
    Move-Item -LiteralPath $legacyDisk -Destination $disk
    Write-Host "Migrated the existing Arch disk to the named VM filename without recreating it."
}
if (-not (Test-Path $disk)) {
    & $qemuImg.FullName create -f qcow2 $disk "${DiskGiB}G"
    if ($LASTEXITCODE -ne 0) { throw "qemu-img could not create $disk." }
}
elseif ((Get-Item $disk).Length -eq 0) {
    throw "Existing guest disk is empty; refusing to overwrite it. Remove it yourself only if it is disposable."
}

Write-Host "WINQ-EMU runtime, Arch ISO, and $VmName guest disk are ready under $DataRoot."
Write-Host "No existing disk was replaced."
