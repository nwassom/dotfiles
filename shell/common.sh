# ============================================================
# SHARED SHELL CONFIG
# Bash + Zsh
# ============================================================

export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"

export PATH="$HOME/.local/bin:$PATH"

# ------------------------------------------------------------
# Navigation
# ------------------------------------------------------------

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# ------------------------------------------------------------
# Files
# ------------------------------------------------------------

if command -v eza >/dev/null 2>&1; then
    alias ls='eza --group-directories-first'
    alias ll='eza -lah --group-directories-first --git'
    alias la='eza -a --group-directories-first'
    alias lt='eza --tree --level=2 --group-directories-first'
else
    alias ll='ls -lah'
    alias la='ls -A'
fi

# ------------------------------------------------------------
# Neovim
# ------------------------------------------------------------

alias v='nvim'
alias vim='nvim'
alias vi='nvim'

# ------------------------------------------------------------
# Git
# ------------------------------------------------------------

alias gs='git status -sb'
alias ga='git add'
alias gaa='git add -A'
alias gd='git diff'
alias gds='git diff --staged'
alias gc='git commit'
alias gp='git pull --rebase'
alias gps='git push'
alias gl='git log --oneline --graph --decorate -15'
alias gco='git checkout'
alias gb='git branch'

# ------------------------------------------------------------
# Utilities
# ------------------------------------------------------------

alias c='clear'

if command -v bat >/dev/null 2>&1; then
    alias b='bat'
fi
