# Arch + Hyprland in QEMU/WHPX

This creates a reproducible vanilla Arch guest using the pinned WINQ-EMU
runtime, BIOS boot, a QCOW2 disk on a user-selected non-C: drive, and an Arch
Linux Archive package snapshot pinned to the ISO date.

The initial guest contains current Hyprland, Ghostty, Mesa, and VirGL/Venus diagnostic
tools, and no dock, theme, or development workstation stack. Hyprland uses the
display's preferred mode, enables animations, and starts Ghostty on login. The guest
clones this repository to `/home/nwassom/dotfiles` and runs its QEMU Ansible playbook
locally; Windows host files are not mounted in the guest.

## Install

First verify WHPX from elevated PowerShell. The scripts do not enable Windows
features or restart the host:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform
```

Then run one command from the repository root:

```powershell
.\OS\arch\qemu\host\install.ps1 -DataRoot G:\ArchHyprlandVM -DotfilesRef main
```

On first run, the script prepares QEMU, installs Arch from the ISO, clones the selected
public GitHub ref into the guest, applies Ansible locally, and boots Hyprland. Confirm
the guest disk wipe when prompted; add `-ConfirmWipe` to authorize it non-interactively.
Use a commit SHA with `-DotfilesRef` to reproduce a specific dotfiles revision. The
installer downloads its bootstrap from that ref, so push the desired revision first.
On later runs, the same command launches the installed guest directly.

The guest autologs into Hyprland and opens Ghostty. Use `Super+Return` to open
another terminal, `Super+1/2/3` to switch workspaces, and `Super+Shift+Q` to exit
Hyprland. QEMU, the ISO, QCOW2 disk, logs, and temporary sockets stay under the
selected data root. The installed dotfiles commit is recorded in
`/etc/arch-hyprland-dotfiles.commit`.

## Renderer check

Inside Hyprland:

```sh
glxinfo -B
vulkaninfo --summary
hyprctl monitors all
glmark2-wayland --fullscreen
```

The guest must report a VirGL renderer, not `llvmpipe`. Check `hyprctl monitors`
for the mode QEMU exposes; 4K/144 Hz is only available if the host display and
QEMU/WHPX virtio-gpu path expose it. Venus/Vulkan is optional. No NVIDIA Linux
driver is installed in the guest.

`versions.json` pins the runtime, ISO checksum, and Arch repository snapshot.
Update those pins deliberately and rerun performance checks. `setup.ps1` never
overwrites an existing `arch.qcow2`.
