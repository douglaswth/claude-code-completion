#!/usr/bin/env bash

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    MOCK_HOME="$(mktemp -d)"
    SESSION_DIR="$(mktemp -d)"
    SHADOW_BASE="$(mktemp -d)"
    export XDG_CACHE_HOME="$(mktemp -d)"

    write_mock_claude "$MOCK_BIN" "$(cat <<'BODY'
case "$*" in
    "--version") echo "1.0.0 (Claude Code)" ;;
    "--help") echo "Usage: claude [options]" ;;
    "plugin list --json")
        echo '[{"name":"superpowers","version":"1.0"},{"name":"my-plugin","version":"2.0"}]'
        ;;
esac
BODY
)"

    export PATH="$MOCK_BIN:$PATH"
    export HOME="$MOCK_HOME"
    source_claude_bash

    # Session 1: simple user message
    cat > "$SESSION_DIR/session1.jsonl" << 'SESSION'
{"type":"queue-operation","timestamp":"2026-02-01T10:00:00.000Z","sessionId":"aaa"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Fix the login bug"}]},"timestamp":"2026-02-01T10:00:01.000Z","sessionId":"aaa"}
{"type":"assistant","timestamp":"2026-02-01T10:00:05.000Z","sessionId":"aaa"}
SESSION

    # Session 2: first user message has IDE metadata, second is real
    cat > "$SESSION_DIR/session2.jsonl" << 'SESSION'
{"type":"queue-operation","timestamp":"2026-03-01T15:00:00.000Z","sessionId":"bbb"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<ide_opened_file>Some IDE stuff</ide_opened_file>"}]},"timestamp":"2026-03-01T15:00:01.000Z","sessionId":"bbb"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Add the new feature"}]},"timestamp":"2026-03-01T15:00:02.000Z","sessionId":"bbb"}
{"type":"assistant","timestamp":"2026-03-01T15:00:10.000Z","sessionId":"bbb"}
SESSION

    # Build a PATH with jq removed for fallback tests
    NO_JQ_PATH=""
    local _shadow_idx=0
    local _path_dirs _dir _shadow _f _name
    IFS=':' read -ra _path_dirs <<< "$PATH"
    for _dir in "${_path_dirs[@]}"; do
        [[ -z "$_dir" ]] && continue
        if [[ -x "$_dir/jq" ]]; then
            _shadow="$SHADOW_BASE/s${_shadow_idx}"
            _shadow_idx=$((_shadow_idx + 1))
            mkdir -p "$_shadow"
            for _f in "$_dir"/*; do
                [[ -e "$_f" ]] || continue
                _name="${_f##*/}"
                [[ "$_name" == "jq" ]] && continue
                ln -sf "$_f" "$_shadow/$_name" 2>/dev/null || true
            done
            NO_JQ_PATH="${NO_JQ_PATH:+$NO_JQ_PATH:}$_shadow"
        else
            NO_JQ_PATH="${NO_JQ_PATH:+$NO_JQ_PATH:}$_dir"
        fi
    done
}

function tear_down_after_script() {
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN" "$MOCK_HOME" "$SESSION_DIR" "$SHADOW_BASE"
}

# --- jq path tests (skip if jq not installed) ---

function test_session_message_jq_extracts_simple_message() {
    if ! command -v jq &>/dev/null; then skip; return; fi
    local result
    result="$(_claude_session_message_jq "$SESSION_DIR/session1.jsonl")"
    assert_same "Fix the login bug" "$result"
}

function test_session_message_jq_skips_ide_metadata() {
    if ! command -v jq &>/dev/null; then skip; return; fi
    local result
    result="$(_claude_session_message_jq "$SESSION_DIR/session2.jsonl")"
    assert_same "Add the new feature" "$result"
}

# --- grep fallback tests ---

function test_session_message_grep_extracts_simple_message() {
    local result
    result="$(_claude_session_message_grep "$SESSION_DIR/session1.jsonl")"
    assert_same "Fix the login bug" "$result"
}

function test_session_message_grep_skips_ide_metadata() {
    local result
    result="$(_claude_session_message_grep "$SESSION_DIR/session2.jsonl")"
    assert_same "Add the new feature" "$result"
}

# --- plugin names with jq ---

function test_plugin_names_with_jq() {
    if ! command -v jq &>/dev/null; then skip; return; fi
    local result
    result="$(_claude_plugin_names)"
    assert_contains "superpowers" "$result"
    assert_contains "my-plugin" "$result"
}

# --- plugin names without jq ---

function test_plugin_names_without_jq() {
    local OLD_PATH="$PATH"
    PATH="$NO_JQ_PATH"
    local result
    result="$(_claude_plugin_names)"
    PATH="$OLD_PATH"
    assert_contains "superpowers" "$result"
    assert_contains "my-plugin" "$result"
}
