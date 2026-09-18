#!/usr/bin/env bash
# Test runner — finds bashunit, installs if needed, then runs tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# bashunit lives in lib/ and nowhere else. A copy on PATH is deliberately not
# consulted: it would silently take precedence over the managed one, which is
# how a checkout ends up running a different version from CI and reporting
# different coverage for identical code.
BASHUNIT="$PROJECT_ROOT/lib/bashunit"
# Records when upstream was last consulted. Holds a Unix timestamp as text
# rather than relying on the file's mtime, because reading mtime portably
# needs the GNU/BSD `stat` split this script would otherwise not care about.
STAMP="$PROJECT_ROOT/lib/.bashunit-checked"
CHECK_INTERVAL=86400  # once a day

# Install bashunit into lib/, optionally pinning a version.
#
# Staged through a temp directory because the upstream installer deletes the
# existing binary *before* downloading (`rm -f "$DIR"/bashunit; cd "$DIR"`),
# so installing straight into lib/ would leave no bashunit at all if the
# download failed - and `exec` below would then die before running a test.
# Staging is what makes the caller's "keeping $have" message true.
#
# `curl -f` matters: without it a captive portal or proxy answering 200 with
# an HTML page pipes that HTML into bash.
install_bashunit() {
    local want="${1:-latest}" staging output
    staging="$(mktemp -d)"
    if output="$(curl -fsS https://bashunit.com/install.sh | bash -s -- "$staging" "$want" 2>&1)" \
        && [[ -x "$staging/bashunit" ]]; then
        # Confirm we got the version we asked for. The installer takes
        # "<dir> <version>" today, but if that parsing ever changes it could
        # succeed while quietly ignoring the version - and the daily check
        # would then find the same mismatch and re-download forever, saying
        # nothing. Report the discrepancy once rather than loop in silence.
        local got
        got="$(grep -m1 -oE 'BASHUNIT_VERSION="[^"]+"' "$staging/bashunit" | cut -d'"' -f2 || true)"
        if [[ "$want" != "latest" && -n "$got" && "$got" != "$want" ]]; then
            echo "warning: asked bashunit's installer for $want but it delivered ${got}" >&2
        fi
        mkdir -p "$PROJECT_ROOT/lib"
        mv "$staging/bashunit" "$BASHUNIT"
        rm -rf "$staging"
        return 0
    fi
    printf '%s\n' "$output" >&2
    rm -rf "$staging"
    return 1
}

installed_version() {
    grep -m1 -oE 'BASHUNIT_VERSION="[^"]+"' "$BASHUNIT" 2>/dev/null | cut -d'"' -f2
}

# Latest release tag, via the redirect on releases/latest. That is github.com
# rather than api.github.com, so it is not subject to the unauthenticated API
# rate limit, and a HEAD request costs a couple of hundred milliseconds.
# Prints nothing when offline or when GitHub is unreachable; every caller
# treats empty as "cannot tell" and carries on.
latest_version() {
    curl -fsSI --max-time 5 https://github.com/TypedDevs/bashunit/releases/latest 2>/dev/null \
        | grep -i '^location:' | sed 's#.*/tag/##' | tr -d '\r'
}

if [[ ! -x "$BASHUNIT" ]]; then
    echo "Installing bashunit to lib/..."
    install_bashunit
    date +%s > "$STAMP"
else
    # The cached copy never updates itself, while CI installs fresh on every
    # run, so a checkout drifts behind without any visible symptom. Check at
    # most once a day: the probe is cheap but not free, and the answer does
    # not change often.
    last=0
    if [[ -f "$STAMP" ]]; then
        read -r last < "$STAMP" || true
        [[ "$last" =~ ^[0-9]+$ ]] || last=0
    fi
    now="$(date +%s)"
    if (( now - last >= CHECK_INTERVAL )); then
        # Stamped regardless of outcome, so an offline run costs one bounded
        # probe a day rather than one on every invocation.
        echo "$now" > "$STAMP"
        # `|| true` is load-bearing: this script runs under `set -e` with
        # `pipefail`, so a failing curl (offline, GitHub down) or a grep that
        # matches nothing would otherwise abort the whole test run before a
        # single test executed. Both callers already treat empty as "cannot
        # tell".
        have="$(installed_version || true)"
        latest="$(latest_version || true)"
        semver='^[0-9]+\.[0-9]+\.[0-9]+$'
        if [[ ! "$latest" =~ $semver ]]; then
            # Offline, or a Location header pointing somewhere other than a
            # release tag. Cannot tell, so leave the copy alone.
            :
        elif [[ ! "$have" =~ $semver ]]; then
            # A deliberately installed beta reports
            # "(non-stable) beta after 0.51.0 [...] #abc1234", which equals no
            # release tag and would otherwise be replaced by stable every day.
            # Say so rather than silently doing nothing, since silence is the
            # very failure this check exists to prevent.
            echo "note: bashunit reports version ${have:-unknown}; leaving it as is"
        elif [[ "$have" != "$latest" ]]; then
            echo "Refreshing bashunit $have -> $latest ..."
            # The tag is passed explicitly: the installer's own notion of
            # "latest" is hardcoded at deploy time (LATEST_BASHUNIT_VERSION),
            # so asking it for "latest" could reinstall the version we already
            # have and repeat that every day forever.
            install_bashunit "$latest" || echo "warning: refresh to $latest failed, keeping $have"
        fi
    fi
fi

# Parse args
ARGS=("$SCRIPT_DIR")
for arg in "$@"; do
    case "$arg" in
        --coverage) ARGS+=(--coverage --coverage-paths "$PROJECT_ROOT/claude.bash") ;;
        *) ARGS+=("$arg") ;;
    esac
done

exec "$BASHUNIT" "${ARGS[@]}"
