#!/usr/bin/env bash
# Runs the engine patch cases (command line, received TOS) against a built engine in a throwaway prefix under $TMPDIR.
# Run: brasa/tests/build-tests.sh && brasa/tests/run-tests.sh <engine root>
# Prints "PASS|FAIL <case>" per case; exit 0 when every case passes.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../constants.sh
source "$TESTS_DIR/../constants.sh"
# shellcheck source=test-constants.sh
source "$TESTS_DIR/test-constants.sh"
# shellcheck source=../lib.sh
source "$TESTS_DIR/../lib.sh"
# shellcheck source=run-lib.sh
source "$TESTS_DIR/run-lib.sh"

[[ $# -eq 1 && -x "$1/bin/wine" ]] || die "usage: run-tests.sh <engine root, with bin/wine>"
ENGINE_ROOT="$(cd "$1" && pwd)"
WINE="$ENGINE_ROOT/bin/wine"
WINESERVER="$ENGINE_ROOT/bin/wineserver"
for arch in "${TEST_ARCHS[@]}"; do
  [[ -f "$TESTS_OUT_DIR/$arch/spawner.exe" ]] || die "test programs missing: run brasa/tests/build-tests.sh"
done

PREFIXES=()
cleanup() {
  local prefix
  for prefix in ${PREFIXES[@]+"${PREFIXES[@]}"}; do
    WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
    rm -rf -- "${prefix:?}"
  done
}
trap cleanup EXIT

# ---------- Prefix and wine ----------
export WINEDLLOVERRIDES="$TEST_DLL_OVERRIDES"
export WINEDEBUG="-all"
export WINEARCH="win64"

new_prefix() {
  WINEPREFIX="$(mktemp -d "${TMPDIR:-/tmp}/${TEST_PREFIX_NAME_PREFIX}$$.XXXXXX")"
  export WINEPREFIX
  PREFIXES+=("$WINEPREFIX")
  OUT_FILE="$WINEPREFIX/$TEST_OUT_NAME"
  export "$TEST_OUT_ENV=$(z_path_of "$OUT_FILE")"
  "$WINE" wineboot --init >/dev/null 2>&1 || die "could not create the test prefix"
}

reg_clear() { "$WINE" reg delete "$REG_PARENT_KEY" /f >/dev/null 2>&1 || true; }
reg_put() { "$WINE" reg add "$REG_KEY" /v "$1" /t REG_SZ /d "$2" /f >/dev/null; }
reg_import() { "$WINE" regedit /S "$(z_path_of "$TESTS_REG_DIR/$1")" >/dev/null 2>&1; }

# ---------- Spawning (environment: SPAWNER_ARCH, CHILD_ARCH, SPAWN_FLAGS, WIN_PREFIX) ----------
install_child() {
  local target="$WINEPREFIX/$TEST_DRIVE_DIR/$1"
  mkdir -p "$(dirname "$target")"
  cp "$TESTS_OUT_DIR/${CHILD_ARCH:-x86_64}/$ECHO_EXE" "$target"
}

spawner_exe() { printf '%s/%s/spawner.exe' "$TESTS_OUT_DIR" "${SPAWNER_ARCH:-x86_64}"; }

# Runs the spawner on a child (Windows path) and its raw arguments; its own output goes to stdout.
spawn() {
  local child="$1"
  shift
  rm -f "$OUT_FILE"
  # shellcheck disable=SC2086  # SPAWN_FLAGS is a list of flags on purpose
  "$WINE" "$(spawner_exe)" ${SPAWN_FLAGS:-} "$child" "$@" 2>&1 || true
}

received_line() { cat "$OUT_FILE" 2>/dev/null || true; }

# ---------- Cases ----------
MISMATCHES=""

expect() {
  local mismatch
  mismatch="$(mismatch_of "$1" "$2" "$3")"
  [[ -z "$mismatch" ]] || MISMATCHES+="${MISMATCHES:+ }$mismatch"
}

# Installs the child, starts it and expects it to receive its line plus the given options.
expect_spawn() {
  local relative="$1" options="$2" window
  shift 2
  install_child "$relative"
  window="${WIN_PREFIX:-}$(win_path_of "$relative")"
  spawn "$window" "$@" >/dev/null
  expect "${EXPECT_LABEL:-$relative}" "$(compose_line "$window" "${EXPECT_ARGS-$*}" "$options")" "$(received_line)"
}

HELPER="bin/$HELPER_EXE"

case_appendsOptions() {
  reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
  expect_spawn "$HELPER" "$STEAM_OPTIONS" $CHILD_ARGS
}

case_noKeyUnchanged() { expect_spawn "$HELPER" "" $CHILD_ARGS; }

case_otherExeUnchanged() {
  reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
  expect_spawn "bin/$ECHO_EXE" "" $CHILD_ARGS
}

case_caseInsensitive() {
  reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
  expect_spawn "BIN/STEAMWEBHELPER.EXE" "$STEAM_OPTIONS" $CHILD_ARGS
}

case_similarNamesUnchanged() {
  reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
  expect_spawn "bin/$HELPER_EXE.bak" "" $CHILD_ARGS
  expect_spawn "bin/x$HELPER_EXE" "" $CHILD_ARGS
  reg_clear
  reg_put "$REG_PATH_VALUE_NAME" "$STEAM_OPTIONS"
  expect_spawn "$HELPER" "" $CHILD_ARGS
}

case_spacesAndQuotes() {
  reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
  expect_spawn "dir with spaces/$HELPER_EXE" "$STEAM_OPTIONS" "$QUOTED_ARG"
}

case_appNameOnly() {
  reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
  SPAWN_FLAGS="--app" expect_spawn "$HELPER" "$STEAM_OPTIONS"
}

case_noArguments() {
  reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
  expect_spawn "$HELPER" "$STEAM_OPTIONS"
}

case_uncPath() {
  reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
  WIN_PREFIX='\\?\' expect_spawn "$HELPER" "$STEAM_OPTIONS" $CHILD_ARGS
}

case_from32to64() {
  reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
  SPAWNER_ARCH=i386 CHILD_ARCH=x86_64 expect_spawn "$HELPER" "$STEAM_OPTIONS" $CHILD_ARGS
}

case_from64to32() {
  reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
  SPAWNER_ARCH=x86_64 CHILD_ARCH=i386 expect_spawn "$HELPER" "$STEAM_OPTIONS" $CHILD_ARGS
}

case_tooLongIgnored() {
  reg_put "$REG_VALUE_NAME" "$(repeat_char "$FILL_CHAR" "$TOO_LONG_OPTIONS_CHARS")"
  expect_spawn "$HELPER" "" $CHILD_ARGS
}

case_emptyIgnored() {
  reg_import "$EMPTY_REG"
  expect_spawn "$HELPER" "" $CHILD_ARGS
}

# Each .reg of the list is tried alone and must leave the line unchanged.
expect_all_ignored() {
  local file
  for file in "$@"; do
    reg_clear
    reg_import "$file"
    EXPECT_LABEL="$file" expect_spawn "$HELPER" "" $CHILD_ARGS
  done
}

case_wrongTypeIgnored() { expect_all_ignored "${WRONG_TYPE_REGS[@]}"; }
case_controlCharsIgnored() { expect_all_ignored "${CONTROL_CHAR_REGS[@]}"; }

case_resultTooLongIgnored() {
  reg_put "$REG_VALUE_NAME" "$(repeat_char "$FILL_CHAR" "$LONG_OPTIONS_CHARS")"
  expect_spawn "$HELPER" "" "$(repeat_char "$FILL_CHAR" "$LONG_ARGS_CHARS")"
}

case_maxOptionsAccepted() {
  local options
  options="$(repeat_char "$FILL_CHAR" "$MAX_OPTIONS_CHARS")"
  reg_put "$REG_VALUE_NAME" "$options"
  expect_spawn "$HELPER" "$options" $CHILD_ARGS
}

# Result of exactly MAX_RESULT_CHARS plus the given extra characters, through one padded argument.
expect_result_of_length() {
  local extra="$1" options="$2" window pad
  window="$(win_path_of "$HELPER")"
  pad="$(repeat_char "$FILL_CHAR" "$(args_length_for_total "$((MAX_RESULT_CHARS + extra))" "$window" "$STEAM_OPTIONS")")"
  SPAWN_FLAGS="--pad ${#pad}" EXPECT_ARGS="$pad" expect_spawn "$HELPER" "$options"
}

case_resultAtLimitAppended() {
  reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
  expect_result_of_length 0 "$STEAM_OPTIONS"
}

case_resultOverLimitIgnored() {
  reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
  expect_result_of_length 1 ""
}

# The ACL cannot be undone by the test, so this case gets a prefix of its own.
case_unreadableKey() {
  new_prefix
  "$WINE" "$TESTS_OUT_DIR/x86_64/deny-key.exe" >/dev/null 2>&1 || expect "deny-key" "ok" "failed"
  expect_spawn "$HELPER" "" $CHILD_ARGS
}

# Invalid values that carry both markers: the log may name the channel and the exe, nothing else.
case_logHasNoContent() {
  local relative="$HELPER" window log marker_value
  marker_value="$(repeat_char "$BRASA_OPTIONS_MARKER" "$MARKER_REPEATS")"
  install_child "$relative"
  window="$(win_path_of "$relative")"
  reg_import "$LOG_MARKER_REG"
  log="$(WINEDEBUG="$LOG_DEBUG_SETTING" spawn "$window" "$BRASA_ARGS_MARKER")"
  reg_put "$REG_VALUE_NAME" "$marker_value"
  log+=$'\n'"$(WINEDEBUG="$LOG_DEBUG_SETTING" spawn "$window" "$BRASA_ARGS_MARKER")"
  mentions_all "$log" "$LOG_CHANNEL" "$REG_VALUE_NAME" || expect "log-names-channel-and-exe" "yes" "no"
  expect "log-leaks-markers" "" "$(markers_found_in "$log" "$BRASA_OPTIONS_MARKER" "$BRASA_ARGS_MARKER" | tr '\n' ' ')"
}

# Steam's networking sockets assert when IP_RECVTOS gives no IP_TOS control message.
case_receivesTos() {
  local arch received
  for arch in "${TEST_ARCHS[@]}"; do
    received="$("$WINE" "$TESTS_OUT_DIR/$arch/$RECV_TOS_EXE" "$SENT_TOS" 2>/dev/null | tr -d '\r' || true)"
    expect "recv-tos-$arch" "$EXPECTED_TOS_LINE" "$received"
  done
}

# ---------- Performance ----------
PERF_VARIANTS=(none mismatch match)
PERF_ECHO_REL="bin/$ECHO_EXE"

perf_prepare() {
  reg_clear
  [[ "$1" == none ]] || reg_put "$REG_VALUE_NAME" "$STEAM_OPTIONS"
}

perf_child() {
  [[ "$1" == match ]] && printf '%s' "$HELPER" || printf '%s' "$PERF_ECHO_REL"
}

# Prints the milliseconds of PERF_CREATIONS creations, or nothing when the run failed.
perf_sample() {
  local variant="$1" output
  perf_prepare "$variant"
  output="$(SPAWN_FLAGS="--repeat $PERF_CREATIONS" spawn "$(win_path_of "$(perf_child "$variant")")" | tr -d '\r')"
  [[ "$output" =~ ^[0-9]+$ ]] && printf '%s' "$output" || true
}

perf_record() {
  local variable="perf_samples_$1" sample
  sample="$(perf_sample "$1")"
  [[ -n "$sample" ]] || MISMATCHES+="${MISMATCHES:+ }no-sample-$1"
  printf -v "$variable" '%s %s' "${!variable}" "$sample"
}

case_performance() {
  local round variant samples baseline value
  install_child "$HELPER"
  install_child "$PERF_ECHO_REL"
  for variant in "${PERF_VARIANTS[@]}"; do printf -v "perf_samples_$variant" '%s' ''; done
  for ((round = 0; round < PERF_WARMUP_ROUNDS; round++)); do
    for variant in "${PERF_VARIANTS[@]}"; do perf_sample "$variant" >/dev/null; done
  done
  for ((round = 0; round < PERF_ROUNDS; round++)); do
    for variant in "${PERF_VARIANTS[@]}"; do perf_record "$variant"; done
  done
  [[ -z "$MISMATCHES" ]] || return 0
  # shellcheck disable=SC2154  # set by printf -v above
  baseline="$(median $perf_samples_none)"
  for variant in mismatch match; do
    samples="perf_samples_$variant"
    value="$(median ${!samples})"
    printf 'INFO performance median ms per %s creations: none=%s %s=%s\n' "$PERF_CREATIONS" "$baseline" "$variant" "$value"
    within_ratio "$value" "$baseline" || MISMATCHES+="${MISMATCHES:+ }$variant-over-ratio"
  done
}

# ---------- Main ----------
CASES=(
  appendsOptions noKeyUnchanged otherExeUnchanged caseInsensitive similarNamesUnchanged
  spacesAndQuotes appNameOnly noArguments uncPath from32to64 from64to32 tooLongIgnored
  emptyIgnored wrongTypeIgnored controlCharsIgnored resultTooLongIgnored maxOptionsAccepted resultAtLimitAppended resultOverLimitIgnored logHasNoContent
  performance unreadableKey receivesTos
)

run_case() {
  MISMATCHES=""
  reg_clear
  "case_$1"
  verdict_line "$1" "$MISMATCHES"
}

overall=0
new_prefix
for name in "${CASES[@]}"; do
  run_case "$name" || overall=1
done
exit "$overall"
