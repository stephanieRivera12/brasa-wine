#!/usr/bin/env bash
# Builds the x86_64 runtime libraries of the brasa engine into DEPS_PREFIX, from the same
# sources and versions CrossOver 26.3.0 uses (spec 5.3). Re-running skips what is built.
set -euo pipefail

BRASA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=constants.sh
source "$BRASA_DIR/constants.sh"
# shellcheck source=lib.sh
source "$BRASA_DIR/lib.sh"

# Runs a command as x86_64 with the deps environment. Only the tools come from Homebrew.
run_x86() {
  arch -x86_64 env \
    "PATH=$TOOLS_PATH:$PATH" \
    "CC=$TARGET_CC" "CXX=$TARGET_CXX" \
    "MACOSX_DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET" \
    "PKG_CONFIG_LIBDIR=$DEPS_PREFIX/lib/pkgconfig" \
    "CPPFLAGS=-I$DEPS_PREFIX/include" "LDFLAGS=-L$DEPS_PREFIX/lib" \
    "$@"
}

archive_path() {
  local url_var="$1_URL"
  printf '%s/%s' "$DEPS_SRC_DIR" "$(basename "${!url_var}")"
}

download() {
  local name="$1" url_var="$1_URL" sha_var="$1_SHA256" archive
  archive="$(archive_path "$name")"
  [[ -s "$archive" ]] || curl -fL --retry 3 -o "$archive" "${!url_var}"
  verify_sha256 "$archive" "${!sha_var}"
}

# Downloads every source; an empty constant must not stop the others from printing their hash.
download_all() {
  local name status=0
  mkdir -p "$DEPS_SRC_DIR"
  for name in "${DOWNLOAD_NAMES[@]}"; do
    download "$name" || status=$?
  done
  return "$status"
}

# Unpacks an archive into DEPS_BUILD_DIR/<id>-src and prints that directory.
unpack() {
  local id="$1" archive="$2" dir="$DEPS_BUILD_DIR/$1-src"
  rm -rf -- "${dir:?}"
  mkdir -p "$dir"
  tar -xf "$archive" -C "$dir" --strip-components=1
  printf '%s' "$dir"
}

# Copies into <build_dir> the source files that <id>'s Makefile expects next to it (OUT_OF_TREE_INPUTS).
copy_out_of_tree_inputs() {
  local id="$1" source_dir="$2" build_dir="$3" pair
  for pair in "${OUT_OF_TREE_INPUTS[@]}"; do
    [[ "${pair%%:*}" == "$id" ]] && cp "$source_dir/${pair##*:}" "$build_dir/"
  done
  return 0
}

# Builds <id> out of tree from <source_dir>/configure; the rest of the arguments are its flags.
build_autotools() {
  local id="$1" source_dir="$2" dir="$DEPS_BUILD_DIR/$1"
  shift 2
  if is_built "$id"; then
    echo "Already built: $id"
    return 0
  fi
  say "Building $id"
  rm -rf -- "${dir:?}"
  mkdir -p "$dir"
  copy_out_of_tree_inputs "$id" "$source_dir" "$dir"
  (
    cd "$dir"
    run_x86 "$source_dir/configure" "${DEPS_COMMON_CONFIGURE_FLAGS[@]}" "$@"
    run_x86 make -j"$(sysctl -n hw.ncpu)"
    run_x86 make install
  )
  mark_built "$id"
}

build_from_archive() {
  local name="$1" id="$2" source_dir
  shift 2
  is_built "$id" || source_dir="$(unpack "$id" "$(archive_path "$name")")"
  build_autotools "$id" "${source_dir:-}" "$@"
}

install_moltenvk() {
  local id="moltenvk-$MOLTENVK_VERSION" dir="$DEPS_BUILD_DIR/moltenvk-$MOLTENVK_VERSION" dylib
  if is_built "$id"; then
    echo "Already built: $id"
    return 0
  fi
  say "Installing $id ($TARGET_ARCH slice only)"
  rm -rf -- "${dir:?}"
  mkdir -p "$dir" "$DEPS_PREFIX/lib"
  tar -xf "$(archive_path MOLTENVK)" -C "$dir"
  dylib="$(find "$dir" -type f -name "$MOLTENVK_DYLIB" | head -n 1)"
  [[ -n "$dylib" ]] || die "$MOLTENVK_DYLIB not found in the MoltenVK package"
  lipo -thin "$TARGET_ARCH" "$dylib" -output "$DEPS_PREFIX/lib/$MOLTENVK_DYLIB"
  mark_built "$id"
}

relocate_ids() {
  local lib
  for lib in "${DEPS_LIBS[@]}"; do
    install_name_tool -id "$RPATH_ID_PREFIX$lib" "$DEPS_PREFIX/lib/$lib"
  done
  ln -sf "$LIB_FREETYPE" "$DEPS_PREFIX/lib/$LIB_FREETYPE_LINK"
}

relocate_dependencies() {
  local pair lib dependency
  for pair in "${DEPS_RELOCATIONS[@]}"; do
    lib="${pair%%:*}"
    dependency="${pair##*:}"
    install_name_tool -change "$DEPS_PREFIX/lib/$dependency" "$RPATH_ID_PREFIX$dependency" "$DEPS_PREFIX/lib/$lib"
  done
}

verify_library() {
  local lib="$1" path="$DEPS_PREFIX/lib/$1" bad
  [[ "$(lipo -archs "$path")" == "$TARGET_ARCH" ]] || die "$lib is not $TARGET_ARCH only"
  bad="$(disallowed_dependencies "$(otool -L "$path")")"
  [[ -z "$bad" ]] || { printf '%s\n' "$bad" >&2; return "$EXIT_BAD_DEPENDENCY"; }
}

verify_all() {
  local lib
  for lib in "${DEPS_LIBS[@]}"; do
    verify_library "$lib" || die "$lib depends on something outside @rpath, /usr/lib and /System"
    echo "ok: $lib"
  done
}

main() {
  prepare_workspace
  mkdir -p "$DEPS_PREFIX" "$DEPS_BUILD_DIR"
  download_all || exit "$?"
  build_autotools "gmp-$GMP_VERSION" "$GMP_SOURCE_DIR" "${GMP_CONFIGURE_FLAGS[@]}"
  build_from_archive NETTLE "nettle-$NETTLE_VERSION" "${NETTLE_CONFIGURE_FLAGS[@]}"
  build_autotools "gnutls-$GNUTLS_VERSION" "$GNUTLS_SOURCE_DIR" "${GNUTLS_CONFIGURE_FLAGS[@]}"
  build_from_archive FREETYPE "freetype-$FREETYPE_VERSION" "${FREETYPE_CONFIGURE_FLAGS[@]}"
  build_from_archive SDL2 "sdl2-$SDL2_VERSION" "${SDL2_CONFIGURE_FLAGS[@]}"
  build_from_archive LIBINOTIFY "libinotify-$LIBINOTIFY_VERSION" "${LIBINOTIFY_CONFIGURE_FLAGS[@]}"
  install_moltenvk
  relocate_ids
  relocate_dependencies
  verify_all
  say "Libraries ready in $DEPS_PREFIX/lib"
}

main "$@"
