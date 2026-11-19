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

# The real text of this Wine's configure (configure:9599), not our own constant.
REAL_MINGW_LOG="$SCRATCH/mingw.log"
printf 'configure: WARNING: Suitable PE cross-compiler not found, you should install mingw-w64 or llvm-mingw.\n' > "$REAL_MINGW_LOG"
check "real missing-mingw message fails" "$EXIT_CONFIGURE_WARNING" "$(status_of check_configure_log "$REAL_MINGW_LOG")"

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

# has_rpath
OTOOL_L="Load command 12
          cmd LC_RPATH
      cmdsize 40
         path @loader_path/../.. (offset 12)"
check "has_rpath finds the exact rpath" 0 "$(status_of has_rpath "$OTOOL_L" "@loader_path/../..")"
check "has_rpath ignores a longer rpath" 1 "$(status_of has_rpath "$OTOOL_L" "@loader_path/..")"
check "has_rpath fails when absent" 1 "$(status_of has_rpath "$OTOOL_L" "@loader_path/../lib")"

# forbidden_strings_in
FORBIDDEN_STRINGS=("/Users/" "/work/dir")
check "clean strings pass" "" "$(forbidden_strings_in $'libgnutls.30.dylib\n/usr/local/share/certs/')"
check "user path is reported" "/Users/me/build/x.c" "$(forbidden_strings_in $'ok\n/Users/me/build/x.c')"
check "work dir is reported" "/work/dir/a" "$(forbidden_strings_in $'/work/dir/a')"

# link_tools
mkdir -p "$SCRATCH/brew" "$SCRATCH/tools"
: > "$SCRATCH/brew/pkgconf"; : > "$SCRATCH/brew/x86_64-w64-mingw32-gcc"; : > "$SCRATCH/brew/freetype-config"
link_tools "$SCRATCH/tools" "$SCRATCH/brew/pkgconf" "$SCRATCH/brew/x86_64-w64-mingw32-*" "$SCRATCH/brew/absent"
check "link_tools links the listed tool" 1 "$([[ -L "$SCRATCH/tools/pkgconf" ]] && echo 1 || echo 0)"
check "link_tools expands globs" 1 "$([[ -L "$SCRATCH/tools/x86_64-w64-mingw32-gcc" ]] && echo 1 || echo 0)"
check "link_tools leaves out freetype-config" 0 "$([[ -e "$SCRATCH/tools/freetype-config" ]] && echo 1 || echo 0)"
check "link_tools skips what is absent" 0 "$([[ -e "$SCRATCH/tools/absent" ]] && echo 1 || echo 0)"

# engine_binaries_with_rpath
ENGINE_FIXTURE="$SCRATCH/engine"
mkdir -p "$ENGINE_FIXTURE/bin" "$ENGINE_FIXTURE/lib/wine/x86_64-unix"
check "no .so makes engine_binaries_with_rpath fail" 1 "$(status_of engine_binaries_with_rpath "$ENGINE_FIXTURE")"
: > "$ENGINE_FIXTURE/lib/wine/x86_64-unix/ntdll.so"
ENGINE_LISTING="$(engine_binaries_with_rpath "$ENGINE_FIXTURE" | sort)"
check "bin/wine has the bin rpath" 1 "$(grep -cxF "$ENGINE_FIXTURE/bin/wine:$RPATH_BIN" <<< "$ENGINE_LISTING")"
check "bin/wineserver has the bin rpath" 1 "$(grep -cxF "$ENGINE_FIXTURE/bin/wineserver:$RPATH_BIN" <<< "$ENGINE_LISTING")"
check "each .so has the unix rpath" 1 "$(grep -cxF "$ENGINE_FIXTURE/lib/wine/x86_64-unix/ntdll.so:$RPATH_UNIX_LIBS" <<< "$ENGINE_LISTING")"

# shipped_strings / leaks_in must not fail open
FAKE_BIN_DIR="$SCRATCH/faketools"
mkdir -p "$FAKE_BIN_DIR" "$SCRATCH/tmp"
printf '#!/bin/bash\ncat "$2"\n' > "$FAKE_BIN_DIR/fake-strings"
chmod +x "$FAKE_BIN_DIR/fake-strings"
CLEAN_BINARY="$SCRATCH/clean.bin"; printf 'libgnutls.30.dylib\n' > "$CLEAN_BINARY"
DIRTY_BINARY="$SCRATCH/dirty.bin"; printf '/Users/me/build/x.o\n' > "$DIRTY_BINARY"

STRIP_TOOL=false
check "shipped_strings fails when strip fails" 1 "$(TMPDIR="$SCRATCH/tmp" status_of shipped_strings "$CLEAN_BINARY")"
check "shipped_strings cleans its temp dir after a failure" 0 "$(find "$SCRATCH/tmp" -mindepth 1 | wc -l | tr -d ' ')"
STRIP_TOOL=true; STRINGS_TOOL="$FAKE_BIN_DIR/fake-strings"; OTOOL_TOOL=true
check "shipped_strings prints the strings" "libgnutls.30.dylib" "$(shipped_strings "$CLEAN_BINARY")"

STRINGS_TOOL=false
check "leaks_in reports a failed inspection" 1 "$(leaks_in "$CLEAN_BINARY" "@loader_path/../.." | grep -c "could not inspect")"
STRIP_TOOL=false; STRINGS_TOOL="$FAKE_BIN_DIR/fake-strings"
check "leaks_in reports a failed strip" 1 "$(leaks_in "$CLEAN_BINARY" "@loader_path/../.." | grep -c "could not inspect")"
STRIP_TOOL=true
check "leaks_in on a missing file reports it" 1 "$(OTOOL_TOOL=false leaks_in "$SCRATCH/absent" "@loader_path/../.." | grep -c "could not inspect")"
check "leaks_in reports a build path" 1 "$(leaks_in "$DIRTY_BINARY" "@loader_path/../.." | grep -c "contains a build path")"
check "leaks_in sees no build path in a clean binary" 0 "$(leaks_in "$CLEAN_BINARY" "@loader_path/../.." | grep -c "contains a build path")"

if ((failures > 0)); then
  printf '%d test(s) failed\n' "$failures"
  exit 1
fi
printf 'all tests passed\n'
