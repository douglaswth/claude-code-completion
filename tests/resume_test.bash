#!/usr/bin/env bash

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    MOCK_HOME="$(mktemp -d)"
    export XDG_CACHE_HOME="$(mktemp -d)"

    create_mock_claude "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"
    export HOME="$MOCK_HOME"

    # Create fake session files for a project at /home/user/myproject
    PROJ_DIR="$MOCK_HOME/.claude/projects/-home-user-myproject"
    mkdir -p "$PROJ_DIR"

    # Session 1: older
    cat > "$PROJ_DIR/aaaaaaaa-1111-1111-1111-111111111111.jsonl" << 'SESSION'
{"type":"queue-operation","timestamp":"2026-02-01T10:00:00.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Fix the login bug"}]},"timestamp":"2026-02-01T10:00:01.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"assistant","timestamp":"2026-02-01T10:00:05.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
SESSION

    # Session 2: newer (sleep 1 to ensure different mtime)
    sleep 1
    cat > "$PROJ_DIR/bbbbbbbb-2222-2222-2222-222222222222.jsonl" << 'SESSION'
{"type":"queue-operation","timestamp":"2026-03-01T15:00:00.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<ide_opened_file>Some IDE stuff</ide_opened_file>"}]},"timestamp":"2026-03-01T15:00:01.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Add the new feature"}]},"timestamp":"2026-03-01T15:00:02.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"assistant","timestamp":"2026-03-01T15:00:10.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
SESSION

    source_claude_bash

    # Override _claude_encoded_cwd to match our fake project
    eval '_claude_encoded_cwd() { echo "-home-user-myproject"; }'
}

function tear_down_after_script() {
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN" "$MOCK_HOME"
}

function test_complete_sessions_finds_both_sessions() {
    COMPREPLY=()
    _claude_complete_sessions ""
    assert_equals "2" "${#COMPREPLY[@]}"
}

function test_session_1_uuid_present() {
    COMPREPLY=()
    _claude_complete_sessions ""
    local result="${COMPREPLY[*]}"
    assert_contains "aaaaaaaa-1111-1111-1111-111111111111" "$result"
}

function test_session_2_uuid_present() {
    COMPREPLY=()
    _claude_complete_sessions ""
    local result="${COMPREPLY[*]}"
    assert_contains "bbbbbbbb-2222-2222-2222-222222222222" "$result"
}

function test_partial_uuid_filters() {
    COMPREPLY=()
    _claude_complete_sessions "aaa"
    assert_equals "1" "${#COMPREPLY[@]}"
}
