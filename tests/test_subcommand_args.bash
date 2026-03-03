#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

export XDG_CACHE_HOME="$(mktemp -d)"
MOCK_BIN="$(mktemp -d)"
trap 'rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN"' EXIT

# Create mock claude with mcp list and plugin list output
cat > "$MOCK_BIN/claude" << 'MOCK'
#!/usr/bin/env bash
case "$*" in
    "--version") echo "1.0.0 (Claude Code)" ;;
    "--help")
        cat << 'HELP'
Usage: claude [options] [command] [prompt]

Options:
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  mcp                            Configure MCP servers
  plugin                         Manage plugins
HELP
        ;;
    "mcp --help")
        cat << 'HELP'
Usage: claude mcp [options] [command]

Options:
  -h, --help                                     Display help

Commands:
  get <name>                                     Get server
  list                                           List servers
  remove [options] <name>                        Remove server
HELP
        ;;
    "plugin --help")
        cat << 'HELP'
Usage: claude plugin [options] [command]

Options:
  -h, --help                           Display help

Commands:
  disable [options] [plugin]           Disable a plugin
  enable [options] <plugin>            Enable a plugin
  list [options]                       List installed plugins
  uninstall|remove [options] <plugin>  Uninstall a plugin
HELP
        ;;
    "mcp list")
        cat << 'OUTPUT'
Checking MCP server health...

my-sentry: https://mcp.sentry.dev/mcp - ✓ Connected
my-github: /usr/bin/gh-mcp (stdio) - ✓ Connected
OUTPUT
        ;;
    "plugin list --json")
        cat << 'OUTPUT'
[{"name":"superpowers","version":"4.3.1","enabled":true},{"name":"my-plugin","version":"1.0.0","enabled":false}]
OUTPUT
        ;;
esac
MOCK
chmod +x "$MOCK_BIN/claude"
export PATH="$MOCK_BIN:$PATH"

source "$SCRIPT_DIR/../claude.bash"

_simulate_completion() {
    local cmdline="$1"
    COMP_LINE="$cmdline"
    COMP_POINT=${#cmdline}
    read -ra COMP_WORDS <<< "$cmdline"
    if [[ "$cmdline" == *" " ]]; then
        COMP_WORDS+=("")
    fi
    COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
    COMPREPLY=()
    _claude
    echo "${COMPREPLY[*]}"
}

# Test: "claude mcp get " completes MCP server names
result="$(_simulate_completion "claude mcp get ")"
if [[ "$result" == *"my-sentry"* ]] && [[ "$result" == *"my-github"* ]]; then
    pass "'claude mcp get ' completes server names"
else
    fail "'claude mcp get ' completes server names (got: $result)"
fi

# Test: "claude mcp remove " completes MCP server names
result="$(_simulate_completion "claude mcp remove ")"
if [[ "$result" == *"my-sentry"* ]]; then
    pass "'claude mcp remove ' completes server names"
else
    fail "'claude mcp remove ' completes server names (got: $result)"
fi

# Test: "claude plugin disable " completes plugin names
result="$(_simulate_completion "claude plugin disable ")"
if [[ "$result" == *"superpowers"* ]] && [[ "$result" == *"my-plugin"* ]]; then
    pass "'claude plugin disable ' completes plugin names"
else
    fail "'claude plugin disable ' completes plugin names (got: $result)"
fi

# Test: "claude plugin enable " completes plugin names
result="$(_simulate_completion "claude plugin enable ")"
if [[ "$result" == *"superpowers"* ]]; then
    pass "'claude plugin enable ' completes plugin names"
else
    fail "'claude plugin enable ' completes plugin names (got: $result)"
fi

# Test: "claude plugin uninstall " completes plugin names
result="$(_simulate_completion "claude plugin uninstall ")"
if [[ "$result" == *"superpowers"* ]]; then
    pass "'claude plugin uninstall ' completes plugin names"
else
    fail "'claude plugin uninstall ' completes plugin names (got: $result)"
fi

if [[ $FAILURES -gt 0 ]]; then
    echo "$FAILURES test(s) failed"
    exit 1
else
    echo "All tests passed"
fi
