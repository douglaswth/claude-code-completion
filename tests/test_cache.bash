#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

# Use temp dir for XDG cache during tests
export XDG_CACHE_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_CACHE_HOME"' EXIT

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

# Test: _claude_cleanup_old_cache removes old version directories
base_dir="$XDG_CACHE_HOME/claude-code-completion/bash"
mkdir -p "$base_dir/0.9.0" "$base_dir/0.8.0"
_claude_cleanup_old_cache
if [[ ! -d "$base_dir/0.9.0" ]] && [[ ! -d "$base_dir/0.8.0" ]]; then
    pass "_claude_cleanup_old_cache removes old versions"
else
    fail "_claude_cleanup_old_cache removes old versions"
fi

# Test: _claude_cleanup_old_cache preserves current version directory
if [[ -d "$cache_dir" ]]; then
    pass "_claude_cleanup_old_cache preserves current version"
else
    fail "_claude_cleanup_old_cache preserves current version"
fi

if [[ $FAILURES -gt 0 ]]; then
    echo "$FAILURES test(s) failed"
    exit 1
else
    echo "All tests passed"
fi
