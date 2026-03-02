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

_claude_parse_flags() {
    # Parse flags from help output on stdin
    # Outputs all flag forms (short and long), one per line
    local line
    while IFS= read -r line; do
        # Match lines starting with optional spaces then a dash
        if [[ "$line" =~ ^[[:space:]]+(-[a-zA-Z]),?[[:space:]]+(--[a-zA-Z][-a-zA-Z]*) ]]; then
            echo "${BASH_REMATCH[1]}"
            echo "${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]+(--[a-zA-Z][-a-zA-Z]*) ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done
}

_claude_parse_flags_with_args() {
    # Parse flags that take arguments (have <value> or [value] after them)
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+(-[a-zA-Z]),?[[:space:]]+(--[a-zA-Z][-a-zA-Z]*)[[:space:]]+[\<\[] ]]; then
            echo "${BASH_REMATCH[1]}"
            echo "${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]+(--[a-zA-Z][-a-zA-Z]*)[[:space:]]+[\<\[] ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done
}

_claude_parse_subcommands() {
    # Parse subcommand names from help output on stdin
    # Looks for lines in the "Commands:" section
    local in_commands=0
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^Commands: ]]; then
            in_commands=1
            continue
        fi
        if [[ $in_commands -eq 1 ]]; then
            # Empty line or non-indented line ends commands section
            [[ -z "$line" ]] && continue
            [[ ! "$line" =~ ^[[:space:]] ]] && break
            # Extract command name (first word, handle "update|upgrade" aliases)
            if [[ "$line" =~ ^[[:space:]]+([a-zA-Z][-a-zA-Z]*) ]]; then
                echo "${BASH_REMATCH[1]}"
            fi
        fi
    done
}

_claude_build_cache() {
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    mkdir -p "$cache_dir"

    # Parse root level
    local help_output
    help_output="$(claude --help 2>/dev/null)"
    echo "$help_output" | _claude_parse_flags > "$cache_dir/_root_flags"
    echo "$help_output" | _claude_parse_flags_with_args > "$cache_dir/_root_flags_with_args"
    echo "$help_output" | _claude_parse_subcommands > "$cache_dir/_root_subcommands"

    # Parse each subcommand
    local subcmd
    while IFS= read -r subcmd; do
        [[ -z "$subcmd" ]] && continue
        local sub_help
        sub_help="$(claude "$subcmd" --help 2>/dev/null)" || continue
        echo "$sub_help" | _claude_parse_flags > "$cache_dir/${subcmd}_flags"
        echo "$sub_help" | _claude_parse_flags_with_args > "$cache_dir/${subcmd}_flags_with_args"
        echo "$sub_help" | _claude_parse_subcommands > "$cache_dir/${subcmd}_subcommands"
    done < "$cache_dir/_root_subcommands"

    # Clean up old versions
    _claude_cleanup_old_cache
}

_claude() {
    local cur prev words cword
    _init_completion || return

    local cache_dir
    cache_dir="$(_claude_cache_dir)"

    # Build cache if needed
    if [[ ! -d "$cache_dir" ]]; then
        _claude_build_cache
    fi

    # Determine which subcommand we're in (if any)
    local subcmd=""
    local i
    for (( i=1; i < cword; i++ )); do
        if [[ "${words[i]}" != -* ]]; then
            local potential="${words[i]}"
            if [[ -f "$cache_dir/_root_subcommands" ]] && grep -qx "$potential" "$cache_dir/_root_subcommands"; then
                subcmd="$potential"
                break
            fi
        fi
    done

    if [[ -n "$subcmd" ]]; then
        # Inside a subcommand
        if [[ "$cur" == -* ]]; then
            # Complete subcommand flags
            if [[ -f "$cache_dir/${subcmd}_flags" ]]; then
                COMPREPLY=( $(compgen -W "$(cat "$cache_dir/${subcmd}_flags")" -- "$cur") )
            fi
        else
            # Complete sub-subcommands
            if [[ -f "$cache_dir/${subcmd}_subcommands" ]]; then
                COMPREPLY=( $(compgen -W "$(cat "$cache_dir/${subcmd}_subcommands")" -- "$cur") )
            fi
        fi
    else
        # Top level
        if [[ "$cur" == -* ]]; then
            # Complete flags
            if [[ -f "$cache_dir/_root_flags" ]]; then
                COMPREPLY=( $(compgen -W "$(cat "$cache_dir/_root_flags")" -- "$cur") )
            fi
        else
            # Complete subcommands
            if [[ -f "$cache_dir/_root_subcommands" ]]; then
                COMPREPLY=( $(compgen -W "$(cat "$cache_dir/_root_subcommands")" -- "$cur") )
            fi
        fi
    fi
}

complete -F _claude claude
