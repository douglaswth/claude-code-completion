#!/usr/bin/env bash

# The cache build shells out to `claude` many times — once per node in the
# command tree, in parallel — from whatever shell the user pressed TAB in.
# Those probes must not touch that shell's terminal:
#
#   * stdin. A probe that inherits the terminal can swallow characters the
#     user typed ahead. Worse, an interactive shell has job control on, so a
#     backgrounded probe sits in its own process group — and the kernel stops
#     a background process group that reads or reconfigures the controlling
#     terminal. `claude` does both at startup, so every probe stopped before
#     writing a byte, the empty raw file was read as "probe failed", and the
#     published cache was missing every subcommand below the root.
#
#   * the caller's job table. Backgrounding in the interactive shell itself
#     printed `[1] 12345` / `Stopped` notifications over the readline display
#     and stranded the stopped probes as jobs.
#
# Neither symptom can appear without a terminal, and the test suite has none,
# so these tests check the two underlying properties directly: a probe never
# gets a byte of the caller's stdin, and a probe never lands in a process
# group of its own.

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    export PROBE_STDIN_LOG="$MOCK_BIN/stdin.log"
    export PROBE_PGID_LOG="$MOCK_BIN/pgid.log"

    write_mock_claude "$MOCK_BIN" "$(cat <<'BODY'
# Record anything this probe manages to take off stdin, and the process
# group it was launched into (as "<pgid> <pid>").
if [[ -n "$PROBE_STDIN_LOG" ]] && IFS= read -r -t 2 _stolen; then
    printf '%s\n' "$_stolen" >> "$PROBE_STDIN_LOG"
fi
# Only the fan-out probes — `claude <path> --help` — are backgrounded, and
# only they are at issue. Under job control a *foreground* invocation is a
# process group leader too, which is both expected and harmless.
case "$*" in
    *" --help")
        if [[ -n "$PROBE_PGID_LOG" ]]; then
            printf '%s %s\n' "$(ps -o pgid= -p $$ 2>/dev/null | tr -dc '0-9')" "$$" \
                >> "$PROBE_PGID_LOG"
        fi
        ;;
esac

case "$*" in
    "--version") echo "1.0.0 (Claude Code)" ;;
    "--help")
        cat << 'HELP'
Usage: claude [options] [command] [prompt]

Options:
  -h, --help        Display help
  -v, --version     Output the version number

Commands:
  auth              Manage authentication
  doctor            Check health of auto-updater
  mcp               Configure MCP servers
HELP
        ;;
    "auth --help")
        cat << 'HELP'
Usage: claude auth [options] [command]

Options:
  -h, --help        Display help

Commands:
  login             Sign in
  logout            Log out
  status            Show status
HELP
        ;;
    "doctor --help")
        cat << 'HELP'
Usage: claude doctor [options]

Options:
  -h, --help        Display help
HELP
        ;;
    "mcp --help")
        cat << 'HELP'
Usage: claude mcp [options] [command]

Options:
  -h, --help        Display help

Commands:
  get <name>        Get server
  list              List servers
HELP
        ;;
    "mcp list")
        echo "everything: npx -y @modelcontextprotocol/server-everything"
        echo "filesystem: npx -y @modelcontextprotocol/server-filesystem"
        ;;
    *) ;;
esac
BODY
)"

    export PATH="$MOCK_BIN:$PATH"
    source_claude_bash

    # Lines for a probe to steal if it inherits the caller's stdin. More than
    # the tree has nodes, so a theft cannot be masked by running out of input.
    STDIN_FEED="$MOCK_BIN/feed.txt"
    local i
    for (( i = 0; i < 64; i++ )); do echo "TYPED-AHEAD-$i"; done > "$STDIN_FEED"
}

function set_up() {
    # A fresh cache dir per test, so every test actually drives a build.
    export XDG_CACHE_HOME="$(mktemp -d)"
    : > "$PROBE_STDIN_LOG"
    : > "$PROBE_PGID_LOG"
}

function tear_down() {
    rm -rf "$XDG_CACHE_HOME"
}

function tear_down_after_script() {
    rm -rf "$MOCK_BIN"
}

# --- stdin ---------------------------------------------------------------

function test_cache_build_takes_nothing_from_the_callers_stdin() {
    simulate_completion "claude " > /dev/null < "$STDIN_FEED"
    assert_empty "$(cat "$PROBE_STDIN_LOG")"
}

function test_cache_build_leaves_the_callers_stdin_unread() {
    # The same property from the caller's side: the first line typed ahead is
    # still the first line waiting once completion is done.
    local first
    first="$( { simulate_completion "claude " > /dev/null; IFS= read -r line; echo "$line"; } < "$STDIN_FEED" )"
    assert_equals "TYPED-AHEAD-0" "$first"
}

function test_subcommand_helpers_take_nothing_from_the_callers_stdin() {
    # `claude mcp list` and friends run outside the cache build, on the same
    # terminal, and need the same treatment.
    simulate_completion "claude mcp get " > /dev/null < "$STDIN_FEED"
    assert_empty "$(cat "$PROBE_STDIN_LOG")"
}

# --- job control ---------------------------------------------------------

function test_probes_do_not_land_in_process_groups_of_their_own() {
    # Job control on, as it is in the interactive shell a user completes in.
    set -m
    simulate_completion "claude " > /dev/null < /dev/null
    set +m

    local own_group
    own_group="$(awk '$1 == $2' "$PROBE_PGID_LOG")"
    assert_empty "$own_group"
}

function test_the_probe_log_is_not_empty() {
    # Guards the two assertions above against passing because nothing ran.
    set -m
    simulate_completion "claude " > /dev/null < /dev/null
    set +m
    assert_greater_or_equal_than 4 "$(wc -l < "$PROBE_PGID_LOG" | tr -dc '0-9')"
}
