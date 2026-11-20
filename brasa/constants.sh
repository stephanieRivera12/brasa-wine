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
ENGINE_VERSION="26.3.0-2"
STAGE_ENGINE_DIR="$STAGE_DIR$ENGINE_PREFIX"   # what build.sh installs
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
# Tools only, never libraries: /opt/homebrew/bin has freetype-config, which configure runs before
# pkg-config. Wine sees just this folder of links plus the system folders.
TOOLS_BIN_DIR="$WORK_DIR/tools"
TOOLS_PATH="$TOOLS_BIN_DIR"
SYSTEM_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
TOOL_SOURCES=(
  "$BISON_BIN_DIR/bison"
  "$BREW_PREFIX/bin/pkg-config"
  "$BREW_PREFIX/bin/pkgconf"
  "$BREW_PREFIX/bin/x86_64-w64-mingw32-*"
  "$BREW_PREFIX/bin/i686-w64-mingw32-*"
)
# Host variables that add library paths on top of PKG_CONFIG_LIBDIR and the flags.
LEAKY_ENV_VARS=(PKG_CONFIG_PATH CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH)
TARGET_ARCH="x86_64"
TARGET_HOST="x86_64-apple-darwin"
DEPLOYMENT_TARGET="14.0"
TARGET_CC="clang -arch $TARGET_ARCH"
TARGET_CXX="clang++ -arch $TARGET_ARCH"

# ---------- Library versions ----------
GMP_VERSION="6.3.0"
NETTLE_VERSION="3.10"
GNUTLS_VERSION="3.8.13"   # official release: 3.8.12 and 3.8.13 fix CVE-2026-1584, -33845, -33846, -42009, -42010
FREETYPE_VERSION="2.13.3"
SDL2_VERSION="2.30.12"
LIBINOTIFY_VERSION="20240724"
MOLTENVK_VERSION="1.2.10"

# ---------- Sources downloaded (empty SHA-256: deps.sh prints it and stops) ----------
DOWNLOAD_NAMES=(NETTLE GNUTLS FREETYPE SDL2 LIBINOTIFY MOLTENVK)
NETTLE_URL="https://ftp.gnu.org/gnu/nettle/nettle-$NETTLE_VERSION.tar.gz"
NETTLE_SHA256="b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c"
# Official GnuTLS, not CodeWeavers' 3.8.3: signed by Zoltan Fridrich (maintainer); same soname (libgnutls.30).
GNUTLS_URL="https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-$GNUTLS_VERSION.tar.xz"
GNUTLS_SHA256="ffed8ec1bf09c2426d4f14aae377de4753b53e537d685e604e99a8b16ca9c97e"
# CodeWeavers' freetype is a git checkout (no generated configure, empty dlg submodule); its src/ and
# include/ are identical to this signed release (checked with diff -rq, signature by Werner Lemberg).
FREETYPE_URL="https://download-mirror.savannah.gnu.org/releases/freetype/freetype-$FREETYPE_VERSION.tar.xz"
FREETYPE_SHA256="0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289"
SDL2_URL="https://github.com/libsdl-org/SDL/releases/download/release-$SDL2_VERSION/SDL2-$SDL2_VERSION.tar.gz"
SDL2_SHA256="ac356ea55e8b9dd0b2d1fa27da40ef7e238267ccf9324704850d5d47375b48ea"
LIBINOTIFY_URL="https://github.com/libinotify-kqueue/libinotify-kqueue/releases/download/$LIBINOTIFY_VERSION/libinotify-$LIBINOTIFY_VERSION.tar.gz"
LIBINOTIFY_SHA256="5cc3fb7af407b17b7daa871cc98bb882716c4b5c296fadfb66bfe86c37cc599c"
# v1.2.10 has no release of its own; its binaries hang on v1.2.10-rc2, which is the same commit (edbdcf0).
MOLTENVK_RELEASE_TAG="v$MOLTENVK_VERSION-rc2"
MOLTENVK_URL="https://github.com/KhronosGroup/MoltenVK/releases/download/$MOLTENVK_RELEASE_TAG/MoltenVK-macos.tar"
MOLTENVK_SHA256="64527dc74ea037182de4923095506ecbc66599a9124b4af99de01238c56c3ed1"
MOLTENVK_DYLIB="libMoltenVK.dylib"

# ---------- Sources from CodeWeavers (gmp only; gnutls is the official tarball above) ----------
GMP_SOURCE_DIR="$CROSSOVER_SOURCES_DIR/gnutls/gmp"
# ---------- Library flags ----------
# Libraries embed __FILE__ (gnutls, SDL2, ...): the compiler maps this Mac's build folders to neutral
# ones. Passed in CC, so a library that sets its own CFLAGS (libinotify) keeps the map.
DEPS_PATH_MAP_FLAGS="-ffile-prefix-map=$SOURCE_LINKS_DIR=/brasa-src -ffile-prefix-map=$DEPS_BUILD_DIR=/brasa-deps-build"
DEPS_CC="$TARGET_CC $DEPS_PATH_MAP_FLAGS"
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
  # Empty = no system-wide priority file: otherwise 3.8.13 embeds <prefix>/etc/gnutls/config (a build
  # path) and would let a file on the Mac change how the engine negotiates TLS.
  "--with-system-priority-file="
  --disable-nls --disable-tools --disable-doc --disable-tests --disable-cxx
  "LDFLAGS=-L$DEPS_PREFIX/lib -Wl,-rpath,@loader_path"   # finds libgmp next to libgnutls
  # nettle is static, so its link checks must also name gmp (configure only tries -lhogweed alone)
  "NETTLE_LIBS=-lnettle" "HOGWEED_LIBS=-lhogweed -lnettle -lgmp" "GMP_LIBS=-lgmp"
)
FREETYPE_CONFIGURE_FLAGS=(
  --with-bzip2=yes --with-png=no --with-harfbuzz=no --with-brotli=no --with-zlib=no
)
SDL2_CONFIGURE_FLAGS=(--disable-static)
LIBINOTIFY_CONFIGURE_FLAGS=(
  --disable-static
  # The SDK has fdclosedir only from macOS 26.4; below our floor (14) libinotify must use its own
  # compat/fdclosedir.c, as it did with older SDKs. The SDK still tags the call, hence the warning off.
  "ac_cv_func_fdclosedir=no" "CFLAGS=-g -O2 -Wno-unguarded-availability-new"
)

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
ALLOWED_DEPENDENCY_PREFIXES=("@rpath/" "@loader_path/" "/usr/lib/" "/System/")
ALLOWED_RPATH_PREFIXES=("@rpath" "@loader_path" "/usr/lib/" "/System/")
# "build id:file" pairs copied from the source into the build dir before configure: libinotify's
# Makefile passes "-export-symbols libinotify.sym" as a relative path, which breaks out-of-tree builds.
OUT_OF_TREE_INPUTS=("libinotify-$LIBINOTIFY_VERSION:libinotify.sym")

# ---------- Wine configure ----------
SOURCE_PATH_MAP_FLAGS="-ffile-prefix-map=$FORK_SOURCE_DIR=/brasa-wine-src -ffile-prefix-map=$BUILD_DIR=/brasa-wine-build"
WINE_CONFIGURE_FLAGS=(
  "--prefix=$ENGINE_PREFIX" --enable-archs=i386,x86_64
  --without-x --without-wayland --without-alsa --without-oss --without-pulse
  --without-cups --without-sane --without-v4l2 --without-udev --without-usb
  --without-gstreamer
  --with-freetype --with-gnutls --with-sdl --with-vulkan --with-inotify
  # Wine's own assertions and critical-section names embed __FILE__; without this the PE dlls
  # would carry the path of this Mac. -g -O2 is configure's default, kept as it is.
  "CFLAGS=-g -O2 $SOURCE_PATH_MAP_FLAGS" "CROSSCFLAGS=-g -O2 $SOURCE_PATH_MAP_FLAGS"
)
# Short soname that Wine opens through the LC_RPATH of the .so that asks for it.
WINE_SONAME_ASSIGNMENTS=(
  "ac_cv_lib_soname_gnutls=$LIB_GNUTLS"
  "ac_cv_lib_soname_freetype=$LIB_FREETYPE_LINK"
  "ac_cv_lib_soname_MoltenVK=$LIB_MOLTENVK"
  "ac_cv_lib_soname_SDL2=$LIB_SDL2"
)
RPATH_UNIX_LIBS="@loader_path/../.."   # lib/wine/x86_64-unix -> lib
RPATH_BIN="@loader_path/../lib"        # bin -> lib
ENGINE_BIN_BINARIES=(wine wineserver)
OTOOL_TOOL="otool"
STRIP_TOOL="strip"
STRINGS_TOOL="strings"
LIPO_TOOL="lipo"
ENGINE_UNIX_LIBS_DIR="lib/wine/x86_64-unix"
WINE_LDFLAGS_RPATHS="-Wl,-rpath,$RPATH_UNIX_LIBS -Wl,-rpath,$RPATH_BIN"
FORBIDDEN_STRINGS=("/Users/" "/opt/homebrew" "$WORK_DIR" "$BUILD_DIR" "$DEPS_PREFIX" "$BRASA_ROOT")
CONFIGURE_FATAL_WARNINGS=(
  "fonts won't be supported"
  "no schannel support"
  "Vulkan won't be supported"
  "filesystem change notifications won't be supported"
  "PE cross-compiler not found"
)
CONFIGURE_LOG_NAME="configure.log"

# ---------- Exit codes ----------
EXIT_HASH_UNSET=3
EXIT_HASH_MISMATCH=4
EXIT_CONFIGURE_WARNING=5
EXIT_BAD_DEPENDENCY=6
EXIT_MISSING_OUTPUT=7
EXIT_LEAK=8
EXIT_CHECK_FAILED=9
EXIT_MISSING_SOURCE=10

# ---------- Package (spec 5.5) ----------
ENGINES_VENDOR_DIR="$BRASA_ROOT/vendor/engines"
ENGINE_OUTPUT="$ENGINES_VENDOR_DIR/wine-brasa-$ENGINE_VERSION"
PACKAGE_WORK_DIR="$WORK_DIR/brasa-package"
DOWNLOADS_DIR="$WORK_DIR/downloads"
VERSION_FILE="VERSION"
LICENSES_DIR="licenses"
LICENSES_README_SOURCE="$BRASA_FORK_DIR/brasa/licenses/README.md"
# Not Wine's: the DXMT spike left these in the stage; make-app.sh adds DXMT itself (spec 5.7).
NOT_WINE_FILES=(winemetal.so winemetal.dll)
ENGINE_FILE_MODE_STRIP="go-w"

# wine-mono and wine-gecko, unpacked as CrossOver does. Empty SHA-256: package.sh prints it and stops.
MONO_VERSION="10.4.1"
GECKO_VERSION="2.47.4"
ADDON_NAMES=(MONO GECKO_X86 GECKO_X86_64)
ADDONS_BASE_URL="https://dl.winehq.org/wine"
MONO_URL="$ADDONS_BASE_URL/wine-mono/$MONO_VERSION/wine-mono-$MONO_VERSION-x86.tar.xz"
MONO_SHA256="a16606ef0724202e6a6848ece6e0cbba64d11e2f11aefe744af1d93c6d9f99bb"
MONO_DEST="share/wine/mono"
GECKO_X86_URL="$ADDONS_BASE_URL/wine-gecko/$GECKO_VERSION/wine-gecko-$GECKO_VERSION-x86.tar.xz"
GECKO_X86_SHA256="2cfc8d5c948602e21eff8a78613e1826f2d033df9672cace87fed56e8310afb6"
GECKO_X86_DEST="share/wine/gecko"
GECKO_X86_64_URL="$ADDONS_BASE_URL/wine-gecko/$GECKO_VERSION/wine-gecko-$GECKO_VERSION-x86_64.tar.xz"
GECKO_X86_64_SHA256="fd88fc7e537d058d7a8abf0c1ebc90c574892a466de86706a26d254710a82814"
GECKO_X86_64_DEST="share/wine/gecko"
ADDON_FOLDERS=(
  "$MONO_DEST/wine-mono-$MONO_VERSION"
  "$GECKO_X86_DEST/wine-gecko-$GECKO_VERSION-x86"
  "$GECKO_X86_64_DEST/wine-gecko-$GECKO_VERSION-x86_64"
)
# ---------- Licences (one folder per component under licenses/) ----------
LICENSE_COMPONENTS=(wine gmp nettle gnutls libtasn1 libunistring freetype moltenvk sdl2 libinotify dxmt dxvk mono gecko)
GNUTLS_REAL_DIR="$CROSSOVER_SOURCES_REAL_DIR/gnutls"
# Not inside the DXMT/DXVK release tarballs; texts fetched from the upstream tags (3Shain/dxmt v0.80, Gcenx/DXVK-macOS v1.10.3-20230507-repack).
DXMT_LICENSE_SOURCE="$BRASA_FORK_DIR/brasa/licenses/third-party/dxmt/LICENSE"
DXVK_LICENSE_SOURCE="$BRASA_FORK_DIR/brasa/licenses/third-party/dxvk/LICENSE"
MONO_LICENSE_SOURCE="$BRASA_FORK_DIR/brasa/licenses/third-party/mono/COPYING"
GECKO_LICENSE_SOURCE="$BRASA_FORK_DIR/brasa/licenses/third-party/gecko/LICENSE"
GECKO_LICENSE_HTML_SOURCE="$BRASA_FORK_DIR/brasa/licenses/third-party/gecko/license.html"
# "component|file": copied into licenses/<component>/.
LICENSE_FILES=(
  "wine|$BRASA_FORK_DIR/COPYING.LIB"
  "wine|$BRASA_FORK_DIR/LICENSE"
  "gmp|$GNUTLS_REAL_DIR/gmp/COPYING"
  "gmp|$GNUTLS_REAL_DIR/gmp/COPYINGv2"
  "gmp|$GNUTLS_REAL_DIR/gmp/COPYINGv3"
  "gmp|$GNUTLS_REAL_DIR/gmp/COPYING.LESSERv3"
  "dxmt|$DXMT_LICENSE_SOURCE"
  "dxvk|$DXVK_LICENSE_SOURCE"
  "mono|$MONO_LICENSE_SOURCE"
  "gecko|$GECKO_LICENSE_SOURCE"
  "gecko|$GECKO_LICENSE_HTML_SOURCE"
)
# "component|tarball|member|file name inside licenses/<component>/"
LICENSE_TAR_MEMBERS=(
  "nettle|nettle-$NETTLE_VERSION.tar.gz|nettle-$NETTLE_VERSION/COPYING.LESSERv3|COPYING.LESSERv3"
  "nettle|nettle-$NETTLE_VERSION.tar.gz|nettle-$NETTLE_VERSION/COPYINGv2|COPYINGv2"
  "nettle|nettle-$NETTLE_VERSION.tar.gz|nettle-$NETTLE_VERSION/COPYINGv3|COPYINGv3"
  "gnutls|gnutls-$GNUTLS_VERSION.tar.xz|gnutls-$GNUTLS_VERSION/COPYING|COPYING"
  "gnutls|gnutls-$GNUTLS_VERSION.tar.xz|gnutls-$GNUTLS_VERSION/COPYING.LESSERv2|COPYING.LESSERv2"
  "libtasn1|gnutls-$GNUTLS_VERSION.tar.xz|gnutls-$GNUTLS_VERSION/COPYING.LESSERv2|COPYING.LESSERv2"
  "libtasn1|gnutls-$GNUTLS_VERSION.tar.xz|gnutls-$GNUTLS_VERSION/lib/minitasn1/libtasn1.h|libtasn1.h"
  # gnulib copy inside gnutls (lib/unistring): its headers say LGPL 2.1 or later
  "libunistring|gnutls-$GNUTLS_VERSION.tar.xz|gnutls-$GNUTLS_VERSION/COPYING.LESSERv2|COPYING.LESSERv2"
  "freetype|freetype-$FREETYPE_VERSION.tar.xz|freetype-$FREETYPE_VERSION/docs/FTL.TXT|FTL.TXT"
  "freetype|freetype-$FREETYPE_VERSION.tar.xz|freetype-$FREETYPE_VERSION/docs/GPLv2.TXT|GPLv2.TXT"
  "sdl2|SDL2-$SDL2_VERSION.tar.gz|SDL2-$SDL2_VERSION/LICENSE.txt|LICENSE.txt"
  "libinotify|libinotify-$LIBINOTIFY_VERSION.tar.gz|libinotify-$LIBINOTIFY_VERSION/LICENSE|LICENSE"
  "moltenvk|MoltenVK-macos.tar|MoltenVK/LICENSE|LICENSE"
)
# Wine's libs/ folder holds third-party code (png, tiff, ...) with its own licences, shipped under
# licenses/wine/libs/<lib>/. These are Wine's own helper libraries: Wine's licence covers them.
WINE_LIBS_DIR="$BRASA_FORK_DIR/libs"
WINE_OWN_LIBS=(adsiid dmoguids dxerr8 dxerr9 dxguid mfuuid strmbase strmiids uuid wbemuuid wmcodecdspuuid)
WINE_LIB_LICENSE_NAMES=("LICENSE*" "COPYING*" "COPYRIGHT*" "NOTICE*")   # matched without case
WINE_LIBS_LICENSE_SUBDIR="wine/libs"
CHECK_PROBLEMS_SHOWN=20

# ---------- Stripping (PE dlls need the mingw tool of their architecture) ----------
PE_STRIP_TOOLS=("lib/wine/i386-windows:i686-w64-mingw32-strip" "lib/wine/x86_64-windows:x86_64-w64-mingw32-strip")

# ---------- Package safety ----------
PREVIOUS_ENGINE_SUFFIX=".previous"
MACHO_MAGICS=(feedface cefaedfe feedfacf cffaedfe cafebabe cafebabf)
STATUS_UNREADABLE=2

# ---------- Third-party source offer (spec 5.6) ----------
# Empty SHA-256: fetch-third-party-sources.sh prints it and stops (exit 3).
SOURCES_OUT_DIR="$BRASA_BUILD_DIR/brasa-third-party-sources"
SOURCES_SUMS_NAME="SHA256SUMS"
TAR_TOOL="/usr/bin/tar"   # bsdtar: -s renames the top folder
# No owner of this Mac and no AppleDouble files inside the offered archives.
TAR_PACK_FLAGS=(--no-mac-metadata --uid 0 --gid 0 --uname root --gname wheel)
# "folder|archive|top folder inside it": the exact CodeWeavers sources that deps.sh compiled.
PACKED_SOURCES=(
  "$GNUTLS_REAL_DIR/gmp|gmp-$GMP_VERSION-codeweavers-src.tar.xz|gmp-$GMP_VERSION"
)
# Archives of the offer that are downloaded and pinned. The first five are already in DEPS_SRC_DIR.
# The *_SRC ones are the source code of the binaries Brasa ships unchanged.
SOURCE_DOWNLOADS=(NETTLE GNUTLS FREETYPE SDL2 LIBINOTIFY MOLTENVK_SRC MONO_SRC GECKO_SRC)
# v1.2.10-rc2 (the tag of the shipped binary) is the same commit as v1.2.10 (edbdcf0).
MOLTENVK_SRC_URL="https://github.com/KhronosGroup/MoltenVK/archive/refs/tags/v$MOLTENVK_VERSION.tar.gz"
MOLTENVK_SRC_FILE="MoltenVK-$MOLTENVK_VERSION-src.tar.gz"
MOLTENVK_SRC_SHA256="3435d34ea2dafb043dd82ac5e9d2de7090462ab7cea6ad8bcc14d9c34ff99e9c"
MONO_SRC_URL="$ADDONS_BASE_URL/wine-mono/$MONO_VERSION/wine-mono-$MONO_VERSION-src.tar.xz"
MONO_SRC_SHA256="128e335396689e466dff5e1aa0770a714dbe3d16397fc4ddbb8a80999c67323b"
GECKO_SRC_URL="$ADDONS_BASE_URL/wine-gecko/$GECKO_VERSION/wine-gecko-$GECKO_VERSION-src.tar.xz"
GECKO_SRC_SHA256="bf31b6619570ce289f07298bdd670081635cd12104010050f06c16e44ccd153f"
# "component|tarball|member|file name": copied into licenses/<component>/ only if the tarball and the
# member exist. MoltenVK's source may carry a NOTICE (Apache 2.0 s4d); unverified until the first
# run of fetch-third-party-sources.sh.
OPTIONAL_LICENSE_TAR_MEMBERS=(
  "moltenvk|$MOLTENVK_SRC_FILE|MoltenVK-$MOLTENVK_VERSION/NOTICE|NOTICE"
)
