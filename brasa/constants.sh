#!/usr/bin/env bash
# Every version, path, URL, hash, package and flag of the brasa build lives here.
# Meant to be sourced. Needs bash 3.2 (the macOS one): no associative arrays.

# ---------- Paths ----------
BRASA_FORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # vendor/brasa-wine
BRASA_ROOT="$(cd "$BRASA_FORK_DIR/../.." && pwd)"                   # the Brasa repository
# autoconf and make break on spaces in paths, and the Brasa folder has one ("paginas web"). The
# real work happens in a space-free folder; <Brasa>/build/<name> links to each result and the
# sources are reached through links in WORK_DIR/src.
: "${BRASA_WORK_DIR:=$HOME/.brasa-engine-work}"
WORK_DIR="$BRASA_WORK_DIR"
BUILD_DIR="$WORK_DIR/brasa-wine"
STAGE_DIR="$WORK_DIR/brasa-wine-stage"
DEPS_PREFIX="$WORK_DIR/brasa-deps"
DEPS_SRC_DIR="$WORK_DIR/brasa-deps-src"
DEPS_BUILD_DIR="$WORK_DIR/brasa-deps-build"
DEPS_STAMP_DIR="$DEPS_PREFIX/.stamps"
SOURCE_LINKS_DIR="$WORK_DIR/src"
FORK_SOURCE_DIR="$SOURCE_LINKS_DIR/brasa-wine"
CROSSOVER_SOURCES_DIR="$SOURCE_LINKS_DIR/crossover-sources"
CROSSOVER_SOURCES_REAL_DIR="$BRASA_ROOT/vendor/crossover-source/sources"
BRASA_BUILD_DIR="$BRASA_ROOT/build"
BRASA_VISIBLE_RESULTS=(brasa-deps brasa-deps-src brasa-wine brasa-wine-stage)

# ---------- Engine ----------
ENGINE_PREFIX="/opt/wine-brasa"
ENGINE_VERSION="26.3.0-1"
ENGINE_OUTPUT="$STAGE_DIR$ENGINE_PREFIX"
ENGINE_REQUIRED_PATHS=(
  bin/wine
  bin/wineserver
  lib/wine/x86_64-unix
  lib/wine/x86_64-windows
  lib/wine/i386-windows
)

# ---------- Toolchain ----------
BREW="/opt/homebrew/bin/brew"
BREW_PACKAGES=(mingw-w64 bison pkgconf)
BREW_PREFIX="/opt/homebrew"
BISON_BIN_DIR="$BREW_PREFIX/opt/bison/bin"
TOOLS_PATH="$BISON_BIN_DIR:$BREW_PREFIX/bin"   # tools only, never libraries
TARGET_ARCH="x86_64"
TARGET_HOST="x86_64-apple-darwin"
DEPLOYMENT_TARGET="14.0"
TARGET_CC="clang -arch $TARGET_ARCH"
TARGET_CXX="clang++ -arch $TARGET_ARCH"

# ---------- Library versions ----------
GMP_VERSION="6.3.0"
NETTLE_VERSION="3.10"
GNUTLS_VERSION="3.8.3"
FREETYPE_VERSION="2.13.3"
SDL2_VERSION="2.30.12"
LIBINOTIFY_VERSION="20240724"
MOLTENVK_VERSION="1.2.10"

# ---------- Sources downloaded (empty SHA-256: deps.sh prints it and stops) ----------
DOWNLOAD_NAMES=(NETTLE SDL2 LIBINOTIFY MOLTENVK)
NETTLE_URL="https://ftp.gnu.org/gnu/nettle/nettle-$NETTLE_VERSION.tar.gz"
NETTLE_SHA256=""
SDL2_URL="https://github.com/libsdl-org/SDL/releases/download/release-$SDL2_VERSION/SDL2-$SDL2_VERSION.tar.gz"
SDL2_SHA256=""
LIBINOTIFY_URL="https://github.com/libinotify-kqueue/libinotify-kqueue/releases/download/$LIBINOTIFY_VERSION/libinotify-$LIBINOTIFY_VERSION.tar.gz"
LIBINOTIFY_SHA256=""
# v1.2.10 has no release of its own; its binaries hang on v1.2.10-rc2, which is the same commit (edbdcf0).
MOLTENVK_RELEASE_TAG="v$MOLTENVK_VERSION-rc2"
MOLTENVK_URL="https://github.com/KhronosGroup/MoltenVK/releases/download/$MOLTENVK_RELEASE_TAG/MoltenVK-macos.tar"
MOLTENVK_SHA256=""
MOLTENVK_DYLIB="libMoltenVK.dylib"

# ---------- Sources from CodeWeavers ----------
GMP_SOURCE_DIR="$CROSSOVER_SOURCES_DIR/gnutls/gmp"
GNUTLS_SOURCE_DIR="$CROSSOVER_SOURCES_DIR/gnutls/gnutls"
FREETYPE_SOURCE_DIR="$CROSSOVER_SOURCES_DIR/freetype"

# ---------- Library flags ----------
DEPS_COMMON_CONFIGURE_FLAGS=(
  "--host=$TARGET_HOST"
  "--prefix=$DEPS_PREFIX"
  "--libdir=$DEPS_PREFIX/lib"
)
GMP_CONFIGURE_FLAGS=(--enable-fat --enable-shared --disable-static)
NETTLE_CONFIGURE_FLAGS=(
  --disable-shared --enable-static --with-pic
  --disable-documentation --disable-openssl
)
GNUTLS_CONFIGURE_FLAGS=(
  --with-included-libtasn1 --with-included-unistring
  --without-p11-kit --without-idn --without-zlib --without-brotli --without-zstd
  --without-tpm --without-tpm2
  --disable-nls --disable-tools --disable-doc --disable-tests --disable-cxx --disable-guile
  "LDFLAGS=-L$DEPS_PREFIX/lib -Wl,-rpath,@loader_path"   # finds libgmp next to libgnutls
)
FREETYPE_CONFIGURE_FLAGS=(
  --with-bzip2=yes --with-png=no --with-harfbuzz=no --with-brotli=no --with-zlib=no
)
SDL2_CONFIGURE_FLAGS=(--disable-static)
LIBINOTIFY_CONFIGURE_FLAGS=(--disable-static)

# ---------- Runtime libraries (file names, as Wine opens them) ----------
LIB_GMP="libgmp.10.dylib"
LIB_GNUTLS="libgnutls.30.dylib"
LIB_FREETYPE="libfreetype.6.dylib"
LIB_FREETYPE_LINK="libfreetype.dylib"
LIB_SDL2="libSDL2-2.0.0.dylib"
LIB_INOTIFY="libinotify.0.dylib"
LIB_MOLTENVK="$MOLTENVK_DYLIB"
DEPS_LIBS=("$LIB_GMP" "$LIB_GNUTLS" "$LIB_FREETYPE" "$LIB_SDL2" "$LIB_INOTIFY" "$LIB_MOLTENVK")
RPATH_ID_PREFIX="@rpath/"
# "library:dependency" pairs whose absolute dependency path becomes @rpath/<dependency>.
DEPS_RELOCATIONS=("$LIB_GNUTLS:$LIB_GMP")
ALLOWED_DEPENDENCY_PREFIXES=("@rpath/" "/usr/lib/" "/System/")

# ---------- Wine configure ----------
WINE_CONFIGURE_FLAGS=(
  "--prefix=$ENGINE_PREFIX" --enable-archs=i386,x86_64
  --without-x --without-wayland --without-alsa --without-oss --without-pulse
  --without-cups --without-sane --without-v4l2 --without-udev --without-usb
  --without-gstreamer
  --with-freetype --with-gnutls --with-sdl --with-vulkan --with-inotify
)
# Short soname that Wine opens through the LC_RPATH of the .so that asks for it.
WINE_SONAME_ASSIGNMENTS=(
  "ac_cv_lib_soname_gnutls=$LIB_GNUTLS"
  "ac_cv_lib_soname_freetype=$LIB_FREETYPE_LINK"
  "ac_cv_lib_soname_MoltenVK=$LIB_MOLTENVK"
  "ac_cv_lib_soname_SDL2=$LIB_SDL2"
)
WINE_LDFLAGS_RPATHS="-Wl,-rpath,@loader_path/../.. -Wl,-rpath,@loader_path/../lib"
CONFIGURE_FATAL_WARNINGS=(
  "fonts won't be supported"
  "no schannel support"
  "Vulkan won't be supported"
  "filesystem change notifications won't be supported"
  "MinGW compiler not found"
)
CONFIGURE_LOG_NAME="configure.log"

# ---------- Exit codes ----------
EXIT_HASH_UNSET=3
EXIT_HASH_MISMATCH=4
EXIT_CONFIGURE_WARNING=5
EXIT_BAD_DEPENDENCY=6
EXIT_MISSING_OUTPUT=7
