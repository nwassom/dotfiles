# Arch + Hyprland in QEMU/WHPX

This provisions a minimal Arch guest in QEMU on Windows. On first boot, Arch
clones this public repository and runs its QEMU Ansible playbook locally. No
WSL, SSH, or host-side Ansible is required.

The guest uses the pinned WINQ-EMU runtime, an Arch Linux Archive snapshot, a
QCOW2 disk, and QEMU virtio-GPU with VirGL. It installs Hyprland, Ghostty,
Mesa, and graphics diagnostics; no dock, theme, or workstation stack.

## Install

Requirements: Windows with Hypervisor Platform enabled, PowerShell, internet
access, and a fixed NTFS/ReFS data drive other than C: with at least 25 GiB
free. The selected path must not contain spaces. Check the Windows feature in
elevated PowerShell with `Get-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform`;
if disabled, enable it with `Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All`
and reboot.

Copy `.env.example` to `.env` at the repository root and set `ARCH_QEMU_DATA_ROOT`
to your VM storage path. `ARCH_QEMU_DOTFILES_REF` defaults to `main`; set it to
a branch, tag, or commit that is available on GitHub. The guest clones from
GitHub, so push the revision you want to test before launching.

From PowerShell at the repository root:

```powershell
Copy-Item .env.example .env
# Edit .env and set ARCH_QEMU_DATA_ROOT to a non-C: path, e.g. G:\ArchHyprlandVM
.\OS\arch\qemu\host\install.ps1
```

On first install, confirm the wipe of the newly-created VM disk. Keep the QEMU
window open while Arch boots, clones the selected revision, and runs Ansible;
Hyprland starts after provisioning. Re-running the command starts the VM.

The guest autologs into Hyprland and opens Ghostty. Use `Super+Return` for
another terminal, `Super+1/2/3` to switch workspaces, and `Super+Shift+Q` to
exit Hyprland. Installer and QEMU logs are under the configured data root's
`logs` directory.

## Check graphics

Inside Hyprland:

```sh
glxinfo -B
hyprctl monitors all
vulkaninfo --summary
glmark2-wayland --fullscreen
```

VirGL (not `llvmpipe`) is the MVP acceleration check. 4K/144 Hz depends on
what the host display and QEMU/WHPX virtio-GPU path expose; first confirm a
working Hyprland session and a usable monitor mode. Venus/Vulkan is optional.

`versions.json` pins the QEMU runtime, Arch ISO checksum, and package snapshot.
`setup.ps1` never overwrites an existing VM disk. To retry from scratch, only
remove the VM data root if you are sure its disk is disposable.
