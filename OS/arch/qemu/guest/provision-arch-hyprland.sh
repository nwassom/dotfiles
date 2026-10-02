#!/usr/bin/env bash
set -Eeuo pipefail

commit_file=/etc/arch-hyprland-dotfiles.commit
[[ -s "$commit_file" ]] && exit 0

modprobe qemu_fw_cfg 2>/dev/null || true
token=/sys/firmware/qemu_fw_cfg/by_name/github-token/raw
askpass=
if [[ -r "$token" ]]; then
    askpass=$(mktemp)
    cat > "$askpass" <<'ASKPASS'
#!/bin/sh
case "$1" in
    *Username*) printf '%s\n' nwassom ;;
    *) cat /sys/firmware/qemu_fw_cfg/by_name/github-token/raw ;;
esac
ASKPASS
    chmod 0700 "$askpass"
    export GIT_ASKPASS="$askpass"
fi
export GIT_TERMINAL_PROMPT=0
trap '[[ -z "$askpass" ]] || rm -f "$askpass"' EXIT

repo=$(</etc/arch-hyprland-dotfiles-repo)
ref=$(</etc/arch-hyprland-dotfiles-ref)
user=nwassom
[[ ! -r /etc/arch-hyprland-user ]] || user=$(</etc/arch-hyprland-user)
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
    ansible-playbook -i 'arch_qemu,' OS/arch/qemu/ansible/playbook.yml \
    --extra-vars "arch_user=$user ansible_connection=local"

chown -R "$user:$user" "$target"
git -C "$target" rev-parse HEAD > "$commit_file.tmp"
mv "$commit_file.tmp" "$commit_file"
