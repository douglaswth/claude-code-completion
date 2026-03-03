#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

export XDG_CACHE_HOME="$(mktemp -d)"
MOCK_BIN="$(mktemp -d)"
trap 'rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN"' EXIT

# Create mock claude command
cat > "$MOCK_BIN/claude" << 'MOCK'
#!/usr/bin/env bash
case "$*" in
    "--version")
        echo "1.0.0 (Claude Code)"
        ;;
    "--help")
        cat << 'HELP'
Usage: claude [options] [command] [prompt]

Arguments:
  prompt                         Your prompt

Options:
  --add-dir <directories...>     Additional directories
  -c, --continue                 Continue most recent conversation
  --model <model>                Model for session
  -p, --print                    Print response and exit
  -r, --resume [value]           Resume a conversation by session ID
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
  mcp                            Configure MCP servers
  plugin                         Manage plugins
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
  status [options]  Show authentication status
HELP
        ;;
    "mcp --help")
        cat << 'HELP'
Usage: claude mcp [options] [command]

Options:
  -h, --help                                     Display help

Commands:
  add [options] <name> <commandOrUrl> [args...]  Add an MCP server
  get <name>                                     Get MCP server details
  list                                           List MCP servers
  remove [options] <name>                        Remove an MCP server
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
  install|i [options] <plugin>         Install a plugin
  list [options]                       List installed plugins
  uninstall|remove [options] <plugin>  Uninstall a plugin
HELP
        ;;
esac
MOCK
chmod +x "$MOCK_BIN/claude"
export PATH="$MOCK_BIN:$PATH"

source "$SCRIPT_DIR/../claude.bash"

# Build the cache
_claude_build_cache

cache_dir="$(_claude_cache_dir)"

# Test: root flags file exists and contains expected flags
if [[ -f "$cache_dir/_root_flags" ]]; then
    pass "root flags file created"
else
    fail "root flags file created"
fi

if grep -q "^--model$" "$cache_dir/_root_flags"; then
    pass "root flags contains --model"
else
    fail "root flags contains --model"
fi

if grep -q "^-p$" "$cache_dir/_root_flags"; then
    pass "root flags contains -p"
else
    fail "root flags contains -p"
fi

# Test: root subcommands file exists and contains expected subcommands
if [[ -f "$cache_dir/_root_subcommands" ]]; then
    pass "root subcommands file created"
else
    fail "root subcommands file created"
fi

if grep -q "^auth$" "$cache_dir/_root_subcommands"; then
    pass "root subcommands contains auth"
else
    fail "root subcommands contains auth"
fi

if grep -q "^mcp$" "$cache_dir/_root_subcommands"; then
    pass "root subcommands contains mcp"
else
    fail "root subcommands contains mcp"
fi

# Test: flags-with-args file tracks which flags take arguments
if [[ -f "$cache_dir/_root_flags_with_args" ]]; then
    pass "root flags_with_args file created"
else
    fail "root flags_with_args file created"
fi

if grep -q "^--model$" "$cache_dir/_root_flags_with_args"; then
    pass "flags_with_args contains --model"
else
    fail "flags_with_args contains --model"
fi

# --continue is boolean, should NOT be in flags_with_args
if grep -q "^--continue$" "$cache_dir/_root_flags_with_args"; then
    fail "--continue should not be in flags_with_args"
else
    pass "--continue is not in flags_with_args"
fi

# Test: subcommand flags parsed
if [[ -f "$cache_dir/mcp_subcommands" ]]; then
    pass "mcp subcommands file created"
else
    fail "mcp subcommands file created"
fi

if grep -q "^add$" "$cache_dir/mcp_subcommands"; then
    pass "mcp subcommands contains add"
else
    fail "mcp subcommands contains add"
fi

if [[ $FAILURES -gt 0 ]]; then
    echo "$FAILURES test(s) failed"
    exit 1
else
    echo "All tests passed"
fi
