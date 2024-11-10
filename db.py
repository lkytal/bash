cd ~

sudo apt update
apt install -o Dpkg::Options::="--force-confold" -y --allow-unauthenticated --ignore-missing language-pack-zh-hans language-pack-zh-hans-base avahi-daemon git vim wget nvtop curl zsh libnss-mdns mdns-scan

curl -L git.io/antigen > antigen.zsh

wget https://raw.githubusercontent.com/lkytal/bash/main/.zshrc -O .zshrc

git clone https://github.com/wting/autojump.git
cd autojump
./install.py

wget "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
bash Miniforge3-$(uname)-$(uname -m).sh -b

./miniforge3/bin/conda init zsh

conda create -n ue python=3.10 -y
conda activate ue

pip install tensorflow==2.14.1
pip install tensorflow_io
pip install boto3
pip install -U jupyterlab
pip install numba pandas matplotlib tqdm nbdime seaborn scikit-learn jupyter_contrib_nbextensions
                  
cat 'jupyter lab --ip 0.0.0.0 --port 8888 --no-browser --ContentsManager.allow_hidden=True --allow-root=True' > lab.py
