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

LICENSE_FILES_REAL=("${LICENSE_FILES[@]}")
LICENSE_TAR_MEMBERS_REAL=("${LICENSE_TAR_MEMBERS[@]}")
REAL_WINE_LIBS_DIR="$WINE_LIBS_DIR"
REAL_WINE_OWN_LIBS=("${WINE_OWN_LIBS[@]}")
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
OPTIONAL_LICENSE_TAR_MEMBERS=()
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

# Wine's bundled third-party libs: every licence-like file lands in licenses/wine/libs/<lib>/
WINE_LIBS_DIR="$SCRATCH/wine-libs"
WINE_OWN_LIBS=(own)
mkdir -p "$WINE_LIBS_DIR/own" "$WINE_LIBS_DIR/png" "$WINE_LIBS_DIR/tiff" "$WINE_LIBS_DIR/bare"
printf 'x' > "$WINE_LIBS_DIR/own/LICENSE"
printf 'png' > "$WINE_LIBS_DIR/png/LICENSE"; printf 'src' > "$WINE_LIBS_DIR/png/png.c"
printf 'tiff' > "$WINE_LIBS_DIR/tiff/COPYRIGHT"; printf 'n' > "$WINE_LIBS_DIR/tiff/notice.txt"
check "third-party libs exclude Wine's own" "bare png tiff" "$(third_party_wine_libs | tr '\n' ' ' | sed 's/ $//')"
check "licence-like files are found, others not" "$WINE_LIBS_DIR/png/LICENSE" "$(wine_lib_license_files png)"
install_wine_lib_licenses "$PKG/licenses"
check "a lib's licence is copied under its name" "png" "$(cat "$PKG/licenses/wine/libs/png/LICENSE")"
check "every licence-like file of a lib is copied" "COPYRIGHT notice.txt" "$(ls "$PKG/licenses/wine/libs/tiff" | tr '\n' ' ' | sed 's/ $//')"
check "a lib without a licence file gets no folder" 0 "$([[ -e "$PKG/licenses/wine/libs/bare" ]] && echo 1 || echo 0)"
check "a source file is not copied" 0 "$([[ -e "$PKG/licenses/wine/libs/png/png.c" ]] && echo 1 || echo 0)"
check "Wine's own libs are not copied" 0 "$([[ -e "$PKG/licenses/wine/libs/own" ]] && echo 1 || echo 0)"
WINE_LIBS_DIR="$SCRATCH/no-such-libs"
check "a missing libs folder is an error, not an empty list" 1 "$(status_of third_party_wine_libs)"

# optional licence members (MoltenVK NOTICE): copied only when the source tarball has them
mkdir -p "$LIC_SRC/t/src-1"; printf 'notice' > "$LIC_SRC/t/src-1/NOTICE"; printf 'other' > "$LIC_SRC/t/src-1/README"
(cd "$LIC_SRC/t" && tar -czf "$LIC_SRC/with-notice.tar.gz" src-1)
mkdir -p "$LIC_SRC/t/src-2"; printf 'other' > "$LIC_SRC/t/src-2/README"
(cd "$LIC_SRC/t" && tar -czf "$LIC_SRC/without-notice.tar.gz" src-2)
mkdir -p "$LIC_SRC/t/src-3"; printf 'elsewhere' > "$LIC_SRC/t/src-3/NOTICE.txt"
(cd "$LIC_SRC/t" && tar -czf "$LIC_SRC/moved-notice.tar.gz" src-3)
optional() { OPTIONAL_LICENSE_TAR_MEMBERS=("$1"); }
optional "opt|with-notice.tar.gz|src-1/NOTICE|NOTICE"
check "an optional member present in the tarball is copied" 0 "$(status_of install_optional_licenses "$PKG/licenses")"
install_optional_licenses "$PKG/licenses"
check "the copied member has its content" "notice" "$(cat "$PKG/licenses/opt/NOTICE")"
optional "opt2|without-notice.tar.gz|src-2/NOTICE|NOTICE"
check "no NOTICE anywhere upstream is accepted" 0 "$(status_of install_optional_licenses "$PKG/licenses")"
check "no NOTICE upstream is recorded in the output" 1 "$(install_optional_licenses "$PKG/licenses" 2>&1 | grep -c 'no NOTICE upstream' || true)"
check "no NOTICE upstream creates no file" 0 "$([[ -e "$PKG/licenses/opt2" ]] && echo 1 || echo 0)"
optional "opt3|moved-notice.tar.gz|src-1/NOTICE|NOTICE"
check "a NOTICE at another path (other top folder) fails" "$EXIT_MISSING_SOURCE" "$(status_of install_optional_licenses "$PKG/licenses")"
check "the failure names the NOTICE found" 1 "$(install_optional_licenses "$PKG/licenses" 2>&1 | grep -c 'src-3/NOTICE.txt' || true)"
optional "opt4|absent.tar.gz|x/NOTICE|NOTICE"
check "an absent tarball fails, never skips" "$EXIT_MISSING_SOURCE" "$(status_of install_optional_licenses "$PKG/licenses")"
DEPS_SRC_DIR="$LIC_SRC"
check "an absent optional tarball is listed as a missing source" "tarball $LIC_SRC/absent.tar.gz" "$(missing_license_sources)"
OPTIONAL_LICENSE_TAR_MEMBERS=()

# the real constants: libunistring ships the LGPL 2.1 text, Wine ships its LICENSE
check "libunistring has one licence entry, the LGPL 2.1 from the official gnutls tarball" \
  "libunistring|gnutls-$GNUTLS_VERSION.tar.xz|gnutls-$GNUTLS_VERSION/COPYING.LESSERv2|COPYING.LESSERv2" \
  "$(printf '%s\n' "${LICENSE_TAR_MEMBERS_REAL[@]}" | grep '^libunistring|')"
check "gnutls licences come from the official tarball (GPL 3 and LGPL 2.1)" \
  "gnutls|gnutls-$GNUTLS_VERSION.tar.xz|gnutls-$GNUTLS_VERSION/COPYING|COPYING gnutls|gnutls-$GNUTLS_VERSION.tar.xz|gnutls-$GNUTLS_VERSION/COPYING.LESSERv2|COPYING.LESSERv2" \
  "$(printf '%s\n' "${LICENSE_TAR_MEMBERS_REAL[@]}" | grep '^gnutls|' | tr '\n' ' ' | sed 's/ $//')"
check "libtasn1 licences come from the official tarball" 2 \
  "$(printf '%s\n' "${LICENSE_TAR_MEMBERS_REAL[@]}" | grep -c "^libtasn1|gnutls-$GNUTLS_VERSION.tar.xz|" || true)"
check "no licence is read from CodeWeavers' gnutls tree any more" 0 \
  "$(printf '%s\n' "${LICENSE_FILES_REAL[@]}" | grep -c "$GNUTLS_REAL_DIR/gnutls" || true)"
check "the gnutls version is the official 3.8.13" "3.8.13" "$GNUTLS_VERSION"
check "the engine revision is 26.3.0-3" "26.3.0-3" "$ENGINE_VERSION"
check "the gnutls soname Wine expects is unchanged" "libgnutls.30.dylib" "$LIB_GNUTLS"
check "Wine's LICENSE is listed" 1 "$(printf '%s\n' "${LICENSE_FILES_REAL[@]}" | grep -c "^wine|$BRASA_FORK_DIR/LICENSE$" || true)"
check "the real Wine libs folder exists" 1 "$([[ -d "$REAL_WINE_LIBS_DIR" ]] && echo 1 || echo 0)"
check "every real third-party Wine lib has a licence-like file" "" "$(WINE_LIBS_DIR="$REAL_WINE_LIBS_DIR"; WINE_OWN_LIBS=("${REAL_WINE_OWN_LIBS[@]}"); for lib in $(third_party_wine_libs); do [[ -n "$(wine_lib_license_files "$lib")" ]] || echo "$lib"; done)"

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
