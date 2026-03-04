# bashunit Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the hand-rolled bash test framework with bashunit, add coverage, and set up GitHub Actions CI.

**Architecture:** Each test file sources a shared bootstrap that provides mock-building and completion-simulation helpers. Tests use bashunit's `set_up_before_script` for per-file mock setup and `set_up`/`tear_down` for per-test temp directory lifecycle. Coverage uses bashunit's built-in `DEBUG` trap against `claude.bash`.

**Tech Stack:** bashunit (assumed pre-installed locally), bash, GitHub Actions

**Reference:** Design doc at `docs/plans/2026-03-03-bashunit-migration-design.md`

---

### Task 1: Infrastructure — .gitignore, bashunit env, bootstrap

**Files:**
- Modify: `.gitignore`
- Create: `.bashunit.env`
- Create: `tests/bootstrap.bash`

**Step 1: Update .gitignore**

Add coverage output and CI-local bashunit to `.gitignore`:

```
coverage/
lib/
```

**Step 2: Create `.bashunit.env`**

bashunit configuration file. Sets the bootstrap file path.

```bash
BASHUNIT_BOOTSTRAP="tests/bootstrap.bash"
```

**Step 3: Create `tests/bootstrap.bash`**

This is sourced by bashunit before every test file. It provides shared helper functions.

Important: bashunit runs tests in subshells, so all functions defined here must be exported with `export -f` to be available in test functions.

```bash
#!/usr/bin/env bash

# --- Shared test infrastructure for bashunit ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create a minimal mock claude command in the given directory.
# Writes a script that handles --version and a basic --help.
# Callers can append additional case branches before closing the case/esac.
#
# Usage:
#   create_mock_claude "$MOCK_BIN"                    # creates base mock
#   append_mock_claude "$MOCK_BIN" "auth --help" \    # add a case branch
#     'echo "Usage: claude auth"'
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
```

**Step 4: Run bashunit to verify bootstrap loads**

Run: `bashunit tests/` (no test files yet, should exit cleanly or report 0 tests)
Expected: No errors about bootstrap loading.

**Step 5: Commit**

```
git add .gitignore .bashunit.env tests/bootstrap.bash
git commit -m "test: add bashunit infrastructure (bootstrap, config, gitignore)"
```

---

### Task 2: Migrate skeleton test

**Files:**
- Create: `tests/skeleton_test.bash`
- Reference: `tests/test_skeleton.bash` (old, read-only)

**Step 1: Write `tests/skeleton_test.bash`**

This is the simplest test — just verifies sourcing `claude.bash` registers the completion.

```bash
#!/usr/bin/env bash

function set_up_before_script() {
    # skeleton test doesn't need a mock — it just tests that sourcing registers completion
    complete -r claude 2>/dev/null || true
    source_claude_bash
}

function test_completion_registered_for_claude() {
    assert_successful_code "complete -p claude"
}

function test_claude_function_exists() {
    assert_successful_code "declare -F _claude"
}
```

**Step 2: Run the new test**

Run: `bashunit tests/skeleton_test.bash`
Expected: 2 tests pass.

**Step 3: Commit**

```
git add tests/skeleton_test.bash
git commit -m "test: migrate skeleton test to bashunit"
```

---

### Task 3: Migrate cache test

**Files:**
- Create: `tests/cache_test.bash`
- Reference: `tests/test_cache.bash` (old, read-only)

**Step 1: Write `tests/cache_test.bash`**

```bash
#!/usr/bin/env bash

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    create_mock_claude "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"
    source_claude_bash
}

function set_up() {
    export XDG_CACHE_HOME="$(mktemp -d)"
}

function tear_down() {
    rm -rf "$XDG_CACHE_HOME"
}

function tear_down_after_script() {
    rm -rf "$MOCK_BIN"
}

function test_cache_dir_returns_correct_path_prefix() {
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_contains "$cache_dir" "$XDG_CACHE_HOME/claude-code-completion/bash/"
}

function test_cache_dir_includes_version_component() {
    local cache_dir version_part
    cache_dir="$(_claude_cache_dir)"
    version_part="${cache_dir#"$XDG_CACHE_HOME/claude-code-completion/bash/"}"
    assert_not_empty "$version_part"
}

function test_ensure_cache_creates_directory() {
    _claude_ensure_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_directory_exists "$cache_dir"
}

function test_cleanup_old_cache_removes_old_versions() {
    _claude_ensure_cache
    local base_dir="$XDG_CACHE_HOME/claude-code-completion/bash"
    mkdir -p "$base_dir/0.9.0" "$base_dir/0.8.0"
    _claude_cleanup_old_cache
    assert_directory_not_exists "$base_dir/0.9.0"
    assert_directory_not_exists "$base_dir/0.8.0"
}

function test_cleanup_old_cache_preserves_current_version() {
    _claude_ensure_cache
    local cache_dir base_dir
    cache_dir="$(_claude_cache_dir)"
    base_dir="$XDG_CACHE_HOME/claude-code-completion/bash"
    mkdir -p "$base_dir/0.9.0"
    _claude_cleanup_old_cache
    assert_directory_exists "$cache_dir"
}
```

**Step 2: Run the test**

Run: `bashunit tests/cache_test.bash`
Expected: 5 tests pass.

**Step 3: Commit**

```
git add tests/cache_test.bash
git commit -m "test: migrate cache test to bashunit"
```

---

### Task 4: Migrate help parsing test

**Files:**
- Create: `tests/help_parsing_test.bash`
- Reference: `tests/test_help_parsing.bash` (old, read-only)

This test needs a richer mock that includes `auth --help`, `mcp --help`, and `plugin --help` responses.

**Step 1: Write `tests/help_parsing_test.bash`**

```bash
#!/usr/bin/env bash

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    export XDG_CACHE_HOME="$(mktemp -d)"

    write_mock_claude "$MOCK_BIN" "$(cat <<'BODY'
case "$*" in
    "--version") echo "1.0.0 (Claude Code)" ;;
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
BODY
)"

    export PATH="$MOCK_BIN:$PATH"
    source_claude_bash
    _claude_build_cache
    CACHE_DIR="$(_claude_cache_dir)"
}

function tear_down_after_script() {
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN"
}

function test_root_flags_file_exists() {
    assert_file_exists "$CACHE_DIR/_root_flags"
}

function test_root_flags_contains_model() {
    assert_file_contains "$CACHE_DIR/_root_flags" "--model"
}

function test_root_flags_contains_short_print() {
    assert_file_contains "$CACHE_DIR/_root_flags" "-p"
}

function test_root_subcommands_file_exists() {
    assert_file_exists "$CACHE_DIR/_root_subcommands"
}

function test_root_subcommands_contains_auth() {
    assert_file_contains "$CACHE_DIR/_root_subcommands" "auth"
}

function test_root_subcommands_contains_mcp() {
    assert_file_contains "$CACHE_DIR/_root_subcommands" "mcp"
}

function test_flags_with_args_file_exists() {
    assert_file_exists "$CACHE_DIR/_root_flags_with_args"
}

function test_flags_with_args_contains_model() {
    assert_file_contains "$CACHE_DIR/_root_flags_with_args" "--model"
}

function test_flags_with_args_excludes_continue() {
    assert_file_not_contains "$CACHE_DIR/_root_flags_with_args" "--continue"
}

function test_mcp_subcommands_file_exists() {
    assert_file_exists "$CACHE_DIR/mcp_subcommands"
}

function test_mcp_subcommands_contains_add() {
    assert_file_contains "$CACHE_DIR/mcp_subcommands" "add"
}
```

**Step 2: Run the test**

Run: `bashunit tests/help_parsing_test.bash`
Expected: 11 tests pass.

**Step 3: Commit**

```
git add tests/help_parsing_test.bash
git commit -m "test: migrate help parsing test to bashunit"
```

---

### Task 5: Migrate completion test

**Files:**
- Create: `tests/completion_test.bash`
- Reference: `tests/test_completion.bash` (old, read-only)

First test file using `simulate_completion` from the bootstrap.

**Step 1: Write `tests/completion_test.bash`**

```bash
#!/usr/bin/env bash

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    export XDG_CACHE_HOME="$(mktemp -d)"

    write_mock_claude "$MOCK_BIN" "$(cat <<'BODY'
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
BODY
)"

    export PATH="$MOCK_BIN:$PATH"
    source_claude_bash
}

function tear_down_after_script() {
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN"
}

function test_bare_claude_shows_subcommands() {
    local result
    result="$(simulate_completion "claude ")"
    assert_contains "$result" "auth"
    assert_contains "$result" "mcp"
}

function test_bare_claude_does_not_show_flags() {
    local result
    result="$(simulate_completion "claude ")"
    assert_not_contains "$result" "--model"
}

function test_dash_shows_flags() {
    local result
    result="$(simulate_completion "claude -")"
    assert_contains "$result" "--model"
    assert_contains "$result" "-p"
}

function test_double_dash_shows_long_flags() {
    local result
    result="$(simulate_completion "claude --")"
    assert_contains "$result" "--model"
}

function test_partial_subcommand_completes() {
    local result
    result="$(simulate_completion "claude au")"
    assert_contains "$result" "auth"
}

function test_auth_subcommand_shows_auth_subcommands() {
    local result
    result="$(simulate_completion "claude auth ")"
    assert_contains "$result" "login"
    assert_contains "$result" "logout"
}

function test_mcp_subcommand_shows_mcp_subcommands() {
    local result
    result="$(simulate_completion "claude mcp ")"
    assert_contains "$result" "add"
    assert_contains "$result" "list"
}
```

**Step 2: Run the test**

Run: `bashunit tests/completion_test.bash`
Expected: 7 tests pass.

**Step 3: Commit**

```
git add tests/completion_test.bash
git commit -m "test: migrate completion test to bashunit"
```

---

### Task 6: Migrate flag args test

**Files:**
- Create: `tests/flag_args_test.bash`
- Reference: `tests/test_flag_args.bash` (old, read-only)

**Step 1: Write `tests/flag_args_test.bash`**

```bash
#!/usr/bin/env bash

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    export XDG_CACHE_HOME="$(mktemp -d)"

    write_mock_claude "$MOCK_BIN" "$(cat <<'BODY'
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
BODY
)"

    export PATH="$MOCK_BIN:$PATH"
    source_claude_bash
}

function tear_down_after_script() {
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN"
}

function test_model_completes_aliases() {
    local result
    result="$(simulate_completion "claude --model ")"
    assert_contains "$result" "sonnet"
    assert_contains "$result" "opus"
    assert_contains "$result" "haiku"
}

function test_permission_mode_completes_choices() {
    local result
    result="$(simulate_completion "claude --permission-mode ")"
    assert_contains "$result" "default"
    assert_contains "$result" "plan"
}

function test_output_format_completes_choices() {
    local result
    result="$(simulate_completion "claude --output-format ")"
    assert_contains "$result" "text"
    assert_contains "$result" "json"
    assert_contains "$result" "stream-json"
}

function test_effort_completes_levels() {
    local result
    result="$(simulate_completion "claude --effort ")"
    assert_contains "$result" "low"
    assert_contains "$result" "medium"
    assert_contains "$result" "high"
}

function test_input_format_completes_choices() {
    local result
    result="$(simulate_completion "claude --input-format ")"
    assert_contains "$result" "text"
    assert_contains "$result" "stream-json"
}

function test_model_partial_input_filters() {
    local result
    result="$(simulate_completion "claude --model so")"
    assert_contains "$result" "sonnet"
    assert_not_contains "$result" "opus"
}
```

**Step 2: Run the test**

Run: `bashunit tests/flag_args_test.bash`
Expected: 6 tests pass.

**Step 3: Commit**

```
git add tests/flag_args_test.bash
git commit -m "test: migrate flag args test to bashunit"
```

---

### Task 7: Migrate resume test

**Files:**
- Create: `tests/resume_test.bash`
- Reference: `tests/test_resume.bash` (old, read-only)

This test has unique setup: fake HOME, fake session JSONL files, and an overridden `_claude_encoded_cwd`.

**Step 1: Write `tests/resume_test.bash`**

```bash
#!/usr/bin/env bash

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    MOCK_HOME="$(mktemp -d)"
    export XDG_CACHE_HOME="$(mktemp -d)"

    create_mock_claude "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"
    export HOME="$MOCK_HOME"

    # Create fake session files for a project at /home/user/myproject
    PROJ_DIR="$MOCK_HOME/.claude/projects/-home-user-myproject"
    mkdir -p "$PROJ_DIR"

    # Session 1: older
    cat > "$PROJ_DIR/aaaaaaaa-1111-1111-1111-111111111111.jsonl" << 'SESSION'
{"type":"queue-operation","timestamp":"2026-02-01T10:00:00.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Fix the login bug"}]},"timestamp":"2026-02-01T10:00:01.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"assistant","timestamp":"2026-02-01T10:00:05.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
SESSION

    # Session 2: newer (sleep 1 to ensure different mtime)
    sleep 1
    cat > "$PROJ_DIR/bbbbbbbb-2222-2222-2222-222222222222.jsonl" << 'SESSION'
{"type":"queue-operation","timestamp":"2026-03-01T15:00:00.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<ide_opened_file>Some IDE stuff</ide_opened_file>"}]},"timestamp":"2026-03-01T15:00:01.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Add the new feature"}]},"timestamp":"2026-03-01T15:00:02.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"assistant","timestamp":"2026-03-01T15:00:10.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
SESSION

    source_claude_bash

    # Override _claude_encoded_cwd to match our fake project
    eval '_claude_encoded_cwd() { echo "-home-user-myproject"; }'
}

function tear_down_after_script() {
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN" "$MOCK_HOME"
}

function test_complete_sessions_finds_both_sessions() {
    COMPREPLY=()
    _claude_complete_sessions ""
    assert_equals "${#COMPREPLY[@]}" "2"
}

function test_session_1_uuid_present() {
    COMPREPLY=()
    _claude_complete_sessions ""
    local result="${COMPREPLY[*]}"
    assert_contains "$result" "aaaaaaaa-1111-1111-1111-111111111111"
}

function test_session_2_uuid_present() {
    COMPREPLY=()
    _claude_complete_sessions ""
    local result="${COMPREPLY[*]}"
    assert_contains "$result" "bbbbbbbb-2222-2222-2222-222222222222"
}

function test_partial_uuid_filters() {
    COMPREPLY=()
    _claude_complete_sessions "aaa"
    assert_equals "${#COMPREPLY[@]}" "1"
}
```

**Step 2: Run the test**

Run: `bashunit tests/resume_test.bash`
Expected: 4 tests pass.

**Step 3: Commit**

```
git add tests/resume_test.bash
git commit -m "test: migrate resume test to bashunit"
```

---

### Task 8: Migrate fallbacks test

**Files:**
- Create: `tests/fallbacks_test.bash`
- Reference: `tests/test_fallbacks.bash` (old, read-only)

This test verifies jq and grep/sed fallback paths for session message extraction and plugin name listing. It builds a `NO_JQ_PATH` to test without jq.

**Step 1: Write `tests/fallbacks_test.bash`**

```bash
#!/usr/bin/env bash

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    MOCK_HOME="$(mktemp -d)"
    SESSION_DIR="$(mktemp -d)"
    SHADOW_BASE="$(mktemp -d)"
    export XDG_CACHE_HOME="$(mktemp -d)"

    write_mock_claude "$MOCK_BIN" "$(cat <<'BODY'
case "$*" in
    "--version") echo "1.0.0 (Claude Code)" ;;
    "--help") echo "Usage: claude [options]" ;;
    "plugin list --json")
        echo '[{"name":"superpowers","version":"1.0"},{"name":"my-plugin","version":"2.0"}]'
        ;;
esac
BODY
)"

    export PATH="$MOCK_BIN:$PATH"
    export HOME="$MOCK_HOME"
    source_claude_bash

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

    # Build a PATH with jq removed for fallback tests
    NO_JQ_PATH=""
    local _shadow_idx=0
    local _path_dirs _dir _shadow _f _name
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
}

function tear_down_after_script() {
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN" "$MOCK_HOME" "$SESSION_DIR" "$SHADOW_BASE"
}

# --- jq path tests (skip if jq not installed) ---

function test_session_message_jq_extracts_simple_message() {
    if ! command -v jq &>/dev/null; then skip; return; fi
    local result
    result="$(_claude_session_message_jq "$SESSION_DIR/session1.jsonl")"
    assert_same "$result" "Fix the login bug"
}

function test_session_message_jq_skips_ide_metadata() {
    if ! command -v jq &>/dev/null; then skip; return; fi
    local result
    result="$(_claude_session_message_jq "$SESSION_DIR/session2.jsonl")"
    assert_same "$result" "Add the new feature"
}

# --- grep fallback tests ---

function test_session_message_grep_extracts_simple_message() {
    local result
    result="$(_claude_session_message_grep "$SESSION_DIR/session1.jsonl")"
    assert_same "$result" "Fix the login bug"
}

function test_session_message_grep_skips_ide_metadata() {
    local result
    result="$(_claude_session_message_grep "$SESSION_DIR/session2.jsonl")"
    assert_same "$result" "Add the new feature"
}

# --- plugin names with jq ---

function test_plugin_names_with_jq() {
    if ! command -v jq &>/dev/null; then skip; return; fi
    local result
    result="$(_claude_plugin_names)"
    assert_contains "$result" "superpowers"
    assert_contains "$result" "my-plugin"
}

# --- plugin names without jq ---

function test_plugin_names_without_jq() {
    local OLD_PATH="$PATH"
    PATH="$NO_JQ_PATH"
    local result
    result="$(_claude_plugin_names)"
    PATH="$OLD_PATH"
    assert_contains "$result" "superpowers"
    assert_contains "$result" "my-plugin"
}
```

**Step 2: Run the test**

Run: `bashunit tests/fallbacks_test.bash`
Expected: 6 tests pass (or 4 pass + 2 skipped if jq is not installed).

**Step 3: Commit**

```
git add tests/fallbacks_test.bash
git commit -m "test: migrate fallbacks test to bashunit"
```

---

### Task 9: Migrate subcommand args test

**Files:**
- Create: `tests/subcommand_args_test.bash`
- Reference: `tests/test_subcommand_args.bash` (old, read-only)

**Step 1: Write `tests/subcommand_args_test.bash`**

```bash
#!/usr/bin/env bash

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    export XDG_CACHE_HOME="$(mktemp -d)"

    write_mock_claude "$MOCK_BIN" "$(cat <<'BODY'
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
BODY
)"

    export PATH="$MOCK_BIN:$PATH"
    source_claude_bash
}

function tear_down_after_script() {
    rm -rf "$XDG_CACHE_HOME" "$MOCK_BIN"
}

function test_mcp_get_completes_server_names() {
    local result
    result="$(simulate_completion "claude mcp get ")"
    assert_contains "$result" "my-sentry"
    assert_contains "$result" "my-github"
}

function test_mcp_remove_completes_server_names() {
    local result
    result="$(simulate_completion "claude mcp remove ")"
    assert_contains "$result" "my-sentry"
}

function test_plugin_disable_completes_plugin_names() {
    local result
    result="$(simulate_completion "claude plugin disable ")"
    assert_contains "$result" "superpowers"
    assert_contains "$result" "my-plugin"
}

function test_plugin_enable_completes_plugin_names() {
    local result
    result="$(simulate_completion "claude plugin enable ")"
    assert_contains "$result" "superpowers"
}

function test_plugin_uninstall_completes_plugin_names() {
    local result
    result="$(simulate_completion "claude plugin uninstall ")"
    assert_contains "$result" "superpowers"
}
```

**Step 2: Run the test**

Run: `bashunit tests/subcommand_args_test.bash`
Expected: 5 tests pass.

**Step 3: Commit**

```
git add tests/subcommand_args_test.bash
git commit -m "test: migrate subcommand args test to bashunit"
```

---

### Task 10: Remove old test files

**Files:**
- Delete: `tests/test_skeleton.bash`
- Delete: `tests/test_cache.bash`
- Delete: `tests/test_help_parsing.bash`
- Delete: `tests/test_completion.bash`
- Delete: `tests/test_flag_args.bash`
- Delete: `tests/test_resume.bash`
- Delete: `tests/test_fallbacks.bash`
- Delete: `tests/test_subcommand_args.bash`

**Step 1: Run the full bashunit suite to confirm everything passes**

Run: `bashunit tests/`
Expected: All tests pass (approx 46 assertions across 8 test files).

**Step 2: Delete old test files**

```bash
git rm tests/test_skeleton.bash tests/test_cache.bash tests/test_help_parsing.bash \
       tests/test_completion.bash tests/test_flag_args.bash tests/test_resume.bash \
       tests/test_fallbacks.bash tests/test_subcommand_args.bash
```

**Step 3: Run bashunit again to confirm nothing broke**

Run: `bashunit tests/`
Expected: Same results — old files were not being picked up by bashunit anyway.

**Step 4: Commit**

```
git add -A tests/
git commit -m "test: remove old hand-rolled test files"
```

---

### Task 11: Add GitHub Actions CI

**Files:**
- Create: `.github/workflows/test.yml`

**Step 1: Write `.github/workflows/test.yml`**

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install bashunit
        run: curl -s https://bashunit.typeddevs.com/install.sh | bash

      - name: Run tests
        run: ./lib/bashunit tests/

      - name: Run tests with coverage
        run: ./lib/bashunit tests/ --coverage --coverage-paths claude.bash
```

**Step 2: Commit**

```
git add .github/workflows/test.yml
git commit -m "ci: add GitHub Actions workflow for bashunit tests"
```

---

### Task 12: Update documentation

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update CLAUDE.md testing section**

Replace the current `## Testing` section with:

```markdown
## Testing

Tests use [bashunit](https://bashunit.typeddevs.com/) in `tests/`:

\`\`\`bash
# Run all tests
bashunit tests/

# Run a single test file
bashunit tests/completion_test.bash

# Run with coverage
bashunit tests/ --coverage --coverage-paths claude.bash
\`\`\`

Tests use mock `claude` commands to avoid requiring a real installation. Shared test infrastructure lives in `tests/bootstrap.bash`.

### Prerequisites

- [bashunit](https://bashunit.typeddevs.com/installation) (`brew install bashunit`)
```

**Step 2: Commit**

```
git add CLAUDE.md
git commit -m "docs: update testing instructions for bashunit"
```
