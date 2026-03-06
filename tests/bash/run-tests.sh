#!/usr/bin/env bash
# Test runner — finds bashunit, installs if needed, then runs tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Find bashunit: PATH first, then lib/bashunit, then auto-install
if command -v bashunit &>/dev/null; then
    BASHUNIT="bashunit"
elif [[ -x "$PROJECT_ROOT/lib/bashunit" ]]; then
    BASHUNIT="$PROJECT_ROOT/lib/bashunit"
else
    echo "Installing bashunit to lib/..."
    (cd "$PROJECT_ROOT" && curl -s https://bashunit.typeddevs.com/install.sh | bash)
    BASHUNIT="$PROJECT_ROOT/lib/bashunit"
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
