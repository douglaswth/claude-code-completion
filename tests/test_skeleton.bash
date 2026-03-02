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
