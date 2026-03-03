#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

export XDG_CACHE_HOME="$(mktemp -d)"
MOCK_BIN="$(mktemp -d)"
trap 'rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN"' EXIT

# Reuse mock claude from previous tasks
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
  --effort <level>               Effort level (low, medium, high)
  --input-format <format>        Input format (choices: "text", "stream-json")
  --model <model>                Model for session
  --output-format <format>       Output format (choices: "text", "json", "stream-json")
  --permission-mode <mode>       Permission mode (choices: "acceptEdits", "bypassPermissions", "default", "dontAsk", "plan")
  -p, --print                    Print response and exit
  -r, --resume [value]           Resume a conversation
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
  mcp                            Configure MCP servers
HELP
        ;;
    "auth --help") echo "Usage: claude auth" ;;
    "mcp --help") echo "Usage: claude mcp" ;;
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

# Test: --model completes model names
result="$(_simulate_completion "claude --model ")"
if [[ "$result" == *"sonnet"* ]] && [[ "$result" == *"opus"* ]] && [[ "$result" == *"haiku"* ]]; then
    pass "'--model ' completes model aliases"
else
    fail "'--model ' completes model aliases (got: $result)"
fi

# Test: --permission-mode completes choices
result="$(_simulate_completion "claude --permission-mode ")"
if [[ "$result" == *"default"* ]] && [[ "$result" == *"plan"* ]]; then
    pass "'--permission-mode ' completes choices"
else
    fail "'--permission-mode ' completes choices (got: $result)"
fi

# Test: --output-format completes choices
result="$(_simulate_completion "claude --output-format ")"
if [[ "$result" == *"text"* ]] && [[ "$result" == *"json"* ]] && [[ "$result" == *"stream-json"* ]]; then
    pass "'--output-format ' completes choices"
else
    fail "'--output-format ' completes choices (got: $result)"
fi

# Test: --effort completes levels
result="$(_simulate_completion "claude --effort ")"
if [[ "$result" == *"low"* ]] && [[ "$result" == *"medium"* ]] && [[ "$result" == *"high"* ]]; then
    pass "'--effort ' completes levels"
else
    fail "'--effort ' completes levels (got: $result)"
fi

# Test: --input-format completes choices
result="$(_simulate_completion "claude --input-format ")"
if [[ "$result" == *"text"* ]] && [[ "$result" == *"stream-json"* ]]; then
    pass "'--input-format ' completes choices"
else
    fail "'--input-format ' completes choices (got: $result)"
fi

# Test: --model with partial input filters
result="$(_simulate_completion "claude --model so")"
if [[ "$result" == *"sonnet"* ]] && [[ "$result" != *"opus"* ]]; then
    pass "'--model so' filters to sonnet"
else
    fail "'--model so' filters to sonnet (got: $result)"
fi

if [[ $FAILURES -gt 0 ]]; then
    echo "$FAILURES test(s) failed"
    exit 1
else
    echo "All tests passed"
fi
