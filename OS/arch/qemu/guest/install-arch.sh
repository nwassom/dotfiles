#!/usr/bin/env bash
set -Eeuo pipefail

DISK=/dev/vda
ARCH_USER=${ARCH_USER:-nwassom}
ARCH_HOSTNAME=${ARCH_HOSTNAME:-arch-hyprland}
ARCH_TIMEZONE=${ARCH_TIMEZONE:-America/New_York}
ARCH_REPO_SNAPSHOT=${ARCH_REPO_SNAPSHOT:-2026/10/01}
ARCH_DISK_GIB=${ARCH_DISK_GIB:-64}

if [[ ${EUID} -ne 0 ]]; then
    echo "Run this installer as root from the Arch ISO." >&2
    exit 1
fi

exec > >(tee -a /dev/ttyS0) 2>&1

modprobe qemu_fw_cfg
if [[ ! -r /sys/firmware/qemu_fw_cfg/by_name/dotfiles-repo/raw || ! -r /sys/firmware/qemu_fw_cfg/by_name/dotfiles-ref/raw ]]; then
    echo "QEMU did not provide the dotfiles repository and ref." >&2
    exit 1
fi
ARCH_DOTFILES_REPO=$(</sys/firmware/qemu_fw_cfg/by_name/dotfiles-repo/raw)
ARCH_DOTFILES_REF=$(</sys/firmware/qemu_fw_cfg/by_name/dotfiles-ref/raw)
if [[ "$ARCH_DOTFILES_REPO" != "https://github.com/nwassom/dotfiles.git" || ! "$ARCH_DOTFILES_REF" =~ ^[A-Za-z0-9._/-]+$ || "$ARCH_DOTFILES_REF" == *..* ]]; then
    echo "Invalid dotfiles repository or ref." >&2
    exit 1
fi

if [[ ! "$ARCH_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "Invalid ARCH_USER." >&2
    exit 1
fi
if [[ ! "$ARCH_HOSTNAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "Invalid ARCH_HOSTNAME." >&2
    exit 1
fi

if [[ ! -b "$DISK" || "$(lsblk -dn -o TYPE "$DISK")" != "disk" ]]; then
    echo "Expected the new QEMU virtio disk at $DISK." >&2
    exit 1
fi
disk_bytes=$(blockdev --getsize64 "$DISK")
minimum_bytes=$((ARCH_DISK_GIB * 1024 * 1024 * 1024 - 1024 * 1024 * 1024))
if (( disk_bytes < minimum_bytes )); then
    echo "$DISK is smaller than the configured ${ARCH_DISK_GIB} GiB VM disk." >&2
    exit 1
fi

lsblk "$DISK"
read -r -p "Type WIPE-ARCH-GUEST to format only the new VM disk $DISK: " confirm
if [[ "$confirm" != "WIPE-ARCH-GUEST" ]]; then
    echo "Disk formatting cancelled."
    exit 1
fi

echo "Installing from Arch Linux Archive snapshot $ARCH_REPO_SNAPSHOT"
printf 'Server = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "$ARCH_REPO_SNAPSHOT" > /etc/pacman.d/mirrorlist
pacman -Syy --noconfirm

wipefs --all --force "$DISK"
printf 'label: dos\nunit: sectors\n\nstart=2048, type=83, bootable\n' | sfdisk --wipe always "$DISK"
partprobe "$DISK"
udevadm settle
mkfs.ext4 -F /dev/vda1
mount /dev/vda1 /mnt

pacstrap -K /mnt \
    base \
    linux \
    linux-firmware \
    amd-ucode \
    grub \
    sudo \
    networkmanager \
    ansible \
    git \
    python \
    dbus

genfstab -U /mnt > /mnt/etc/fstab
printf 'Server = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "$ARCH_REPO_SNAPSHOT" > /mnt/etc/pacman.d/mirrorlist

arch-chroot /mnt /usr/bin/env \
    ARCH_USER="$ARCH_USER" \
    ARCH_HOSTNAME="$ARCH_HOSTNAME" \
    ARCH_TIMEZONE="$ARCH_TIMEZONE" \
    ARCH_DOTFILES_REPO="$ARCH_DOTFILES_REPO" \
    ARCH_DOTFILES_REF="$ARCH_DOTFILES_REF" \
    /bin/bash -e <<'CHROOT'
set -euo pipefail

echo "$ARCH_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 $ARCH_HOSTNAME.localdomain $ARCH_HOSTNAME
EOF

printf 'en_US.UTF-8 UTF-8\n' > /etc/locale.gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
locale-gen
ln -sf "/usr/share/zoneinfo/$ARCH_TIMEZONE" /etc/localtime
hwclock --systohc

useradd --create-home --groups wheel,video,audio --shell /bin/bash "$ARCH_USER"
passwd --lock root
passwd --lock "$ARCH_USER"

install -d -o root -g root -m 0755 /etc/sudoers.d
printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel
visudo -cf /etc/sudoers.d/10-wheel

install -d -o root -g root -m 0755 /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $ARCH_USER --noclear %I xterm-256color
EOF

cat > "/home/$ARCH_USER/.bash_profile" <<'EOF'
if [[ "$(tty 2>/dev/null)" == /dev/tty1 ]] && command -v Hyprland >/dev/null 2>&1; then
    exec Hyprland
fi
EOF
chown "$ARCH_USER:$ARCH_USER" "/home/$ARCH_USER/.bash_profile"

printf '%s\n' "$ARCH_DOTFILES_REPO" > /etc/arch-hyprland-dotfiles-repo
printf '%s\n' "$ARCH_DOTFILES_REF" > /etc/arch-hyprland-dotfiles-ref

cat > /usr/local/bin/provision-arch-hyprland <<'PROVISION'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ -s /etc/arch-hyprland-dotfiles.commit ]]; then exit 0; fi
repo=$(</etc/arch-hyprland-dotfiles-repo)
ref=$(</etc/arch-hyprland-dotfiles-ref)
target=/home/nwassom/dotfiles
if [[ ! -d "$target/.git" ]]; then
    git clone "$repo" "$target"
fi
git -C "$target" fetch --tags --force origin
git -C "$target" checkout --detach "$ref"
cd "$target"
ANSIBLE_CONFIG="$target/OS/arch/qemu/ansible/ansible.cfg" \
    ansible-playbook -i 'arch_qemu,' OS/arch/qemu/ansible/playbook.yml \
    --extra-vars 'arch_user=nwassom ansible_connection=local'
chown -R nwassom:nwassom "$target"
git -C "$target" rev-parse HEAD > /etc/arch-hyprland-dotfiles.commit
PROVISION
chmod 0755 /usr/local/bin/provision-arch-hyprland

cat > /etc/systemd/system/arch-hyprland-provision.service <<'EOF'
[Unit]
Description=Clone dotfiles and provision Hyprland
Wants=network-online.target
After=NetworkManager.service network-online.target
Before=getty@tty1.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/provision-arch-hyprland
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable NetworkManager NetworkManager-wait-online.service arch-hyprland-provision.service getty@tty1.service
CHROOT

arch-chroot /mnt grub-install --target=i386-pc --recheck "$DISK"
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
arch-chroot /mnt mkinitcpio -P
printf 'WINQ-EMU runtime: Alpha 10 / QEMU 11.0.0\nArch snapshot: %s\n' "$ARCH_REPO_SNAPSHOT" > /mnt/etc/arch-hyprland-build

sync
umount -R /mnt
echo "Initial Arch base guest installed. Powering off for Ansible provisioning."
poweroff
