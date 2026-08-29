# ==============================================================================
# 1. COMPLETIONS & ENVIRONMENT
# ==============================================================================
# Add completion directories to fpath before compinit
fpath=(
  /usr/share/zsh/site-functions
  /usr/share/zsh/plugins/zsh-completions/src
  $fpath
)

# Speed up compinit by caching dump and regenerating only once every 24 hours
autoload -Uz compinit
for dump in ~/.zcompdump(N.mh+24); do
  compinit
done
compinit -C

# Case-insensitive + partial fuzzy tab completion matching
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*:messages' format '%F{purple}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}-- no matches --%f'
zstyle ':completion:*' group-name ''

# ==============================================================================
# 2. SHELL HISTORY & NAVIGATION OPTIONS
# ==============================================================================
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000

setopt EXTENDED_HISTORY          # Record timestamp and duration
setopt HIST_EXPIRE_DUPS_FIRST    # Expire duplicate entries first
setopt HIST_IGNORE_DUPS          # Don't record duplicate entry
setopt HIST_IGNORE_ALL_DUPS      # Delete old duplicate entry when new one is added
setopt HIST_FIND_NO_DUPS         # Do not display duplicates when searching
setopt HIST_IGNORE_SPACE         # Do not record command if line starts with a space
setopt HIST_SAVE_NO_DUPS         # Do not write duplicate entries in history file
setopt HIST_REDUCE_BLANKS        # Remove superfluous blanks from each command line
setopt HIST_VERIFY               # Don't execute immediately upon history expansion
setopt SHARE_HISTORY             # Share history across all active terminal sessions
setopt AUTO_CD                   # Typing a directory name automatically cd's into it
setopt INTERACTIVE_COMMENTS      # Allow comments starting with # in interactive shell

# ==============================================================================
# 3. PLUGINS (Arch Linux / AUR System Packages)
# ==============================================================================

# fzf-tab: interactive fuzzy completion menu (must load after compinit, before highlighting)
if [[ -f /usr/share/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh ]]; then
  source /usr/share/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh
  # Interactive previews: eza for directories, bat for files
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath 2>/dev/null'
  zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza -1 --color=always $realpath 2>/dev/null'
  zstyle ':fzf-tab:complete:*:*' fzf-preview 'if [[ -d $realpath ]]; then eza -1 --color=always $realpath; elif [[ -f $realpath ]]; then bat --style=numbers --color=always --line-range :50 $realpath 2>/dev/null || cat $realpath; fi'
  zstyle ':fzf-tab:*' switch-group '<' '>'
fi

# zsh-autopair: automatically closes paired quotes and brackets
if [[ -f /usr/share/zsh/plugins/zsh-autopair/autopair.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-autopair/autopair.zsh
  autopair-init
fi

# Autosuggestions: Prioritize 'deja' (intelligent predictive daemon)
# If deja is NOT installed, fallback to classic zsh-autosuggestions to prevent widget conflicts
if ! command -v deja &>/dev/null; then
  if [[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#5f5f5f'
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
  fi
fi

# zsh-history-substring-search: search matching history with Up/Down arrows
if [[ -f /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey -M vicmd 'k' history-substring-search-up
  bindkey -M vicmd 'j' history-substring-search-down
fi

# Syntax Highlighting: real-time color syntax (MUST BE LOADED LAST AMONG PLUGINS)
if [[ -f /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh ]]; then
  source /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh
elif [[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# ==============================================================================
# 4. MODERN CLI TOOL INTEGRATIONS
# ==============================================================================

# Starship Prompt
if command -v starship &>/dev/null; then
  eval "$(starship init zsh)"
fi

# Zoxide (Smarter cd)
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
fi

# FZF keybindings & fuzzy completion (Ctrl+T, Ctrl+R, Alt+C)
if command -v fzf &>/dev/null; then
  source <(fzf --zsh)
fi

# Atuin (Enhanced SQLite history) - disabling up-arrow preserves history-substring-search
if command -v atuin &>/dev/null; then
  eval "$(atuin init zsh --disable-up-arrow)"
fi

# Deja (Predictive inline shell autosuggestions - loaded after syntax highlighting)
if command -v deja &>/dev/null; then
  if [[ -r "$HOME/.local/share/deja/init.zsh" ]]; then
    source "$HOME/.local/share/deja/init.zsh"
  else
    eval "$(deja init zsh)"
  fi
fi

# ==============================================================================
# 5. MODERN ALIASES
# ==============================================================================
if command -v eza &>/dev/null; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -lh --icons --group-directories-first --git'
  alias la='eza -lha --icons --group-directories-first --git'
  alias tree='eza --tree --icons'
fi

if command -v bat &>/dev/null; then
  alias cat='bat --paging=never'
  alias bcat='bat'
fi

if command -v rg &>/dev/null; then
  alias grep='rg'
fi

if command -v fd &>/dev/null; then
  alias find='fd'
fi

if command -v lazygit &>/dev/null; then
  alias lg='lazygit'
fi

if command -v yazi &>/dev/null; then
  alias yz='yazi'
fi

alias g='git'
alias cd='z'

# ==============================================================================
# 6. BANNER
# ==============================================================================
[[ -o interactive ]] && command -v fastfetch &>/dev/null && fastfetch
