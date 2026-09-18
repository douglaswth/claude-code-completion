#!/usr/bin/env bash

# Nesting beyond two levels: the command tree is walked to whatever depth
# `claude --help` actually describes, rather than a fixed subcmd/sub-subcmd
# pair. The mock below carries a three-level group (plugin marketplace), a
# three-level group whose *description* contains angle brackets (plugin eval),
# and a four-level chain (deep one two three) that exists only to prove the
# walk is not hardcoded to three.

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    export XDG_CACHE_HOME="$(mktemp -d)"

    write_mock_claude "$MOCK_BIN" "$(cat <<'BODY'
case "$*" in
    "--version") echo "1.0.0 (Claude Code)" ;;
    "--help")
        cat << 'HELP'
Usage: claude [options] [command] [prompt]

Options:
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  deep                           Four-level nesting probe
  mcp                            Configure MCP servers
  plugin                         Manage plugins
HELP
        ;;
    "plugin --help")
        cat << 'HELP'
Usage: claude plugin [options] [command]

Options:
  -h, --help                           Display help
  --plugin-scope <scope>               Scope for plugin operations

Commands:
  enable [options] <plugin>            Enable a disabled plugin
  eval [options] [target]              Run eval cases (<eval dir>/**/case.yaml
                                       or prompt.md) against a plugin
  help [command]                       display help for command
  list [options]                       List installed plugins
  marketplace                          Manage Claude Code marketplaces
HELP
        ;;
    "plugin enable --help")
        cat << 'HELP'
Usage: claude plugin enable [options] <plugin>

Options:
  -h, --help          Display help for command
  --enable-force      Force enabling the plugin
HELP
        ;;
    "plugin marketplace remove --help")
        cat << 'HELP'
Usage: claude plugin marketplace remove [options] <name>

Options:
  -h, --help          Display help for command
  --remove-force      Remove without confirmation
HELP
        ;;
    "plugin marketplace --help")
        cat << 'HELP'
Usage: claude plugin marketplace [options] [command]

Options:
  -h, --help                  Display help for command
  --marketplace-force         Force the marketplace operation

Commands:
  add [options] <source>      Add a marketplace from a URL, path, or GitHub repo
  list [options]              List all configured marketplaces
  remove [options] <name>     Remove a configured marketplace
  update [options] [name]     Update marketplace(s) from their source
HELP
        ;;
    "plugin eval --help")
        cat << 'HELP'
Usage: claude plugin eval [options] [command] [target]

Options:
  -h, --help        Display help for command

Commands:
  init [options]    Scaffold an eval suite
HELP
        ;;
    "plugin marketplace list --json")
        cat << 'OUTPUT'
[{"name":"claude-plugins-official","source":"github"},{"name":"community-marketplace","source":"git"}]
OUTPUT
        ;;
    "mcp --help")
        cat << 'HELP'
Usage: claude mcp [options] [command]

Options:
  -h, --help                Display help

Commands:
  get <name>                Get server
  list                      List servers
HELP
        ;;
    "mcp get --help")
        cat << 'HELP'
Usage: claude mcp get [options] <name>

Options:
  -h, --help        Display help
  --get-json        Print the server entry as JSON
HELP
        ;;
    "deep --help")
        cat << 'HELP'
Usage: claude deep [options] [command]

Options:
  -h, --help        Display help

Commands:
  one               Level one
HELP
        ;;
    "deep one --help")
        cat << 'HELP'
Usage: claude deep one [options] [command]

Options:
  -h, --help        Display help

Commands:
  two               Level two
HELP
        ;;
    "deep one two --help")
        cat << 'HELP'
Usage: claude deep one two [options] [command]

Options:
  -h, --help        Display help

Commands:
  three             Level three
HELP
        ;;
    "deep one two three --help")
        cat << 'HELP'
Usage: claude deep one two three [options]

Options:
  -h, --help            Display help
  --bottom-flag         A flag only the deepest node has
HELP
        ;;
esac
BODY
)"

    export PATH="$MOCK_BIN:$PATH"
    source_claude_bash
}

function tear_down_after_script() {
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN"
}

# --- The reported bug ---------------------------------------------------

function test_third_level_subcommands_complete() {
    local result
    result="$(simulate_completion "claude plugin marketplace ")"
    assert_contains "add" "$result"
    assert_contains "list" "$result"
    assert_contains "remove" "$result"
    assert_contains "update" "$result"
}

function test_third_level_filters_by_prefix() {
    local result
    result="$(simulate_completion "claude plugin marketplace re")"
    assert_contains "remove" "$result"
    assert_not_contains "add" "$result"
}

function test_third_level_carries_descriptions() {
    local result
    result="$(simulate_completion "claude plugin marketplace ")"
    assert_contains "Remove a configured marketplace" "$result"
}

# A description containing "<eval dir>" must not be mistaken for a required
# argument placeholder and cause the node to be pruned from the walk.
function test_group_with_angle_brackets_in_description_is_probed() {
    local result
    result="$(simulate_completion "claude plugin eval ")"
    assert_contains "init" "$result"
}

# --- Depth is not hardcoded ---------------------------------------------

function test_fourth_level_subcommands_complete() {
    local result
    result="$(simulate_completion "claude deep one two ")"
    assert_contains "three" "$result"
}

function test_fourth_level_flags_complete() {
    local result
    result="$(simulate_completion "claude deep one two three -")"
    assert_contains "--bottom-flag" "$result"
}

# --- Flag scope follows the resolved path -------------------------------

function test_flags_are_scoped_to_the_deepest_node() {
    local result
    result="$(simulate_completion "claude plugin marketplace -")"
    assert_contains "--marketplace-force" "$result"
    assert_not_contains "--plugin-scope" "$result"
}

# --- Positional arguments at the third level ----------------------------

function test_marketplace_remove_completes_marketplace_names() {
    local result
    result="$(simulate_completion "claude plugin marketplace remove ")"
    assert_contains "claude-plugins-official" "$result"
    assert_contains "community-marketplace" "$result"
}

function test_marketplace_update_completes_marketplace_names() {
    local result
    result="$(simulate_completion "claude plugin marketplace update ")"
    assert_contains "claude-plugins-official" "$result"
}

# --- Flags at a leaf that takes a positional argument -------------------

# Regression: pruning nodes with a required <arg> meant their help was never
# probed, so their flags were never cached and `claude plugin install -<TAB>`
# offered nothing at all.

function test_leaf_with_required_arg_completes_its_own_flags() {
    local result
    result="$(simulate_completion "claude plugin enable -")"
    assert_contains "--enable-force" "$result"
}

function test_leaf_flags_are_its_own_not_its_parents() {
    local result
    result="$(simulate_completion "claude plugin enable -")"
    assert_not_contains "--plugin-scope" "$result"
}

function test_mcp_leaf_completes_its_own_flags() {
    local result
    result="$(simulate_completion "claude mcp get -")"
    assert_contains "--get-json" "$result"
}

function test_sub_subcommand_leaf_completes_its_own_flags() {
    local result
    result="$(simulate_completion "claude plugin marketplace remove -")"
    assert_contains "--remove-force" "$result"
}

# --- Pruning ------------------------------------------------------------

function test_prune_predicate_rejects_help() {
    # Status is captured explicitly: a bare non-zero return would abort the
    # test under bashunit's set -e harness before the assertion ran.
    local rc
    rc=0; _claude_node_is_probeable "help" || rc=$?
    assert_equals "1" "$rc"
}

function test_prune_predicate_accepts_everything_else() {
    # Including nodes that take a required argument: they cannot be command
    # groups, but their help still lists the flags they accept.
    local rc
    rc=0; _claude_node_is_probeable "marketplace" || rc=$?
    assert_equals "0" "$rc"
    rc=0; _claude_node_is_probeable "get" || rc=$?
    assert_equals "0" "$rc"
    rc=0; _claude_node_is_probeable "install" || rc=$?
    assert_equals "0" "$rc"
}

function test_only_help_nodes_are_left_unprobed() {
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    simulate_completion "claude plugin " > /dev/null
    # `help` is the one node never probed ...
    assert_file_not_exists "$cache_dir/plugin_help_flags"
    # ... every other node is, so its own flags are cached.
    assert_file_exists "$cache_dir/plugin_enable_flags"
    assert_file_exists "$cache_dir/mcp_get_flags"
}

function test_raw_help_staging_is_not_published_into_the_cache() {
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    simulate_completion "claude plugin " > /dev/null
    assert_directory_not_exists "$cache_dir/.raw"
}

# --- Probe concurrency --------------------------------------------------

function test_probe_concurrency_is_twice_the_core_count() {
    assert_equals "8" "$(_claude_probe_concurrency 4)"
}

function test_probe_concurrency_floor_is_two() {
    # A single-core container must not launch eight Node processes.
    assert_equals "2" "$(_claude_probe_concurrency 1)"
}

function test_probe_concurrency_cap_is_sixteen() {
    # Each probe costs real memory, so a very wide machine is still bounded.
    assert_equals "16" "$(_claude_probe_concurrency 64)"
}

function test_probe_concurrency_clamps_a_zero_core_count() {
    # NUMBER_OF_PROCESSORS is an ordinary environment variable that detection
    # only checks for digits, so 0 can reach here — and an unclamped 0 makes
    # the build loop's `launched % 0` raise a division-by-zero per probe.
    assert_equals "2" "$(_claude_probe_concurrency 0)"
}

function test_cpu_count_reports_a_positive_integer() {
    local n
    n="$(_claude_cpu_count)"
    assert_matches "^[0-9]+$" "$n"
    assert_greater_or_equal_than 1 "$n"
}

# --- Existing two-level behaviour is unchanged --------------------------

function test_second_level_still_completes() {
    local result
    result="$(simulate_completion "claude plugin ")"
    assert_contains "marketplace" "$result"
    assert_contains "eval" "$result"
    assert_contains "list" "$result"
}

function test_root_level_still_completes() {
    local result
    result="$(simulate_completion "claude ")"
    assert_contains "plugin" "$result"
    assert_contains "mcp" "$result"
}

function test_leaf_with_no_subcommands_offers_nothing() {
    local result
    result="$(simulate_completion "claude mcp list ")"
    assert_empty "$result"
}
