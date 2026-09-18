#!/usr/bin/env bash
# Times the cache build on this branch against a baseline ref, and reports the
# machine it ran on. Driven by .github/workflows/bench.yml; runnable locally.
#
# Every timed build runs in its own subshell with its own XDG_CACHE_HOME, so a
# run never reads a cache another run published.
set -euo pipefail

BASELINE_REF="${BASELINE_REF:-main}"
BENCH_REPS="${BENCH_REPS:-3}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

baseline_script="$(mktemp)"
git show "${BASELINE_REF}:claude.bash" > "$baseline_script"

# shellcheck source=/dev/null
cores="$(source ./claude.bash >/dev/null 2>&1; _claude_cpu_count)"
concurrency="$(source ./claude.bash >/dev/null 2>&1; _claude_probe_concurrency)"

version_before="$(claude --version 2>/dev/null | head -1)"

run_build() {
    # Echoes elapsed wall seconds for one full cache build of $1.
    local script="$1" cache elapsed
    cache="$(mktemp -d)"
    TIMEFORMAT=%R
    elapsed="$( { time ( XDG_CACHE_HOME="$cache" bash -c "source '$script'; _claude_build_cache" >/dev/null 2>&1 ) ; } 2>&1 )"
    rm -rf "$cache"
    printf '%s\n' "$elapsed"
}

mean() {
    # Mean of the values on stdin, to two decimals, without requiring bc.
    awk '{ total += $1; n++ } END { if (n) printf "%.2f", total / n; else print "n/a" }'
}

baseline_times=()
branch_times=()
for (( rep=1; rep <= BENCH_REPS; rep++ )); do
    # Interleaved so a machine that slows down partway through penalizes both
    # variants equally rather than whichever ran last.
    baseline_times+=("$(run_build "$baseline_script")")
    branch_times+=("$(run_build "./claude.bash")")
done

version_after="$(claude --version 2>/dev/null | head -1)"

baseline_mean="$(printf '%s\n' "${baseline_times[@]}" | mean)"
branch_mean="$(printf '%s\n' "${branch_times[@]}" | mean)"

{
    echo "### bash — $(uname -s) ($cores cores, concurrency $concurrency)"
    echo
    echo "| Variant | Mean | Runs |"
    echo "| --- | --- | --- |"
    echo "| \`$BASELINE_REF\` (baseline) | ${baseline_mean}s | ${baseline_times[*]} |"
    echo "| this branch | ${branch_mean}s | ${branch_times[*]} |"
    echo
    echo "CLI before: \`$version_before\` · after: \`$version_after\`"
    if [[ "$version_before" != "$version_after" ]]; then
        echo
        echo "> **The CLI updated itself mid-run — these timings are not comparable.**"
    fi
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

rm -f "$baseline_script"

# A version change invalidates the comparison, so fail rather than publish
# numbers that look authoritative and are not.
[[ "$version_before" == "$version_after" ]]
