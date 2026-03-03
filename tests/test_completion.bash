#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

export XDG_CACHE_HOME="$(mktemp -d)"
MOCK_BIN="$(mktemp -d)"
trap 'rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN"' EXIT

# Create mock claude (same as Task 3)
cat > "$MOCK_BIN/claude" << 'MOCK'
#!/usr/bin/env bash
case "$*" in
    "--version") echo "1.0.0 (Claude Code)" ;;
    "--help")
        cat << 'HELP'
Usage: claude [options] [command] [prompt]

Options:
  --add-dir <directories...>     Additional directories
  -c, --continue                 Continue most recent conversation
  --model <model>                Model for session
  -p, --print                    Print response and exit
  -r, --resume [value]           Resume a conversation
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
  mcp                            Configure MCP servers
HELP
        ;;
    "auth --help")
        cat << 'HELP'
Usage: claude auth [options] [command]

Options:
  -h, --help        Display help

Commands:
  login [options]   Sign in
  logout            Log out
  status [options]  Show status
HELP
        ;;
    "mcp --help")
        cat << 'HELP'
Usage: claude mcp [options] [command]

Options:
  -h, --help        Display help

Commands:
  add [options] <name> <commandOrUrl> [args...]  Add server
  get <name>                                     Get server
  list                                           List servers
  remove [options] <name>                        Remove server
HELP
        ;;
esac
MOCK
chmod +x "$MOCK_BIN/claude"
export PATH="$MOCK_BIN:$PATH"

source "$SCRIPT_DIR/../claude.bash"

# Helper to simulate completion
_simulate_completion() {
    # Usage: _simulate_completion "claude mcp " (cursor at end)
    local cmdline="$1"
    COMP_LINE="$cmdline"
    COMP_POINT=${#cmdline}
    # Split into words
    read -ra COMP_WORDS <<< "$cmdline"
    # If line ends with space, we're completing a new word
    if [[ "$cmdline" == *" " ]]; then
        COMP_WORDS+=("")
    fi
    COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
    COMPREPLY=()
    _claude
    echo "${COMPREPLY[*]}"
}

# Test: "claude " shows subcommands (not flags)
result="$(_simulate_completion "claude ")"
if [[ "$result" == *"auth"* ]] && [[ "$result" == *"mcp"* ]]; then
    pass "'claude ' completes subcommands"
else
    fail "'claude ' completes subcommands (got: $result)"
fi
if [[ "$result" != *"--model"* ]]; then
    pass "'claude ' does not show flags"
else
    fail "'claude ' does not show flags (got: $result)"
fi

# Test: "claude -" shows flags
result="$(_simulate_completion "claude -")"
if [[ "$result" == *"--model"* ]] && [[ "$result" == *"-p"* ]]; then
    pass "'claude -' completes flags"
else
    fail "'claude -' completes flags (got: $result)"
fi

# Test: "claude --" shows long flags
result="$(_simulate_completion "claude --")"
if [[ "$result" == *"--model"* ]]; then
    pass "'claude --' completes long flags"
else
    fail "'claude --' completes long flags (got: $result)"
fi

# Test: "claude au" completes to auth
result="$(_simulate_completion "claude au")"
if [[ "$result" == *"auth"* ]]; then
    pass "'claude au' completes to auth"
else
    fail "'claude au' completes to auth (got: $result)"
fi

# Test: "claude auth " shows auth subcommands
result="$(_simulate_completion "claude auth ")"
if [[ "$result" == *"login"* ]] && [[ "$result" == *"logout"* ]]; then
    pass "'claude auth ' completes auth subcommands"
else
    fail "'claude auth ' completes auth subcommands (got: $result)"
fi

# Test: "claude mcp " shows mcp subcommands
result="$(_simulate_completion "claude mcp ")"
if [[ "$result" == *"add"* ]] && [[ "$result" == *"list"* ]]; then
    pass "'claude mcp ' completes mcp subcommands"
else
    fail "'claude mcp ' completes mcp subcommands (got: $result)"
fi

if [[ $FAILURES -gt 0 ]]; then
    echo "$FAILURES test(s) failed"
    exit 1
else
    echo "All tests passed"
fi
