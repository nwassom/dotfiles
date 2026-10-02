#!/usr/bin/env bash
set -Eeuo pipefail

modprobe qemu_fw_cfg 2>/dev/null || true
settings=/sys/firmware/qemu_fw_cfg/by_name/guest-settings/raw
refresh=/sys/firmware/qemu_fw_cfg/by_name/provision-refresh/raw
commit_file=/etc/arch-hyprland-dotfiles.commit
if [[ -s "$commit_file" && ! -r "$refresh" ]]; then exit 0; fi
[[ -r "$settings" ]] || { echo "QEMU did not provide guest settings." >&2; exit 1; }
source "$settings"

repo=$(</etc/arch-hyprland-dotfiles-repo)
ref=${ARCH_QEMU_DOTFILES_REF:?Missing ARCH_QEMU_DOTFILES_REF}
user=${ARCH_QEMU_GUEST_USER:?Missing ARCH_QEMU_GUEST_USER}
scale=${ARCH_HYPRLAND_SCALE:?Missing ARCH_HYPRLAND_SCALE}
target="/home/$user/dotfiles"

for _ in {1..60}; do
    getent hosts github.com >/dev/null && break
    sleep 2
done
getent hosts github.com >/dev/null || { echo "GitHub DNS is not available; check NetworkManager." >&2; exit 1; }

if [[ ! -d "$target/.git" ]]; then
    git clone "$repo" "$target"
fi
git -C "$target" fetch --tags --force origin
git -C "$target" checkout --detach "$ref"
cd "$target"
ANSIBLE_CONFIG="$target/OS/arch/qemu/ansible/ansible.cfg" \
    ansible-playbook -i 'arch_qemu,' -c local OS/arch/qemu/ansible/playbook.yml \
    --extra-vars "arch_user=$user hyprland_scale=$scale"

chown -R "$user:$user" "$target"
printf '%s\n' "$(git -C "$target" rev-parse HEAD) $ref $scale" > "$commit_file.tmp"
mv "$commit_file.tmp" "$commit_file"
