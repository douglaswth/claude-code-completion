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

    # Session 1: oldest
    cat > "$PROJ_DIR/aaaaaaaa-1111-1111-1111-111111111111.jsonl" << 'SESSION'
{"type":"queue-operation","timestamp":"2026-02-01T10:00:00.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Fix the login bug"}]},"timestamp":"2026-02-01T10:00:01.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"assistant","timestamp":"2026-02-01T10:00:05.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
SESSION
    touch -t 202602010000 "$PROJ_DIR/aaaaaaaa-1111-1111-1111-111111111111.jsonl"

    # Session 2: newer, with IDE metadata in first user message
    cat > "$PROJ_DIR/bbbbbbbb-2222-2222-2222-222222222222.jsonl" << 'SESSION'
{"type":"queue-operation","timestamp":"2026-03-01T15:00:00.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<ide_opened_file>Some IDE stuff</ide_opened_file>"}]},"timestamp":"2026-03-01T15:00:01.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Add the new feature"}]},"timestamp":"2026-03-01T15:00:02.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"assistant","timestamp":"2026-03-01T15:00:10.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
SESSION
    touch -t 202603010000 "$PROJ_DIR/bbbbbbbb-2222-2222-2222-222222222222.jsonl"

    # Session 3: no user message (only queue-operation and assistant)
    cat > "$PROJ_DIR/dddddddd-4444-4444-4444-444444444444.jsonl" << 'SESSION'
{"type":"queue-operation","timestamp":"2026-05-01T09:00:00.000Z","sessionId":"dddddddd-4444-4444-4444-444444444444"}
{"type":"assistant","timestamp":"2026-05-01T09:00:05.000Z","sessionId":"dddddddd-4444-4444-4444-444444444444"}
SESSION
    touch -t 202605010000 "$PROJ_DIR/dddddddd-4444-4444-4444-444444444444.jsonl"

    source_claude_bash

    # Override _claude_encoded_cwd to match our fake project
    eval '_claude_encoded_cwd() { echo "-home-user-myproject"; }'

    # Build a PATH with jq removed for fallback tests
    SHADOW_BASE="$(mktemp -d)"
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
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN" "$MOCK_HOME" "$SHADOW_BASE"
}

function test_complete_sessions_finds_all_sessions() {
    COMPREPLY=()
    _claude_complete_sessions ""
    assert_equals "3" "${#COMPREPLY[@]}"
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

function test_no_user_message_falls_back_to_session_label() {
    COMPREPLY=()
    _claude_complete_sessions ""
    local result="${COMPREPLY[*]}"
    assert_contains "(session)" "$result"
}

# --- End-to-end tests via simulate_completion ---

function test_e2e_resume_shows_sessions() {
    local result
    result="$(simulate_completion "claude --resume ")"
    assert_contains "aaaaaaaa-1111-1111-1111-111111111111" "$result"
    assert_contains "bbbbbbbb-2222-2222-2222-222222222222" "$result"
}

function test_e2e_resume_no_jq_shows_sessions() {
    if ! command -v jq &>/dev/null; then skip; return; fi
    local OLD_PATH="$PATH"
    PATH="$NO_JQ_PATH"
    local result
    result="$(simulate_completion "claude --resume ")"
    PATH="$OLD_PATH"
    assert_contains "aaaaaaaa-1111-1111-1111-111111111111" "$result"
    assert_contains "bbbbbbbb-2222-2222-2222-222222222222" "$result"
}

function test_e2e_resume_no_match_returns_empty() {
    local result
    result="$(simulate_completion "claude --resume zzz")"
    assert_empty "$result"
}
