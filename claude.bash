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

# Cache schema version. Bump on any change to bundled-flag data, sidecar
# file format, or cache layout. Bumps invalidate existing caches for the
# same CLI version.
_CLAUDE_CACHE_VERSION=1

# Bundled flags last extended through CHANGELOG version: 0.0.0
# (The skill at .claude/skills/refresh-bundled-flags/ updates this marker.)
#
# Format: scope<TAB>name<TAB>takes_arg<TAB>arg_type<TAB>description
#   scope     — "_root" or a subcommand name (mcp, plugin, agents, …)
#   name      — flag form (e.g. --foo). Short forms are separate entries.
#   takes_arg — 0 or 1
#   arg_type  — none | file | dir | choice:a,b,c | unknown
#   description — short text; no embedded tabs
_CLAUDE_EXTRA_FLAGS=()

# Split a tab-separated extra-flag record into its fields.
# Usage: _claude_parse_extra_flag_record "$record" scope name takes_arg arg_type desc
_claude_parse_extra_flag_record() {
    local record="$1"
    local -n _scope="$2" _name="$3" _takes_arg="$4" _arg_type="$5" _desc="$6"
    IFS=$'\t' read -r _scope _name _takes_arg _arg_type _desc <<< "$record"
}

_claude_version() {
    claude --version 2>/dev/null | head -1 | awk '{print $1}'
}

_claude_cache_dir() {
    local xdg_cache="${XDG_CACHE_HOME:-$HOME/.cache}"
    echo "$xdg_cache/claude-code-completion/bash/$(_claude_version)-c${_CLAUDE_CACHE_VERSION}"
}

_claude_ensure_cache() {
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    mkdir -p "$cache_dir"
}

_claude_cleanup_old_cache() {
    local xdg_cache="${XDG_CACHE_HOME:-$HOME/.cache}"
    local base_dir="$xdg_cache/claude-code-completion/bash"
    local current_key
    current_key="$(_claude_version)-c${_CLAUDE_CACHE_VERSION}"

    [[ -d "$base_dir" ]] || return 0

    local dir
    for dir in "$base_dir"/*/; do
        [[ -d "$dir" ]] || continue
        local dir_key
        dir_key="$(basename "$dir")"
        if [[ "$dir_key" != "$current_key" ]]; then
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

_claude_parse_flag_descriptions() {
    # Parse "<flag><TAB><description>" lines from help output on stdin.
    # Two whitespace gap separates the flag block (with optional <value>
    # / [value] argument placeholder) from the description. Mirrors
    # fnrhombus's PowerShell parser at claude.ps1's _ClaudeParseFlagDescriptions.
    local line short long rest desc
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+(-[a-zA-Z]),?[[:space:]]+(--[a-zA-Z][-a-zA-Z]*)(.*)$ ]]; then
            short="${BASH_REMATCH[1]}"
            long="${BASH_REMATCH[2]}"
            rest="${BASH_REMATCH[3]}"
            if [[ "$rest" =~ [[:space:]][[:space:]]+([^[:space:]].*)$ ]]; then
                desc="${BASH_REMATCH[1]}"
                printf '%s\t%s\n' "$short" "$desc"
                printf '%s\t%s\n' "$long" "$desc"
            fi
        elif [[ "$line" =~ ^[[:space:]]+(--[a-zA-Z][-a-zA-Z]*)(.*)$ ]]; then
            long="${BASH_REMATCH[1]}"
            rest="${BASH_REMATCH[2]}"
            if [[ "$rest" =~ [[:space:]][[:space:]]+([^[:space:]].*)$ ]]; then
                desc="${BASH_REMATCH[1]}"
                printf '%s\t%s\n' "$long" "$desc"
            fi
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
    echo "$help_output" | _claude_parse_flag_descriptions > "$cache_dir/_root_flag_descriptions"
    echo "$help_output" | _claude_parse_subcommands > "$cache_dir/_root_subcommands"

    # Parse each subcommand
    local subcmd
    while IFS= read -r subcmd; do
        [[ -z "$subcmd" ]] && continue
        local sub_help
        sub_help="$(claude "$subcmd" --help 2>/dev/null)" || continue
        echo "$sub_help" | _claude_parse_flags > "$cache_dir/${subcmd}_flags"
        echo "$sub_help" | _claude_parse_flags_with_args > "$cache_dir/${subcmd}_flags_with_args"
        echo "$sub_help" | _claude_parse_flag_descriptions > "$cache_dir/${subcmd}_flag_descriptions"
        echo "$sub_help" | _claude_parse_subcommands > "$cache_dir/${subcmd}_subcommands"
    done < "$cache_dir/_root_subcommands"

    # Merge bundled flags into the cache files (skip ones already present from --help).
    local rec scope name takes_arg arg_type desc flags_file
    for rec in "${_CLAUDE_EXTRA_FLAGS[@]}"; do
        [[ -z "$rec" ]] && continue
        _claude_parse_extra_flag_record "$rec" scope name takes_arg arg_type desc
        flags_file="$cache_dir/${scope}_flags"
        [[ -f "$flags_file" ]] || continue
        if grep -qFx -- "$name" "$flags_file"; then
            continue  # --help wins on overlap
        fi
        echo "$name" >> "$flags_file"
        if [[ "$takes_arg" == "1" ]]; then
            echo "$name" >> "$cache_dir/${scope}_flags_with_args"
        fi
        printf '%s\t%s\n' "$name" "$desc" >> "$cache_dir/${scope}_flag_descriptions"
        printf '%s\t%s\n' "$name" "$arg_type" >> "$cache_dir/${scope}_flag_arg_types"
    done

    # Clean up old versions
    _claude_cleanup_old_cache
}

_claude_encoded_cwd() {
    # Encode current directory the way Claude does: replace / with -
    # Use pwd -P to resolve symlinks (e.g. /home -> /usr/home on FreeBSD)
    # so the path matches what the Claude CLI stores in ~/.claude/projects.
    local cwd
    cwd="$(pwd -P)"
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
    local file="$1" line msg
    line=$(grep '"type":"user"' "$file" \
        | grep -v '<ide_' \
        | grep -v '<command-' \
        | head -1)
    [[ -z "$line" ]] && return
    # Try array form first: content:[{"type":"text","text":"..."}]
    msg=$(echo "$line" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p' | head -1)
    # Fall back to string form: content:"..."
    [[ -z "$msg" ]] && msg=$(echo "$line" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p' | head -1)
    echo "$msg"
}

_claude_session_message() {
    if command -v jq &>/dev/null; then
        _claude_session_message_jq "$1"
    else
        _claude_session_message_grep "$1"
    fi
}

_claude_format_descriptions() {
    # Format completion candidates with aligned descriptions (Cobra/kubectl pattern).
    # Takes array name containing "value\tdescription" entries.
    # When displayed, bash shows "value    # description" but only inserts the
    # common prefix of all values (i.e., the descriptions are never inserted).
    local -n arr="$1"
    local tab=$'\t'
    local longest=0

    for entry in "${arr[@]}"; do
        local val="${entry%%$tab*}"
        (( ${#val} > longest )) && longest=${#val}
    done

    COMPREPLY=()
    for entry in "${arr[@]}"; do
        local comp desc
        if [[ "$entry" == *$tab* ]]; then
            desc="${entry#*$tab}"
            comp="${entry%%$tab*}"
            local maxdesc=$(( ${COLUMNS:-80} - longest - 4 ))
            if (( maxdesc > 8 )); then
                printf -v comp "%-${longest}s" "$comp"
            fi
            if (( maxdesc > 0 )); then
                (( ${#desc} > maxdesc )) && desc="${desc:0:$((maxdesc-1))}…"
                comp+="  # $desc"
            fi
        else
            comp="$entry"
        fi
        COMPREPLY+=("$comp")
    done

    # Preserve display order on bash 4.4+
    if [[ ${BASH_VERSINFO[0]} -ge 5 || (${BASH_VERSINFO[0]} -eq 4 && ${BASH_VERSINFO[1]} -ge 4) ]]; then
        compopt -o nosort 2>/dev/null || true
    fi
}

_claude_complete_sessions() {
    local cur="$1"
    local encoded_cwd
    encoded_cwd="$(_claude_encoded_cwd)"
    local session_dir="$HOME/.claude/projects/${encoded_cwd}"

    [[ -d "$session_dir" ]] || return

    # List JSONL files sorted by modification time (newest first), limit to 10
    # Uses ls -1t for portability (GNU find -printf / head -z / cut -z are not
    # available on macOS).  Session filenames are UUIDs so globbing is safe.
    local files=()
    local _f
    while IFS= read -r _f; do
        files+=("$_f")
    done < <(ls -1t "$session_dir"/*.jsonl 2>/dev/null | head -n 10)

    local tab=$'\t'
    local candidates=()
    for file in "${files[@]}"; do
        local basename="${file##*/}"
        local session_id="${basename%.jsonl}"
        if [[ "$session_id" == "$cur"* ]]; then
            local msg
            msg="$(_claude_session_message "$file")"
            candidates+=("${session_id}${tab}${msg:-(session)}")
        fi
    done

    if (( ${#candidates[@]} == 0 )); then
        return
    elif (( ${#candidates[@]} == 1 )) || [[ ${COMP_TYPE:-9} == @(37|42) ]]; then
        # Single match or menu-complete: strip description so it inserts cleanly
        COMPREPLY=()
        local c
        for c in "${candidates[@]}"; do
            COMPREPLY+=("${c%%$tab*}")
        done
    else
        # Multiple matches: format with aligned descriptions
        _claude_format_descriptions candidates
    fi
}

# Hardcoded model IDs (update when new models are released)
_CLAUDE_KNOWN_MODELS=(
    sonnet opus haiku
    claude-sonnet-4-5-20250514
    claude-sonnet-4-6
    claude-opus-4-5-20250514
    claude-opus-4-6
    claude-opus-4-7
    claude-haiku-4-5-20251001
)

_claude_lookup_arg_type() {
    # Look up the bundled arg_type for a flag in the given scope. Returns
    # empty string if no entry. Pure bash; no external commands.
    local flag="$1" scope="$2"
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    local file="$cache_dir/${scope}_flag_arg_types"
    [[ -f "$file" ]] || return
    local f t
    while IFS=$'\t' read -r f t; do
        if [[ "$f" == "$flag" ]]; then
            echo "$t"
            return
        fi
    done < "$file"
}

_claude_complete_flag_arg() {
    # Complete arguments for flags that take values
    # $1 = flag name, $2 = current word, $3 = scope (default: _root)
    local flag="$1"
    local cur="$2"
    local scope="${3:-_root}"

    case "$flag" in
        --model)
            # Merge aliases + hardcoded + help-parsed models
            local models=("${_CLAUDE_KNOWN_MODELS[@]}")
            # Add any models from help output (look for model IDs in help text)
            local cache_dir
            cache_dir="$(_claude_cache_dir)"
            if [[ -f "$cache_dir/_root_help" ]]; then
                while IFS= read -r line; do
                    if [[ "$line" =~ claude-[a-z]+-[0-9][a-z0-9-]* ]]; then
                        models+=("${BASH_REMATCH[0]}")
                    fi
                done < "$cache_dir/_root_help"
            fi
            COMPREPLY=( $(compgen -W "${models[*]}" -- "$cur") )
            ;;
        --permission-mode)
            COMPREPLY=( $(compgen -W "acceptEdits auto bypassPermissions default dontAsk plan" -- "$cur") )
            ;;
        --output-format)
            COMPREPLY=( $(compgen -W "text json stream-json" -- "$cur") )
            ;;
        --input-format)
            COMPREPLY=( $(compgen -W "text stream-json" -- "$cur") )
            ;;
        --effort)
            COMPREPLY=( $(compgen -W "low medium high max" -- "$cur") )
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
            # Consult bundled arg_type sidecar before falling back to file completion.
            local arg_type
            arg_type="$(_claude_lookup_arg_type "$flag" "$scope")"
            case "$arg_type" in
                dir)
                    COMPREPLY=( $(compgen -d -- "$cur") )
                    ;;
                choice:*)
                    local choices="${arg_type#choice:}"
                    COMPREPLY=( $(compgen -W "${choices//,/ }" -- "$cur") )
                    ;;
                none)
                    COMPREPLY=()
                    ;;
                file|unknown|"")
                    COMPREPLY=( $(compgen -f -- "$cur") )
                    ;;
            esac
            ;;
    esac
}

_claude_mcp_server_names() {
    # Extract server names from "claude mcp list" output
    # Format: "name: url - status" — extract the first word before the colon
    claude mcp list 2>/dev/null | grep ':' | grep -v '^Checking\|^$' | sed 's/:.*//' | sed 's/^[[:space:]]*//'
}

_claude_plugin_names() {
    # Extract plugin names from "claude plugin list --json" output
    if command -v jq &>/dev/null; then
        claude plugin list --json 2>/dev/null | jq -r '.[].name' 2>/dev/null
    else
        claude plugin list --json 2>/dev/null | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//'
    fi
}

_claude_complete_subcmd_arg() {
    local subcmd="$1"
    local sub_subcmd="$2"
    local cur="$3"

    case "${subcmd}/${sub_subcmd}" in
        mcp/get|mcp/remove)
            local names
            names="$(_claude_mcp_server_names)"
            COMPREPLY=( $(compgen -W "$names" -- "$cur") )
            ;;
        plugin/disable|plugin/enable|plugin/uninstall|plugin/remove)
            local names
            names="$(_claude_plugin_names)"
            COMPREPLY=( $(compgen -W "$names" -- "$cur") )
            ;;
    esac
}

_claude_flag_candidates_with_descriptions() {
    # Build a "flag<TAB>desc" array (printed to stdout, one per line) for the
    # flags in $1 that match prefix $2. Looks up descriptions in $3.
    local flags_file="$1"
    local prefix="$2"
    local desc_file="$3"

    declare -A descs
    if [[ -f "$desc_file" ]]; then
        local f d
        while IFS=$'\t' read -r f d; do
            descs["$f"]="$d"
        done < "$desc_file"
    fi

    local flag
    while IFS= read -r flag; do
        [[ -z "$flag" ]] && continue
        [[ "$flag" == "$prefix"* ]] || continue
        if [[ -n "${descs[$flag]:-}" ]]; then
            printf '%s\t%s\n' "$flag" "${descs[$flag]}"
        else
            echo "$flag"
        fi
    done < "$flags_file"
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
        local _scope="_root"
        if [[ -n "$subcmd" ]]; then
            flags_with_args_file="$cache_dir/${subcmd}_flags_with_args"
            _scope="$subcmd"
        fi
        if [[ -f "$flags_with_args_file" ]] && grep -qx -- "$prev" "$flags_with_args_file"; then
            _claude_complete_flag_arg "$prev" "$cur" "$_scope"
            return
        fi
    fi

    if [[ -n "$subcmd" ]]; then
        # Find sub-subcommand if present
        local sub_subcmd=""
        for (( i=i+1; i < cword; i++ )); do
            if [[ "${words[i]}" != -* ]]; then
                local potential="${words[i]}"
                if [[ -f "$cache_dir/${subcmd}_subcommands" ]] && grep -qx "$potential" "$cache_dir/${subcmd}_subcommands"; then
                    sub_subcmd="$potential"
                    break
                fi
            fi
        done

        if [[ "$cur" == -* ]]; then
            if [[ -f "$cache_dir/${subcmd}_flags" ]]; then
                local candidates=()
                while IFS= read -r line; do
                    candidates+=("$line")
                done < <(_claude_flag_candidates_with_descriptions \
                    "$cache_dir/${subcmd}_flags" "$cur" \
                    "$cache_dir/${subcmd}_flag_descriptions")
                if (( ${#candidates[@]} == 1 )) || [[ ${COMP_TYPE:-9} == @(37|42) ]]; then
                    # Single match or menu-complete: strip description so insertion is clean.
                    COMPREPLY=()
                    local c
                    for c in "${candidates[@]}"; do
                        COMPREPLY+=("${c%%$'\t'*}")
                    done
                else
                    _claude_format_descriptions candidates
                fi
            fi
        elif [[ -n "$sub_subcmd" ]]; then
            # Complete positional args for sub-subcommands
            _claude_complete_subcmd_arg "$subcmd" "$sub_subcmd" "$cur"
        else
            if [[ -f "$cache_dir/${subcmd}_subcommands" ]]; then
                COMPREPLY=( $(compgen -W "$(cat "$cache_dir/${subcmd}_subcommands")" -- "$cur") )
            fi
        fi
    else
        # Top level
        if [[ "$cur" == -* ]]; then
            # Complete flags
            if [[ -f "$cache_dir/_root_flags" ]]; then
                local candidates=()
                while IFS= read -r line; do
                    candidates+=("$line")
                done < <(_claude_flag_candidates_with_descriptions \
                    "$cache_dir/_root_flags" "$cur" \
                    "$cache_dir/_root_flag_descriptions")
                if (( ${#candidates[@]} == 1 )) || [[ ${COMP_TYPE:-9} == @(37|42) ]]; then
                    # Single match or menu-complete: strip description so insertion is clean.
                    COMPREPLY=()
                    local c
                    for c in "${candidates[@]}"; do
                        COMPREPLY+=("${c%%$'\t'*}")
                    done
                else
                    _claude_format_descriptions candidates
                fi
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
