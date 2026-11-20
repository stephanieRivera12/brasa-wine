#!/usr/bin/env bash
# Checks of a packaged engine (spec 5.5). Meant to be sourced after constants.sh and lib.sh.
# Each check_* prints one line per problem and nothing when the engine passes.

# Prints the LC_RPATH paths of an `otool -l` output.
rpaths_of() {
  awk '/cmd LC_RPATH/ { wanted = 1 } wanted && $1 == "path" { print $2; wanted = 0 }' <<< "$1"
}

# Prints the LC_RPATH paths of an `otool -l` output that start outside the allowed prefixes.
disallowed_rpaths() {
  local path prefix allowed
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    allowed=0
    for prefix in "${ALLOWED_RPATH_PREFIXES[@]}"; do
      [[ "$path" == "$prefix"* ]] && allowed=1
    done
    ((allowed)) || printf '%s\n' "$path"
  done <<< "$(rpaths_of "$1")"
}

# Problems of a Mach-O from the text of `otool -L`, `otool -l` and `lipo -archs`.
load_command_problems() {
  local dependencies="$1" load_commands="$2" archs="$3" outside
  outside="$(disallowed_dependencies "$dependencies")"
  [[ -z "$outside" ]] || printf 'dependency outside the engine and the system: %s\n' "$outside"
  outside="$(disallowed_rpaths "$load_commands")"
  [[ -z "$outside" ]] || printf 'LC_RPATH outside the engine and the system: %s\n' "$outside"
  [[ "$archs" == "$TARGET_ARCH" ]] || printf 'architecture is "%s", not %s\n' "$archs" "$TARGET_ARCH"
}

# Same, running the tools; a tool that fails is a problem, never a pass.
macho_problems() {
  local dependencies load_commands archs
  dependencies="$("$OTOOL_TOOL" -L "$1")" \
    && load_commands="$("$OTOOL_TOOL" -l "$1")" \
    && archs="$("$LIPO_TOOL" -archs "$1")" \
    || { printf 'could not inspect it (otool or lipo failed)\n'; return 0; }
  load_command_problems "$dependencies" "$load_commands" "$archs"
}

# Succeeds for the first four bytes (hex) of any Mach-O magic (thin, either endianness, or fat).
is_macho_magic() {
  local magic
  for magic in "${MACHO_MAGICS[@]}"; do
    [[ "$1" == "$magic" ]] && return 0
  done
  return 1
}

# 0 for a Mach-O, 1 for anything else, 2 when the file cannot be read.
is_macho() {
  local magic
  magic="$(od -An -tx1 -N4 "$1")" || return "$STATUS_UNREADABLE"
  is_macho_magic "${magic// /}"
}

# Prints every file under root that is a Mach-O or cannot be read (so it fails inspection).
macho_files() {
  local file status
  while IFS= read -r file; do
    status=0
    is_macho "$file" || status=$?
    ((status == 1)) || printf '%s\n' "$file"
  done < <(find "$1" -type f)
  return 0
}

# One line per forbidden string inside the file, as it will ship (Mach-O without debug info).
personal_path_problems() {
  local file="$1" text hit status=0
  is_macho "$file" || status=$?
  case "$status" in
    0) text="$(shipped_strings "$file")" || status=$STATUS_UNREADABLE ;;
    1) text="$("$STRINGS_TOOL" -a "$file")" || status=$STATUS_UNREADABLE ;;
  esac
  ((status == 0 || status == 1)) || { printf '%s: could not be scanned\n' "$file"; return 0; }
  # A here-string, not a process substitution: bash 3.2 leaks a descriptor per <( ) in a loop.
  while IFS= read -r hit; do
    [[ -n "$hit" ]] && printf '%s: contains a personal or build path: %s\n' "$file" "$hit"
  done <<< "$(forbidden_strings_in "$text")"
  return 0
}

# Prints the relative folders of root that are absent or empty.
empty_dirs() {
  local root="$1" dir
  shift
  for dir in "$@"; do
    [[ -d "$root/$dir" && -n "$(ls -A "$root/$dir" 2>/dev/null)" ]] || printf '%s\n' "$dir"
  done
}

# Prints the components without a licence file in the licences folder.
components_without_license() {
  local component
  for component in "${LICENSE_COMPONENTS[@]}"; do
    [[ -d "$1/$component" && -n "$(ls -A "$1/$component" 2>/dev/null)" ]] || printf '%s\n' "$component"
  done
}

# Prints the third-party libs of Wine that have no licence in the engine. An unreadable libs
# folder is reported too: never a silent pass.
wine_libs_without_license() {
  local libs lib dir
  libs="$(third_party_wine_libs 2>/dev/null)" || { printf '%s (cannot list it)\n' "$WINE_LIBS_DIR"; return 0; }
  for lib in $libs; do
    dir="$1/$WINE_LIBS_LICENSE_SUBDIR/$lib"
    [[ -d "$dir" && -n "$(ls -A "$dir" 2>/dev/null)" ]] || printf '%s\n' "$lib"
  done
}

missing_license_readme() {
  [[ -s "$1/README.md" ]] || printf 'README.md\n'
}

# Prints the files writable by group or others.
writable_by_others() {
  find "$1" ! -type l \( -perm -020 -o -perm -002 \)
}

# Prints the symlinks that are absolute, dangling or resolve outside root.
escaping_links() {
  local root link target resolved
  root="$(cd -P "$1" && pwd -P)"
  while IFS= read -r link; do
    target="$(readlink "$link")"
    if [[ "$target" != /* ]] \
      && resolved="$(cd -P "$(dirname "$link")/$(dirname "$target")" 2>/dev/null && pwd -P)" \
      && [[ "$resolved/" == "$root/"* && -e "$link" ]]; then
      continue
    fi
    printf '%s\n' "$link"
  done < <(find "$1" -type l)
}

# ---------- The checks of check-engine.sh ----------

check_load_commands() {
  local file problems
  while IFS= read -r file; do
    problems="$(macho_problems "$file")"
    [[ -z "$problems" ]] || sed "s|^|${file#"$1"/}: |" <<< "$problems"
  done < <(macho_files "$1")
}

check_personal_paths() {
  local file
  while IFS= read -r file; do
    personal_path_problems "$file"
  done < <(find "$1" -type f)
}

check_sonames() {
  local missing
  missing="$(missing_paths "$1" "${DEPS_LIBS[@]/#/lib/}" "lib/$LIB_FREETYPE_LINK")"
  [[ -z "$missing" ]] || sed 's|^|missing: |' <<< "$missing"
}

check_addons() {
  local missing
  missing="$(empty_dirs "$1" "${ADDON_FOLDERS[@]}")"
  [[ -z "$missing" ]] || sed 's|^|missing or empty: |' <<< "$missing"
}

check_licenses() {
  components_without_license "$1/$LICENSES_DIR" | sed 's|^|no licence for: |'
  wine_libs_without_license "$1/$LICENSES_DIR" | sed 's|^|no licence for Wine lib: |'
  missing_license_readme "$1/$LICENSES_DIR" | sed 's|^|missing: |'
}

check_permissions() {
  writable_by_others "$1" | sed 's|^|writable by others: |'
}

check_links() {
  escaping_links "$1" | sed 's|^|link leaves the engine: |'
}

ENGINE_CHECKS=(load_commands personal_paths sonames addons licenses permissions links)

# Runs every check on the engine; prints PASS/FAIL per check and fails if any fails.
run_engine_checks() {
  local root="$1" name problems failed=0
  for name in "${ENGINE_CHECKS[@]}"; do
    problems="$("check_$name" "$root")"
    if [[ -z "$problems" ]]; then
      printf 'PASS %s\n' "$name"
    else
      printf 'FAIL %s\n' "$name"
      head -n "$CHECK_PROBLEMS_SHOWN" <<< "$problems" | sed 's|^|     |'
      failed=1
    fi
  done
  return "$failed"
}
