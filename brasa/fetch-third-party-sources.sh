#!/usr/bin/env bash
# Gathers the source code of the third-party components of the engine into SOURCES_OUT_DIR, with a
# SHA256SUMS (spec 5.6). Empty or wrong SHA-256 constants: prints the hashes and stops (exit 3 or 4).
set -euo pipefail

BRASA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=constants.sh
source "$BRASA_DIR/constants.sh"
# shellcheck source=lib.sh
source "$BRASA_DIR/lib.sh"

source_file_name() {
  local url_var="$1_URL" file_var="$1_FILE"
  printf '%s' "${!file_var:-$(basename "${!url_var}")}"
}

archive_path() {
  printf '%s/%s' "$DEPS_SRC_DIR" "$(source_file_name "$1")"
}

fetch_if_missing() {
  local name="$1" url_var="$1_URL" archive
  archive="$(archive_path "$name")"
  [[ -s "$archive" ]] || download_file "${!url_var}" "$archive"
}

verify_download() {
  local sha_var="$1_SHA256"
  verify_sha256 "$(archive_path "$1")" "${!sha_var}"
}

# Downloads and verifies every archive; all hashes are printed before stopping. Returns the worst status.
fetch_and_verify_downloads() {
  local name status worst=0
  mkdir -p "$DEPS_SRC_DIR"
  for name in "${SOURCE_DOWNLOADS[@]}"; do
    status=0
    { fetch_if_missing "$name" && verify_download "$name"; } || status=$?
    ((status > worst)) && worst="$status"
  done
  return "$worst"
}

missing_packed_folders() {
  local entry folder
  for entry in "${PACKED_SOURCES[@]}"; do
    folder="${entry%%|*}"
    [[ -d "$folder" ]] || printf '%s\n' "$folder"
  done
}

# Packs "<folder>|<archive>|<top folder>" into SOURCES_OUT_DIR.
pack_source() {
  local folder archive top
  IFS='|' read -r folder archive top <<< "$1"
  "$TAR_TOOL" -cJf "$SOURCES_OUT_DIR/$archive" "${TAR_PACK_FLAGS[@]}" \
    -s "|^\./|$top/|" -s "|^\.\$|$top|" -C "$folder" .
}

pack_all_sources() {
  local entry
  for entry in "${PACKED_SOURCES[@]}"; do
    say "Packing ${entry#*|}"
    pack_source "$entry"
  done
}

copy_downloads() {
  local name
  for name in "${SOURCE_DOWNLOADS[@]}"; do
    cp "$(archive_path "$name")" "$SOURCES_OUT_DIR/"
  done
}

write_sums() {
  (
    cd "$SOURCES_OUT_DIR"
    find . -maxdepth 1 -type f ! -name "$SOURCES_SUMS_NAME" | sed 's|^\./||' | LC_ALL=C sort \
      | while read -r file; do shasum -a 256 "$file"; done > "$SOURCES_SUMS_NAME"
  )
}

main() {
  local missing
  missing="$(missing_packed_folders)"
  [[ -z "$missing" ]] || { printf 'Source folders missing:\n%s\n' "$missing" >&2; exit "$EXIT_MISSING_SOURCE"; }
  fetch_and_verify_downloads || exit "$?"
  rm -rf -- "${SOURCES_OUT_DIR:?}"
  mkdir -p "$SOURCES_OUT_DIR"
  pack_all_sources
  copy_downloads
  write_sums
  say "Sources ready in $SOURCES_OUT_DIR ($(wc -l < "$SOURCES_OUT_DIR/$SOURCES_SUMS_NAME" | tr -d ' ') files)"
}

[[ "${BASH_SOURCE[0]}" != "$0" ]] || main "$@"
