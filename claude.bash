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
    echo "$help_output" > "$cache_dir/_root_help"
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

_claude_encoded_cwd() {
    # Encode current directory the way Claude does: replace / with -
    local cwd="${PWD}"
    echo "${cwd//\//-}"
}

_claude_session_message_jq() {
    # Extract first real user message using jq
    local file="$1"
    jq -r '
        select(.type == "user")
        | .message.content
        | if type == "array" then
            .[] | select(.type == "text") | .text
          elif type == "string" then .
          else empty
          end
    ' "$file" 2>/dev/null | grep -v '<ide_\|<command-' | head -1
}

_claude_session_message_grep() {
    # Extract first real user message using grep/sed fallback
    local file="$1"
    grep '"type":"user"' "$file" \
        | grep -v '<ide_' \
        | grep -v '<command-' \
        | head -1 \
        | sed -n 's/.*"text":"\([^"]*\)".*/\1/p' \
        | head -1
}

_claude_session_message() {
    if command -v jq &>/dev/null; then
        _claude_session_message_jq "$1"
    else
        _claude_session_message_grep "$1"
    fi
}

_claude_complete_sessions() {
    local cur="$1"
    local encoded_cwd
    encoded_cwd="$(_claude_encoded_cwd)"
    local session_dir="$HOME/.claude/projects/${encoded_cwd}"

    [[ -d "$session_dir" ]] || return

    # List JSONL files sorted by modification time (newest first), limit to 10
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$session_dir" -maxdepth 1 -name '*.jsonl' -printf '%T@\t%p\0' \
        | sort -z -t$'\t' -k1 -rn \
        | head -z -n 10 \
        | cut -z -f2-)

    local session_ids=()
    for file in "${files[@]}"; do
        local basename="${file##*/}"
        local session_id="${basename%.jsonl}"
        # Filter by current word
        if [[ "$session_id" == "$cur"* ]]; then
            session_ids+=("$session_id")
        fi
    done

    COMPREPLY=("${session_ids[@]}")
}

# Hardcoded model IDs (update when new models are released)
_CLAUDE_KNOWN_MODELS=(
    sonnet opus haiku
    claude-sonnet-4-5-20250514
    claude-sonnet-4-6
    claude-opus-4-5-20250514
    claude-opus-4-6
    claude-haiku-4-5-20251001
)

_claude_complete_flag_arg() {
    # Complete arguments for flags that take values
    # $1 = flag name, $2 = current word
    local flag="$1"
    local cur="$2"

    case "$flag" in
        --model)
            # Merge aliases + hardcoded + help-parsed models
            local models=("${_CLAUDE_KNOWN_MODELS[@]}")
            # Add any models from help output (look for model IDs in help text)
            local cache_dir
            cache_dir="$(_claude_cache_dir)"
            if [[ -f "$cache_dir/_root_help" ]]; then
                while IFS= read -r line; do
                    if [[ "$line" =~ claude-[a-z]+-[0-9] ]]; then
                        models+=("${BASH_REMATCH[0]}")
                    fi
                done < "$cache_dir/_root_help"
            fi
            COMPREPLY=( $(compgen -W "${models[*]}" -- "$cur") )
            ;;
        --permission-mode)
            COMPREPLY=( $(compgen -W "acceptEdits bypassPermissions default dontAsk plan" -- "$cur") )
            ;;
        --output-format)
            COMPREPLY=( $(compgen -W "text json stream-json" -- "$cur") )
            ;;
        --input-format)
            COMPREPLY=( $(compgen -W "text stream-json" -- "$cur") )
            ;;
        --effort)
            COMPREPLY=( $(compgen -W "low medium high" -- "$cur") )
            ;;
        --resume|-r)
            _claude_complete_sessions "$cur"
            ;;
        --add-dir)
            # Directory completion only
            COMPREPLY=( $(compgen -d -- "$cur") )
            ;;
        --debug-file|--mcp-config|--settings)
            # File completion
            COMPREPLY=( $(compgen -f -- "$cur") )
            ;;
        --plugin-dir)
            # Directory completion
            COMPREPLY=( $(compgen -d -- "$cur") )
            ;;
        *)
            # Unknown flag arg — default to file completion
            COMPREPLY=( $(compgen -f -- "$cur") )
            ;;
    esac
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

    # Check if previous word is a flag that takes an argument
    if [[ "$prev" == -* ]]; then
        local flags_with_args_file="$cache_dir/_root_flags_with_args"
        if [[ -n "$subcmd" ]]; then
            flags_with_args_file="$cache_dir/${subcmd}_flags_with_args"
        fi
        if [[ -f "$flags_with_args_file" ]] && grep -qx -- "$prev" "$flags_with_args_file"; then
            _claude_complete_flag_arg "$prev" "$cur"
            return
        fi
    fi

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
