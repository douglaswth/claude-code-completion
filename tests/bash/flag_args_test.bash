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
  --debug-file <file>            Debug output file
  --effort <level>               Effort level (low, medium, high)
  --input-format <format>        Input format (choices: "text", "stream-json")
  --model <model>                Model for session
  --output-format <format>       Output format (choices: "text", "json", "stream-json")
  --permission-mode <mode>       Permission mode (choices: "acceptEdits", "bypassPermissions", "default", "dontAsk", "plan")
  --plugin-dir <directory>       Plugin directory
  -p, --print                    Print response and exit
  -r, --resume [value]           Resume a conversation
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
  mcp                            Configure MCP servers
HELP
        ;;
    "auth --help") echo "Usage: claude auth" ;;
    "mcp --help") echo "Usage: claude mcp" ;;
esac
BODY
)"

    # Create a temp directory with known files and subdirs for completion tests
    COMP_DIR="$(mktemp -d)"
    mkdir -p "$COMP_DIR/subdir_one" "$COMP_DIR/subdir_two"
    touch "$COMP_DIR/file_alpha.txt" "$COMP_DIR/file_beta.log"

    export PATH="$MOCK_BIN:$PATH"
    source_claude_bash
}

function tear_down_after_script() {
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN" "$COMP_DIR"
}

function test_model_completes_aliases() {
    local result
    result="$(simulate_completion "claude --model ")"
    assert_contains "sonnet" "$result"
    assert_contains "opus" "$result"
    assert_contains "haiku" "$result"
}

function test_permission_mode_completes_choices() {
    local result
    result="$(simulate_completion "claude --permission-mode ")"
    assert_contains "default" "$result"
    assert_contains "plan" "$result"
}

function test_output_format_completes_choices() {
    local result
    result="$(simulate_completion "claude --output-format ")"
    assert_contains "text" "$result"
    assert_contains "json" "$result"
    assert_contains "stream-json" "$result"
}

function test_effort_completes_levels() {
    local result
    result="$(simulate_completion "claude --effort ")"
    assert_contains "low" "$result"
    assert_contains "medium" "$result"
    assert_contains "high" "$result"
}

function test_input_format_completes_choices() {
    local result
    result="$(simulate_completion "claude --input-format ")"
    assert_contains "text" "$result"
    assert_contains "stream-json" "$result"
}

function test_model_partial_input_filters() {
    local result
    result="$(simulate_completion "claude --model so")"
    assert_contains "sonnet" "$result"
    assert_not_contains "opus" "$result"
}

function test_add_dir_completes_directories() {
    local result
    result="$(simulate_completion "claude --add-dir $COMP_DIR/")"
    assert_contains "subdir_one" "$result"
    assert_contains "subdir_two" "$result"
    assert_not_contains "file_alpha" "$result"
}

function test_debug_file_completes_files() {
    local result
    result="$(simulate_completion "claude --debug-file $COMP_DIR/")"
    assert_contains "file_alpha.txt" "$result"
    assert_contains "file_beta.log" "$result"
}

function test_plugin_dir_completes_directories() {
    local result
    result="$(simulate_completion "claude --plugin-dir $COMP_DIR/")"
    assert_contains "subdir_one" "$result"
    assert_contains "subdir_two" "$result"
    assert_not_contains "file_alpha" "$result"
}
