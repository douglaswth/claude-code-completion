#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

export XDG_CACHE_HOME="$(mktemp -d)"
MOCK_BIN="$(mktemp -d)"
MOCK_HOME="$(mktemp -d)"
trap "rm -rf $XDG_CACHE_HOME $MOCK_BIN $MOCK_HOME" EXIT

# Create mock claude
cat > "$MOCK_BIN/claude" << 'MOCK'
#!/usr/bin/env bash
case "$*" in
    "--version") echo "1.0.0 (Claude Code)" ;;
    "--help")
        cat << 'HELP'
Usage: claude [options] [command] [prompt]

Options:
  --model <model>                Model for session
  -r, --resume [value]           Resume a conversation
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
HELP
        ;;
    "auth --help") echo "Usage: claude auth" ;;
esac
MOCK
chmod +x "$MOCK_BIN/claude"
export PATH="$MOCK_BIN:$PATH"

# Create fake session files for a project at /home/user/myproject
export HOME="$MOCK_HOME"
PROJ_DIR="$MOCK_HOME/.claude/projects/-home-user-myproject"
mkdir -p "$PROJ_DIR"

# Session 1: older
cat > "$PROJ_DIR/aaaaaaaa-1111-1111-1111-111111111111.jsonl" << 'SESSION'
{"type":"queue-operation","timestamp":"2026-02-01T10:00:00.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Fix the login bug"}]},"timestamp":"2026-02-01T10:00:01.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"assistant","timestamp":"2026-02-01T10:00:05.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
SESSION

# Session 2: newer
sleep 1
cat > "$PROJ_DIR/bbbbbbbb-2222-2222-2222-222222222222.jsonl" << 'SESSION'
{"type":"queue-operation","timestamp":"2026-03-01T15:00:00.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<ide_opened_file>Some IDE stuff</ide_opened_file>"}]},"timestamp":"2026-03-01T15:00:01.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Add the new feature"}]},"timestamp":"2026-03-01T15:00:02.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"assistant","timestamp":"2026-03-01T15:00:10.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
SESSION

source "$SCRIPT_DIR/../claude.bash"

# Override PWD to match our fake project
cd /home/user/myproject 2>/dev/null || {
    # Can't cd there, so override the function
    eval '_claude_encoded_cwd() { echo "-home-user-myproject"; }'
}

# Test: _claude_complete_sessions produces session IDs
COMPREPLY=()
_claude_complete_sessions ""
if [[ ${#COMPREPLY[@]} -eq 2 ]]; then
    pass "found 2 sessions"
else
    fail "found 2 sessions (got ${#COMPREPLY[@]})"
fi

# Test: both UUIDs are present
result="${COMPREPLY[*]}"
if [[ "$result" == *"aaaaaaaa-1111-1111-1111-111111111111"* ]]; then
    pass "session 1 UUID present"
else
    fail "session 1 UUID present (got: $result)"
fi
if [[ "$result" == *"bbbbbbbb-2222-2222-2222-222222222222"* ]]; then
    pass "session 2 UUID present"
else
    fail "session 2 UUID present (got: $result)"
fi

# Test: partial UUID filters
COMPREPLY=()
_claude_complete_sessions "aaa"
if [[ ${#COMPREPLY[@]} -eq 1 ]]; then
    pass "partial UUID 'aaa' matches 1 session"
else
    fail "partial UUID 'aaa' matches 1 session (got ${#COMPREPLY[@]})"
fi

if [[ $FAILURES -gt 0 ]]; then
    echo "$FAILURES test(s) failed"
    exit 1
else
    echo "All tests passed"
fi
