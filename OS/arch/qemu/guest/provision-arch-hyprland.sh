#!/usr/bin/env bash
set -Eeuo pipefail

modprobe qemu_fw_cfg 2>/dev/null || true
refresh=/sys/firmware/qemu_fw_cfg/by_name/provision-refresh/raw
commit_file=/etc/arch-hyprland-dotfiles.commit
if [[ -s "$commit_file" && ! -r "$refresh" ]]; then exit 0; fi

repo=$(</etc/arch-hyprland-dotfiles-repo)
user=$(</etc/arch-hyprland-user)
ref_file=/sys/firmware/qemu_fw_cfg/by_name/qemu-dotfiles-ref/raw
scale_file=/sys/firmware/qemu_fw_cfg/by_name/qemu-hyprland-scale/raw
ref=$(if [[ -r "$ref_file" ]]; then cat "$ref_file"; else cat /etc/arch-hyprland-dotfiles-ref; fi)
scale=$(if [[ -r "$scale_file" ]]; then cat "$scale_file"; else cat /etc/arch-hyprland-scale; fi)
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
