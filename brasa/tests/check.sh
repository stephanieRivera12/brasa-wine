#!/usr/bin/env bash
# Assertion helpers shared by the shell tests. Meant to be sourced.

failures=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s (expected %q, got %q)\n' "$name" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}

status_of() {
  local status=0
  ( "$@" ) >/dev/null 2>&1 || status=$?
  printf '%s' "$status"
}

finish_checks() {
  if ((failures > 0)); then
    printf '%d test(s) failed\n' "$failures"
    exit 1
  fi
  printf 'all tests passed\n'
}
