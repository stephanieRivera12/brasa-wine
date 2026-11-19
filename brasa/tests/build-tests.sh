#!/usr/bin/env bash
# Compiles the test programs for x86_64 and i386 into build/brasa-wine-tests/<arch>/.
# Run: brasa/tests/build-tests.sh
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../constants.sh
source "$TESTS_DIR/../constants.sh"
# shellcheck source=test-constants.sh
source "$TESTS_DIR/test-constants.sh"
# shellcheck source=../lib.sh
source "$TESTS_DIR/../lib.sh"

compiler_of() {
  local variable="TEST_CC_$1"
  printf '%s' "${!variable}"
}

build_program() {
  local arch="$1" program="$2" compiler
  compiler="$(compiler_of "$arch")"
  "$compiler" "${TEST_CFLAGS[@]}" -o "$TESTS_OUT_DIR/$arch/$program.exe" "$TESTS_SRC_DIR/$program.c"
}

for arch in "${TEST_ARCHS[@]}"; do
  mkdir -p "$TESTS_OUT_DIR/$arch"
  for program in "${TEST_PROGRAMS[@]}"; do
    build_program "$arch" "$program" || die "could not build $program for $arch"
  done
done
printf 'built %s for %s into %s\n' "${TEST_PROGRAMS[*]}" "${TEST_ARCHS[*]}" "$TESTS_OUT_DIR"
