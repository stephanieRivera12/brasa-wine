#!/usr/bin/env bash
# Tests of brasa/fetch-third-party-sources.sh on fixtures (no network, no real sources).
# Run: brasa/tests/test-fetch-third-party-sources.sh
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../constants.sh
source "$TESTS_DIR/../constants.sh"
# shellcheck source=../lib.sh
source "$TESTS_DIR/../lib.sh"
# shellcheck source=../fetch-third-party-sources.sh
source "$TESTS_DIR/../fetch-third-party-sources.sh"
# shellcheck source=check.sh
source "$TESTS_DIR/check.sh"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/brasa-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT

# The real URLs, before the fixtures replace them.
REAL_URLS="$MOLTENVK_SRC_URL $MONO_SRC_URL $GECKO_SRC_URL"
REAL_GNUTLS_URL="$GNUTLS_URL"
REAL_GNUTLS_SHA256="$GNUTLS_SHA256"
REAL_PACKED_SOURCES=("${PACKED_SOURCES[@]}")
REAL_SOURCE_DOWNLOADS=("${SOURCE_DOWNLOADS[@]}")

REMOTE="$SCRATCH/remote"          # stands for the servers
FIXTURE_FOLDERS="$SCRATCH/folders"
DEPS_SRC_DIR="$SCRATCH/deps-src"
SOURCES_OUT_DIR="$SCRATCH/out"
download_file() { cp "$1" "$2"; }

# Every downloaded source is a small file named like its real archive.
mkdir -p "$REMOTE"
for name in "${SOURCE_DOWNLOADS[@]}"; do
  url_var="${name}_URL"
  fixture_name="$(source_file_name "$name")"
  printf 'content of %s' "$fixture_name" > "$REMOTE/$fixture_name"
  printf -v "$url_var" '%s' "$REMOTE/$fixture_name"
  printf -v "${name}_SHA256" '%s' "$(sha256_of "$REMOTE/$fixture_name")"
done

# Packed folders: a file, a hidden file and a link, in folders with a space in their path.
PACKED_SOURCES=("$FIXTURE_FOLDERS/with space/gmp|gmp-x-src.tar.xz|gmp-x" "$FIXTURE_FOLDERS/gnutls|gnutls-x-src.tar.xz|gnutls-x")
mkdir -p "$FIXTURE_FOLDERS/with space/gmp/sub" "$FIXTURE_FOLDERS/gnutls"
printf 'gmp file' > "$FIXTURE_FOLDERS/with space/gmp/sub/file.c"
printf 'hidden' > "$FIXTURE_FOLDERS/with space/gmp/.hidden"
ln -s sub/file.c "$FIXTURE_FOLDERS/with space/gmp/link"
printf 'gnutls file' > "$FIXTURE_FOLDERS/gnutls/file.c"

# Success: downloads, verifies, packs, copies, lists.
check "a clean run succeeds" 0 "$(status_of main)"
EXPECTED_FILES=$(( ${#PACKED_SOURCES[@]} + ${#SOURCE_DOWNLOADS[@]} ))
check "every source is in the output plus its sums" "$((EXPECTED_FILES + 1))" "$(find "$SOURCES_OUT_DIR" -type f | wc -l | tr -d ' ')"
check "SHA256SUMS lists every file" "$EXPECTED_FILES" "$(wc -l < "$SOURCES_OUT_DIR/$SOURCES_SUMS_NAME" | tr -d ' ')"
check "SHA256SUMS verifies with shasum" 0 "$(status_of bash -c 'cd "$1" && shasum -a 256 -c "$2"' _ "$SOURCES_OUT_DIR" "$SOURCES_SUMS_NAME")"
check "the sources were downloaded to DEPS_SRC_DIR" 1 "$([[ -s "$(archive_path MONO_SRC)" ]] && echo 1 || echo 0)"
check "the downloaded archives are copied unchanged" "$(sha256_of "$REMOTE/$(source_file_name NETTLE)")" "$(sha256_of "$SOURCES_OUT_DIR/$(source_file_name NETTLE)")"

PACKED_LIST="$("$TAR_TOOL" -tJf "$SOURCES_OUT_DIR/gmp-x-src.tar.xz" | LC_ALL=C sort | tr '\n' ' ')"
check "packed archive has the renamed top folder, hidden files and links" \
  "gmp-x/ gmp-x/.hidden gmp-x/link gmp-x/sub/ gmp-x/sub/file.c " "$PACKED_LIST"
check "packed archive keeps the content" "gmp file" "$("$TAR_TOOL" -xJOf "$SOURCES_OUT_DIR/gmp-x-src.tar.xz" gmp-x/sub/file.c)"
check "packed archive carries no owner of this Mac" 0 "$("$TAR_TOOL" -tvJf "$SOURCES_OUT_DIR/gnutls-x-src.tar.xz" | grep -c "$(id -un)" || true)"

# Same input, same offer.
FIRST_SUMS="$(cat "$SOURCES_OUT_DIR/$SOURCES_SUMS_NAME")"
main >/dev/null 2>&1
check "a second run gives the same SHA256SUMS" "$FIRST_SUMS" "$(cat "$SOURCES_OUT_DIR/$SOURCES_SUMS_NAME")"

# A stale file of an earlier run does not stay in the offer.
printf 'old' > "$SOURCES_OUT_DIR/stale.tar.xz"
main >/dev/null 2>&1
check "a stale file is removed" 0 "$([[ -e "$SOURCES_OUT_DIR/stale.tar.xz" ]] && echo 1 || echo 0)"

# An altered archive no longer matches its pinned hash.
rm -rf "$SOURCES_OUT_DIR"
printf 'tampered' > "$(archive_path SDL2)"
check "a pinned hash that does not match stops with the mismatch code" "$EXIT_HASH_MISMATCH" "$(status_of main)"
check "the tampered file is deleted" 0 "$([[ -e "$(archive_path SDL2)" ]] && echo 1 || echo 0)"
check "a mismatch leaves no output" 0 "$([[ -e "$SOURCES_OUT_DIR" ]] && echo 1 || echo 0)"

# Empty constants: every hash is printed, nothing is offered.
rm -rf "$DEPS_SRC_DIR" "$SOURCES_OUT_DIR"
MONO_SRC_SHA256=""; GECKO_SRC_SHA256=""
check "empty hashes stop with the hash-unset code" "$EXIT_HASH_UNSET" "$(status_of main)"
check "empty hashes print each computed hash" 2 "$(main 2>&1 | grep -c 'computed:' || true)"
check "empty hashes leave no output" 0 "$([[ -e "$SOURCES_OUT_DIR" ]] && echo 1 || echo 0)"
check "empty hashes keep the downloads" 1 "$([[ -s "$(archive_path GECKO_SRC)" ]] && echo 1 || echo 0)"

# A mismatch wins over an empty hash.
printf 'tampered' > "$(archive_path NETTLE)"
check "a mismatch outranks an empty hash" "$EXIT_HASH_MISMATCH" "$(status_of main)"

# Missing CodeWeavers folder.
rm -rf "$DEPS_SRC_DIR"
MONO_SRC_SHA256="$(sha256_of "$REMOTE/$(source_file_name MONO_SRC)")"; GECKO_SRC_SHA256="$(sha256_of "$REMOTE/$(source_file_name GECKO_SRC)")"
rm -rf "$FIXTURE_FOLDERS/gnutls"
check "a missing source folder stops with the missing-source code" "$EXIT_MISSING_SOURCE" "$(status_of main)"
check "the missing folder is named" 1 "$(main 2>&1 | grep -c "$FIXTURE_FOLDERS/gnutls" || true)"

# Failed download (server unreachable).
download_file() { return 22; }
mkdir -p "$FIXTURE_FOLDERS/gnutls"
check "a failed download stops the run" 1 "$([[ "$(status_of main)" != 0 ]] && echo 1 || echo 0)"

# The real constants of the offer.
check "the source URLs are the v1.2.10 tag and the winehq source archives" \
  "https://github.com/KhronosGroup/MoltenVK/archive/refs/tags/v1.2.10.tar.gz https://dl.winehq.org/wine/wine-mono/10.4.1/wine-mono-10.4.1-src.tar.xz https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-src.tar.xz" \
  "$REAL_URLS"

# gnutls is the official tarball, offered unchanged; only gmp is still packed from CodeWeavers.
check "gnutls is downloaded and offered unchanged" 1 "$(printf '%s\n' "${REAL_SOURCE_DOWNLOADS[@]}" | grep -c '^GNUTLS$' || true)"
check "only gmp is packed from CodeWeavers" "1" "${#REAL_PACKED_SOURCES[@]}"
check "the packed source is gmp" 1 "$(printf '%s\n' "${REAL_PACKED_SOURCES[@]}" | grep -c '|gmp-' || true)"
check "the gnutls URL is the official 3.8.13 tarball" \
  "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.13.tar.xz" "$REAL_GNUTLS_URL"
check "the gnutls hash is pinned" "ffed8ec1bf09c2426d4f14aae377de4753b53e537d685e604e99a8b16ca9c97e" "$REAL_GNUTLS_SHA256"

finish_checks
