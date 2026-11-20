#!/usr/bin/env bash
# Shared functions of the brasa scripts. Meant to be sourced after constants.sh.

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

say() {
  printf '\n== %s\n' "$*"
}

# Downloads <url> ($1) into <file> ($2); fails on an HTTP error.
download_file() {
  curl --fail --location --retry 3 --output "$2" "$1"
}

sha256_of() {
  local file="$1"
  shasum -a 256 "$file" | cut -d' ' -f1
}

# Succeeds when the file matches the constant. An empty constant prints the computed hash and
# stops; a mismatch deletes the file.
verify_sha256() {
  local file="$1" expected="$2" actual
  actual="$(sha256_of "$file")"
  if [[ -z "$expected" ]]; then
    printf 'SHA-256 constant is empty for %s\n  computed: %s\n  Check it against the official page or signature, then set it in constants.sh.\n' \
      "$(basename "$file")" "$actual" >&2
    return "$EXIT_HASH_UNSET"
  fi
  if [[ "$actual" != "$expected" ]]; then
    printf 'SHA-256 mismatch for %s\n  expected: %s\n  computed: %s\n' "$(basename "$file")" "$expected" "$actual" >&2
    rm -f -- "$file"
    return "$EXIT_HASH_MISMATCH"
  fi
}

# Fails (and prints the lines) when a configure log reports something missing.
check_configure_log() {
  local log="$1" pattern_args=() warning
  for warning in "${CONFIGURE_FATAL_WARNINGS[@]}"; do
    pattern_args+=(-e "$warning")
  done
  if grep -F "${pattern_args[@]}" "$log" >&2; then
    return "$EXIT_CONFIGURE_WARNING"
  fi
}

# Prints the dependencies of an `otool -L` output that are outside the allowed prefixes.
disallowed_dependencies() {
  local otool_output="$1" line path prefix allowed
  while read -r line; do
    path="${line%% (*}"
    allowed=0
    for prefix in "${ALLOWED_DEPENDENCY_PREFIXES[@]}"; do
      [[ "$path" == "$prefix"* ]] && allowed=1
    done
    ((allowed)) || printf '%s\n' "$path"
  done < <(printf '%s\n' "$otool_output" | tail -n +2)
}

# Prints the relative paths that do not exist under root.
missing_paths() {
  local root="$1" path
  shift
  for path in "$@"; do
    [[ -e "$root/$path" ]] || printf '%s\n' "$path"
  done
}

is_built() {
  [[ -e "$DEPS_STAMP_DIR/$1" ]]
}

mark_built() {
  mkdir -p "$DEPS_STAMP_DIR"
  : > "$DEPS_STAMP_DIR/$1"
}

# Autoconf and make cannot handle spaces in paths.
die_if_whitespace() {
  [[ "$1" != *[[:space:]]* ]] || die "Path with spaces is not supported: $1"
}

# Points link at target; refuses to replace anything that is not a link.
link_dir() {
  local target="$1" link="$2"
  [[ ! -e "$link" || -L "$link" ]] || die "$link exists and is not a link"
  ln -sfn "$target" "$link"
}

prepare_workspace() {
  local name
  die_if_whitespace "$WORK_DIR"
  mkdir -p "$SOURCE_LINKS_DIR" "$BRASA_BUILD_DIR"
  link_tools "$TOOLS_BIN_DIR" "${TOOL_SOURCES[@]}"
  link_dir "$BRASA_FORK_DIR" "$FORK_SOURCE_DIR"
  link_dir "$CROSSOVER_SOURCES_REAL_DIR" "$CROSSOVER_SOURCES_DIR"
  for name in "${BRASA_VISIBLE_RESULTS[@]}"; do
    mkdir -p "$WORK_DIR/$name"
    link_dir "$WORK_DIR/$name" "$BRASA_BUILD_DIR/$name"
  done
}

# Links every existing file matching the given paths (globs allowed) into dest.
link_tools() {
  local dest="$1" pattern candidate
  shift
  mkdir -p "$dest"
  for pattern in "$@"; do
    # shellcheck disable=SC2231
    for candidate in $pattern; do
      [[ -e "$candidate" ]] && link_dir "$candidate" "$dest/$(basename "$candidate")"
    done
  done
  return 0
}

# Succeeds when an `otool -l` output has an LC_RPATH with exactly this path.
has_rpath() {
  local otool_output="$1" rpath="$2"
  grep -Fq "path $rpath (offset" <<< "$otool_output"
}

# Prints the lines of a `strings` output that hold a forbidden string.
forbidden_strings_in() {
  local strings_output="$1" pattern_args=() forbidden
  for forbidden in "${FORBIDDEN_STRINGS[@]}"; do
    pattern_args+=(-e "$forbidden")
  done
  grep -F "${pattern_args[@]}" <<< "$strings_output" || true
}

# Prints "<binary>:<expected rpath>" for every binary of an installed engine; fails when
# there is no unix library at all.
engine_binaries_with_rpath() {
  local root="$1" name libs
  for name in "${ENGINE_BIN_BINARIES[@]}"; do
    printf '%s:%s\n' "$root/bin/$name" "$RPATH_BIN"
  done
  libs="$(find "$root/$ENGINE_UNIX_LIBS_DIR" -name '*.so' 2>/dev/null)"
  [[ -n "$libs" ]] || { printf 'No .so files in %s/%s\n' "$root" "$ENGINE_UNIX_LIBS_DIR" >&2; return 1; }
  printf '%s\n' "$libs" | sed "s|\$|:$RPATH_UNIX_LIBS|"
}

# Strings of what will ship: the binary without debug symbols (they keep the object paths).
# Fails when copying, stripping or reading fails; the temp dir is always removed.
shipped_strings() {
  local dir copy status=0
  dir="$(mktemp -d "${TMPDIR:-/tmp}/brasa-strip.XXXXXX")"
  copy="$dir/$(basename "$1")"
  cp "$1" "$copy" && "$STRIP_TOOL" -S "$copy" && "$STRINGS_TOOL" -a "$copy" || status=$?
  rm -rf -- "${dir:?}"
  return "$status"
}

# Prints one line per problem of an installed binary (nothing when it is clean): dependencies
# only @rpath, /usr/lib, /System; the expected LC_RPATH; no build path inside. A tool that
# fails is a problem too, never a pass.
leaks_in() {
  local binary="$1" expected_rpath="$2" dependencies load_commands strings_output bad
  dependencies="$("$OTOOL_TOOL" -L "$binary")" \
    && load_commands="$("$OTOOL_TOOL" -l "$binary")" \
    && strings_output="$(shipped_strings "$binary")" \
    || { printf '%s: could not inspect it (otool, strip or strings failed)\n' "$binary"; return 0; }
  bad="$(disallowed_dependencies "$dependencies")"
  [[ -z "$bad" ]] || printf '%s: dependency outside @rpath, /usr/lib, /System: %s\n' "$binary" "$bad"
  has_rpath "$load_commands" "$expected_rpath" || printf '%s: LC_RPATH %s missing\n' "$binary" "$expected_rpath"
  bad="$(forbidden_strings_in "$strings_output")"
  [[ -z "$bad" ]] || printf '%s: contains a build path: %s\n' "$binary" "$bad"
}

# Prints the libs of Wine's libs/ folder that are third-party code. Fails when the folder is missing.
third_party_wine_libs() {
  local lib
  [[ -d "$WINE_LIBS_DIR" ]] || { printf 'ERROR: %s is missing\n' "$WINE_LIBS_DIR" >&2; return 1; }
  for lib in $(find "$WINE_LIBS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort); do
    [[ " ${WINE_OWN_LIBS[*]} " == *" $lib "* ]] || printf '%s\n' "$lib"
  done
}

# Prints the licence-like files (LICENSE*, COPYING*, ...) at the top of a Wine lib folder.
wine_lib_license_files() {
  local pattern name_args=()
  for pattern in "${WINE_LIB_LICENSE_NAMES[@]}"; do
    name_args+=(-o -iname "$pattern")
  done
  find "$WINE_LIBS_DIR/$1" -maxdepth 1 -type f \( "${name_args[@]:1}" \) | LC_ALL=C sort
}
