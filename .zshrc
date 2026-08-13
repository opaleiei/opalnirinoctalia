autoload -Uz compinit && compinit
source /usr/share/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh

#source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
fpath+=(/usr/share/zsh/site-functions)

bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

eval "$(starship init zsh)"
eval "$(zoxide init zsh)"
eval "$(atuin init zsh)"
eval "$(deja init zsh)"
source /usr/share/zsh/plugins/zsh-autopair/autopair.zsh
autopair-init
alias ls='eza --icons --group-directories-first'
alias ll='eza -l --icons --group-directories-first'
alias la='eza -la --icons --group-directories-first'
alias tree='eza --tree --icons'
alias cat='bat'
alias cd='z'
# dimmer/brighter suggestion color
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#5f5f5f'


# also suggest from completions, not just history
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
# verbose completions with descriptions
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*:messages' format '%F{purple}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}-- no matches --%f'

# group results by type (commands, files, options, etc.)
zstyle ':completion:*' group-name ''

# case-insensitive + partial matching
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# colorize file listings in completion using LS_COLORS
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# fzf-tab preview pane for directories
zstyle ':fzf-tab:complete:*:*' fzf-preview 'ls --color $realpath 2>/dev/null'
[[ -o interactive ]] && fastfetch
