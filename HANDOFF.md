# Dotfiles Handoff

## Goal

Create one consistent terminal environment across macOS, Linux, WSL, and
Windows. Build and tune the Linux desktop in an Intel Mac UTM VM first, then
reproduce it on the GFE laptop.

## Target Linux Desktop

- Arch Linux x86_64
- KDE Plasma
- SDDM
- Wayland, with X11 fallback
- Hyprland is optional later, not the initial desktop

## Current Repository State

- `install.sh` supports `macos`, `linux`, and `wsl` profiles.
- Common shell, Git, tmux, Starship, Neovim, and Ghostty configs are linked.
- Git identity belongs in `~/.config/git/local`.
- Read `README.md` and `profiles/README.md` before changing the layout.
- Existing Ghostty, tmux, shell, and Starship changes were user work and must
  not be reverted.

## Immediate VM Steps

1. Create an x86_64 Linux VM in UTM.
2. Install Arch with ext4, systemd-boot, NetworkManager, and a normal sudo
   user.
3. Install KDE Plasma, SDDM, Wayland, PipeWire, SPICE support, and common
   development tools.
4. Enable NetworkManager, SDDM, and the UTM guest agents.
5. Clone this repository inside the VM.
6. Run `./install.sh --profile linux`.
7. Configure `~/.config/git/local` from `git/local.example`.
8. Test Ghostty, Zsh, Starship, tmux, Neovim, clipboard sharing, display
   resizing, and Wayland.
9. Take a UTM snapshot before experimenting with KDE appearance.

## Next Repository Work

- Add a reproducible package/tool manifest for macOS and Arch.
- Finish platform-specific Ghostty configs.
- Add KDE configuration as a selectable desktop profile.
- Test Alma Linux with the same common terminal profile.
- Validate CAC reader, VPN, meetings, screen sharing, and external displays on
  the GFE VM.
