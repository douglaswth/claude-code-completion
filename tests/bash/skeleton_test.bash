#!/usr/bin/env bash

function set_up_before_script() {
    complete -r claude 2>/dev/null || true
    source_claude_bash
}

function test_completion_registered_for_claude() {
    assert_successful_code "complete -p claude"
}

function test_claude_function_exists() {
    assert_successful_code "declare -F _claude"
}
