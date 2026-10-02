# Personal terminal rice (separate from the dots' config.fish so dots updates don't touch it)
status is-interactive; or return

# Smarter cd: `z foo` jumps to the most frecent dir matching foo, `zi` picks with fzf
command -q zoxide; and zoxide init fish | source

# Ctrl+T files, Ctrl+R history, Alt+C dirs (Ubuntu ships the fish bindings under doc/)
set -l fzf_keys /usr/share/doc/fzf/examples/key-bindings.fish
if command -q fzf; and test -f $fzf_keys
    source $fzf_keys
    fzf_key_bindings
    set -gx FZF_DEFAULT_OPTS "--height 40% --layout=reverse --border rounded --info=inline --color=bg+:#363a4f,bg:-1,spinner:#f4dbd6,hl:#ed8796,fg:#cad3f5,header:#ed8796,info:#c6a0f6,pointer:#f4dbd6,marker:#b7bdf8,fg+:#cad3f5,prompt:#c6a0f6,hl+:#ed8796"
end

# bat is installed as `batcat` on Ubuntu
if command -q batcat
    alias cat 'batcat --paging=never --style=plain'
    set -gx BAT_THEME "Catppuccin Macchiato"
    set -gx MANPAGER "sh -c 'col -bx | batcat -l man -p'"
end

# eza (the dots alias `ls` already)
if command -q eza
    alias ll 'eza --icons=auto -l --git --group-directories-first'
    alias la 'eza --icons=auto -la --git --group-directories-first'
    alias lt 'eza --icons=auto --tree --level=2'
end

# One compact fastfetch per new terminal window (delete this block for a silent start)
function fish_greeting
    command -q fastfetch; and fastfetch --logo small --structure Title:OS:Kernel:Shell:CPU:GPU:Memory
end
