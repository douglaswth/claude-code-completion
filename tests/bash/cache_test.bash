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

function test_cache_dir_returns_correct_path_prefix() {
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_contains "$XDG_CACHE_HOME/claude-code-completion/bash/" "$cache_dir"
}

function test_cache_dir_falls_back_to_home_cache_when_xdg_unset() {
    unset XDG_CACHE_HOME
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_contains "$HOME/.cache/claude-code-completion/bash/" "$cache_dir"
}

function test_cache_dir_includes_version_component() {
    local cache_dir version_part
    cache_dir="$(_claude_cache_dir)"
    version_part="${cache_dir#"$XDG_CACHE_HOME/claude-code-completion/bash/"}"
    assert_not_empty "$version_part"
}

function test_ensure_cache_creates_directory() {
    _claude_ensure_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_directory_exists "$cache_dir"
}

function test_cleanup_old_cache_removes_old_versions() {
    _claude_ensure_cache
    local base_dir="$XDG_CACHE_HOME/claude-code-completion/bash"
    mkdir -p "$base_dir/0.9.0-c1" "$base_dir/0.8.0-c1"
    _claude_cleanup_old_cache
    assert_directory_not_exists "$base_dir/0.9.0-c1"
    assert_directory_not_exists "$base_dir/0.8.0-c1"
}

function test_cleanup_old_cache_preserves_current_version() {
    _claude_ensure_cache
    local cache_dir base_dir
    cache_dir="$(_claude_cache_dir)"
    base_dir="$XDG_CACHE_HOME/claude-code-completion/bash"
    mkdir -p "$base_dir/0.9.0"
    _claude_cleanup_old_cache
    assert_directory_exists "$cache_dir"
}

# --- Build cache tests ---

function test_build_cache_creates_root_flags_file() {
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_exists "$cache_dir/_root_flags"
}

function test_build_cache_root_flags_contains_model() {
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_contains "$cache_dir/_root_flags" "--model"
}

function test_build_cache_creates_root_subcommands_file() {
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_exists "$cache_dir/_root_subcommands"
}

function test_build_cache_root_subcommands_contains_doctor() {
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_contains "$cache_dir/_root_subcommands" "doctor"
}

function test_build_cache_creates_doctor_flags_file() {
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_exists "$cache_dir/doctor_flags"
}

function test_build_cache_creates_doctor_flags_with_args_file() {
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_exists "$cache_dir/doctor_flags_with_args"
}

function test_build_cache_creates_doctor_subcommands_file() {
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_exists "$cache_dir/doctor_subcommands"
}

function test_cache_dir_includes_schema_version_suffix() {
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    # Expected format: <base>/bash/<cli-version>-c<schema-version>
    local last_segment="${cache_dir##*/}"
    assert_matches '^[0-9]+\.[0-9]+\.[0-9]+-c[0-9]+$' "$last_segment"
}

function test_cleanup_old_cache_removes_old_schema_version() {
    _claude_ensure_cache
    local base_dir="$XDG_CACHE_HOME/claude-code-completion/bash"
    # Same CLI version, different schema version
    mkdir -p "$base_dir/1.0.0-c0"
    _claude_cleanup_old_cache
    assert_directory_not_exists "$base_dir/1.0.0-c0"
}

function test_cleanup_old_cache_removes_pre_schema_directories() {
    _claude_ensure_cache
    local base_dir="$XDG_CACHE_HOME/claude-code-completion/bash"
    # Old format with no -cN suffix
    mkdir -p "$base_dir/1.0.0"
    _claude_cleanup_old_cache
    assert_directory_not_exists "$base_dir/1.0.0"
}
