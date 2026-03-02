# Bash Completion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a bash completion script for the `claude` CLI that dynamically parses help output with version-based caching, provides smart completions for flags like `--model` and `--resume`, and completes subcommand-specific arguments.

**Architecture:** Single file `claude.bash` containing all completion logic. A main `_claude` function dispatches to helper functions for caching, help parsing, flag-argument completion, and session lookup. Registered via `complete -F _claude claude`.

**Tech Stack:** Bash, grep, sed, awk, optional jq

---

### Task 1: Script skeleton and registration

**Files:**
- Create: `claude.bash`
- Create: `tests/test_skeleton.bash`

**Step 1: Write the failing test**

Create `tests/test_skeleton.bash` using a simple test harness (plain bash assertions). Test that sourcing `claude.bash` registers the completion:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

# Test: sourcing registers completion for claude
complete -r claude 2>/dev/null || true
source "$SCRIPT_DIR/../claude.bash"
if complete -p claude &>/dev/null; then
    pass "completion registered for claude"
else
    fail "completion not registered for claude"
fi

# Test: _claude function exists
if declare -F _claude &>/dev/null; then
    pass "_claude function exists"
else
    fail "_claude function exists"
fi

if [[ $FAILURES -gt 0 ]]; then
    echo "$FAILURES test(s) failed"
    exit 1
else
    echo "All tests passed"
fi
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test_skeleton.bash`
Expected: FAIL — `claude.bash` doesn't exist yet

**Step 3: Write minimal implementation**

Create `claude.bash`:

```bash
#!/usr/bin/env bash
# Bash completion for the claude CLI (Claude Code)
# https://github.com/anthropics/claude-code

_claude() {
    local cur prev words cword
    _init_completion || return
}

complete -F _claude claude
```

Note: `_init_completion` comes from bash-completion. If it's not available, we need a fallback. Add this before `_claude`:

```bash
# Fallback if bash-completion's _init_completion is not available
if ! declare -F _init_completion &>/dev/null; then
    _init_completion() {
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    }
fi
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test_skeleton.bash`
Expected: PASS

**Step 5: Commit**

```bash
git add claude.bash tests/test_skeleton.bash
git commit -m "feat: add completion script skeleton with registration"
```

---

### Task 2: Cache directory setup and version detection

**Files:**
- Modify: `claude.bash`
- Create: `tests/test_cache.bash`

**Step 1: Write the failing test**

Create `tests/test_cache.bash`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

# Use temp dir for XDG cache during tests
export XDG_CACHE_HOME="$(mktemp -d)"
trap "rm -rf $XDG_CACHE_HOME" EXIT

source "$SCRIPT_DIR/../claude.bash"

# Test: _claude_cache_dir returns correct path structure
cache_dir="$(_claude_cache_dir)"
if [[ "$cache_dir" == "$XDG_CACHE_HOME/claude-code-completion/bash/"* ]]; then
    pass "_claude_cache_dir returns correct path prefix"
else
    fail "_claude_cache_dir returns correct path prefix (got: $cache_dir)"
fi

# Test: cache dir includes a version component
version_part="${cache_dir#$XDG_CACHE_HOME/claude-code-completion/bash/}"
if [[ -n "$version_part" ]]; then
    pass "_claude_cache_dir includes version component"
else
    fail "_claude_cache_dir includes version component"
fi

# Test: _claude_ensure_cache creates the directory
_claude_ensure_cache
if [[ -d "$cache_dir" ]]; then
    pass "_claude_ensure_cache creates cache directory"
else
    fail "_claude_ensure_cache creates cache directory"
fi

if [[ $FAILURES -gt 0 ]]; then
    echo "$FAILURES test(s) failed"
    exit 1
else
    echo "All tests passed"
fi
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test_cache.bash`
Expected: FAIL — functions don't exist yet

**Step 3: Write minimal implementation**

Add to `claude.bash` (before the `_claude` function):

```bash
_claude_version() {
    claude --version 2>/dev/null | head -1 | awk '{print $1}'
}

_claude_cache_dir() {
    local xdg_cache="${XDG_CACHE_HOME:-$HOME/.cache}"
    echo "$xdg_cache/claude-code-completion/bash/$(_claude_version)"
}

_claude_ensure_cache() {
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    mkdir -p "$cache_dir"
}

_claude_cleanup_old_cache() {
    local xdg_cache="${XDG_CACHE_HOME:-$HOME/.cache}"
    local base_dir="$xdg_cache/claude-code-completion/bash"
    local current_version
    current_version="$(_claude_version)"

    [[ -d "$base_dir" ]] || return 0

    local dir
    for dir in "$base_dir"/*/; do
        [[ -d "$dir" ]] || continue
        local dir_version
        dir_version="$(basename "$dir")"
        if [[ "$dir_version" != "$current_version" ]]; then
            rm -rf "$dir"
        fi
    done
}
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test_cache.bash`
Expected: PASS

**Step 5: Commit**

```bash
git add claude.bash tests/test_cache.bash
git commit -m "feat: add cache directory setup and version detection"
```

---

### Task 3: Help parsing — extract flags and subcommands

**Files:**
- Modify: `claude.bash`
- Create: `tests/test_help_parsing.bash`

**Step 1: Write the failing test**

Create `tests/test_help_parsing.bash`. This test uses a mock `claude` command to avoid depending on a real installation:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

export XDG_CACHE_HOME="$(mktemp -d)"
MOCK_BIN="$(mktemp -d)"
trap "rm -rf $XDG_CACHE_HOME $MOCK_BIN" EXIT

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
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test_help_parsing.bash`
Expected: FAIL — `_claude_build_cache` not defined

**Step 3: Write minimal implementation**

Add to `claude.bash`:

```bash
_claude_parse_flags() {
    # Parse flags from help output on stdin
    # Outputs all flag forms (short and long), one per line
    local line
    while IFS= read -r line; do
        # Match lines starting with optional spaces then a dash
        if [[ "$line" =~ ^[[:space:]]+(-[a-zA-Z]),?[[:space:]]+(--[a-zA-Z][-a-zA-Z]*) ]]; then
            echo "${BASH_REMATCH[1]}"
            echo "${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]+(--[a-zA-Z][-a-zA-Z]*) ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done
}

_claude_parse_flags_with_args() {
    # Parse flags that take arguments (have <value> after them)
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+(-[a-zA-Z]),?[[:space:]]+(--[a-zA-Z][-a-zA-Z]*)[[:space:]]+\< ]]; then
            echo "${BASH_REMATCH[1]}"
            echo "${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]+(--[a-zA-Z][-a-zA-Z]*)[[:space:]]+\< ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done
}

_claude_parse_subcommands() {
    # Parse subcommand names from help output on stdin
    # Looks for lines in the "Commands:" section
    local in_commands=0
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^Commands: ]]; then
            in_commands=1
            continue
        fi
        if [[ $in_commands -eq 1 ]]; then
            # Empty line or non-indented line ends commands section
            [[ -z "$line" ]] && continue
            [[ ! "$line" =~ ^[[:space:]] ]] && break
            # Extract command name (first word, handle "update|upgrade" aliases)
            if [[ "$line" =~ ^[[:space:]]+([a-zA-Z][-a-zA-Z]*) ]]; then
                echo "${BASH_REMATCH[1]}"
            fi
        fi
    done
}

_claude_build_cache() {
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    mkdir -p "$cache_dir"

    # Parse root level
    local help_output
    help_output="$(claude --help 2>/dev/null)"
    echo "$help_output" | _claude_parse_flags > "$cache_dir/_root_flags"
    echo "$help_output" | _claude_parse_flags_with_args > "$cache_dir/_root_flags_with_args"
    echo "$help_output" | _claude_parse_subcommands > "$cache_dir/_root_subcommands"

    # Parse each subcommand
    local subcmd
    while IFS= read -r subcmd; do
        [[ -z "$subcmd" ]] && continue
        local sub_help
        sub_help="$(claude "$subcmd" --help 2>/dev/null)" || continue
        echo "$sub_help" | _claude_parse_flags > "$cache_dir/${subcmd}_flags"
        echo "$sub_help" | _claude_parse_flags_with_args > "$cache_dir/${subcmd}_flags_with_args"
        echo "$sub_help" | _claude_parse_subcommands > "$cache_dir/${subcmd}_subcommands"
    done < "$cache_dir/_root_subcommands"

    # Clean up old versions
    _claude_cleanup_old_cache
}
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test_help_parsing.bash`
Expected: PASS

**Step 5: Commit**

```bash
git add claude.bash tests/test_help_parsing.bash
git commit -m "feat: add help output parsing and cache building"
```

---

### Task 4: Core completion logic — subcommands and flags

**Files:**
- Modify: `claude.bash`
- Create: `tests/test_completion.bash`

**Step 1: Write the failing test**

Create `tests/test_completion.bash`. This uses a helper to simulate completion:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

export XDG_CACHE_HOME="$(mktemp -d)"
MOCK_BIN="$(mktemp -d)"
trap "rm -rf $XDG_CACHE_HOME $MOCK_BIN" EXIT

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
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test_completion.bash`
Expected: FAIL — `_claude` function doesn't produce completions yet

**Step 3: Write minimal implementation**

Replace the `_claude` function in `claude.bash`:

```bash
_claude() {
    local cur prev words cword
    _init_completion || return

    local cache_dir
    cache_dir="$(_claude_cache_dir)"

    # Build cache if needed
    if [[ ! -d "$cache_dir" ]]; then
        _claude_build_cache
    fi

    # Determine which subcommand we're in (if any)
    local subcmd=""
    local i
    for (( i=1; i < cword; i++ )); do
        if [[ "${words[i]}" != -* ]]; then
            local potential="${words[i]}"
            if [[ -f "$cache_dir/_root_subcommands" ]] && grep -qx "$potential" "$cache_dir/_root_subcommands"; then
                subcmd="$potential"
                break
            fi
        fi
    done

    if [[ -n "$subcmd" ]]; then
        # Inside a subcommand
        if [[ "$cur" == -* ]]; then
            # Complete subcommand flags
            if [[ -f "$cache_dir/${subcmd}_flags" ]]; then
                COMPREPLY=( $(compgen -W "$(cat "$cache_dir/${subcmd}_flags")" -- "$cur") )
            fi
        else
            # Complete sub-subcommands
            if [[ -f "$cache_dir/${subcmd}_subcommands" ]]; then
                COMPREPLY=( $(compgen -W "$(cat "$cache_dir/${subcmd}_subcommands")" -- "$cur") )
            fi
        fi
    else
        # Top level
        if [[ "$cur" == -* ]]; then
            # Complete flags
            if [[ -f "$cache_dir/_root_flags" ]]; then
                COMPREPLY=( $(compgen -W "$(cat "$cache_dir/_root_flags")" -- "$cur") )
            fi
        else
            # Complete subcommands
            if [[ -f "$cache_dir/_root_subcommands" ]]; then
                COMPREPLY=( $(compgen -W "$(cat "$cache_dir/_root_subcommands")" -- "$cur") )
            fi
        fi
    fi
}
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test_completion.bash`
Expected: PASS

**Step 5: Commit**

```bash
git add claude.bash tests/test_completion.bash
git commit -m "feat: add core completion logic for subcommands and flags"
```

---

### Task 5: Smart flag argument completions

**Files:**
- Modify: `claude.bash`
- Create: `tests/test_flag_args.bash`

**Step 1: Write the failing test**

Create `tests/test_flag_args.bash`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

export XDG_CACHE_HOME="$(mktemp -d)"
MOCK_BIN="$(mktemp -d)"
trap "rm -rf $XDG_CACHE_HOME $MOCK_BIN" EXIT

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
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test_flag_args.bash`
Expected: FAIL — no smart flag argument handling yet

**Step 3: Write minimal implementation**

Add a `_claude_complete_flag_arg` function and the hardcoded model list to `claude.bash`. Modify `_claude` to call it when the previous word is a flag that takes arguments.

Add before `_claude`:

```bash
# Hardcoded model IDs (update when new models are released)
_CLAUDE_KNOWN_MODELS=(
    sonnet opus haiku
    claude-sonnet-4-5-20250514
    claude-sonnet-4-6
    claude-opus-4-5-20250514
    claude-opus-4-6
    claude-haiku-4-5-20251001
)

_claude_complete_flag_arg() {
    # Complete arguments for flags that take values
    # $1 = flag name, $2 = current word
    local flag="$1"
    local cur="$2"

    case "$flag" in
        --model)
            # Merge aliases + hardcoded + help-parsed models
            local models=("${_CLAUDE_KNOWN_MODELS[@]}")
            # Add any models from help output (look for model IDs in help text)
            local cache_dir
            cache_dir="$(_claude_cache_dir)"
            if [[ -f "$cache_dir/_root_help" ]]; then
                while IFS= read -r line; do
                    if [[ "$line" =~ claude-[a-z]+-[0-9] ]]; then
                        models+=("${BASH_REMATCH[0]}")
                    fi
                done < "$cache_dir/_root_help"
            fi
            COMPREPLY=( $(compgen -W "${models[*]}" -- "$cur") )
            ;;
        --permission-mode)
            COMPREPLY=( $(compgen -W "acceptEdits bypassPermissions default dontAsk plan" -- "$cur") )
            ;;
        --output-format)
            COMPREPLY=( $(compgen -W "text json stream-json" -- "$cur") )
            ;;
        --input-format)
            COMPREPLY=( $(compgen -W "text stream-json" -- "$cur") )
            ;;
        --effort)
            COMPREPLY=( $(compgen -W "low medium high" -- "$cur") )
            ;;
        --add-dir)
            # Directory completion only
            COMPREPLY=( $(compgen -d -- "$cur") )
            ;;
        --debug-file|--mcp-config|--settings)
            # File completion
            COMPREPLY=( $(compgen -f -- "$cur") )
            ;;
        --plugin-dir)
            # Directory completion
            COMPREPLY=( $(compgen -d -- "$cur") )
            ;;
        *)
            # Unknown flag arg — default to file completion
            COMPREPLY=( $(compgen -f -- "$cur") )
            ;;
    esac
}
```

Modify `_claude` to check if `prev` is a flag that takes arguments. Insert this near the top of the function, after cache setup and before the subcommand/flag branching:

```bash
    # Check if previous word is a flag that takes an argument
    if [[ "$prev" == -* ]]; then
        local flags_with_args_file="$cache_dir/_root_flags_with_args"
        if [[ -n "$subcmd" ]]; then
            flags_with_args_file="$cache_dir/${subcmd}_flags_with_args"
        fi
        if [[ -f "$flags_with_args_file" ]] && grep -qx -- "$prev" "$flags_with_args_file"; then
            _claude_complete_flag_arg "$prev" "$cur"
            return
        fi
    fi
```

Also, in `_claude_build_cache`, save the raw help output for model ID extraction:

```bash
    echo "$help_output" > "$cache_dir/_root_help"
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test_flag_args.bash`
Expected: PASS

**Step 5: Commit**

```bash
git add claude.bash tests/test_flag_args.bash
git commit -m "feat: add smart flag argument completions"
```

---

### Task 6: Session ID completion for --resume

**Files:**
- Modify: `claude.bash`
- Create: `tests/test_resume.bash`

**Step 1: Write the failing test**

Create `tests/test_resume.bash`. This creates fake session JSONL files:

```bash
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
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test_resume.bash`
Expected: FAIL — `_claude_complete_sessions` not defined

**Step 3: Write minimal implementation**

Add to `claude.bash`:

```bash
_claude_encoded_cwd() {
    # Encode current directory the way Claude does: replace / with -
    local cwd="${PWD}"
    echo "${cwd//\//-}"
}

_claude_session_message_jq() {
    # Extract first real user message using jq
    local file="$1"
    jq -r '
        select(.type == "user")
        | .message.content
        | if type == "array" then
            .[] | select(.type == "text") | .text
          elif type == "string" then .
          else empty
          end
    ' "$file" 2>/dev/null | grep -v '<ide_\|<command-' | head -1
}

_claude_session_message_grep() {
    # Extract first real user message using grep/sed fallback
    local file="$1"
    grep '"type":"user"' "$file" \
        | grep -v '<ide_' \
        | grep -v '<command-' \
        | head -1 \
        | sed -n 's/.*"text":"\([^"]*\)".*/\1/p' \
        | head -1
}

_claude_session_message() {
    if command -v jq &>/dev/null; then
        _claude_session_message_jq "$1"
    else
        _claude_session_message_grep "$1"
    fi
}

_claude_complete_sessions() {
    local cur="$1"
    local encoded_cwd
    encoded_cwd="$(_claude_encoded_cwd)"
    local session_dir="$HOME/.claude/projects/${encoded_cwd}"

    [[ -d "$session_dir" ]] || return

    # List JSONL files sorted by modification time (newest first), limit to 10
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$session_dir" -maxdepth 1 -name '*.jsonl' -printf '%T@\t%p\0' \
        | sort -z -t$'\t' -k1 -rn \
        | head -z -n 10 \
        | cut -z -f2-)

    local session_ids=()
    for file in "${files[@]}"; do
        local basename="${file##*/}"
        local session_id="${basename%.jsonl}"
        # Filter by current word
        if [[ "$session_id" == "$cur"* ]]; then
            session_ids+=("$session_id")
        fi
    done

    COMPREPLY=("${session_ids[@]}")
}
```

Wire it into `_claude_complete_flag_arg`:

```bash
        --resume|-r)
            _claude_complete_sessions "$cur"
            ;;
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test_resume.bash`
Expected: PASS

**Step 5: Commit**

```bash
git add claude.bash tests/test_resume.bash
git commit -m "feat: add session ID completion for --resume"
```

---

### Task 7: Subcommand-specific argument completions (MCP and plugin names)

**Files:**
- Modify: `claude.bash`
- Create: `tests/test_subcommand_args.bash`

**Step 1: Write the failing test**

Create `tests/test_subcommand_args.bash`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

export XDG_CACHE_HOME="$(mktemp -d)"
MOCK_BIN="$(mktemp -d)"
trap "rm -rf $XDG_CACHE_HOME $MOCK_BIN" EXIT

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
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test_subcommand_args.bash`
Expected: FAIL — no MCP/plugin name completion logic yet

**Step 3: Write minimal implementation**

Add to `claude.bash`:

```bash
_claude_mcp_server_names() {
    # Extract server names from "claude mcp list" output
    # Format: "name: url - status" — extract the first word before the colon
    claude mcp list 2>/dev/null | grep ':' | grep -v '^Checking\|^$' | sed 's/:.*//' | sed 's/^[[:space:]]*//'
}

_claude_plugin_names() {
    # Extract plugin names from "claude plugin list --json" output
    if command -v jq &>/dev/null; then
        claude plugin list --json 2>/dev/null | jq -r '.[].name' 2>/dev/null
    else
        claude plugin list --json 2>/dev/null | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//'
    fi
}
```

Modify the subcommand completion section of `_claude` to detect sub-subcommands that take positional arguments. Add this logic inside the `if [[ -n "$subcmd" ]]` block, after identifying the sub-subcommand:

```bash
    if [[ -n "$subcmd" ]]; then
        # Find sub-subcommand if present
        local sub_subcmd=""
        for (( i=i+1; i < cword; i++ )); do
            if [[ "${words[i]}" != -* ]]; then
                local potential="${words[i]}"
                if [[ -f "$cache_dir/${subcmd}_subcommands" ]] && grep -qx "$potential" "$cache_dir/${subcmd}_subcommands"; then
                    sub_subcmd="$potential"
                    break
                fi
            fi
        done

        # Check if prev is a flag with args at subcommand level
        if [[ "$prev" == -* ]]; then
            local flags_with_args_file="$cache_dir/${subcmd}_flags_with_args"
            if [[ -f "$flags_with_args_file" ]] && grep -qx -- "$prev" "$flags_with_args_file"; then
                _claude_complete_flag_arg "$prev" "$cur"
                return
            fi
        fi

        if [[ "$cur" == -* ]]; then
            if [[ -f "$cache_dir/${subcmd}_flags" ]]; then
                COMPREPLY=( $(compgen -W "$(cat "$cache_dir/${subcmd}_flags")" -- "$cur") )
            fi
        elif [[ -n "$sub_subcmd" ]]; then
            # Complete positional args for sub-subcommands
            _claude_complete_subcmd_arg "$subcmd" "$sub_subcmd" "$cur"
        else
            if [[ -f "$cache_dir/${subcmd}_subcommands" ]]; then
                COMPREPLY=( $(compgen -W "$(cat "$cache_dir/${subcmd}_subcommands")" -- "$cur") )
            fi
        fi
    fi
```

Add the dispatcher function:

```bash
_claude_complete_subcmd_arg() {
    local subcmd="$1"
    local sub_subcmd="$2"
    local cur="$3"

    case "${subcmd}/${sub_subcmd}" in
        mcp/get|mcp/remove)
            local names
            names="$(_claude_mcp_server_names)"
            COMPREPLY=( $(compgen -W "$names" -- "$cur") )
            ;;
        plugin/disable|plugin/enable|plugin/uninstall|plugin/remove)
            local names
            names="$(_claude_plugin_names)"
            COMPREPLY=( $(compgen -W "$names" -- "$cur") )
            ;;
    esac
}
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test_subcommand_args.bash`
Expected: PASS

**Step 5: Commit**

```bash
git add claude.bash tests/test_subcommand_args.bash
git commit -m "feat: add MCP server and plugin name completions"
```

---

### Task 8: Run all tests and update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Run all tests**

Run: `for t in tests/test_*.bash; do echo "=== $t ==="; bash "$t"; done`
Expected: All tests pass

**Step 2: Update CLAUDE.md with build/test instructions**

Replace the contents of `CLAUDE.md`:

```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Shell completion for the `claude` CLI (Claude Code). Currently provides bash tab-completion; zsh and fish support planned.

## Architecture

Single-file bash completion script (`claude.bash`) with:
- Dynamic help parsing — extracts flags and subcommands from `claude --help` at completion time
- Version-based caching at `$XDG_CACHE_HOME/claude-code-completion/bash/<version>/`
- Smart completions for flag arguments (models, permission modes, session IDs, etc.)
- MCP server and plugin name completion for relevant subcommands
- Optional `jq` dependency for session JSONL parsing, with grep/sed fallback

## Testing

Tests are plain bash scripts in `tests/`:

```bash
# Run all tests
for t in tests/test_*.bash; do bash "$t"; done

# Run a single test
bash tests/test_completion.bash
```

Tests use mock `claude` commands to avoid requiring a real installation.

## Design Documents

- `docs/plans/2026-03-02-bash-completion-design.md` — design decisions and rationale
```

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with architecture and test instructions"
```
