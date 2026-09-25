# ============================================================
# ZSH
# ============================================================

# Homebrew
if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# Shared config
DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/dotfiles}"
source "$DOTFILES_ROOT/shell/common.sh"

# History
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000

setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY
setopt AUTO_CD

# Completion
autoload -Uz compinit
compinit

# Better directory navigation
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi

# Standard prompt
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi
