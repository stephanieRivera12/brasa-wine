#!/usr/bin/env bash
# Pure functions of run-tests.sh. Meant to be sourced after ../constants.sh and test-constants.sh.

# The line a child must receive: quoted path, then the arguments, then the options.
compose_line() {
  local path="$1" args="$2" options="$3" line
  line="\"$path\""
  [[ -z "$args" ]] || line+=" $args"
  [[ -z "$options" ]] || line+=" $options"
  printf '%s' "$line"
}

# Length of the single argument that makes compose_line(path, argument, options) total characters.
args_length_for_total() {
  local total="$1" path="$2" options="$3"
  printf '%s' "$((total - ${#path} - QUOTES_AROUND_PATH - SEPARATORS_AROUND_ARGS - ${#options}))"
}

# Windows path of a file relative to the test folder of the prefix.
win_path_of() {
  local relative="$1"
  printf '%s\%s' "$TEST_WIN_DIR" "${relative//\//\\}"
}

# Windows path (drive Z:) of a unix path.
z_path_of() {
  local unix_path="$1"
  printf 'Z:%s' "${unix_path//\//\\}"
}

# The text repeated count times (a pipe: bash substitution on 32 000 characters is too slow).
repeat_char() {
  local text="$1" count="$2"
  ((count > 0)) || return 0
  yes "$text" | head -n "$count" | tr -d '\n'
}

# REG_SZ value of a .reg file as hex(1): UTF-16LE bytes plus the terminator. ASCII text only.
reg_sz_hex() {
  local text="$1" bytes="" index
  for ((index = 0; index < ${#text}; index++)); do
    bytes+="$(printf '%02x,00,' "'${text:index:1}")"
  done
  printf 'hex(1):%s00,00' "$bytes"
}

# A whole .reg file (CRLF line ends) with one value of the patch key.
reg_file_text() {
  local name="$1" value="$2"
  printf '%s\r\n\r\n%s\r\n"%s"=%s\r\n' "$REG_HEADER" "$REG_KEY_HEADER" "$name" "$value"
}

# Prints the median; for an even count, the lower of the two middle values.
median() {
  local count=$#
  printf '%s\n' "$@" | sort -n | sed -n "$(((count + 1) / 2))p"
}

# Succeeds when value <= baseline x PERF_RATIO.
within_ratio() {
  local value="$1" baseline="$2"
  ((value * PERF_RATIO_DENOMINATOR <= baseline * PERF_RATIO_NUMERATOR))
}

# Prints each marker that appears in the log.
markers_found_in() {
  local log="$1" marker
  shift
  for marker in "$@"; do
    [[ "$log" != *"$marker"* ]] || printf '%s\n' "$marker"
  done
}

# Succeeds when the text holds every word.
mentions_all() {
  local text="$1" word
  shift
  for word in "$@"; do
    [[ "$text" == *"$word"* ]] || return 1
  done
}

# Prints the label when the two lines differ.
mismatch_of() {
  local label="$1" expected="$2" received="$3"
  [[ "$expected" == "$received" ]] || printf '%s' "$label"
}

# Prints "PASS name" or "FAIL name (labels)"; the status is the verdict.
verdict_line() {
  local name="$1" mismatches="$2"
  if [[ -z "$mismatches" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (%s)\n' "$name" "$mismatches"
    return 1
  fi
}
