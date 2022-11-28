bindkey '\e[1~' beginning-of-line
bindkey '\e[4~' end-of-line
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line

[[ -s ~/.autojump/etc/profile.d/autojump.sh ]] && source ~/.autojump/etc/profile.d/autojump.sh
#. /usr/share/autojump/autojump.sh

autoload -U compinit && compinit -u

source ~/antigen.zsh

# Load the oh-my-zsh's library.
antigen use oh-my-zsh

# Bundles from the default repo (robbyrussell's oh-my-zsh).
antigen bundle greymd/docker-zsh-completion
antigen bundle git
antigen bundle pip
antigen bundle docker
antigen bundle command-not-found
antigen bundle unixorn/autoupdate-antigen.zshplugin
antigen bundle webyneter/docker-aliases.git
antigen bundle Aloxaf/fzf-tab

antigen bundle chrissicool/zsh-256color

# Syntax highlighting bundle.
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle zsh-users/zsh-autosuggestions

bindkey '^ ' autosuggest-accept

export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=242"

# Load the theme.
antigen theme ys

# Tell Antigen that you're done.
antigen apply

eval "$(zoxide init zsh)"

alias dstop='docker stop'
alias drs='docker restart'

alias s='screen'
alias sl='screen -ls'
alias sr='screen -r'

alias top='LANG=en_US.utf8 TERM=xterm-256color gtop'

export PATH="$HOME/.local/bin:$PATH"
