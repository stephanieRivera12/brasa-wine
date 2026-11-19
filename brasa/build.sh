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

# Build tools such as tools/sfnt2fon/sfnt2fon run during make and load @rpath/libfreetype.6.dylib
# through @loader_path/../.., which is BUILD_DIR itself; links there let them find the libraries.
link_deps_for_build_tools() {
  local lib
  for lib in "${DEPS_LIBS[@]}"; do
    ln -sfn "$DEPS_PREFIX/lib/$lib" "$BUILD_DIR/$lib"
  done
}

compile_wine() {
  say "Compiling Wine"
  link_deps_for_build_tools
  (cd "$BUILD_DIR" && run_x86 make -j"$(sysctl -n hw.ncpu)")
}

install_wine() {
  say "Installing into $STAGE_DIR"
  rm -rf -- "${STAGE_DIR:?}"
  (cd "$BUILD_DIR" && run_x86 make install-lib DESTDIR="$STAGE_DIR")
}

# Links the libraries into the stage's lib/, where the rpaths look, so the stage runs for the
# Task 1–2 tests. package.sh (Task 3) replaces them with real copies.
link_deps_into_stage() {
  local lib
  for lib in "${DEPS_LIBS[@]}" "$LIB_FREETYPE_LINK"; do
    ln -sfn "$DEPS_PREFIX/lib/$lib" "$STAGE_ENGINE_DIR/lib/$lib"
  done
}

verify_output() {
  local missing
  missing="$(missing_paths "$STAGE_ENGINE_DIR" "${ENGINE_REQUIRED_PATHS[@]}")"
  [[ -z "$missing" ]] || { printf 'Missing in %s:\n%s\n' "$STAGE_ENGINE_DIR" "$missing" >&2; exit "$EXIT_MISSING_OUTPUT"; }
}

verify_no_leaks() {
  local entry leaks="" entries
  entries="$(engine_binaries_with_rpath "$STAGE_ENGINE_DIR")" || exit "$EXIT_MISSING_OUTPUT"
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
  link_deps_into_stage
  verify_output
  verify_no_leaks
  say "Engine ready in $STAGE_ENGINE_DIR"
}

main "$@"
