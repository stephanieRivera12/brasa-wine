#!/usr/bin/env bash
# Tests of the pure parts of brasa/tests/run-lib.sh. Run: brasa/tests/test-run-lib.sh
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../constants.sh
source "$TESTS_DIR/../constants.sh"
# shellcheck source=test-constants.sh
source "$TESTS_DIR/test-constants.sh"
# shellcheck source=run-lib.sh
source "$TESTS_DIR/run-lib.sh"
# shellcheck source=check.sh
source "$TESTS_DIR/check.sh"

# compose_line
WIN_HELPER='C:\brasa-test\bin\steamwebhelper.exe'
check "compose_line quotes the path" '"C:\x.exe"' "$(compose_line 'C:\x.exe' "" "")"
check "compose_line adds arguments" '"C:\x.exe" a b' "$(compose_line 'C:\x.exe' "a b" "")"
check "compose_line adds options after arguments" '"C:\x.exe" a b --o' "$(compose_line 'C:\x.exe' "a b" "--o")"
check "compose_line adds options without arguments" '"C:\x.exe" --o' "$(compose_line 'C:\x.exe' "" "--o")"

# args_length_for_total: length of the one argument that makes the whole line total characters
check "args_length_for_total subtracts path, quotes, two spaces and options" 5 "$(args_length_for_total 20 'C:\x.exe' '--o')"
check "a line built with that length has the total length" 20 \
  "$(compose_line 'C:\x.exe' "$(repeat_char a "$(args_length_for_total 20 'C:\x.exe' '--o')")" '--o' | wc -c | tr -d ' ')"

# win_path_of / z_path_of
check "win_path_of turns slashes into backslashes" 'C:\brasa-test\bin\a.exe' "$(win_path_of "bin/a.exe")"
check "win_path_of keeps spaces" 'C:\brasa-test\dir with spaces\a.exe' "$(win_path_of "dir with spaces/a.exe")"
check "z_path_of maps a unix path to Z:" 'Z:\var\tmp\x.reg' "$(z_path_of "/var/tmp/x.reg")"

# repeat_char
check "repeat_char repeats" "aaa" "$(repeat_char a 3)"
check "repeat_char of zero is empty" "" "$(repeat_char a 0)"
check "repeat_char makes a long string" "$TOO_LONG_OPTIONS_CHARS" "$(repeat_char a "$TOO_LONG_OPTIONS_CHARS" | wc -c | tr -d ' ')"

check "repeat_char repeats a whole marker" "abab" "$(repeat_char ab 2)"
check "repeat_char of a result-limit string is exact" "$LONG_ARGS_CHARS" "$(repeat_char a "$LONG_ARGS_CHARS" | wc -c | tr -d ' ')"

# reg_sz_hex
check "reg_sz_hex encodes UTF-16LE with terminator" 'hex(1):41,00,00,00' "$(reg_sz_hex "A")"
check "reg_sz_hex encodes a newline" 'hex(1):41,00,0a,00,42,00,00,00' "$(reg_sz_hex $'A\nB')"
check "reg_sz_hex encodes DEL" 'hex(1):7f,00,00,00' "$(reg_sz_hex $'\x7f')"
check "reg_sz_hex of empty text is the terminator" 'hex(1):00,00' "$(reg_sz_hex "")"

# reg_file_text and the committed marker file
MARKER_VALUE_HEX="$(reg_sz_hex "$BRASA_OPTIONS_MARKER"$'\n'x)"
SAMPLE_REG="$(reg_file_text "$REG_VALUE_NAME" "hex(1):41,00,00,00" | tr -d '\r')"
check "reg_file_text has the header, the key and the value" \
  "$REG_HEADER||[HKEY_CURRENT_USER\\Software\\Brasa\\AppendCommandLine]|\"steamwebhelper.exe\"=hex(1):41,00,00,00" \
  "$(printf '%s' "$SAMPLE_REG" | tr '\n' '|')"
check "reg_file_text uses CRLF line ends" 1 "$(reg_file_text x "hex(1):00,00" | head -1 | grep -c $'\r')"
check "committed log-control-marker.reg is what reg_file_text builds" \
  "$(reg_file_text "$REG_VALUE_NAME" "$MARKER_VALUE_HEX" | shasum -a 256)" "$(shasum -a 256 < "$TESTS_REG_DIR/$LOG_MARKER_REG")"

# median
check "median of an odd list" 7 "$(median 9 7 8 1 3)"
check "median sorts numerically, not as text" 20 "$(median 100 20 3)"
check "median of an even list is the lower middle" 2 "$(median 4 1 3 2)"
check "median of one value" 5 "$(median 5)"

# within_ratio (threshold: value * 100 <= baseline * 101)
check "equal values are within the ratio" 0 "$(status_of within_ratio 1000 1000)"
check "exactly 1% over is within the ratio" 0 "$(status_of within_ratio 1010 1000)"
check "just over 1% is outside the ratio" 1 "$(status_of within_ratio 1011 1000)"
check "faster than the baseline is within the ratio" 0 "$(status_of within_ratio 900 1000)"

# markers_found_in / mentions_all
LOG_CLEAN=$'warn:brasa:append_command_line ignoring value L"steamwebhelper.exe": control character\n'
LOG_LEAK="warn:brasa:x \"$BRASA_ARGS_MARKER\" and $BRASA_OPTIONS_MARKER"
check "markers_found_in is empty on a clean log" "" "$(markers_found_in "$LOG_CLEAN" "$BRASA_OPTIONS_MARKER" "$BRASA_ARGS_MARKER")"
check "markers_found_in lists both leaked markers" "$BRASA_OPTIONS_MARKER $BRASA_ARGS_MARKER" "$(markers_found_in "$LOG_LEAK" "$BRASA_OPTIONS_MARKER" "$BRASA_ARGS_MARKER" | sort -r | tr '\n' ' ' | sed 's/ $//')"
check "mentions_all accepts a log with every word" 0 "$(status_of mentions_all "$LOG_CLEAN" brasa steamwebhelper.exe)"
check "mentions_all fails when a word is missing" 1 "$(status_of mentions_all "$LOG_CLEAN" brasa other.exe)"
check "mentions_all fails on an empty log" 1 "$(status_of mentions_all "" brasa steamwebhelper.exe)"

# verdict_line and the mismatch list
check "verdict_line passes without mismatches" "PASS appendsOptions" "$(verdict_line appendsOptions "")"
check "verdict_line fails and names the mismatches" "FAIL appendsOptions (dword multisz)" "$(verdict_line appendsOptions "dword multisz")"
check "verdict_line status is 0 on PASS" 0 "$(status_of verdict_line x "")"
check "verdict_line status is 1 on FAIL" 1 "$(status_of verdict_line x "bad")"
check "mismatch_of is empty when equal" "" "$(mismatch_of first "same" "same")"
check "mismatch_of names the label when different" "first" "$(mismatch_of first "same" "other")"

finish_checks
