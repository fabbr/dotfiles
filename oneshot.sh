#!/usr/bin/env bash
set -euo pipefail

# ================== UI ==================
GREEN="\033[1;32m"; BLUE="\033[1;34m"; YELLOW="\033[1;33m"; NC="\033[0m"
BAR="████████████████████████████████"
step(){ echo -e "${BLUE}[$1] ${BAR}${NC}\n${YELLOW}→ $2${NC}"; }
ok(){ echo -e "${GREEN}✓ $1${NC}"; }

# ================== Target user ==================
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[ -n "$TARGET_HOME" ] || exit 1
as_user(){ sudo -H -u "$TARGET_USER" bash -lc "$1"; }

backup(){ [ -f "$1" ] && cp -a "$1" "$1.bak.$(date +%Y%m%d-%H%M%S)" || true; }
append_once(){ grep -qxF "$1" "$2" 2>/dev/null || printf "\n%s\n" "$1" >> "$2"; }

# ================== Packages ==================
step "1/10" "Installing packages"
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y tmux git curl zsh zfsutils-linux fzf zoxide
elif command -v dnf >/dev/null 2>&1; then
  sudo dnf install -y tmux git curl zsh zfs || true
else
  echo "Unsupported package manager"; exit 1
fi
ok "Packages installed"

# ================== Aliases ==================
step "2/10" "Setting aliases (ll, tmux -u)"
backup "$TARGET_HOME/.bashrc"
backup "$TARGET_HOME/.zshrc"
append_once "alias ll='ls -la'" "$TARGET_HOME/.bashrc"
append_once "alias ll='ls -la'" "$TARGET_HOME/.zshrc"
append_once "alias tmux='tmux -u'" "$TARGET_HOME/.bashrc"
append_once "alias tmux='tmux -u'" "$TARGET_HOME/.zshrc"
ok "Aliases set"

# ================== TPM ==================
step "3/10" "Installing tmux plugin manager"
as_user "mkdir -p ~/.tmux/plugins && [ -d ~/.tmux/plugins/tpm ] || git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm"
ok "TPM installed"

# ================== tmux.conf ==================
step "4/10" "Configuring tmux"
backup "$TARGET_HOME/.tmux.conf"
as_user "curl -fsSL -o ~/.tmux.conf https://github.com/dispatch-yt/dot-files/raw/main/.tmux.conf"

ZSH_BIN="$(command -v zsh)"
cat >> "$TARGET_HOME/.tmux.conf" <<EOF

# --- zsh + unicode ---
set -g default-shell $ZSH_BIN
set -g default-command "$ZSH_BIN -l"
set -g default-terminal "tmux-256color"
set -as terminal-overrides ",*:Tc"
set -g update-environment "LANG LC_ALL LC_CTYPE"
EOF
ok "tmux configured"

# ================== oh-my-zsh ==================
step "5/10" "Installing oh-my-zsh + powerlevel10k"
as_user "
cd ~ &&
curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o install.sh &&
RUNZSH=no CHSH=no sh install.sh --unattended || true
"
as_user "[ -f ~/.oh-my-zsh/oh-my-zsh.sh ] || git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh"
as_user "[ -d ~/.oh-my-zsh/themes/powerlevel10k ] || git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/themes/powerlevel10k"
ok "oh-my-zsh installed"

# ================== zsh configs ==================
step "6/10" "Installing zsh configs"
backup "$TARGET_HOME/.zshrc"
backup "$TARGET_HOME/.p10k.zsh"

as_user "curl -fsSL https://gist.github.com/knutole/668dbfc9a7454f6e6bd9ba53d6bdc4dc/raw/.zshrc -o ~/.zshrc"
as_user "curl -fsSL https://github.com/fabbr/dotfiles/raw/main/.p10k.zsh -o ~/.p10k.zsh"

as_user "
sed -i '/~\\/\\.oh-my-zsh\\/oh-my-zsh\\.sh/d' ~/.zshrc
sed -i '/oh-my-zsh\\.sh/d' ~/.zshrc
printf '\nexport ZSH=\"\$HOME/.oh-my-zsh\"\n[ -f \"\$ZSH/oh-my-zsh.sh\" ] && source \"\$ZSH/oh-my-zsh.sh\"\n' >> ~/.zshrc
"

append_once "alias ll='ls -la'" "$TARGET_HOME/.zshrc"
append_once "alias tmux='tmux -u'" "$TARGET_HOME/.zshrc"
ok "zsh config installed"

# ================== zsh plugins ==================
step "7/10" "Installing zsh plugins"
as_user "
mkdir -p ~/.oh-my-zsh/custom/plugins &&
[ -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ] || git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting &&
[ -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ] || git clone https://github.com/zsh-users/zsh-autosuggestions.git ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
"
ok "Plugins installed"

# ================== tmux plugins ==================
step "8/10" "Installing tmux plugins"
as_user "
tmux start-server || true
tmux new-session -d -s __tpm_install 2>/dev/null || true
~/.tmux/plugins/tpm/bin/install_plugins >/dev/null 2>&1 || true
tmux kill-session -t __tpm_install 2>/dev/null || true
"
ok "tmux plugins installed"

# ================== default shell ==================
step "9/10" "Setting default shell to zsh"
sudo usermod --shell "$ZSH_BIN" "$TARGET_USER" || true
ok "Default shell set"

# ================== launch zsh ==================
step "10/10" "Launching zsh"
ok "Bootstrap complete"
zsh
