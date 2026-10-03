function Convert-IntegerSetting {
    param([string]$Name, [string]$Value, [int]$Minimum, [int]$Maximum)
    $number = 0
    if (-not [int]::TryParse($Value, [ref]$number) -or $number -lt $Minimum -or $number -gt $Maximum) {
        throw "$Name must be between $Minimum and $Maximum."
    }
    return $number
}

function Get-QemuSettings {
    param([Parameter(Mandatory)][string]$EnvPath)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $EnvPath) {
        if ($line -match '^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$') {
            $values[$Matches[1]] = $Matches[2].Trim([char[]]@('"', "'"))
        }
    }

    $legacyDataRoot = if ($values.ContainsKey("ARCH_QEMU_DATA_ROOT")) { [System.IO.Path]::GetFullPath($values.ARCH_QEMU_DATA_ROOT).TrimEnd('\') } else { $null }
    $vmName = if ($values.ContainsKey("ARCH_QEMU_VM_NAME") -and $values["ARCH_QEMU_VM_NAME"]) {
        $values["ARCH_QEMU_VM_NAME"]
    }
    elseif ($legacyDataRoot) {
        Split-Path -Leaf $legacyDataRoot
    }
    else {
        "ArchHyprland"
    }
    if ($vmName -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]*$' -or $vmName.EndsWith(" ") -or $vmName.EndsWith(".")) {
        throw "ARCH_QEMU_VM_NAME must be a Windows-safe folder name (letters, numbers, spaces, '.', '_' and '-')."
    }
    if (-not $values.ContainsKey("ARCH_QEMU_STORAGE_ROOT") -and $legacyDataRoot) {
        $values.ARCH_QEMU_STORAGE_ROOT = Split-Path -Parent $legacyDataRoot
    }
    if (-not ($values.ContainsKey("ARCH_QEMU_STORAGE_ROOT") -and $values["ARCH_QEMU_STORAGE_ROOT"])) { throw "Set ARCH_QEMU_STORAGE_ROOT in $EnvPath." }
    if (-not [System.IO.Path]::IsPathRooted($values.ARCH_QEMU_STORAGE_ROOT)) {
        throw "ARCH_QEMU_STORAGE_ROOT must be an absolute path."
    }

    $shortcut = if ($values.ContainsKey("ARCH_QEMU_SHORTCUT") -and $values["ARCH_QEMU_SHORTCUT"]) { $values["ARCH_QEMU_SHORTCUT"].ToLowerInvariant() } else { "desktop" }
    if ($shortcut -notin @("desktop", "start-menu", "none")) { throw "ARCH_QEMU_SHORTCUT must be desktop, start-menu, or none." }
    $videoMode = if ($values.ContainsKey("ARCH_QEMU_VIDEO_MODE") -and $values["ARCH_QEMU_VIDEO_MODE"]) { $values["ARCH_QEMU_VIDEO_MODE"].ToLowerInvariant() } else { "virgl" }
    if ($videoMode -notin @("virgl", "virgl-core", "software")) { throw "ARCH_QEMU_VIDEO_MODE must be virgl, virgl-core, or software." }

    $cpuText = if ($values.ContainsKey("ARCH_QEMU_CPUS") -and $values["ARCH_QEMU_CPUS"]) { $values["ARCH_QEMU_CPUS"] } else { "8" }
    $memoryText = if ($values.ContainsKey("ARCH_QEMU_MEMORY_MIB") -and $values["ARCH_QEMU_MEMORY_MIB"]) { $values["ARCH_QEMU_MEMORY_MIB"] } else { "6144" }
    $diskText = if ($values.ContainsKey("ARCH_QEMU_DISK_GIB") -and $values["ARCH_QEMU_DISK_GIB"]) { $values["ARCH_QEMU_DISK_GIB"] } else { "64" }
    $gpuText = if ($values.ContainsKey("ARCH_QEMU_GPU_HOSTMEM_GIB") -and $values["ARCH_QEMU_GPU_HOSTMEM_GIB"]) { $values["ARCH_QEMU_GPU_HOSTMEM_GIB"] } else { "4" }
    $values.ARCH_QEMU_CPUS = Convert-IntegerSetting "ARCH_QEMU_CPUS" $cpuText 2 16
    $values.ARCH_QEMU_MEMORY_MIB = Convert-IntegerSetting "ARCH_QEMU_MEMORY_MIB" $memoryText 4096 16384
    $values.ARCH_QEMU_DISK_GIB = Convert-IntegerSetting "ARCH_QEMU_DISK_GIB" $diskText 32 1024
    $values.ARCH_QEMU_GPU_HOSTMEM_GIB = Convert-IntegerSetting "ARCH_QEMU_GPU_HOSTMEM_GIB" $gpuText 1 8

    $fullscreen = if ($values.ContainsKey("ARCH_QEMU_FULLSCREEN")) { $values["ARCH_QEMU_FULLSCREEN"] } else { "true" }
    $parsedFullscreen = $false
    if (-not [bool]::TryParse($fullscreen, [ref]$parsedFullscreen)) { throw "ARCH_QEMU_FULLSCREEN must be true or false." }

    $scale = if ($values.ContainsKey("ARCH_HYPRLAND_SCALE") -and $values["ARCH_HYPRLAND_SCALE"]) { $values["ARCH_HYPRLAND_SCALE"] } else { "1.5" }
    $parsedScale = 0.0
    if ($scale -notmatch '^\d+(\.\d+)?$' -or -not [double]::TryParse($scale, [System.Globalization.NumberStyles]::AllowDecimalPoint, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedScale) -or $parsedScale -lt 0.75 -or $parsedScale -gt 3.0) {
        throw "ARCH_HYPRLAND_SCALE must be between 0.75 and 3.0."
    }

    $guestUser = if ($values.ContainsKey("ARCH_QEMU_GUEST_USER") -and $values["ARCH_QEMU_GUEST_USER"]) { $values["ARCH_QEMU_GUEST_USER"] } else { "nwassom" }
    if ($guestUser -notmatch '^[a-z_][a-z0-9_-]*$') { throw "ARCH_QEMU_GUEST_USER is not a valid Arch username." }
    $timezone = if ($values.ContainsKey("ARCH_QEMU_TIMEZONE") -and $values["ARCH_QEMU_TIMEZONE"]) { $values["ARCH_QEMU_TIMEZONE"] } else { "America/New_York" }
    if ($timezone -notmatch '^[A-Za-z0-9_+/-]+$' -or $timezone.Contains("..")) { throw "ARCH_QEMU_TIMEZONE is invalid." }
    $dotfilesRef = if ($values.ContainsKey("ARCH_QEMU_DOTFILES_REF") -and $values["ARCH_QEMU_DOTFILES_REF"]) { $values["ARCH_QEMU_DOTFILES_REF"] } else { "main" }
    if ($dotfilesRef -notmatch '^[A-Za-z0-9._/-]+$' -or $dotfilesRef.Contains("..")) { throw "ARCH_QEMU_DOTFILES_REF is invalid." }

    $hostname = ($vmName.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($hostname -notmatch '^[a-z]') { $hostname = "vm-$hostname" }
    if ($hostname.Length -gt 63) { $hostname = $hostname.Substring(0, 63).TrimEnd('-') }
    $storageRoot = [System.IO.Path]::GetFullPath($values.ARCH_QEMU_STORAGE_ROOT)
    [pscustomobject]@{
        VmName = $vmName
        StorageRoot = $storageRoot
        DataRoot = [System.IO.Path]::GetFullPath((Join-Path $storageRoot $vmName))
        Cpus = $values.ARCH_QEMU_CPUS
        MemoryMiB = $values.ARCH_QEMU_MEMORY_MIB
        DiskGiB = $values.ARCH_QEMU_DISK_GIB
        GPUHostMemoryGiB = $values.ARCH_QEMU_GPU_HOSTMEM_GIB
        VideoMode = $videoMode
        Fullscreen = $parsedFullscreen
        Scale = $scale
        GuestUser = $guestUser
        Timezone = $timezone
        Hostname = $hostname
        DotfilesRef = $dotfilesRef
        Shortcut = $shortcut
    }
}

function Write-QemuGuestSettings {
    param([Parameter(Mandatory)]$Settings, [Parameter(Mandatory)][string]$Path)

    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $lines = @(
        "ARCH_QEMU_VM_NAME='$($Settings.VmName)'"
        "ARCH_QEMU_DISK_GIB='$($Settings.DiskGiB)'"
        "ARCH_QEMU_GUEST_USER='$($Settings.GuestUser)'"
        "ARCH_QEMU_TIMEZONE='$($Settings.Timezone)'"
        "ARCH_QEMU_HOSTNAME='$($Settings.Hostname)'"
        "ARCH_HYPRLAND_SCALE='$($Settings.Scale)'"
        "ARCH_QEMU_DOTFILES_REF='$($Settings.DotfilesRef)'"
    )
    [System.IO.File]::WriteAllText($Path, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
}

function New-QemuShortcut {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ScriptPath, [switch]$Reconfigure)

    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $powershell = Join-Path $PSHOME "powershell.exe"
    if (-not (Test-Path $powershell)) { $powershell = (Get-Process -Id $PID).Path }
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($Path)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" + $(if ($Reconfigure) { " -Reconfigure" } else { "" })
    $shortcut.WorkingDirectory = Split-Path -Parent $ScriptPath
    $shortcut.WindowStyle = 7
    $shortcut.Save()
}
