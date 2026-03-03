#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }
skip() { echo "SKIP: $1"; }

export XDG_CACHE_HOME="$(mktemp -d)"
MOCK_BIN="$(mktemp -d)"
MOCK_HOME="$(mktemp -d)"
SESSION_DIR="$(mktemp -d)"
SHADOW_BASE="$(mktemp -d)"
trap 'rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN" "$MOCK_HOME" "$SESSION_DIR" "$SHADOW_BASE"' EXIT

# Create mock claude
cat > "$MOCK_BIN/claude" << 'MOCK'
#!/usr/bin/env bash
case "$*" in
    "--version") echo "1.0.0 (Claude Code)" ;;
    "--help") echo "Usage: claude [options]" ;;
    "plugin list --json")
        echo '[{"name":"superpowers","version":"1.0"},{"name":"my-plugin","version":"2.0"}]'
        ;;
esac
MOCK
chmod +x "$MOCK_BIN/claude"
export PATH="$MOCK_BIN:$PATH"

export HOME="$MOCK_HOME"

source "$SCRIPT_DIR/../claude.bash"

# --- Test data: session JSONL files ---

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

# --- Build a PATH with jq truly removed ---
# For each PATH directory containing jq, create a shadow directory with
# symlinks to everything except jq. This makes `command -v jq` fail.

NO_JQ_PATH=""
_shadow_idx=0
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

# --- Tests: _claude_session_message_jq ---

if command -v jq &>/dev/null; then
    result="$(_claude_session_message_jq "$SESSION_DIR/session1.jsonl")"
    if [[ "$result" == "Fix the login bug" ]]; then
        pass "_claude_session_message_jq extracts simple message"
    else
        fail "_claude_session_message_jq extracts simple message (got: '$result')"
    fi

    result="$(_claude_session_message_jq "$SESSION_DIR/session2.jsonl")"
    if [[ "$result" == "Add the new feature" ]]; then
        pass "_claude_session_message_jq skips IDE metadata"
    else
        fail "_claude_session_message_jq skips IDE metadata (got: '$result')"
    fi
else
    skip "_claude_session_message_jq extracts simple message (jq not installed)"
    skip "_claude_session_message_jq skips IDE metadata (jq not installed)"
fi

# --- Tests: _claude_session_message_grep ---

result="$(_claude_session_message_grep "$SESSION_DIR/session1.jsonl")"
if [[ "$result" == "Fix the login bug" ]]; then
    pass "_claude_session_message_grep extracts simple message"
else
    fail "_claude_session_message_grep extracts simple message (got: '$result')"
fi

result="$(_claude_session_message_grep "$SESSION_DIR/session2.jsonl")"
if [[ "$result" == "Add the new feature" ]]; then
    pass "_claude_session_message_grep skips IDE metadata"
else
    fail "_claude_session_message_grep skips IDE metadata (got: '$result')"
fi

# --- Tests: _claude_plugin_names with jq ---

if command -v jq &>/dev/null; then
    result="$(_claude_plugin_names)"
    if [[ "$result" == *"superpowers"* ]] && [[ "$result" == *"my-plugin"* ]]; then
        pass "_claude_plugin_names with jq returns plugin names"
    else
        fail "_claude_plugin_names with jq returns plugin names (got: '$result')"
    fi
else
    skip "_claude_plugin_names with jq (jq not installed)"
fi

# --- Tests: _claude_plugin_names without jq ---

OLD_PATH="$PATH"
PATH="$NO_JQ_PATH"

result="$(_claude_plugin_names)"

PATH="$OLD_PATH"

if [[ "$result" == *"superpowers"* ]] && [[ "$result" == *"my-plugin"* ]]; then
    pass "_claude_plugin_names without jq returns plugin names"
else
    fail "_claude_plugin_names without jq returns plugin names (got: '$result')"
fi

# --- Summary ---

if [[ $FAILURES -gt 0 ]]; then
    echo "$FAILURES test(s) failed"
    exit 1
else
    echo "All tests passed"
fi
