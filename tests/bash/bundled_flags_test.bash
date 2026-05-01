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
    _CLAUDE_EXTRA_FLAGS=()
}

function tear_down_after_script() {
    rm -rf "$MOCK_BIN"
}

function test_extra_flags_array_exists() {
    declare -p _CLAUDE_EXTRA_FLAGS &>/dev/null
    assert_successful_code "$?"
}

function test_extra_flags_is_indexed_array() {
    local attrs
    attrs="$(declare -p _CLAUDE_EXTRA_FLAGS 2>/dev/null)"
    assert_matches '^declare -a ' "$attrs"
}

function test_parse_extra_flag_record_splits_five_fields() {
    local rec=$'_root\t--foo\t1\tdir\tExample description'
    local scope name takes_arg arg_type desc
    _claude_parse_extra_flag_record "$rec" scope name takes_arg arg_type desc
    assert_equals "_root" "$scope"
    assert_equals "--foo" "$name"
    assert_equals "1" "$takes_arg"
    assert_equals "dir" "$arg_type"
    assert_equals "Example description" "$desc"
}

function test_parse_extra_flag_handles_choice_arg_type() {
    local rec=$'mcp\t--bar\t1\tchoice:a,b,c\tWith choices'
    local scope name takes_arg arg_type desc
    _claude_parse_extra_flag_record "$rec" scope name takes_arg arg_type desc
    assert_equals "choice:a,b,c" "$arg_type"
}

function test_parse_extra_flag_handles_takes_arg_zero() {
    local rec=$'_root\t--baz\t0\tnone\tBoolean flag'
    local scope name takes_arg arg_type desc
    _claude_parse_extra_flag_record "$rec" scope name takes_arg arg_type desc
    assert_equals "0" "$takes_arg"
    assert_equals "none" "$arg_type"
}

function test_parse_extra_flag_record_handles_empty_record() {
    local scope name takes_arg arg_type desc
    _claude_parse_extra_flag_record "" scope name takes_arg arg_type desc
    assert_equals "" "$scope"
    assert_equals "" "$name"
    assert_equals "" "$takes_arg"
    assert_equals "" "$arg_type"
    assert_equals "" "$desc"
}

function _setup_extra_flag() {
    # Inject one bundled flag entry for this test only.
    _CLAUDE_EXTRA_FLAGS=("$1")
}

function test_bundled_root_flag_appears_in_root_flags() {
    _setup_extra_flag $'_root\t--bundled-root\t0\tnone\tA bundled root flag'
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_contains "$cache_dir/_root_flags" "--bundled-root"
}

function test_bundled_subcommand_flag_appears_in_subcommand_flags_only() {
    _setup_extra_flag $'mcp\t--bundled-mcp\t0\tnone\tA bundled mcp flag'
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_contains "$cache_dir/mcp_flags" "--bundled-mcp"
    assert_file_not_contains "$cache_dir/_root_flags" "--bundled-mcp"
}

function test_bundled_flag_with_takes_arg_appears_in_flags_with_args() {
    _setup_extra_flag $'_root\t--bundled-arg\t1\tdir\tTakes a dir'
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_contains "$cache_dir/_root_flags_with_args" "--bundled-arg"
}

function test_bundled_flag_without_arg_not_in_flags_with_args() {
    _setup_extra_flag $'_root\t--bundled-bool\t0\tnone\tBoolean'
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_not_contains "$cache_dir/_root_flags_with_args" "--bundled-bool"
}

function test_bundled_flag_dedupes_against_help_derived_flag() {
    # --model is already in the mock --help output
    _setup_extra_flag $'_root\t--model\t1\tunknown\tStale bundled entry'
    _claude_build_cache
    local cache_dir count
    cache_dir="$(_claude_cache_dir)"
    count=$(grep -cFx -- "--model" "$cache_dir/_root_flags")
    assert_equals "1" "$count"
}

function test_bundled_description_appears_in_flag_descriptions() {
    _setup_extra_flag $'_root\t--bundled-desc\t0\tnone\tDescriptive text'
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_contains "$cache_dir/_root_flag_descriptions" "--bundled-desc"
    assert_file_contains "$cache_dir/_root_flag_descriptions" "Descriptive text"
}

function test_help_derived_flag_descriptions_present() {
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_contains "$cache_dir/_root_flag_descriptions" "--model"
    assert_file_contains "$cache_dir/_root_flag_descriptions" "Model for session"
}

function test_bundled_arg_type_dir_completes_directories() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    mkdir "$tmpdir/subdir"
    touch "$tmpdir/file.txt"
    cd "$tmpdir" || return
    _setup_extra_flag $'_root\t--my-dir\t1\tdir\tDir flag'
    local result
    result="$(simulate_completion "claude --my-dir ")"
    cd / && rm -rf "$tmpdir"
    assert_contains "subdir" "$result"
    assert_not_contains "file.txt" "$result"
}

function test_bundled_arg_type_choice_completes_options() {
    _setup_extra_flag $'_root\t--my-choice\t1\tchoice:alpha,beta,gamma\tChoice flag'
    local result
    result="$(simulate_completion "claude --my-choice ")"
    assert_contains "alpha" "$result"
    assert_contains "beta" "$result"
    assert_contains "gamma" "$result"
}

function test_bundled_arg_type_none_yields_no_value_completion() {
    _setup_extra_flag $'_root\t--my-bool\t0\tnone\tBoolean flag'
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_not_contains "$cache_dir/_root_flags_with_args" "--my-bool"
}

function test_bundled_arg_type_unknown_falls_back_to_file_completion() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    touch "$tmpdir/somefile"
    cd "$tmpdir" || return
    _setup_extra_flag $'_root\t--my-mystery\t1\tunknown\tMystery flag'
    local result
    result="$(simulate_completion "claude --my-mystery ")"
    cd / && rm -rf "$tmpdir"
    assert_contains "somefile" "$result"
}
