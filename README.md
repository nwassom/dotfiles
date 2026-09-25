
# dotfiles



Personal development environment and machine configuration.



## Managed with



- Git / GitHub

- Dotter

- mise



## Environments



- Windows + WSL Ubuntu

- Linux

- macOS



## Configurations



- Bash

- Zsh

- Git

- Ghostty

- Zed

- OpenCode

- tmux

- Neovim

- mise

- personal scripts



## Fresh machine



```bash

git clone git@github.com:nwassom/dotfiles.git ~/dotfiles

cd ~/dotfiles

./install.sh --profile macos

```

Use `--profile linux` in the Alma or Arch VM, and `--profile wsl` under
Windows. Existing files are moved to `~/.dotfiles-backup/` before they are
replaced. The installer only links configuration; install packages separately.

See [`profiles/README.md`](profiles/README.md) for the environment matrix.

Set the machine's Git identity separately in
`~/.config/git/local`, using `git/local.example` as a template.
