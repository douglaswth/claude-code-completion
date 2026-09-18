#!/usr/bin/env bash

# Guard for the prune heuristic against the REAL claude CLI.
#
# _claude_node_is_probeable skips two classes of node when walking the command
# tree: `help`, and any node whose term column shows a required <arg>. The
# second rule is a Commander.js convention, not a guarantee — an upstream
# `claude foo <bar> baz` would be silently dropped from completion with no
# other symptom. This test walks the installed CLI and asserts that every node
# the heuristic prunes genuinely has no `Commands:` section, so that drift
# surfaces as a failing test instead of a missing completion.
#
# Skipped when no real claude is installed (CI, contributors without it).
# It costs one `claude ... --help` per node, so it is the slowest test here.

function set_up_before_script() {
    REAL_CLAUDE="$(command -v claude 2>/dev/null || true)"
    source_claude_bash
}

function test_prune_heuristic_never_discards_a_real_command_group() {
    if [[ -z "$REAL_CLAUDE" ]]; then
        bashunit::skip "no claude on PATH"
        return
    fi

    local pruned=() offenders=()
    local root_help sub name term sub_help

    root_help="$("$REAL_CLAUDE" --help 2>/dev/null)"
    while IFS= read -r sub; do
        [[ -z "$sub" ]] && continue
        sub_help="$("$REAL_CLAUDE" "$sub" --help 2>/dev/null)" || continue
        while IFS=$'\t' read -r name term; do
            [[ -z "$name" ]] && continue
            if ! _claude_node_is_probeable "$name" "$term"; then
                pruned+=("$sub/$name")
            fi
        done < <(printf '%s\n' "$sub_help" | _claude_parse_subcommand_terms)
    done < <(printf '%s\n' "$root_help" | _claude_parse_subcommands)

    local node
    for node in "${pruned[@]}"; do
        if "$REAL_CLAUDE" ${node//\// } --help 2>/dev/null | grep -q '^Commands:'; then
            offenders+=("$node")
        fi
    done

    assert_empty "${offenders[*]}"
}
