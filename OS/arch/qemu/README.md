# Named Arch + Hyprland QEMU VM

This creates a persistent Arch VM on Windows using QEMU/WHPX and virtio-GPU/VirGL.
The first install runs Ansible once to install Hyprland, Ghostty, fonts, graphics
support, and Foot as a fallback terminal. The VM boots to an Arch shell; run
`Hyprland` when you want the graphical session.

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
display scale. Video modes are `virgl-core` (default), `virgl`, and `software`;
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
disk format when prompted. Existing VM disks are preserved. After setup, use
the generated shortcut; no PowerShell window is needed for routine launches.

## Use and reconfigure

Click `<VM name>.lnk`, or run `host\start.ps1`. The guest autologs into a TTY.
Run `Hyprland` to start the session. Ghostty opens by default; `Super+Return`
opens Ghostty and `Super+Shift+Return` opens Foot as a fallback. `Super+1/2/3`
switches workspaces; `Super+Shift+Q` returns to the shell. Run `sudo poweroff`
to shut the VM down.

The optional `<VM name> - Reconfigure.lnk` (or
`host\start.ps1 -Reconfigure`) explicitly reruns Ansible. Use it after changing
the Hyprland scale or guest Ansible/config. Shut down the VM before
reconfiguring. CPU, memory, GPU host memory, and fullscreen apply at next launch;
disk size, guest username, and timezone are creation-time settings. Changing
the VM name selects a different instance directory.

`versions.json` pins the QEMU runtime and Arch ISO. VM files, logs, and downloads
are under `ARCH_QEMU_STORAGE_ROOT\ARCH_QEMU_VM_NAME`.

## Updating the existing POC VM

An older `.env` containing `ARCH_QEMU_DATA_ROOT=G:\ArchHyprlandVM` is recognized:
it maps to storage root `G:\` and VM name `ArchHyprlandVM`. The installer
renames the old `vm\arch.qcow2` file to the named disk filename without
recreating it.

The older guest contains a one-time provisioner. Before using its new
reconfigure shortcut, open Foot in the existing guest and run this once to
update Ansible, the manual-start shell profile, and the boot-time helper:

```sh
cd ~/dotfiles
git fetch origin main
git checkout --detach FETCH_HEAD
sudo env ANSIBLE_CONFIG="$HOME/dotfiles/OS/arch/qemu/ansible/ansible.cfg" \
  ansible-playbook -i 'arch_qemu,' -c local \
  "$HOME/dotfiles/OS/arch/qemu/ansible/playbook.yml" \
  --extra-vars "arch_user=$USER hyprland_scale=1.5"
```

Then exit Hyprland with `Super+Shift+Q`, run `sudo poweroff` at the shell, and
run `host\install.ps1` from Windows PowerShell once. It renames the existing disk
file without reinstalling Arch, creates the configured shortcut, and starts the
VM with the new TTY-first behavior.
