#!/usr/bin/env bash
# Usage: check-engine.sh <engine folder>. Exits 0 when the engine is self-contained and clean (spec 5.5).
set -euo pipefail

BRASA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=constants.sh
source "$BRASA_DIR/constants.sh"
# shellcheck source=lib.sh
source "$BRASA_DIR/lib.sh"
# shellcheck source=engine-checks.sh
source "$BRASA_DIR/engine-checks.sh"

[[ $# -eq 1 && -d "$1" ]] || die "Usage: $0 <engine folder>"
run_engine_checks "$(cd "$1" && pwd)" || exit "$EXIT_CHECK_FAILED"
