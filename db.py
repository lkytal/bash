cd ~

sudo apt update
apt install -o Dpkg::Options::="--force-confold" -y --allow-unauthenticated --ignore-missing language-pack-zh-hans language-pack-zh-hans-base avahi-daemon git vim wget curl zsh libnss-mdns mdns-scan

curl -L git.io/antigen > antigen.zsh

wget https://raw.githubusercontent.com/lkytal/bash/main/.zshrc -O .zshrc

git clone https://github.com/wting/autojump.git
cd autojump
./install.py
