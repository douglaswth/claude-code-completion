#!/usr/bin/env bash

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    create_mock_claude "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"
    source_claude_bash
}

function set_up() {
    export XDG_CACHE_HOME="$(mktemp -d)"
}

function tear_down() {
    rm -rf "$XDG_CACHE_HOME"
}

function tear_down_after_script() {
    rm -rf "$MOCK_BIN"
}

function test_extra_flags_array_exists() {
    declare -p _CLAUDE_EXTRA_FLAGS &>/dev/null
    assert_successful_code "$?"
}

function test_parse_extra_flag_record_splits_five_fields() {
    local rec=$'_root\t--foo\t1\tdir\tExample description'
    local scope name takes_arg arg_type desc
    _claude_parse_extra_flag "$rec" scope name takes_arg arg_type desc
    assert_equals "_root" "$scope"
    assert_equals "--foo" "$name"
    assert_equals "1" "$takes_arg"
    assert_equals "dir" "$arg_type"
    assert_equals "Example description" "$desc"
}

function test_parse_extra_flag_handles_choice_arg_type() {
    local rec=$'mcp\t--bar\t1\tchoice:a,b,c\tWith choices'
    local scope name takes_arg arg_type desc
    _claude_parse_extra_flag "$rec" scope name takes_arg arg_type desc
    assert_equals "choice:a,b,c" "$arg_type"
}

function test_parse_extra_flag_handles_takes_arg_zero() {
    local rec=$'_root\t--baz\t0\tnone\tBoolean flag'
    local scope name takes_arg arg_type desc
    _claude_parse_extra_flag "$rec" scope name takes_arg arg_type desc
    assert_equals "0" "$takes_arg"
    assert_equals "none" "$arg_type"
}
