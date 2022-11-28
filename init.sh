cd ~

sudo apt update
sudo apt install language-pack-zh-hans language-pack-zh-hans-base avahi-daemon git vim wget curl zsh libnss-mdns mdns-scan python3 python-is-python3

sudo update-locale LANG=en_US.UTF-8

curl -L git.io/antigen > antigen.zsh

wget https://raw.githubusercontent.com/lkytal/bash/main/.zshrc -O .zshrc

git clone https://github.com/wting/autojump.git
cd autojump
./install.py

sudo apt install fzf

chsh `whoami` -s /usr/bin/zsh