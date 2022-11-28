cd ~

sudo apt update
sudo apt install language-pack-zh-hans language-pack-zh-hans-base fzf avahi-daemon git vim wget curl zsh libnss-mdns mdns-scan python3 python-is-python3

update-locale LANG=en_US.UTF-8

chsh /usr/bin/zsh

curl -L git.io/antigen > antigen.zsh

wget https://raw.githubusercontent.com/lkytal/bash/main/.zshrc -O .zshrc

git clone git://github.com/wting/autojump.git
cd autojump
./install.py or ./uninstall.py