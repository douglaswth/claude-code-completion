#!/usr/bin/env bash
# Bash completion for the claude CLI (Claude Code)
# https://github.com/anthropics/claude-code

# Fallback if bash-completion's _init_completion is not available
if ! declare -F _init_completion &>/dev/null; then
    _init_completion() {
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    }
fi

_claude_version() {
    claude --version 2>/dev/null | head -1 | awk '{print $1}'
}

_claude_cache_dir() {
    local xdg_cache="${XDG_CACHE_HOME:-$HOME/.cache}"
    echo "$xdg_cache/claude-code-completion/bash/$(_claude_version)"
}

_claude_ensure_cache() {
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    mkdir -p "$cache_dir"
}

_claude_cleanup_old_cache() {
    local xdg_cache="${XDG_CACHE_HOME:-$HOME/.cache}"
    local base_dir="$xdg_cache/claude-code-completion/bash"
    local current_version
    current_version="$(_claude_version)"

    [[ -d "$base_dir" ]] || return 0

    local dir
    for dir in "$base_dir"/*/; do
        [[ -d "$dir" ]] || continue
        local dir_version
        dir_version="$(basename "$dir")"
        if [[ "$dir_version" != "$current_version" ]]; then
            rm -rf "$dir"
        fi
    done
}

_claude() {
    local cur prev words cword
    _init_completion || return
}

complete -F _claude claude
