#!/usr/bin/env bash
# Turns the built stage into the self-contained engine folder ENGINE_OUTPUT (spec 5.5).
# Empty SHA-256 constants for mono/gecko: prints the computed hashes and stops (exit 3).
set -euo pipefail

BRASA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=constants.sh
source "$BRASA_DIR/constants.sh"
# shellcheck source=lib.sh
source "$BRASA_DIR/lib.sh"
# shellcheck source=engine-checks.sh
source "$BRASA_DIR/engine-checks.sh"

archive_path() {
  local url_var="$1_URL"
  printf '%s/%s' "$DOWNLOADS_DIR" "$(basename "${!url_var}")"
}

remove_non_wine_files() {
  local name
  for name in "${NOT_WINE_FILES[@]}"; do
    find "$1" -type f -name "$name" -delete
  done
}

# The stage links the libraries into the work folder; the package gets real files.
vendor_dependency_libs() {
  local pkg="$1" lib
  for lib in "${DEPS_LIBS[@]}"; do
    rm -f -- "$pkg/lib/$lib"
    cp -L "$DEPS_PREFIX/lib/$lib" "$pkg/lib/$lib"
  done
  ln -sfn "$LIB_FREETYPE" "$pkg/lib/$LIB_FREETYPE_LINK"
}

# Downloads every addon, then verifies all of them so each computed hash is printed in one run.
# Returns the first failing status.
download_and_verify_addons() {
  local name file status=0 code sha_var
  mkdir -p "$DOWNLOADS_DIR"
  for name in "${ADDON_NAMES[@]}"; do
    file="$(archive_path "$name")"
    [[ -f "$file" ]] || download_file "$(url_of "$name")" "$file"
  done
  for name in "${ADDON_NAMES[@]}"; do
    sha_var="${name}_SHA256"
    code=0
    verify_sha256 "$(archive_path "$name")" "${!sha_var}" || code=$?
    ((status != 0)) || status="$code"
  done
  return "$status"
}

url_of() {
  local url_var="$1_URL"
  printf '%s' "${!url_var}"
}

unpack_addons() {
  local pkg="$1" name dest_var dest
  for name in "${ADDON_NAMES[@]}"; do
    dest_var="${name}_DEST"
    dest="$pkg/${!dest_var}"
    mkdir -p "$dest"
    tar -xJf "$(archive_path "$name")" -C "$dest"
  done
}

# Prints "file <path>" or "tarball <path>" for each licence source that does not exist.
missing_license_sources() {
  local entry file tarball
  for entry in "${LICENSE_FILES[@]}"; do
    file="${entry#*|}"
    [[ -f "$file" ]] || printf 'file %s\n' "$file"
  done
  for entry in "${LICENSE_TAR_MEMBERS[@]}"; do
    tarball="$DEPS_SRC_DIR/$(cut -d'|' -f2 <<< "$entry")"
    [[ -f "$tarball" ]] || printf 'tarball %s\n' "$tarball"
  done
}

copy_license_file() {
  local dest="$1" component="$2" file="$3"
  mkdir -p "$dest/$component"
  cp "$file" "$dest/$component/"
}

extract_license_member() {
  local dest="$1" entry="$2" component tarball member name
  IFS='|' read -r component tarball member name <<< "$entry"
  mkdir -p "$dest/$component"
  tar -xOf "$DEPS_SRC_DIR/$tarball" "$member" > "$dest/$component/$name"
}

# Copies the licence-like files of every third-party lib of Wine into <licenses>/wine/libs/<lib>/.
install_wine_lib_licenses() {
  local dest="$1/$WINE_LIBS_LICENSE_SUBDIR" lib file
  for lib in $(third_party_wine_libs); do
    while read -r file; do
      mkdir -p "$dest/$lib"
      cp "$file" "$dest/$lib/"
    done < <(wine_lib_license_files "$lib")
  done
}

# Extracts the members that exist; a missing tarball or member is skipped, not an error.
install_optional_licenses() {
  local dest="$1" entry component tarball member name
  for entry in "${OPTIONAL_LICENSE_TAR_MEMBERS[@]}"; do
    IFS='|' read -r component tarball member name <<< "$entry"
    "$TAR_TOOL" -tf "$DEPS_SRC_DIR/$tarball" "$member" >/dev/null 2>&1 || continue
    mkdir -p "$dest/$component"
    "$TAR_TOOL" -xOf "$DEPS_SRC_DIR/$tarball" "$member" > "$dest/$component/$name"
  done
}

install_licenses() {
  local dest="$1/$LICENSES_DIR" entry
  mkdir -p "$dest"
  for entry in "${LICENSE_FILES[@]}"; do
    copy_license_file "$dest" "${entry%%|*}" "${entry#*|}"
  done
  for entry in "${LICENSE_TAR_MEMBERS[@]}"; do
    extract_license_member "$dest" "$entry"
  done
  install_wine_lib_licenses "$dest"
  install_optional_licenses "$dest"
  cp "$LICENSES_README_SOURCE" "$dest/README.md"
}

# Prints the tool that strips the PE dlls of that path (nothing for other files).
pe_strip_tool_for() {
  local entry
  for entry in "${PE_STRIP_TOOLS[@]}"; do
    [[ "$1" == *"/${entry%%:*}/"* ]] && printf '%s\n' "${entry#*:}"
  done
  return 0
}

is_pe_magic() {
  [[ "$1" == 4d5a* ]]
}

is_pe() {
  is_pe_magic "$(head -c 2 "$1" | od -An -tx1 | tr -d ' \n')"
}

strip_macho_files() {
  local file
  while IFS= read -r file; do
    chmod u+w "$file"
    "$STRIP_TOOL" -S "$file"
  done < <(macho_files "$1")
}

strip_pe_files() {
  local file tool
  while IFS= read -r file; do
    tool="$(pe_strip_tool_for "$file")"
    [[ -n "$tool" ]] && is_pe "$file" || continue
    chmod u+w "$file"
    "$tool" -S "$file"
  done < <(find "$1" -type f)
}

write_version() {
  printf '%s %s\n' "$ENGINE_VERSION" "$2" > "$1/$VERSION_FILE"
}

lock_permissions() {
  chmod -R "$ENGINE_FILE_MODE_STRIP" "$1"
}

assemble_engine() {
  local pkg="$1"
  rm -rf -- "${PACKAGE_WORK_DIR:?}"
  mkdir -p "$pkg"
  cp -RP "$STAGE_ENGINE_DIR/." "$pkg"
  remove_non_wine_files "$pkg"
  vendor_dependency_libs "$pkg"
  unpack_addons "$pkg"
  install_licenses "$pkg"
  strip_macho_files "$pkg"
  strip_pe_files "$pkg"
  write_version "$pkg" "$(git -C "$BRASA_FORK_DIR" rev-parse HEAD)"
  lock_permissions "$pkg"
}

publish_engine() {
  local previous="$ENGINE_OUTPUT$PREVIOUS_ENGINE_SUFFIX"
  mkdir -p "$ENGINES_VENDOR_DIR"
  rm -rf -- "${previous:?}"
  [[ ! -e "$ENGINE_OUTPUT" ]] || mv "$ENGINE_OUTPUT" "$previous"
  mv "$1" "$ENGINE_OUTPUT" || {
    [[ ! -e "$previous" ]] || mv "$previous" "$ENGINE_OUTPUT"
    return 1
  }
  rm -rf -- "${previous:?}"
}

require_sources() {
  local missing
  [[ -d "$STAGE_ENGINE_DIR" ]] || die "Run build.sh first: $STAGE_ENGINE_DIR is missing"
  missing="$(missing_license_sources)"
  [[ -z "$missing" ]] || { printf 'Licence sources missing:\n%s\n' "$missing" >&2; exit "$EXIT_MISSING_SOURCE"; }
}

main() {
  local pkg="$PACKAGE_WORK_DIR/engine"
  PATH="$TOOLS_PATH:$SYSTEM_PATH"
  require_sources
  download_and_verify_addons || exit "$?"
  say "Assembling $pkg"
  assemble_engine "$pkg"
  say "Checking"
  run_engine_checks "$pkg" || exit "$EXIT_CHECK_FAILED"
  publish_engine "$pkg"
  say "Engine ready in $ENGINE_OUTPUT ($(du -sh "$ENGINE_OUTPUT" | cut -f1))"
}

[[ "${BASH_SOURCE[0]}" != "$0" ]] || main "$@"
