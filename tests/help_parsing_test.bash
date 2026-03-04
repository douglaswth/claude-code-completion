#!/usr/bin/env bash

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    export XDG_CACHE_HOME="$(mktemp -d)"

    write_mock_claude "$MOCK_BIN" <<'MOCK'
case "$*" in
    "--version") echo "1.0.0 (Claude Code)" ;;
    "--help")
        cat << 'HELP'
Usage: claude [options] [command] [prompt]

Arguments:
  prompt                         Your prompt

Options:
  --add-dir <directories...>     Additional directories
  -c, --continue                 Continue most recent conversation
  --model <model>                Model for session
  -p, --print                    Print response and exit
  -r, --resume [value]           Resume a conversation by session ID
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
  mcp                            Configure MCP servers
  plugin                         Manage plugins
HELP
        ;;
    "auth --help")
        cat << 'HELP'
Usage: claude auth [options] [command]

Options:
  -h, --help        Display help

Commands:
  login [options]   Sign in
  logout            Log out
  status [options]  Show authentication status
HELP
        ;;
    "mcp --help")
        cat << 'HELP'
Usage: claude mcp [options] [command]

Options:
  -h, --help                                     Display help

Commands:
  add [options] <name> <commandOrUrl> [args...]  Add an MCP server
  get <name>                                     Get MCP server details
  list                                           List MCP servers
  remove [options] <name>                        Remove an MCP server
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
  install|i [options] <plugin>         Install a plugin
  list [options]                       List installed plugins
  uninstall|remove [options] <plugin>  Uninstall a plugin
HELP
        ;;
esac
MOCK

    export PATH="$MOCK_BIN:$PATH"
    source_claude_bash
    _claude_build_cache
    CACHE_DIR="$(_claude_cache_dir)"
}

function tear_down_after_script() {
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN"
}

function test_root_flags_file_exists() {
    assert_file_exists "$CACHE_DIR/_root_flags"
}

function test_root_flags_contains_model() {
    assert_file_contains "$CACHE_DIR/_root_flags" "--model"
}

function test_root_flags_contains_short_print() {
    assert_file_contains "$CACHE_DIR/_root_flags" "-p"
}

function test_root_subcommands_file_exists() {
    assert_file_exists "$CACHE_DIR/_root_subcommands"
}

function test_root_subcommands_contains_auth() {
    assert_file_contains "$CACHE_DIR/_root_subcommands" "auth"
}

function test_root_subcommands_contains_mcp() {
    assert_file_contains "$CACHE_DIR/_root_subcommands" "mcp"
}

function test_flags_with_args_file_exists() {
    assert_file_exists "$CACHE_DIR/_root_flags_with_args"
}

function test_flags_with_args_contains_model() {
    assert_file_contains "$CACHE_DIR/_root_flags_with_args" "--model"
}

function test_flags_with_args_excludes_continue() {
    assert_file_not_contains "$CACHE_DIR/_root_flags_with_args" "--continue"
}

function test_mcp_subcommands_file_exists() {
    assert_file_exists "$CACHE_DIR/mcp_subcommands"
}

function test_mcp_subcommands_contains_add() {
    assert_file_contains "$CACHE_DIR/mcp_subcommands" "add"
}
