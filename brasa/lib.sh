#!/usr/bin/env bash
# Shared functions of the brasa scripts. Meant to be sourced after constants.sh.

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

say() {
  printf '\n== %s\n' "$*"
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
  link_dir "$BRASA_FORK_DIR" "$FORK_SOURCE_DIR"
  link_dir "$CROSSOVER_SOURCES_REAL_DIR" "$CROSSOVER_SOURCES_DIR"
  for name in "${BRASA_VISIBLE_RESULTS[@]}"; do
    mkdir -p "$WORK_DIR/$name"
    link_dir "$WORK_DIR/$name" "$BRASA_BUILD_DIR/$name"
  done
}
