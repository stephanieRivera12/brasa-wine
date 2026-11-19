#!/usr/bin/env bash
# Every literal of the command-line patch tests lives here. Meant to be sourced after
# ../constants.sh. Limits mirror dlls/kernelbase/brasa_constants.h (spec 5.1).

# ---------- Build output ----------
TESTS_SRC_DIR="$BRASA_FORK_DIR/brasa/tests/src"
TESTS_REG_DIR="$BRASA_FORK_DIR/brasa/tests/reg"
TESTS_OUT_DIR="$BRASA_BUILD_DIR/brasa-wine-tests"
TEST_ARCHS=(x86_64 i386)
TEST_CC_x86_64="x86_64-w64-mingw32-gcc"
TEST_CC_i386="i686-w64-mingw32-gcc"
TEST_CFLAGS=(-O2 -Wall -Wextra -Werror -municode)
TEST_PROGRAMS=(spawner echo-cmdline deny-key)

# ---------- Test prefix ----------
TEST_PREFIX_NAME_PREFIX="brasa-wine-tests-"
TEST_DLL_OVERRIDES="mscoree,mshtml="
TEST_DRIVE_DIR="drive_c/brasa-test"
TEST_WIN_DIR='C:\brasa-test'
TEST_OUT_NAME="echo.out"
TEST_OUT_ENV="BRASA_TEST_OUT"

# ---------- Registry ----------
REG_KEY='HKCU\Software\Brasa\AppendCommandLine'
REG_PARENT_KEY='HKCU\Software\Brasa'
REG_HEADER='Windows Registry Editor Version 5.00'
REG_KEY_HEADER='[HKEY_CURRENT_USER\Software\Brasa\AppendCommandLine]'
REG_VALUE_NAME="steamwebhelper.exe"
REG_PATH_VALUE_NAME='bin\steamwebhelper.exe'
REG_OTHER_VALUE_NAME="other.exe"

# ---------- Programs under test ----------
HELPER_EXE="steamwebhelper.exe"
ECHO_EXE="echo-cmdline.exe"
STEAM_OPTIONS="--no-sandbox --in-process-gpu --disable-gpu"
CHILD_ARGS="a b"
QUOTED_ARG='"x y"'

# ---------- Limits (same numbers as brasa_constants.h) ----------
MAX_OPTIONS_CHARS=1024
TOO_LONG_OPTIONS_CHARS=$((MAX_OPTIONS_CHARS + 1))
MAX_CMDLINE_CHARS=32767
LONG_ARGS_CHARS=32000
LONG_OPTIONS_CHARS=1000
FILL_CHAR="a"
MARKER_REPEATS=40         # marker x 40 is over MAX_OPTIONS_CHARS

# ---------- Log check ----------
BRASA_OPTIONS_MARKER="ZZ-BRASA-OPTIONS-MARKER-ZZ"
BRASA_ARGS_MARKER="ZZ-BRASA-ARGS-MARKER-ZZ"
LOG_CHANNEL="brasa"
LOG_DEBUG_SETTING="warn+brasa"
LOG_MARKER_REG="log-control-marker.reg"
EMPTY_REG="empty.reg"
WRONG_TYPE_REGS=(wrong-type-dword.reg wrong-type-multisz.reg wrong-type-expandsz.reg)
CONTROL_CHAR_REGS=(control-newline.reg control-nul.reg control-del.reg)

# ---------- Performance ----------
PERF_WARMUP_ROUNDS=1
PERF_ROUNDS=5
PERF_CREATIONS=200
PERF_RATIO_NUMERATOR=101     # keyed median <= 1.01 x median without key
PERF_RATIO_DENOMINATOR=100
