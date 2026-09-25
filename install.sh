#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROFILE=""

usage() {
    printf '%s\n' "Usage: ./install.sh [--profile macos|linux|wsl]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            PROFILE=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$PROFILE" ]; then
    case "$(uname -s)" in
        Darwin) PROFILE=macos ;;
        Linux)
            case "$(uname -r)" in
                *microsoft*|*Microsoft*|*WSL*) PROFILE=wsl ;;
                *) PROFILE=linux ;;
            esac
            ;;
        *)
            printf '%s\n' "Unsupported OS; pass --profile explicitly." >&2
            exit 1
            ;;
    esac
fi

case "$PROFILE" in
    macos|linux|wsl) ;;
    *)
        printf '%s\n' "Unknown profile: $PROFILE" >&2
        exit 2
        ;;
esac

CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

link() {
    source=$1
    target=$2

    mkdir -p "$(dirname -- "$target")"
    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ "$(readlink "$target" 2>/dev/null || true)" = "$source" ]; then
            return
        fi
        mkdir -p "$BACKUP_DIR"
        mv "$target" "$BACKUP_DIR/$(basename -- "$target")"
    fi
    ln -s "$source" "$target"
    printf 'linked %-30s -> %s\n' "$target" "$source"
}

link "$ROOT/shell/.zshrc" "$HOME/.zshrc"
link "$ROOT/shell/.bashrc" "$HOME/.bashrc"
link "$ROOT/git/.gitconfig" "$HOME/.gitconfig"
link "$ROOT/tmux/tmux.conf" "$HOME/.tmux.conf"
link "$ROOT/starship/starship.toml" "$CONFIG_HOME/starship.toml"
link "$ROOT/nvim" "$CONFIG_HOME/nvim"

case "$PROFILE" in
    macos)
        link "$ROOT/ghostty/common.ghostty" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
        ;;
    linux)
        link "$ROOT/ghostty/common.ghostty" "$CONFIG_HOME/ghostty/config"
        ;;
    wsl)
        printf '%s\n' "Skipping Ghostty: configure the Windows host profile separately."
        ;;
esac

mkdir -p "$CONFIG_HOME/dotfiles"
printf '%s\n' "$PROFILE" > "$CONFIG_HOME/dotfiles/profile"

printf '\n%s\n' "Installed common profile: $PROFILE"
printf '%s\n' "Backups (if any): $BACKUP_DIR"
printf '%s\n' "Package installation and Ghostty/KDE profiles are intentionally separate." 
