#!/usr/bin/env bash
# Tests of brasa/engine-checks.sh (what check-engine.sh runs). Run: brasa/tests/test-engine-checks.sh
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../constants.sh
source "$TESTS_DIR/../constants.sh"
# shellcheck source=../lib.sh
source "$TESTS_DIR/../lib.sh"
# shellcheck source=../engine-checks.sh
source "$TESTS_DIR/../engine-checks.sh"
# shellcheck source=check.sh
source "$TESTS_DIR/check.sh"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/brasa-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT

count_lines() { grep -c . <<< "$1" || true; }

# rpaths_of / disallowed_rpaths
OTOOL_L="Load command 12
          cmd LC_RPATH
      cmdsize 40
         path @loader_path/../.. (offset 12)
Load command 13
          cmd LC_RPATH
      cmdsize 40
         path /opt/homebrew/lib (offset 12)
Load command 14
          cmd LC_LOAD_DYLIB
         name /usr/lib/libSystem.B.dylib (offset 24)"
check "rpaths_of lists every LC_RPATH" $'@loader_path/../..\n/opt/homebrew/lib' "$(rpaths_of "$OTOOL_L")"
check "disallowed_rpaths reports only the outside one" "/opt/homebrew/lib" "$(disallowed_rpaths "$OTOOL_L")"
check "a bare @loader_path rpath is allowed" "" "$(disallowed_rpaths $'cmd LC_RPATH\n path @loader_path (offset 12)')"
check "no LC_RPATH yields nothing" "" "$(disallowed_rpaths "cmd LC_ID_DYLIB")"

# load_command_problems
OTOOL_DEPS_OK=$'x:\n\t@rpath/libgmp.10.dylib (compatibility version 1.0.0)\n\t@loader_path/libx.dylib (compatibility version 1.0.0)\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)'
OTOOL_DEPS_BAD=$'x:\n\t/opt/homebrew/lib/libgmp.10.dylib (compatibility version 1.0.0)'
RPATH_OK=$'cmd LC_RPATH\n path @loader_path/../lib (offset 12)'
check "a clean x86_64 binary has no problems" "" "$(load_command_problems "$OTOOL_DEPS_OK" "$RPATH_OK" "x86_64")"
check "a homebrew dependency is a problem" 1 "$(load_command_problems "$OTOOL_DEPS_BAD" "$RPATH_OK" "x86_64" | grep -c "dependency")"
check "an outside rpath is a problem" 1 "$(load_command_problems "$OTOOL_DEPS_OK" "$OTOOL_L" "x86_64" | grep -c "LC_RPATH")"
check "an arm64 slice is a problem" 1 "$(load_command_problems "$OTOOL_DEPS_OK" "$RPATH_OK" "arm64" | grep -c "architecture")"
check "a fat binary is a problem" 1 "$(load_command_problems "$OTOOL_DEPS_OK" "$RPATH_OK" "x86_64 arm64" | grep -c "architecture")"
check "no architecture is a problem" 1 "$(load_command_problems "$OTOOL_DEPS_OK" "$RPATH_OK" "" | grep -c "architecture")"

# is_macho_magic
check "thin 64-bit Mach-O magic" 0 "$(status_of is_macho_magic "cffaedfe")"
check "fat Mach-O magic" 0 "$(status_of is_macho_magic "cafebabe")"
for magic in feedface cefaedfe feedfacf cffaedfe cafebabe cafebabf; do
  check "Mach-O magic $magic is accepted" 0 "$(status_of is_macho_magic "$magic")"
done
check "text is not Mach-O" 1 "$(status_of is_macho_magic "23212f62")"
check "empty magic is not Mach-O" 1 "$(status_of is_macho_magic "")"

# macho_files / macho_problems with fake tools
ENGINE="$SCRATCH/engine"
mkdir -p "$ENGINE/bin" "$ENGINE/lib/wine/x86_64-unix" "$ENGINE/share"
printf '\xcf\xfa\xed\xfe rest' > "$ENGINE/bin/wine"
printf 'plain text' > "$ENGINE/share/note.txt"
printf '\xcf\xfa\xed\xfe rest' > "$ENGINE/lib/wine/x86_64-unix/ntdll.so"
check "macho_files lists only Mach-O files" "bin/wine
lib/wine/x86_64-unix/ntdll.so" "$(macho_files "$ENGINE" | sed "s|$ENGINE/||" | sort)"

FAKE_DIR="$SCRATCH/fake"; mkdir -p "$FAKE_DIR"
printf '#!/bin/bash\nif [[ "$1" == -L ]]; then printf "x:\\n\\t/opt/homebrew/lib/libz.dylib (compatibility version 1)\\n"; else printf "cmd LC_RPATH\\n path /opt/homebrew (offset 12)\\n"; fi\n' > "$FAKE_DIR/otool"
printf '#!/bin/bash\necho x86_64\n' > "$FAKE_DIR/lipo"
chmod +x "$FAKE_DIR/otool" "$FAKE_DIR/lipo"
OTOOL_TOOL="$FAKE_DIR/otool"; LIPO_TOOL="$FAKE_DIR/lipo"
check "macho_problems reports dependency and rpath" 2 "$(count_lines "$(macho_problems "$ENGINE/bin/wine")")"
LIPO_TOOL=false
check "macho_problems reports a tool failure" 1 "$(macho_problems "$ENGINE/bin/wine" | grep -c "could not inspect")"
OTOOL_TOOL=otool; LIPO_TOOL=lipo

# empty_dirs
mkdir -p "$SCRATCH/addons/full" "$SCRATCH/addons/empty"
: > "$SCRATCH/addons/full/file"
check "empty_dirs lists the empty and the absent" $'empty\nabsent' "$(empty_dirs "$SCRATCH/addons" full empty absent)"

# components_without_license
LICENSE_COMPONENTS=(wine gmp)
LICENSES_DIR_FIXTURE="$SCRATCH/lic"
mkdir -p "$LICENSES_DIR_FIXTURE/wine" "$LICENSES_DIR_FIXTURE/gmp"
: > "$LICENSES_DIR_FIXTURE/wine/COPYING.LIB"
check "a component without a file is reported" "gmp" "$(components_without_license "$LICENSES_DIR_FIXTURE")"
check "a missing README is reported" "README.md" "$(missing_license_readme "$LICENSES_DIR_FIXTURE")"
printf x > "$LICENSES_DIR_FIXTURE/gmp/COPYING"; printf x > "$LICENSES_DIR_FIXTURE/README.md"
check "all components with a file pass" "" "$(components_without_license "$LICENSES_DIR_FIXTURE")"
check "a present README passes" "" "$(missing_license_readme "$LICENSES_DIR_FIXTURE")"

# writable_by_others
mkdir -p "$SCRATCH/perm"; : > "$SCRATCH/perm/ok"; : > "$SCRATCH/perm/group"; : > "$SCRATCH/perm/other"
chmod 644 "$SCRATCH/perm/ok"; chmod 664 "$SCRATCH/perm/group"; chmod 646 "$SCRATCH/perm/other"
check "group- and other-writable files are reported" $'group\nother' "$(writable_by_others "$SCRATCH/perm" | sed "s|$SCRATCH/perm/||" | sort)"

# escaping_links
mkdir -p "$SCRATCH/links/lib" "$SCRATCH/outside"
: > "$SCRATCH/links/lib/real.dylib"
ln -s real.dylib "$SCRATCH/links/lib/inside.dylib"
check "a relative link inside passes" "" "$(escaping_links "$SCRATCH/links")"
ln -s "$SCRATCH/outside" "$SCRATCH/links/lib/abs.dylib"
ln -s ../../outside "$SCRATCH/links/lib/up.dylib"
check "absolute and escaping links are reported" $'lib/abs.dylib\nlib/up.dylib' "$(escaping_links "$SCRATCH/links" | sed "s|$SCRATCH/links/||" | sort)"

# personal_path_problems
FORBIDDEN_STRINGS=("/Users/" "/opt/homebrew")
printf 'fine\n/Users/me/x\n' > "$SCRATCH/leak.txt"; printf 'fine\n/usr/local/share/certs/\n' > "$SCRATCH/clean.txt"
check "a text file with /Users/ is reported" 1 "$(count_lines "$(personal_path_problems "$SCRATCH/leak.txt")")"
check "/usr/local is not searched" "" "$(personal_path_problems "$SCRATCH/clean.txt")"

# check_sonames
SONAME_ENGINE="$SCRATCH/soname"; mkdir -p "$SONAME_ENGINE/lib"
check "all sonames missing" "$(( ${#DEPS_LIBS[@]} + 1 ))" "$(count_lines "$(check_sonames "$SONAME_ENGINE")")"
for lib in "${DEPS_LIBS[@]}"; do : > "$SONAME_ENGINE/lib/$lib"; done
ln -s "$LIB_FREETYPE" "$SONAME_ENGINE/lib/$LIB_FREETYPE_LINK"
check "all sonames present" "" "$(check_sonames "$SONAME_ENGINE")"

# The scan must not leak file descriptors: 3000 files under a low descriptor limit
MANY="$SCRATCH/many"; mkdir -p "$MANY"
for i in $(seq 1 3000); do printf 'clean %s\n' "$i" > "$MANY/f$i.txt"; done
printf '/Users/me/leak\n' > "$MANY/f3000.txt"
MANY_OUTPUT="$( (ulimit -n 64; check_personal_paths "$MANY") 2>&1 || true)"
check "a 3000-file scan under a low fd limit finds only the leak" 1 "$(count_lines "$MANY_OUTPUT")"
check "the leak is the one reported" 1 "$(grep -c "f3000.txt: contains a personal" <<< "$MANY_OUTPUT" || true)"
check "an unreadable file is a problem, not a pass" 1 "$(chmod 000 "$MANY/f1.txt"; check_personal_paths "$MANY" 2>/dev/null | grep -c "f1.txt" || true)"
chmod 644 "$MANY/f1.txt"
RPATH_LOOP_OUTPUT="$( (ulimit -n 64; for _ in $(seq 1 1500); do disallowed_rpaths "$RPATH_OK"; done) 2>&1 || true)"
check "1500 rpath inspections under a low fd limit leave no error" "" "$RPATH_LOOP_OUTPUT"

# Wine's bundled libs: a third-party lib without a licence folder fails the licence check
WINE_LIBS_DIR="$SCRATCH/wine-libs"; WINE_OWN_LIBS=(own)
mkdir -p "$WINE_LIBS_DIR/own" "$WINE_LIBS_DIR/png" "$WINE_LIBS_DIR/bare"
LIC_ENGINE="$SCRATCH/lic-engine"; LICENSES_DIR="licenses"; LICENSE_COMPONENTS=(wine)
mkdir -p "$LIC_ENGINE/licenses/wine/libs/png"
printf x > "$LIC_ENGINE/licenses/wine/COPYING.LIB"; printf x > "$LIC_ENGINE/licenses/README.md"; printf x > "$LIC_ENGINE/licenses/wine/libs/png/LICENSE"
check "a lib without a licence folder is reported" "bare" "$(wine_libs_without_license "$LIC_ENGINE/licenses")"
check "check_licenses fails for it" "no licence for Wine lib: bare" "$(check_licenses "$LIC_ENGINE")"
mkdir -p "$LIC_ENGINE/licenses/wine/libs/bare"
check "an empty licence folder does not count" "bare" "$(wine_libs_without_license "$LIC_ENGINE/licenses")"
printf x > "$LIC_ENGINE/licenses/wine/libs/bare/LICENSE"
check "check_licenses passes once every lib has a licence" "" "$(check_licenses "$LIC_ENGINE")"
WINE_LIBS_DIR="$SCRATCH/no-such-libs"
check "an unreadable libs folder fails the check, never passes" 1 "$(check_licenses "$LIC_ENGINE" | grep -c . || true)"

finish_checks
