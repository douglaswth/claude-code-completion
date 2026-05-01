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
  --add-dir <directories...>     Additional directories
  -c, --continue                 Continue most recent conversation
  --model <model>                Model for session
  -p, --print                    Print response and exit
  -r, --resume [value]           Resume a conversation
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
  doctor                         Check health of auto-updater
  mcp                            Configure MCP servers
HELP
        ;;
    "doctor --help")
        cat << 'HELP'
Usage: claude doctor [options]

Options:
  -h, --help        Display help
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
  status [options]  Show status
HELP
        ;;
    "mcp --help")
        cat << 'HELP'
Usage: claude mcp [options] [command]

Options:
  -h, --help        Display help

Commands:
  add [options] <name> <commandOrUrl> [args...]  Add server
  get <name>                                     Get server
  list                                           List servers
  remove [options] <name>                        Remove server
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

function test_bare_claude_shows_subcommands() {
    local result
    result="$(simulate_completion "claude ")"
    assert_contains "auth" "$result"
    assert_contains "mcp" "$result"
}

function test_bare_claude_does_not_show_flags() {
    local result
    result="$(simulate_completion "claude ")"
    assert_not_contains "--model" "$result"
}

function test_dash_shows_flags() {
    local result
    result="$(simulate_completion "claude -")"
    assert_contains "--model" "$result"
    assert_contains "-p" "$result"
}

function test_double_dash_shows_long_flags() {
    local result
    result="$(simulate_completion "claude --")"
    assert_contains "--model" "$result"
}

function test_partial_subcommand_completes() {
    local result
    result="$(simulate_completion "claude au")"
    assert_contains "auth" "$result"
}

function test_auth_subcommand_shows_auth_subcommands() {
    local result
    result="$(simulate_completion "claude auth ")"
    assert_contains "login" "$result"
    assert_contains "logout" "$result"
}

function test_mcp_subcommand_shows_mcp_subcommands() {
    local result
    result="$(simulate_completion "claude mcp ")"
    assert_contains "add" "$result"
    assert_contains "list" "$result"
}

function test_flag_completion_renders_descriptions_when_multiple_match() {
    # When multiple flags match, descriptions render via the Cobra/kubectl
    # `--flag    # description` formatter. Single-match case strips the
    # description for clean insertion (covered by existing single-match tests).
    local result
    result="$(simulate_completion "claude --")"
    # Several long flags match "--" in the mock; --model has description
    # "Model for session". The formatter renders "--model    # Model for session".
    assert_contains "Model for session" "$result"
}
