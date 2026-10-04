# Named Arch + Hyprland QEMU VM

This creates a persistent Arch VM on Windows using QEMU/WHPX and the POC-tested
virtio-GPU/VirGL/Venus path. The first install runs Ansible once to install
Hyprland, Ghostty, fonts, graphics support, and Foot as a fallback terminal.
greetd/ReGreet provides the graphical login; Hyprland starts after sign-in.

## Configure

Copy `.env.example` to `.env` at the repository root. The storage root and VM
name determine the instance path, QEMU title, disk filename, and optional
shortcut name:

```dotenv
ARCH_QEMU_STORAGE_ROOT=C:\VMs
ARCH_QEMU_VM_NAME=ArchHyprland
ARCH_QEMU_SHORTCUT=desktop
```

That stores the VM under `C:\VMs\ArchHyprland`. Shortcut choices are `desktop`,
`start-menu`, or `none`. C: and paths with spaces are supported.

The remaining settings tune CPU count, RAM, disk size, GPU host memory, video
mode, fullscreen, guest username/timezone, dotfiles revision, and Hyprland
display scale. Video modes are `virgl` (default), `virgl-core`, and `software`;
the first two use VirGL; `software` trades GPU acceleration for compatibility.
The default scale is `1.5`, suitable as a starting point for 4K. Values are
local to each device; `.env` is ignored by Git.

## One-time install

Requirements: Windows Hypervisor Platform enabled, firmware virtualization
available to Windows, internet access, and a local NTFS/ReFS drive with 25 GiB
free. From PowerShell at the repository root:

```powershell
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
notepad .env
.\OS\arch\qemu\host\install.ps1
```

The installer downloads the pinned QEMU runtime and Arch ISO, creates the named
QCOW2 disk, installs Arch, and provisions it on first boot. Confirm the initial
disk format when prompted. During installation, set and confirm the guest login
password in the QEMU window; input is hidden and the password is stored only as
an Arch password hash, never in `.env` or host logs. Existing VM disks are
preserved. After setup, use the generated shortcut; no PowerShell window is
needed for routine launches.

PowerShell validates `.env`, prepends the settings to a temporary copy of
`guest/install-arch.sh`, and passes that bootstrap to the live ISO. The guest
validates every required setting before touching `/dev/vda`, then installs base
Arch. First-boot Ansible installs Hyprland and Ghostty. This keeps the previously
tested custom installer instead of adding a second installer-profile format.

## Use and reconfigure

Click `<VM name>.lnk`, or run `host\start.ps1`. ReGreet shows a graphical login;
sign in as the configured guest user and select Hyprland. No terminal
auto-opens. `Super+Return` opens Ghostty and `Super+Shift+Return` opens Foot as
a fallback. `Super+1/2/3` switches workspaces; `Super+Shift+Q` returns to the
login screen. Run `sudo poweroff` from a terminal to shut down the VM.

The optional `<VM name> - Reconfigure.lnk` (or
`host\start.ps1 -Reconfigure`) explicitly reruns Ansible. Use it after changing
the Hyprland scale or guest Ansible/config. Shut down the VM before
reconfiguring. CPU, memory, GPU host memory, and fullscreen apply at next launch;
disk size, guest username, and timezone are creation-time settings. Changing
the VM name selects a different instance directory.

`versions.json` pins the QEMU runtime and Arch ISO. VM files, logs, and downloads
are under `ARCH_QEMU_STORAGE_ROOT\ARCH_QEMU_VM_NAME`.

## Resetting the existing TTY-only POC VM

An older `.env` containing `ARCH_QEMU_DATA_ROOT=G:\ArchHyprlandVM` is recognized:
it maps to storage root `G:\` and VM name `ArchHyprlandVM`. The installer
renames the old `vm\arch.qcow2` file to the named disk filename without
recreating it.

The older TTY-only POC account has no login password or greetd configuration.
Shut down the VM, then run `host\install.ps1 -Reset` from PowerShell at the repo
root. It deletes only the named guest disk, logs, and temporary files; it keeps
the QEMU runtime, Arch ISO, `.env`, and repository. The script then performs the
full install, including the hidden password prompt and graphical login setup.
