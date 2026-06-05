#!/usr/bin/env bash

# Tests that _claude_version memoizes its result per shell so that
# `claude --version` (a slow Node cold-start) is not spawned on every
# tab press. Invalidation is keyed on the claude binary's path + mtime.

function set_up_before_script() {
    source_claude_bash
}

function set_up() {
    MOCK_BIN="$(mktemp -d)"
    COUNTER="$MOCK_BIN/version_calls"
    export PATH="$MOCK_BIN:$PATH"
    export XDG_CACHE_HOME="$(mktemp -d)"
    # Reset per-shell memoization between tests.
    unset _CLAUDE_VERSION_CACHE _CLAUDE_VERSION_KEY
    _write_counting_mock "$MOCK_BIN"
}

function tear_down() {
    rm -rf "$MOCK_BIN" "$XDG_CACHE_HOME"
}

# A mock that records each `--version` invocation by appending a byte to
# the counter file, so tests can assert how many times it was spawned.
function _write_counting_mock() {
    local mock_bin="$1"
    write_mock_claude "$mock_bin" "$(cat <<BODY
case "\$*" in
    "--version")
        printf 'x' >> "$COUNTER"
        echo "1.0.0 (Claude Code)"
        ;;
    "--help") echo "Usage: claude [options]" ;;
esac
BODY
)"
}

function _version_call_count() {
    [[ -f "$COUNTER" ]] && wc -c < "$COUNTER" | tr -d ' ' || echo 0
}

function test_version_returns_parsed_value() {
    assert_same "1.0.0" "$(_claude_version)"
}

function test_version_invokes_claude_once() {
    _claude_version >/dev/null
    assert_same "1" "$(_version_call_count)"
}

function test_version_is_memoized_across_calls() {
    _claude_version >/dev/null
    _claude_version >/dev/null
    _claude_version >/dev/null
    assert_same "1" "$(_version_call_count)"
}

function test_version_reinvokes_when_binary_mtime_changes() {
    _claude_version >/dev/null
    assert_same "1" "$(_version_call_count)"
    # Simulate an upgrade: same path, newer mtime.
    touch -t 203012312359 "$MOCK_BIN/claude"
    _claude_version >/dev/null
    assert_same "2" "$(_version_call_count)"
}

# Regression: on GNU/Linux `stat -f %m` is invalid and exits non-zero.
# When _claude_mtime probes that form first, the failing assignment trips
# the `set -eE` + ERR-trap harness bashunit wraps around setup hooks,
# aborting every cache-building hook. _claude_mtime must tolerate a
# probe that fails and still return the mtime without aborting.
function test_mtime_tolerates_unsupported_stat_variant_under_errtrace() {
    local fake_bin; fake_bin="$(mktemp -d)"
    # Mimic GNU stat: reject BSD `-f`, honor `-c` with a fixed value.
    cat > "$fake_bin/stat" <<'STAT'
#!/bin/sh
[ "$1" = "-f" ] && exit 1
[ "$1" = "-c" ] && { echo 1700000000; exit 0; }
exit 2
STAT
    chmod +x "$fake_bin/stat"

    local out
    out="$(
        set -eE
        trap 'exit 99' ERR
        export PATH="$fake_bin:$PATH"
        _claude_mtime /any/file
    )"

    rm -rf "$fake_bin"
    assert_same "1700000000" "$out"
}
