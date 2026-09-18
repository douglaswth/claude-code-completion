#!/usr/bin/env bash

# Core detection across platforms. _claude_cpu_count tries nproc, then
# sysctl (macOS/FreeBSD), then getconf, then $NUMBER_OF_PROCESSORS (Git
# Bash/Cygwin), and finally falls back to 1. Only the first branch runs on a
# GNU/Linux developer machine, so the rest are reached here by putting stub
# probes on PATH — the same approach fallbacks_test.bash uses to hide jq.
#
# These branches are not inert: a broken pattern would silently fall through
# to 1, and the only symptom would be a cache build running at concurrency 2
# on a many-core machine — slow, correct, and invisible.

function set_up() {
    STUB_BIN="$(mktemp -d)"
    ORIGINAL_PATH="$PATH"
    source_claude_bash
}

function tear_down() {
    PATH="$ORIGINAL_PATH"
    rm -rf "$STUB_BIN"
}

# Write an executable stub that prints $2 and exits $3 (default 0).
stub() {
    local name="$1" output="$2" code="${3:-0}"
    printf '#!/bin/sh\n%s\nexit %s\n' \
        "${output:+printf '%s\\n' '$output'}" "$code" > "$STUB_BIN/$name"
    chmod +x "$STUB_BIN/$name"
}

# Hide the real probes so only the stubs we install can answer.
isolate() {
    stub nproc "" 1
    stub sysctl "" 1
    stub getconf "" 1
    PATH="$STUB_BIN:$PATH"
}

function test_cpu_count_prefers_nproc() {
    isolate
    stub nproc 6
    assert_equals "6" "$(_claude_cpu_count)"
}

function test_cpu_count_falls_back_to_sysctl() {
    isolate
    stub sysctl 8
    assert_equals "8" "$(_claude_cpu_count)"
}

function test_cpu_count_falls_back_to_getconf() {
    isolate
    stub getconf 12
    assert_equals "12" "$(_claude_cpu_count)"
}

function test_cpu_count_falls_back_to_number_of_processors() {
    isolate
    export NUMBER_OF_PROCESSORS=4
    assert_equals "4" "$(_claude_cpu_count)"
    unset NUMBER_OF_PROCESSORS
}

function test_cpu_count_defaults_to_one_when_nothing_answers() {
    isolate
    unset NUMBER_OF_PROCESSORS
    assert_equals "1" "$(_claude_cpu_count)"
}

function test_cpu_count_ignores_non_numeric_output() {
    # A probe that prints a diagnostic instead of a number must not be
    # believed; the next probe answers.
    isolate
    stub nproc "nproc: failed to determine number of CPUs"
    stub sysctl 3
    assert_equals "3" "$(_claude_cpu_count)"
}
