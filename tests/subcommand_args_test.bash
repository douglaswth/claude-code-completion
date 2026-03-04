#!/usr/bin/env bash

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
  mcp                            Configure MCP servers
  plugin                         Manage plugins
HELP
        ;;
    "mcp --help")
        cat << 'HELP'
Usage: claude mcp [options] [command]

Options:
  -h, --help                                     Display help
  -s, --scope <scope>                            Scope for server

Commands:
  get <name>                                     Get server
  list                                           List servers
  remove [options] <name>                        Remove server
HELP
        ;;
    "plugin --help")
        cat << 'HELP'
Usage: claude plugin [options] [command]

Options:
  -h, --help                           Display help

Commands:
  disable [options] [plugin]           Disable a plugin
  enable [options] <plugin>            Enable a plugin
  list [options]                       List installed plugins
  uninstall|remove [options] <plugin>  Uninstall a plugin
HELP
        ;;
    "mcp list")
        cat << 'OUTPUT'
Checking MCP server health...

my-sentry: https://mcp.sentry.dev/mcp - ✓ Connected
my-github: /usr/bin/gh-mcp (stdio) - ✓ Connected
OUTPUT
        ;;
    "plugin list --json")
        cat << 'OUTPUT'
[{"name":"superpowers","version":"4.3.1","enabled":true},{"name":"my-plugin","version":"1.0.0","enabled":false}]
OUTPUT
        ;;
esac
BODY
)"

    COMP_DIR="$(mktemp -d)"
    touch "$COMP_DIR/config.json"

    export PATH="$MOCK_BIN:$PATH"
    source_claude_bash
}

function tear_down_after_script() {
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN" "$COMP_DIR"
}

function test_mcp_get_completes_server_names() {
    local result
    result="$(simulate_completion "claude mcp get ")"
    assert_contains "my-sentry" "$result"
    assert_contains "my-github" "$result"
}

function test_mcp_remove_completes_server_names() {
    local result
    result="$(simulate_completion "claude mcp remove ")"
    assert_contains "my-sentry" "$result"
}

function test_plugin_disable_completes_plugin_names() {
    local result
    result="$(simulate_completion "claude plugin disable ")"
    assert_contains "superpowers" "$result"
    assert_contains "my-plugin" "$result"
}

function test_plugin_enable_completes_plugin_names() {
    local result
    result="$(simulate_completion "claude plugin enable ")"
    assert_contains "superpowers" "$result"
}

function test_plugin_uninstall_completes_plugin_names() {
    local result
    result="$(simulate_completion "claude plugin uninstall ")"
    assert_contains "superpowers" "$result"
}

function test_subcommand_flag_with_args_completes() {
    local result
    result="$(simulate_completion "claude mcp add --scope $COMP_DIR/")"
    assert_contains "config.json" "$result"
}

function test_subcommand_dash_shows_subcommand_flags() {
    local result
    result="$(simulate_completion "claude mcp -")"
    assert_contains "--help" "$result"
    assert_contains "--scope" "$result"
}
