#!/usr/bin/env bash
# Builds the brasa Wine out of tree as x86_64 and installs it into STAGE_DIR (spec 5.3).
# Needs the libraries of deps.sh. To change configure flags, delete BUILD_DIR first.
set -euo pipefail

BRASA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=constants.sh
source "$BRASA_DIR/constants.sh"
# shellcheck source=lib.sh
source "$BRASA_DIR/lib.sh"

CONFIGURE_LOG="$BUILD_DIR/$CONFIGURE_LOG_NAME"

# Runs a command as x86_64 with the Wine environment. Only the tools come from Homebrew.
unset_flags() {
  local name
  for name in "${LEAKY_ENV_VARS[@]}"; do
    printf -- '-u\n%s\n' "$name"
  done
}

run_x86() {
  local flags=()
  while IFS= read -r line; do flags+=("$line"); done < <(unset_flags)
  arch -x86_64 env "${flags[@]}" \
    "PATH=$TOOLS_PATH:$SYSTEM_PATH" \
    "CC=$TARGET_CC" "CXX=$TARGET_CXX" \
    "MACOSX_DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET" \
    "PKG_CONFIG_LIBDIR=$DEPS_PREFIX/lib/pkgconfig" \
    "CPPFLAGS=-I$DEPS_PREFIX/include" \
    "LDFLAGS=-L$DEPS_PREFIX/lib $WINE_LDFLAGS_RPATHS" \
    "$@"
}

require_deps() {
  local missing
  missing="$(missing_paths "$DEPS_PREFIX" "${DEPS_LIBS[@]/#/lib/}")"
  [[ -z "$missing" ]] || die "Run deps.sh first. Missing in $DEPS_PREFIX: $missing"
}

configure_wine() {
  say "Configuring Wine in $BUILD_DIR"
  rm -rf -- "${BUILD_DIR:?}"
  mkdir -p "$BUILD_DIR"
  (
    cd "$BUILD_DIR"
    run_x86 "${WINE_SONAME_ASSIGNMENTS[@]}" "$FORK_SOURCE_DIR/configure" "${WINE_CONFIGURE_FLAGS[@]}" 2>&1 \
      | tee "$CONFIGURE_LOG"
  )
}

compile_wine() {
  say "Compiling Wine"
  (cd "$BUILD_DIR" && run_x86 make -j"$(sysctl -n hw.ncpu)")
}

install_wine() {
  say "Installing into $STAGE_DIR"
  rm -rf -- "${STAGE_DIR:?}"
  (cd "$BUILD_DIR" && run_x86 make install-lib DESTDIR="$STAGE_DIR")
}

verify_output() {
  local missing
  missing="$(missing_paths "$ENGINE_OUTPUT" "${ENGINE_REQUIRED_PATHS[@]}")"
  [[ -z "$missing" ]] || { printf 'Missing in %s:\n%s\n' "$ENGINE_OUTPUT" "$missing" >&2; exit "$EXIT_MISSING_OUTPUT"; }
}

verify_no_leaks() {
  local entry leaks="" entries
  entries="$(engine_binaries_with_rpath "$ENGINE_OUTPUT")" || exit "$EXIT_MISSING_OUTPUT"
  while IFS= read -r entry; do
    leaks+="$(leaks_in "${entry%%:*}" "${entry#*:}")"$'\n'
  done <<< "$entries"
  [[ -z "${leaks//$'\n'/}" ]] || { printf '%s\n' "$leaks" >&2; exit "$EXIT_LEAK"; }
}

main() {
  prepare_workspace
  require_deps
  [[ -f "$BUILD_DIR/Makefile" ]] || configure_wine
  check_configure_log "$CONFIGURE_LOG" || exit "$?"
  compile_wine
  install_wine
  verify_output
  verify_no_leaks
  say "Engine ready in $ENGINE_OUTPUT"
}

main "$@"
