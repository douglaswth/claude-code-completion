#!/usr/bin/env bash

# --- Shared test infrastructure for bashunit ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create a minimal mock claude command in the given directory.
# Writes a script that handles --version and a basic --help.
#
# Usage:
#   create_mock_claude "$MOCK_BIN"
create_mock_claude() {
    local mock_bin="$1"
    cat > "$mock_bin/claude" << 'MOCK'
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
    *) ;;
esac
MOCK
    chmod +x "$mock_bin/claude"
}

# Replace the mock claude with a custom script body.
# Usage: write_mock_claude "$MOCK_BIN" "$(cat <<'BODY' ... BODY)"
write_mock_claude() {
    local mock_bin="$1"
    local body="$2"
    cat > "$mock_bin/claude" << MOCK
#!/usr/bin/env bash
$body
MOCK
    chmod +x "$mock_bin/claude"
}

# Simulate tab completion for a given command line.
# Sets up COMP_* variables, calls _claude, returns COMPREPLY joined by spaces.
# Usage: result="$(simulate_completion "claude --model ")"
simulate_completion() {
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

# Source the completion script from the project root.
source_claude_bash() {
    source "$PROJECT_ROOT/claude.bash"
}

export SCRIPT_DIR PROJECT_ROOT
export -f create_mock_claude write_mock_claude simulate_completion source_claude_bash
