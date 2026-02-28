#!/bin/bash
set -euo pipefail

# Check if running on a Debian/Ubuntu system
if ! command -v apt &>/dev/null; then
    echo "Error: This script requires apt (Debian/Ubuntu)."
    exit 1
fi

cd ~

sudo apt update
sudo apt install -y language-pack-zh-hans language-pack-zh-hans-base avahi-daemon git vim wget curl zsh libnss-mdns mdns-scan python3 python-is-python3 fzf

sudo update-locale LANG=en_US.UTF-8

# Download antigen (zsh plugin manager)
if [ ! -f ~/antigen.zsh ]; then
    curl -L https://raw.githubusercontent.com/zsh-users/antigen/master/bin/antigen.zsh -o ~/antigen.zsh
fi

# Download .zshrc
wget https://raw.githubusercontent.com/lkytal/bash/main/.zshrc -O ~/.zshrc

# Install zoxide
if ! command -v zoxide &>/dev/null; then
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
fi

# Switch default shell to zsh
chsh "$(whoami)" -s /usr/bin/zsh
