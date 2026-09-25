# Profiles

The repository has one common terminal environment and thin platform profiles:

| Profile | Use |
| --- | --- |
| `macos` | Native Intel macOS |
| `linux` | Alma or Arch Linux |
| `wsl` | Ubuntu or another Linux distribution under Windows |

Install the common environment with:

```sh
./install.sh --profile macos
./install.sh --profile linux
./install.sh --profile wsl
```

The profile is recorded in `$XDG_CONFIG_HOME/dotfiles/profile`. It is metadata
for future platform-specific configuration; the common shell tools remain the
same in every profile.

Create `$XDG_CONFIG_HOME/git/local` from `git/local.example` and set the
identity for that machine. Keep work and personal identities out of this repo.

The first Linux desktop target is KDE Plasma with SDDM and Wayland. Hyprland
will be an optional profile after KDE works reliably for meetings, screen
sharing, and external displays.

Ghostty uses the shared visual configuration on macOS and Linux. WSL keeps
Ghostty on the Windows host and should use the Windows-specific configuration.
