#!/usr/bin/env bash
# Tests of the pure parts of brasa/lib.sh. Run: brasa/tests/test-lib.sh
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../constants.sh
source "$TESTS_DIR/../constants.sh"
# shellcheck source=../lib.sh
source "$TESTS_DIR/../lib.sh"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/brasa-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT

failures=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s (expected %q, got %q)\n' "$name" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}

status_of() {
  local status=0
  ( "$@" ) >/dev/null 2>&1 || status=$?
  printf '%s' "$status"
}

SAMPLE_FILE="$SCRATCH/sample.txt"
printf 'hello\n' > "$SAMPLE_FILE"
SAMPLE_SHA256="5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"

# sha256_of
check "sha256_of computes the digest" "$SAMPLE_SHA256" "$(sha256_of "$SAMPLE_FILE")"

# verify_sha256
check "verify_sha256 accepts a matching hash" 0 "$(status_of verify_sha256 "$SAMPLE_FILE" "$SAMPLE_SHA256")"
check "verify_sha256 stops on an empty constant" "$EXIT_HASH_UNSET" "$(status_of verify_sha256 "$SAMPLE_FILE" "")"
check "verify_sha256 prints the computed hash when empty" "1" \
  "$(verify_sha256 "$SAMPLE_FILE" "" 2>&1 | grep -c "$SAMPLE_SHA256" || true)"
check "verify_sha256 keeps the file when the constant is empty" 1 "$([[ -e "$SAMPLE_FILE" ]] && echo 1 || echo 0)"
check "verify_sha256 fails on a mismatch" "$EXIT_HASH_MISMATCH" "$(status_of verify_sha256 "$SAMPLE_FILE" "deadbeef")"
check "verify_sha256 deletes the file on a mismatch" 0 "$([[ -e "$SAMPLE_FILE" ]] && echo 1 || echo 0)"

# configure_fatal_warnings
CLEAN_LOG="$SCRATCH/clean.log"
printf 'checking for gcc... gcc\nconfigure: Wine is now configured\n' > "$CLEAN_LOG"
check "clean configure log passes" 0 "$(status_of check_configure_log "$CLEAN_LOG")"

for warning in "${CONFIGURE_FATAL_WARNINGS[@]}"; do
  BAD_LOG="$SCRATCH/bad.log"
  printf 'configure: WARNING: libX %s.\n' "$warning" > "$BAD_LOG"
  check "configure log with '$warning' fails" "$EXIT_CONFIGURE_WARNING" "$(status_of check_configure_log "$BAD_LOG")"
done

# disallowed_dependencies
OTOOL_OK="libfoo.dylib:
	@rpath/libfoo.dylib (compatibility version 1.0.0)
	/usr/lib/libbz2.1.0.dylib (compatibility version 1.0.0)
	/System/Library/Frameworks/Metal.framework/Versions/A/Metal (compatibility version 1.0.0)"
OTOOL_BAD="libfoo.dylib:
	@rpath/libfoo.dylib (compatibility version 1.0.0)
	/opt/homebrew/lib/libgmp.10.dylib (compatibility version 1.0.0)"
check "allowed dependencies yield nothing" "" "$(disallowed_dependencies "$OTOOL_OK")"
check "homebrew dependency is reported" "/opt/homebrew/lib/libgmp.10.dylib" "$(disallowed_dependencies "$OTOOL_BAD")"

# missing_paths
mkdir -p "$SCRATCH/root/bin"
: > "$SCRATCH/root/bin/wine"
check "missing_paths lists what is absent" "bin/wineserver" "$(missing_paths "$SCRATCH/root" bin/wine bin/wineserver)"
check "missing_paths is empty when all exist" "" "$(missing_paths "$SCRATCH/root" bin/wine)"

# stamps
DEPS_STAMP_DIR="$SCRATCH/stamps"
check "unbuilt library is not built" 0 "$(is_built gmp-6.3.0 && echo 1 || echo 0)"
mark_built gmp-6.3.0
check "marked library is built" 1 "$(is_built gmp-6.3.0 && echo 1 || echo 0)"
check "another version is not built" 0 "$(is_built gmp-6.4.0 && echo 1 || echo 0)"

# die_if_whitespace
check "path without spaces is accepted" 0 "$(status_of die_if_whitespace "/Users/x/work")"
check "path with spaces is refused" 1 "$(status_of die_if_whitespace "/Users/x/my work")"

# link_dir
mkdir -p "$SCRATCH/target" "$SCRATCH/links" "$SCRATCH/links/real"
link_dir "$SCRATCH/target" "$SCRATCH/links/a"
check "link_dir creates the link" "$SCRATCH/target" "$(readlink "$SCRATCH/links/a")"
check "link_dir is repeatable" 0 "$(status_of link_dir "$SCRATCH/target" "$SCRATCH/links/a")"
check "link_dir refuses to replace a real directory" 1 "$(status_of link_dir "$SCRATCH/target" "$SCRATCH/links/real")"

if ((failures > 0)); then
  printf '%d test(s) failed\n' "$failures"
  exit 1
fi
printf 'all tests passed\n'
