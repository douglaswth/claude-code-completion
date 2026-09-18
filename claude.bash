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
_CLAUDE_CACHE_VERSION=10

# Maximum concurrent `claude ... --help` probes during a cache build. Each is
# a Node cold start, so the per-level fan-out is batched rather than unbounded.
# Left unset so it is derived from the core count per build by
# _claude_probe_concurrency; set it to pin a value (the test suite does).
_CLAUDE_PROBE_CONCURRENCY="${_CLAUDE_PROBE_CONCURRENCY:-}"

# Safety valve on the command-tree walk. Nothing in the CLI approaches this;
# it exists so a pathological help output can never spin the build forever.
_CLAUDE_MAX_DEPTH=6

# Bundled flags last extended through CHANGELOG version: 2.1.276
# (The skill at .claude/skills/refresh-bundled-flags/ updates this marker.)
#
# Format: scope<TAB>name<TAB>takes_arg<TAB>arg_type<TAB>description
#   scope     — "_root" or a subcommand name (mcp, plugin, agents, …)
#   name      — flag form (e.g. --foo). Short forms are separate entries.
#   takes_arg — none | required | optional
#               (required = <value>; optional = [value], may be omitted)
#   arg_type  — none | file | dir | choice:a,b,c | unknown
#   description — short text; no embedded tabs
_CLAUDE_EXTRA_FLAGS=(
    $'_root\t--append-subagent-system-prompt\trequired\tunknown\tText appended to the subagent system prompt'
    $'_root\t--append-subagent-system-prompt-file\trequired\tfile\tRead the subagent system prompt from a file'
    $'_root\t--append-system-prompt-file\trequired\tfile\tRead text appended to the system prompt from a file'
    $'_root\t--background\tnone\tnone\tRun the session in the background'
    $'_root\t--bg\tnone\tnone\tRun the session in the background'
    $'_root\t--capacity\trequired\tunknown\tMax concurrent sessions for --remote-control'
    $'_root\t--channels\trequired\tunknown\tApproved channel servers for this session'
    $'_root\t--cowork\tnone\tnone\tEnable co-worker mode (user-scope only)'
    $'_root\t--create-session-in-dir\tnone\tnone\tPre-create a session in the current directory (--remote-control)'
    $'_root\t--dangerously-load-development-channels\tnone\tnone\tAllow loading MCP channel servers not on the approved allowlist'
    $'_root\t--dump-environment-variables\tnone\tnone\tDump env vars as JSON and quit (debugging)'
    $'_root\t--exec\trequired\tunknown\tCommand to execute in a background session (with --bg)'
    $'_root\t--handle-uri\trequired\tunknown\tHandle a URI (used by OS protocol handler registration)'
    $'_root\t--max-thinking-tokens\trequired\tunknown\tMaximum thinking tokens budget'
    $'_root\t--multi-turn\tnone\tnone\tEnable multi-turn conversation mode'
    $'_root\t--multi-turn-context\trequired\tunknown\tContext for multi-turn mode'
    $'_root\t--multi-turn-model\trequired\tunknown\tModel override for multi-turn mode'
    $'_root\t--no-create-session-in-dir\tnone\tnone\tDo not pre-create a session in the current directory (--remote-control)'
    $'_root\t--plan-mode-instructions\trequired\tunknown\tCustom instructions for plan mode (only with --print)'
    $'_root\t--plan-mode-required\tnone\tnone\tRequire plan mode for the session'
    $'_root\t--remote-control\toptional\tunknown\tConnect local environment to claude.ai/code for remote sessions'
    $'_root\t--resume-session-at\trequired\tunknown\tResume a session from a specific message ID (requires --resume)'
    $'_root\t--rewind-files\trequired\tunknown\tRewind files to a given message ID (requires --resume)'
    $'_root\t--session-mirror\tnone\tnone\tMirror local sessions to claude.ai as view-only'
    $'_root\t--spawn\trequired\tchoice:same-dir,worktree,session\tSpawn mode for --remote-control sessions'
    $'_root\t--system-prompt-file\trequired\tfile\tRead the system prompt from a file'
    $'_root\t--teleport\toptional\tunknown\tResume a teleport session, optionally specify session ID'
    $'_root\t--thinking\trequired\tchoice:enabled,adaptive,disabled\tThinking mode: enabled (adaptive) or disabled'
    $'_root\t--thinking-display\trequired\tunknown\tControl how thinking content is displayed'
)

# Subcommands the CLI implements but omits from the "Commands:" section of
# `claude --help`. The walk can only learn command names from that section, so
# without this the node is never probed, none of its flags are cached, and
# nothing about it can be completed. Bundling its *flags* instead would be
# inert: the merge below skips any scope that was never probed.
#
# Names are added optimistically, exactly as bundled flags are. If one ever
# disappears upstream, its probe returns nothing and no cache files are
# written, so only the bare name is offered - the same trade the flag list
# already makes for older installs.
#
# Format: name<TAB>description
_CLAUDE_EXTRA_SUBCOMMANDS=(
    $'self-hosted-runner\tRun a self-hosted Claude Code runner'
)

# Split a tab-separated extra-flag record into its fields.
# Usage: _claude_parse_extra_flag_record "$record" scope name takes_arg arg_type desc
_claude_parse_extra_flag_record() {
    local record="$1"
    local -n _scope="$2" _name="$3" _takes_arg="$4" _arg_type="$5" _desc="$6"
    IFS=$'\t' read -r _scope _name _takes_arg _arg_type _desc <<< "$record"
}

# Modification time of a file as a Unix timestamp, portable across the
# GNU/Linux (`stat -c %Y`) and FreeBSD/macOS (`stat -f %m`) stat variants.
# The unsupported variant exits non-zero on each platform, so each probe
# is guarded inside the `if` condition (exempt from errexit/ERR traps) and
# the function always returns 0 — callers run it inside command
# substitutions under bashunit's `set -eE` hook harness, where a bare
# failing assignment would otherwise abort the whole hook.
_claude_mtime() {
    local file="$1" m
    if m="$(stat -c %Y "$file" 2>/dev/null)" && [[ "$m" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$m"
    elif m="$(stat -f %m "$file" 2>/dev/null)" && [[ "$m" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$m"
    fi
    return 0
}

_claude_cpu_count() {
    # Logical CPU count (hyperthreads included), portable across the platforms
    # this script supports. Each candidate is guarded the same way _claude_mtime
    # guards its GNU/BSD stat variants: the wrong tool for the platform exits
    # non-zero or prints something non-numeric, so every result is checked
    # before use and the function always returns 0.
    #
    # nproc comes first because it honours CPU affinity — a cgroup- or
    # taskset-limited container reports the budget it actually has rather than
    # the host's core count. sysctl covers macOS and FreeBSD (where nproc is
    # not installed), getconf is the POSIX fallback, and NUMBER_OF_PROCESSORS
    # covers Git Bash / Cygwin on Windows.
    local n
    if n="$(nproc 2>/dev/null)" && [[ "$n" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$n"
    elif n="$(sysctl -n hw.ncpu 2>/dev/null)" && [[ "$n" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$n"
    elif n="$(getconf _NPROCESSORS_ONLN 2>/dev/null)" && [[ "$n" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$n"
    elif [[ "${NUMBER_OF_PROCESSORS:-}" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$NUMBER_OF_PROCESSORS"
    else
        printf '%s\n' 1
    fi
    return 0
}

_claude_probe_concurrency() {
    # How many probes to run at once, from the core count.
    # Usage: _claude_probe_concurrency [cores]   (cores detected when omitted)
    #
    # Probes are CPU-bound Node cold starts with some process-spawn I/O, so
    # mild oversubscription helps: on two cores, 4 and 8 measured the same and
    # both beat 1, while 16 was slower. A very wide machine is still capped,
    # since each probe costs real memory.
    local cores="${1:-$(_claude_cpu_count)}"
    # Clamp the core count, not the result: NUMBER_OF_PROCESSORS is an ordinary
    # environment variable that the detection above only checks for digits, so
    # a `0` reaches here and would make the build loop's `launched % 0` raise a
    # division-by-zero on every probe. Guarding cores also covers a
    # non-numeric value, which bash evaluates as 0.
    if (( cores < 1 )); then
        cores=1
    fi
    local concurrency=$(( cores * 2 ))
    if (( concurrency > 16 )); then
        concurrency=16
    fi
    printf '%s\n' "$concurrency"
}

# Resolve the claude CLI version. `claude --version` is a slow Node
# cold-start (~1.5s), so memoize the result per shell, keyed on the
# binary's path + mtime — an upgrade (new path or rewritten binary)
# invalidates the cache, but repeated tab presses do not respawn Node.
_claude_version() {
    local claude_path key
    claude_path="$(command -v claude 2>/dev/null)"
    key="${claude_path}:$(_claude_mtime "$claude_path")"
    if [[ -n "${_CLAUDE_VERSION_CACHE:-}" && "${_CLAUDE_VERSION_KEY:-}" == "$key" ]]; then
        printf '%s\n' "$_CLAUDE_VERSION_CACHE"
        return
    fi
    _CLAUDE_VERSION_CACHE="$(claude --version 2>/dev/null | head -1 | awk '{print $1}')"
    _CLAUDE_VERSION_KEY="$key"
    printf '%s\n' "$_CLAUDE_VERSION_CACHE"
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
    # Parse flags that take an argument (required <value> or optional [value]).
    # The placeholder follows the flag after a SINGLE space; a 2+ space gap
    # instead introduces the description (e.g. "--mcp-debug   [DEPRECATED…]"),
    # which must not be mistaken for an argument.
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+(-[a-zA-Z]),?[[:space:]]+(--[a-zA-Z][-a-zA-Z]*)[[:space:]][\<\[] ]]; then
            echo "${BASH_REMATCH[1]}"
            echo "${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]+(--[a-zA-Z][-a-zA-Z]*)[[:space:]][\<\[] ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done
}

_claude_parse_flags_with_optional_args() {
    # Parse flags whose argument is OPTIONAL — shown as [value], not <value>.
    # Same single-space rule as _claude_parse_flags_with_args so a description
    # beginning with '[' is not mistaken for an optional argument.
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+(-[a-zA-Z]),?[[:space:]]+(--[a-zA-Z][-a-zA-Z]*)[[:space:]][[] ]]; then
            echo "${BASH_REMATCH[1]}"
            echo "${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]+(--[a-zA-Z][-a-zA-Z]*)[[:space:]][[] ]]; then
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
            # A real command entry sits at the 2-space term column and is a
            # two-column "name  <gap>  description" row. Anchoring on exactly
            # two leading spaces rejects wrapped description lines (indented to
            # the deep help column) and example/code lines (indented 4+);
            # requiring a 2+ space gap before the description rejects bare
            # sub-headings like "Examples:" that have no description column.
            # Extract command name (first word, handle "update|upgrade" aliases)
            local cmd_re='^  ([a-zA-Z][-a-zA-Z]*).*  +[^[:space:]]'
            if [[ "$line" =~ $cmd_re ]]; then
                echo "${BASH_REMATCH[1]}"
            fi
        fi
    done
}

_claude_parse_subcommand_descriptions() {
    # Parse "<name><TAB><description>" lines from the "Commands:" section of
    # help output on stdin. Same row anchoring as _claude_parse_subcommands;
    # the description is the text after the first 2+ space gap, which skips
    # alias forms ("update|upgrade") and argument placeholders ("[options]
    # <name>"). Wrapped descriptions keep only their first line, matching
    # _claude_parse_flag_descriptions.
    local in_commands=0
    local line rest
    while IFS= read -r line; do
        if [[ "$line" =~ ^Commands: ]]; then
            in_commands=1
            continue
        fi
        if [[ $in_commands -eq 1 ]]; then
            [[ -z "$line" ]] && continue
            [[ ! "$line" =~ ^[[:space:]] ]] && break
            local cmd_re='^  ([a-zA-Z][-a-zA-Z]*)(.*)$'
            if [[ "$line" =~ $cmd_re ]]; then
                local name="${BASH_REMATCH[1]}"
                rest="${BASH_REMATCH[2]}"
                if [[ "$rest" =~ [[:space:]][[:space:]]+([^[:space:]].*)$ ]]; then
                    printf '%s\t%s\n' "$name" "${BASH_REMATCH[1]}"
                fi
            fi
        fi
    done
}

_claude_node_is_probeable() {
    # Decide whether a node listed in a "Commands:" section is worth spending a
    # `--help` probe on. Every node is, except Commander's built-in help
    # command, which is always a leaf and whose only flag is --help itself.
    #
    # Every other node is probed even when it cannot be a command group,
    # because its help still carries the flags *it* accepts. Skipping those
    # left `claude plugin install -<TAB>` with nothing to offer.
    local name="$1"
    [[ "$name" == "help" ]] && return 1
    return 0
}

_claude_parse_node() {
    # Write every per-node cache file for one command path from its captured
    # help text.
    # Usage: _claude_parse_node <build dir> <cache key> <raw help file>
    local build_dir="$1" key="$2" raw="$3"
    _claude_parse_flags                   < "$raw" > "$build_dir/${key}_flags"
    _claude_parse_flags_with_args         < "$raw" > "$build_dir/${key}_flags_with_args"
    _claude_parse_flags_with_optional_args < "$raw" > "$build_dir/${key}_flags_with_optional_args"
    _claude_parse_flag_descriptions       < "$raw" > "$build_dir/${key}_flag_descriptions"
    _claude_parse_subcommands             < "$raw" > "$build_dir/${key}_subcommands"
    _claude_parse_subcommand_descriptions  < "$raw" > "$build_dir/${key}_subcommand_descriptions"
}

_claude_build_cache() {
    local cache_dir build_dir raw_dir
    cache_dir="$(_claude_cache_dir)"
    # Build into a private staging dir, then publish atomically with a
    # rename. The real version dir therefore only ever exists fully built —
    # a crashed or interrupted build can never leave a partial/empty cache
    # that later reads would mistake for complete.
    build_dir="${cache_dir}.tmp.$$"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    # Raw help text is staged inside the build dir (so a crash cannot strand
    # it elsewhere) and removed again before the cache is published.
    raw_dir="$build_dir/.raw"
    mkdir -p "$raw_dir"

    claude --help > "$raw_dir/_root" 2>/dev/null
    cp "$raw_dir/_root" "$build_dir/_root_help"

    # Walk the command tree one depth at a time, so the nesting we support is
    # whatever `claude --help` actually describes rather than a fixed number
    # of levels. Per level: parse the help text already captured for its
    # nodes, collect the children worth probing, then fetch that next level.
    #
    # Only the fetch is parallel. Parsing stays serial and in-process because
    # PowerShell's ForEach-Object -Parallel runs each iteration in a runspace
    # that cannot see the script's functions, and both shells must produce
    # identical caches — see docs/plans/2026-09-17-nested-subcommand-completion.md.
    #
    # Cache keys are the command path joined by '_' (plugin_marketplace_flags).
    # That is unambiguous because claude's command names separate words with
    # '-' and never '_'.
    local -a level=( $'_root\t' )
    local depth=0
    local concurrency="${_CLAUDE_PROBE_CONCURRENCY:-$(_claude_probe_concurrency)}"
    while (( ${#level[@]} > 0 && depth < _CLAUDE_MAX_DEPTH )); do
        local -a next_keys=() next_paths=()
        local entry key path name term child_key
        for entry in "${level[@]}"; do
            IFS=$'\t' read -r key path <<< "$entry"
            local raw="$raw_dir/$key"
            # An empty file means the probe failed; leaving the node unparsed
            # keeps stray empty cache files from looking like real answers.
            [[ -s "$raw" ]] || continue
            _claude_parse_node "$build_dir" "$key" "$raw"
            while IFS= read -r name; do
                [[ -z "$name" ]] && continue
                _claude_node_is_probeable "$name" || continue
                if [[ "$key" == "_root" ]]; then
                    child_key="$name"
                else
                    child_key="${key}_${name}"
                fi
                next_keys+=("$child_key")
                next_paths+=("${path:+$path }$name")
            done < <(_claude_parse_subcommands < "$raw")

            # Hidden subcommands are children of the root and of nothing else.
            if [[ "$key" == "_root" ]]; then
                local sub_rec sub_name sub_desc
                for sub_rec in "${_CLAUDE_EXTRA_SUBCOMMANDS[@]}"; do
                    [[ -z "$sub_rec" ]] && continue
                    IFS=$'\t' read -r sub_name sub_desc <<< "$sub_rec"
                    # --help wins on overlap, as it does for bundled flags.
                    grep -qx -- "$sub_name" "$build_dir/_root_subcommands" && continue
                    echo "$sub_name" >> "$build_dir/_root_subcommands"
                    printf '%s\t%s\n' "$sub_name" "$sub_desc" \
                        >> "$build_dir/_root_subcommand_descriptions"
                    next_keys+=("$sub_name")
                    next_paths+=("$sub_name")
                done
            fi
        done

        level=()
        local i launched=0
        for (( i=0; i < ${#next_keys[@]}; i++ )); do
            local -a path_words=()
            read -ra path_words <<< "${next_paths[i]}"
            claude "${path_words[@]}" --help > "$raw_dir/${next_keys[i]}" 2>/dev/null &
            level+=( "${next_keys[i]}"$'\t'"${next_paths[i]}" )
            # Each probe is a Node cold start, so cap the fan-out rather than
            # launching a whole level at once. Plain `wait` works on every
            # bash we support; `wait -n` would require 4.3+.
            launched=$(( launched + 1 ))
            if (( launched % concurrency == 0 )); then
                wait
            fi
        done
        wait
        depth=$(( depth + 1 ))
    done

    # Merge bundled flags into the cache files (skip ones already present from --help).
    local rec scope name takes_arg arg_type desc flags_file
    for rec in "${_CLAUDE_EXTRA_FLAGS[@]}"; do
        [[ -z "$rec" ]] && continue
        _claude_parse_extra_flag_record "$rec" scope name takes_arg arg_type desc
        flags_file="$build_dir/${scope}_flags"
        [[ -f "$flags_file" ]] || continue
        if grep -qFx -- "$name" "$flags_file"; then
            continue  # --help wins on overlap
        fi
        echo "$name" >> "$flags_file"
        if [[ "$takes_arg" != "none" ]]; then
            echo "$name" >> "$build_dir/${scope}_flags_with_args"
        fi
        if [[ "$takes_arg" == "optional" ]]; then
            echo "$name" >> "$build_dir/${scope}_flags_with_optional_args"
        fi
        printf '%s\t%s\n' "$name" "$desc" >> "$build_dir/${scope}_flag_descriptions"
        printf '%s\t%s\n' "$name" "$arg_type" >> "$build_dir/${scope}_flag_arg_types"
    done

    # Publish atomically: drop the raw staging dir and any stale/partial
    # cache, then rename into place.
    rm -rf "$raw_dir"
    rm -rf "$cache_dir"
    mv "$build_dir" "$cache_dir"

    # Clean up old versions (also sweeps any *.tmp.* from crashed builds)
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

_claude_preserve_order() {
    # Keep COMPREPLY in the order we built it. Without this, readline sorts the
    # matches alphabetically before display. No-op on bash < 4.4 (no nosort).
    if [[ ${BASH_VERSINFO[0]} -ge 5 || (${BASH_VERSINFO[0]} -eq 4 && ${BASH_VERSINFO[1]} -ge 4) ]]; then
        compopt -o nosort 2>/dev/null || true
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

    _claude_preserve_order
}

_claude_complete_sessions() {
    local cur="$1"
    local encoded_cwd
    encoded_cwd="$(_claude_encoded_cwd)"
    local session_dir="$HOME/.claude/projects/${encoded_cwd}"

    [[ -d "$session_dir" ]] || return

    # List JSONL files sorted by modification time (newest first).
    # Uses ls -1t for portability (GNU find -printf / head -z / cut -z are not
    # available on macOS).  Session filenames are UUIDs so globbing is safe.
    # The 10-session cap is applied *after* the prefix filter below, so a unique
    # match older than the 10 newest sessions is still reachable.
    local files=()
    local _f
    while IFS= read -r _f; do
        files+=("$_f")
    done < <(ls -1t "$session_dir"/*.jsonl 2>/dev/null)

    local tab=$'\t'
    local candidates=()
    for file in "${files[@]}"; do
        local basename="${file##*/}"
        local session_id="${basename%.jsonl}"
        if [[ "$session_id" == "$cur"* ]]; then
            local msg
            msg="$(_claude_session_message "$file")"
            candidates+=("${session_id}${tab}${msg:-(session)}")
            # Files are newest-first, so the first 10 matches are the 10 newest.
            (( ${#candidates[@]} >= 10 )) && break
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

# Hardcoded model IDs (update when new models are released).
# Order is the display order, following Anthropic's canonical catalog order:
# documented aliases first (each [1m] variant next to its base alias), then
# capability tier descending (fable, opus, sonnet, haiku) with each tier's
# versions newest-first. Alias set per code.claude.com/docs/en/model-config.
# Keep this list and $script:_ClaudeKnownModels in claude.ps1 in sync.
_CLAUDE_KNOWN_MODELS=(
    best
    fable fable[1m]
    opus opus[1m]
    sonnet sonnet[1m]
    haiku
    opusplan opusplan[1m]
    claude-fable-5
    claude-opus-5
    claude-opus-4-8
    claude-opus-4-7
    claude-opus-4-6
    claude-opus-4-5-20251101
    claude-sonnet-5
    claude-sonnet-4-6
    claude-sonnet-4-5-20250929
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

_claude_model_candidates() {
    # Print --model completions, one per line, deduplicated. A model matches
    # when it starts with $cur OR with "claude-$cur", so an alias stem
    # (opus/sonnet/haiku/fable) also reaches its claude-<family>-* versions.
    # Backslashes are stripped from $cur first: readline hands back the word as
    # typed, so a partially typed "opus\[1" must match the literal "opus[1m]".
    local cur="${1//\\/}"
    local models=("${_CLAUDE_KNOWN_MODELS[@]}")
    local cache_dir line
    cache_dir="$(_claude_cache_dir)"
    if [[ -f "$cache_dir/_root_help" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ claude-[a-z]+-[0-9][a-z0-9-]* ]]; then
                models+=("${BASH_REMATCH[0]}")
            fi
        done < "$cache_dir/_root_help"
    fi
    local m
    local -A seen=()
    for m in "${models[@]}"; do
        if [[ "$m" == "$cur"* || "$m" == "claude-$cur"* ]]; then
            if [[ -z "${seen[$m]:-}" ]]; then
                seen[$m]=1
                printf '%s\n' "$m"
            fi
        fi
    done
}

_claude_complete_flag_arg() {
    # Complete arguments for flags that take values
    # $1 = flag name, $2 = current word, $3 = scope (default: _root)
    local flag="$1"
    local cur="$2"
    local scope="${3:-_root}"

    case "$flag" in
        --model)
            COMPREPLY=()
            local _model _escaped
            while IFS= read -r _model; do
                # The [1m] aliases carry glob metacharacters; %q escapes them so
                # the word inserts literally instead of pathname-expanding.
                # Plain ids pass through %q unchanged.
                printf -v _escaped '%q' "$_model"
                COMPREPLY+=("$_escaped")
            done < <(_claude_model_candidates "$cur")
            # Candidates are already in canonical catalog order; don't let
            # readline re-sort them alphabetically.
            _claude_preserve_order
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

_claude_marketplace_names() {
    # Extract marketplace names from "claude plugin marketplace list --json"
    if command -v jq &>/dev/null; then
        claude plugin marketplace list --json 2>/dev/null | jq -r '.[].name' 2>/dev/null
    else
        claude plugin marketplace list --json 2>/dev/null | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//'
    fi
}

_claude_complete_subcmd_arg() {
    # Complete a positional argument for a resolved command path.
    # Usage: _claude_complete_subcmd_arg <path joined by /> <current word>
    local path="$1"
    local cur="$2"

    case "$path" in
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
        plugin/marketplace/remove|plugin/marketplace/update)
            local names
            names="$(_claude_marketplace_names)"
            COMPREPLY=( $(compgen -W "$names" -- "$cur") )
            ;;
    esac
}

_claude_candidates_with_descriptions() {
    # Build a "value<TAB>desc" list (printed to stdout, one per line) for the
    # values in $1 that match prefix $2. Looks up descriptions in $3.
    local list_file="$1"
    local prefix="$2"
    local desc_file="$3"

    declare -A descs
    if [[ -f "$desc_file" ]]; then
        local f d
        while IFS=$'\t' read -r f d; do
            descs["$f"]="$d"
        done < "$desc_file"
    fi

    local value
    while IFS= read -r value; do
        [[ -z "$value" ]] && continue
        [[ "$value" == "$prefix"* ]] || continue
        if [[ -n "${descs[$value]:-}" ]]; then
            printf '%s\t%s\n' "$value" "${descs[$value]}"
        else
            echo "$value"
        fi
    done < "$list_file"
}

_claude_compreply_with_descriptions() {
    # Fill COMPREPLY from the values in $1 that match prefix $2, rendering
    # descriptions from $3 when multiple candidates match. A single match or
    # menu-complete (COMP_TYPE 37/42) inserts the bare value so insertion is
    # clean.
    local list_file="$1" prefix="$2" desc_file="$3"
    local candidates=() line
    while IFS= read -r line; do
        candidates+=("$line")
    done < <(_claude_candidates_with_descriptions "$list_file" "$prefix" "$desc_file")
    if (( ${#candidates[@]} == 1 )) || [[ ${COMP_TYPE:-9} == @(37|42) ]]; then
        COMPREPLY=()
        local c
        for c in "${candidates[@]}"; do
            COMPREPLY+=("${c%%$'\t'*}")
        done
    else
        _claude_format_descriptions candidates
    fi
}

_claude() {
    local cur prev words cword
    _init_completion || return

    local cache_dir
    cache_dir="$(_claude_cache_dir)"

    # Build cache if needed. Gate on a populated cache (the _root_help
    # sentinel), not bare directory existence — an empty or partially
    # written dir must trigger a rebuild rather than serving nothing.
    if [[ ! -f "$cache_dir/_root_help" ]]; then
        _claude_build_cache
    fi

    # Resolve the command path: walk the words left to right, extending the
    # path whenever the next non-flag word is a subcommand of the path so far.
    # Words that match nothing are skipped rather than ending the walk, so a
    # flag's argument ("claude mcp --scope user get") cannot hide the
    # subcommand that follows it.
    local key="_root"
    local -a cmd_path=()
    local i w subs_file
    for (( i=1; i < cword; i++ )); do
        w="${words[i]}"
        [[ "$w" == -* ]] && continue
        subs_file="$cache_dir/${key}_subcommands"
        # No list for this node means it was pruned as a leaf: nothing deeper
        # can match, so stop rather than mistaking a positional argument for
        # a subcommand.
        [[ -f "$subs_file" ]] || break
        if grep -qx -- "$w" "$subs_file"; then
            cmd_path+=("$w")
            if [[ "$key" == "_root" ]]; then
                key="$w"
            else
                key="${key}_${w}"
            fi
        fi
    done

    # Check if previous word is a flag that takes an argument. Flag scope is
    # the resolved path, so a nested node's flags win over its parent's.
    if [[ "$prev" == -* ]]; then
        local flags_with_args_file="$cache_dir/${key}_flags_with_args"
        local optional_args_file="$cache_dir/${key}_flags_with_optional_args"
        if [[ -f "$flags_with_args_file" ]] && grep -qx -- "$prev" "$flags_with_args_file"; then
            # For optional-arg flags, a current word that already starts with '-'
            # means the user is typing the next flag, not the argument — fall
            # through to normal flag/subcommand completion. Otherwise (empty or
            # non-dash word) complete the flag's argument.
            if [[ "$cur" == -* && -f "$optional_args_file" ]] && grep -qx -- "$prev" "$optional_args_file"; then
                : # fall through
            else
                _claude_complete_flag_arg "$prev" "$cur" "$key"
                return
            fi
        fi
    fi

    if [[ "$cur" == -* ]]; then
        # Complete flags for the resolved node
        if [[ -f "$cache_dir/${key}_flags" ]]; then
            _claude_compreply_with_descriptions \
                "$cache_dir/${key}_flags" "$cur" \
                "$cache_dir/${key}_flag_descriptions"
        fi
    elif [[ -s "$cache_dir/${key}_subcommands" ]]; then
        # Complete this node's subcommands. The file exists but is empty for a
        # probed leaf, which must fall through to positional-argument
        # completion instead of offering nothing.
        _claude_compreply_with_descriptions \
            "$cache_dir/${key}_subcommands" "$cur" \
            "$cache_dir/${key}_subcommand_descriptions"
    elif (( ${#cmd_path[@]} > 0 )); then
        # Complete positional args for the resolved leaf
        local joined
        joined="$(IFS=/; printf '%s' "${cmd_path[*]}")"
        _claude_complete_subcmd_arg "$joined" "$cur"
    fi
}

complete -F _claude claude
