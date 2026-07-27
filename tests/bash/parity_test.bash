#!/usr/bin/env bash
# Cross-shell parity: assert claude.bash and claude.ps1 carry the same
# bundled-flag set, marker version, and cache-version constant.

function set_up_before_script() {
    BASH_SCRIPT="$PROJECT_ROOT/claude.bash"
    PS_SCRIPT="$PROJECT_ROOT/claude.ps1"
}

# Source claude.bash in a subshell and dump the array — gives native
# access to the data without parsing.
extract_bash_extra_flags() {
    (
        source "$BASH_SCRIPT" >/dev/null 2>&1
        printf '%s\n' "${_CLAUDE_EXTRA_FLAGS[@]}"
    ) | sort
}

# Parse [pscustomobject]@{...} lines from the PowerShell script and emit
# normalized tab-separated records matching the bash array format
# (scope<TAB>name<TAB>takes_arg<TAB>arg_type<TAB>description).
extract_ps_extra_flags() {
    grep -E '^\s+\[pscustomobject\]@\{' "$PS_SCRIPT" | while IFS= read -r line; do
        local scope name ta arg_type desc
        scope=$(echo "$line" | sed -n "s/.*Scope='\([^']*\)'.*/\1/p")
        name=$(echo "$line"  | sed -n "s/.*Name='\([^']*\)'.*/\1/p")
        ta=$(echo "$line" | sed -n "s/.*TakesArg='\([^']*\)'.*/\1/p")
        arg_type=$(echo "$line" | sed -n "s/.*ArgType='\([^']*\)'.*/\1/p")
        desc=$(echo "$line"     | sed -n "s/.*Description='\([^']*\)'.*/\1/p")
        printf '%s\t%s\t%s\t%s\t%s\n' "$scope" "$name" "$ta" "$arg_type" "$desc"
    done | sort
}

# The known-model lists are a display-order contract, so compare them
# unsorted: both shells must offer the same models in the same order.
extract_bash_known_models() {
    (
        source "$BASH_SCRIPT" >/dev/null 2>&1
        printf '%s\n' "${_CLAUDE_KNOWN_MODELS[@]}"
    )
}

extract_ps_known_models() {
    sed -n '/^\$script:_ClaudeKnownModels = @(/,/^)/p' "$PS_SCRIPT" \
        | grep -oE "'[^']+'" | tr -d "'"
}

function test_known_model_lists_match_in_order() {
    local bash_out ps_out
    bash_out="$(extract_bash_known_models)"
    ps_out="$(extract_ps_known_models)"
    assert_equals "$bash_out" "$ps_out"
}

function test_bundled_flag_sets_match() {
    local bash_out ps_out
    bash_out="$(extract_bash_extra_flags)"
    ps_out="$(extract_ps_extra_flags)"
    assert_equals "$bash_out" "$ps_out"
}

function test_marker_versions_match() {
    local bash_marker ps_marker
    bash_marker="$(grep -o 'last extended through CHANGELOG version: [0-9.][0-9.]*' "$BASH_SCRIPT" | head -1)"
    ps_marker="$(grep -o 'last extended through CHANGELOG version: [0-9.][0-9.]*' "$PS_SCRIPT" | head -1)"
    assert_equals "$bash_marker" "$ps_marker"
}

function test_cache_version_constants_match() {
    local bash_v ps_v
    bash_v="$(grep -E '^_CLAUDE_CACHE_VERSION=' "$BASH_SCRIPT" | head -1 | sed 's/.*=//')"
    ps_v="$(grep -E '^\$script:ClaudeCacheVersion = ' "$PS_SCRIPT" | head -1 | sed 's/.*= //')"
    assert_equals "$bash_v" "$ps_v"
}
