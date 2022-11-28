cd ~

sudo apt update
sudo apt install language-pack-zh-hans language-pack-zh-hans-base fzf avahi-daemon git vim wget curl zsh  autojump-zsh autojump-fish libnss-mdns mdns-scan

update-locale LANG=en_US.UTF-8

chsh /usr/bin/zsh

curl -L git.io/antigen > antigen.zsh

wget https://raw.githubusercontent.com/lkytal/bash/main/.zshrc > .zshrc