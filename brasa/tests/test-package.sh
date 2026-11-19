#!/usr/bin/env bash
# Tests of the steps of brasa/package.sh on fixtures (no network, no real engine).
# Run: brasa/tests/test-package.sh
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../constants.sh
source "$TESTS_DIR/../constants.sh"
# shellcheck source=../lib.sh
source "$TESTS_DIR/../lib.sh"
# shellcheck source=../engine-checks.sh
source "$TESTS_DIR/../engine-checks.sh"
# shellcheck source=../package.sh
source "$TESTS_DIR/../package.sh"
# shellcheck source=check.sh
source "$TESTS_DIR/check.sh"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/brasa-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT

PKG="$SCRATCH/pkg"
mkdir -p "$PKG/lib/wine/x86_64-unix" "$PKG/lib/wine/x86_64-windows"

# remove_non_wine_files
: > "$PKG/lib/wine/x86_64-unix/winemetal.so"; : > "$PKG/lib/wine/x86_64-windows/winemetal.dll"
: > "$PKG/lib/wine/x86_64-unix/ntdll.so"
remove_non_wine_files "$PKG"
check "winemetal.so is removed" 0 "$([[ -e "$PKG/lib/wine/x86_64-unix/winemetal.so" ]] && echo 1 || echo 0)"
check "winemetal.dll is removed" 0 "$([[ -e "$PKG/lib/wine/x86_64-windows/winemetal.dll" ]] && echo 1 || echo 0)"
check "Wine's own files stay" 1 "$([[ -e "$PKG/lib/wine/x86_64-unix/ntdll.so" ]] && echo 1 || echo 0)"

# vendor_dependency_libs: stage symlinks become real files
DEPS_PREFIX="$SCRATCH/deps"; mkdir -p "$DEPS_PREFIX/lib"
for lib in "${DEPS_LIBS[@]}"; do printf '%s' "$lib" > "$DEPS_PREFIX/lib/$lib"; done
for lib in "${DEPS_LIBS[@]}" "$LIB_FREETYPE_LINK"; do ln -s "$DEPS_PREFIX/lib/$lib" "$PKG/lib/$lib"; done
vendor_dependency_libs "$PKG"
check "no library of the package is a symlink except freetype's" 1 "$(find "$PKG/lib" -maxdepth 1 -type l | wc -l | tr -d ' ')"
check "libgnutls is a real copy" "$LIB_GNUTLS" "$(cat "$PKG/lib/$LIB_GNUTLS")"
check "libfreetype.dylib is a relative link" "$LIB_FREETYPE" "$(readlink "$PKG/lib/$LIB_FREETYPE_LINK")"
check "the package has no link leaving it" "" "$(escaping_links "$PKG")"

# fetch_addons (the network is replaced by a local copy)
DOWNLOADS_DIR="$SCRATCH/downloads"
FIXTURE_ADDONS="$SCRATCH/addon-src"
mkdir -p "$FIXTURE_ADDONS/wine-mono-$MONO_VERSION" "$FIXTURE_ADDONS/wine-gecko-$GECKO_VERSION-x86" "$FIXTURE_ADDONS/wine-gecko-$GECKO_VERSION-x86_64"
printf 'MIT' > "$FIXTURE_ADDONS/wine-mono-$MONO_VERSION/LICENSE"
printf 'MPL' > "$FIXTURE_ADDONS/wine-gecko-$GECKO_VERSION-x86/LICENSE"
printf 'MPL' > "$FIXTURE_ADDONS/wine-gecko-$GECKO_VERSION-x86_64/LICENSE"
(cd "$FIXTURE_ADDONS" && tar -cJf mono.tar.xz "wine-mono-$MONO_VERSION" \
  && tar -cJf g86.tar.xz "wine-gecko-$GECKO_VERSION-x86" && tar -cJf g64.tar.xz "wine-gecko-$GECKO_VERSION-x86_64")
MONO_URL="$FIXTURE_ADDONS/mono.tar.xz"; GECKO_X86_URL="$FIXTURE_ADDONS/g86.tar.xz"; GECKO_X86_64_URL="$FIXTURE_ADDONS/g64.tar.xz"
download_file() { cp "$1" "$2"; }

MONO_SHA256=""; GECKO_X86_SHA256=""; GECKO_X86_64_SHA256=""
check "empty hashes stop with the hash-unset code" "$EXIT_HASH_UNSET" "$(status_of download_and_verify_addons)"
check "empty hashes print every computed hash" 3 "$(download_and_verify_addons 2>&1 | grep -c 'computed:' || true)"
check "empty hashes keep the downloads" 1 "$([[ -e "$DOWNLOADS_DIR/mono.tar.xz" ]] && echo 1 || echo 0)"

MONO_SHA256="$(sha256_of "$FIXTURE_ADDONS/mono.tar.xz")"
GECKO_X86_SHA256="$(sha256_of "$FIXTURE_ADDONS/g86.tar.xz")"
GECKO_X86_64_SHA256="deadbeef"
check "a wrong hash fails with the mismatch code" "$EXIT_HASH_MISMATCH" "$(status_of download_and_verify_addons)"
check "a wrong hash deletes that download" 0 "$([[ -e "$DOWNLOADS_DIR/g64.tar.xz" ]] && echo 1 || echo 0)"
GECKO_X86_64_SHA256="$(sha256_of "$FIXTURE_ADDONS/g64.tar.xz")"
check "matching hashes pass" 0 "$(status_of download_and_verify_addons)"

unpack_addons "$PKG"
check "mono lands in share/wine/mono" 1 "$([[ -f "$PKG/share/wine/mono/wine-mono-$MONO_VERSION/LICENSE" ]] && echo 1 || echo 0)"
check "gecko x86_64 lands in share/wine/gecko" 1 "$([[ -f "$PKG/share/wine/gecko/wine-gecko-$GECKO_VERSION-x86_64/LICENSE" ]] && echo 1 || echo 0)"
check "the addons check passes" "" "$(check_addons "$PKG")"

# licences
LIC_SRC="$SCRATCH/lic-src"; mkdir -p "$LIC_SRC/t/pkg-1"
printf 'wine' > "$LIC_SRC/COPYING.LIB"; printf 'inner' > "$LIC_SRC/t/pkg-1/LICENSE"
(cd "$LIC_SRC/t" && tar -czf "$LIC_SRC/pkg-1.tar.gz" pkg-1)
DEPS_SRC_DIR="$LIC_SRC"
LICENSE_FILES=("wine|$LIC_SRC/COPYING.LIB" "gone|$LIC_SRC/absent")
LICENSE_TAR_MEMBERS=("pkg|pkg-1.tar.gz|pkg-1/LICENSE|LICENSE" "pkg2|absent.tar.gz|x/LICENSE|LICENSE")
check "missing licence sources are listed" $'file '"$LIC_SRC/absent"$'\ntarball '"$LIC_SRC/absent.tar.gz" "$(missing_license_sources)"
LICENSE_FILES=("wine|$LIC_SRC/COPYING.LIB"); LICENSE_TAR_MEMBERS=("pkg|pkg-1.tar.gz|pkg-1/LICENSE|LICENSE")
check "no missing sources when all exist" "" "$(missing_license_sources)"
LICENSES_README_SOURCE="$LIC_SRC/README.md"; printf 'where the source is' > "$LICENSES_README_SOURCE"
install_licenses "$PKG"
check "a file licence is copied under its component" "wine" "$(cat "$PKG/licenses/wine/COPYING.LIB")"
check "a tarball member is extracted under its component" "inner" "$(cat "$PKG/licenses/pkg/LICENSE")"
check "the README is copied" "where the source is" "$(cat "$PKG/licenses/README.md")"

# the real licence sources of the fork exist, including mono and gecko
LICENSE_FILES=("mono|$MONO_LICENSE_SOURCE" "gecko|$GECKO_LICENSE_SOURCE" "gecko|$GECKO_LICENSE_HTML_SOURCE")
check "the committed mono and gecko licences exist" "" "$(missing_license_sources)"
install_licenses "$PKG"
check "mono's COPYING is installed" 1 "$([[ -s "$PKG/licenses/mono/COPYING" ]] && echo 1 || echo 0)"
check "gecko's LICENSE and license.html are installed" 2 "$(ls "$PKG/licenses/gecko" | wc -l | tr -d ' ')"

# version and permissions
write_version "$PKG" "abc123"
check "VERSION holds version and commit" "$ENGINE_VERSION abc123" "$(cat "$PKG/$VERSION_FILE")"
chmod 666 "$PKG/lib/$LIB_GNUTLS"
lock_permissions "$PKG"
check "nothing is writable by others afterwards" "" "$(writable_by_others "$PKG")"

# pe_strip_tool_for
check "i386 PE dlls use the i686 tool" "i686-w64-mingw32-strip" "$(pe_strip_tool_for "$PKG/lib/wine/i386-windows/a.dll")"
check "x86_64 PE dlls use the x86_64 tool" "x86_64-w64-mingw32-strip" "$(pe_strip_tool_for "$PKG/lib/wine/x86_64-windows/a.dll")"
check "other files have no PE tool" "" "$(pe_strip_tool_for "$PKG/bin/wine")"
check "MZ is the PE magic" 0 "$(status_of is_pe_magic "4d5a")"
check "text is not PE" 1 "$(status_of is_pe_magic "2321")"

# publish_engine keeps the previous engine unless the new one is in place
ENGINES_VENDOR_DIR="$SCRATCH/engines"; ENGINE_OUTPUT="$ENGINES_VENDOR_DIR/wine-brasa-test"
mkdir -p "$ENGINE_OUTPUT" "$SCRATCH/new"; printf old > "$ENGINE_OUTPUT/id"; printf new > "$SCRATCH/new/id"
check "a failed publish fails" 1 "$(status_of publish_engine "$SCRATCH/absent")"
check "a failed publish keeps the previous engine" "old" "$(cat "$ENGINE_OUTPUT/id")"
check "a failed publish leaves no leftovers" 1 "$(ls "$ENGINES_VENDOR_DIR" | wc -l | tr -d ' ')"
publish_engine "$SCRATCH/new"
check "a publish installs the new engine" "new" "$(cat "$ENGINE_OUTPUT/id")"
check "a publish removes the old one" 1 "$(ls "$ENGINES_VENDOR_DIR" | wc -l | tr -d ' ')"
rm -rf "$ENGINE_OUTPUT"; mkdir -p "$SCRATCH/new2"
publish_engine "$SCRATCH/new2"
check "a first publish works without a previous engine" 1 "$([[ -d "$ENGINE_OUTPUT" ]] && echo 1 || echo 0)"

finish_checks
