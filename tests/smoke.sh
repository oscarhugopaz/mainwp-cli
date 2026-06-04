#!/usr/bin/env bash
# Smoke tests for mainwp. Run with: ./tests/smoke.sh
#
# These tests exercise argument parsing, help output, and error paths
# without making any real network calls. They do not require jq, gum,
# or a configured profile.

set -uo pipefail

ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/mainwp"

PASS=0
FAIL=0
FAILED_TESTS=()

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf '  \033[32m✓\033[0m %s\n' "$label"
    PASS=$((PASS+1))
  else
    printf '  \033[31m✗\033[0m %s\n' "$label"
    printf '    expected to find: %s\n' "$needle"
    printf '    actual:           %s\n' "$haystack"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("$label")
  fi
}

assert_equals() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  \033[32m✓\033[0m %s\n' "$label"
    PASS=$((PASS+1))
  else
    printf '  \033[31m✗\033[0m %s\n' "$label"
    printf '    expected: %s\n' "$expected"
    printf '    actual:   %s\n' "$actual"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("$label")
  fi
}

assert_exit_code() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  \033[32m✓\033[0m %s\n' "$label"
    PASS=$((PASS+1))
  else
    printf '  \033[31m✗\033[0m %s\n' "$label"
    printf '    expected exit: %s\n    actual exit:   %s\n' "$expected" "$actual"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("$label")
  fi
}

run_capture() {
  # run_capture <label> <expected-exit> <args...>
  local label="$1" expected_exit="$2"; shift 2
  local out
  out="$("$BIN" "$@" 2>&1)"
  local code=$?
  assert_exit_code "$label exit code" "$expected_exit" "$code"
  printf '%s' "$out"
}

# ---- tests -----------------------------------------------------------

printf '\n[1] top-level\n'
out="$(run_capture "version flag" 0 --version)"
assert_contains "version output" "$out" "mainwp 0."

out="$(run_capture "top-level help" 0 --help)"
assert_contains "help lists sites" "$out" "sites"
assert_contains "help lists config" "$out" "config"
assert_contains "help lists init"   "$out" "init"

printf '\n[2] help for subcommands\n'
for cmd in init deps config sites clients tags updates costs users settings monitoring api-keys posts pages batch; do
  out="$(run_capture "help $cmd" 0 help "$cmd")"
  assert_contains "help $cmd is non-empty" "$out" "$cmd -"
done

printf '\n[3] unknown commands\n'
run_capture "unknown command" 1 no-such-command >/dev/null
run_capture "unknown subcommand on sites" 1 sites no-such >/dev/null

printf '\n[4] config subcommands work without a real profile\n'
out="$(run_capture "config path" 0 config path)"
assert_contains "config path output" "$out" "mainwp/config.json"

out="$(run_capture "config profile list empty" 0 config profile list)"
assert_contains "no profiles message" "$out" "No profiles configured yet"

printf '\n[5] completion scripts print without error\n'
out="$(run_capture "bash completion" 0 completion bash)"
assert_contains "bash completion header" "$out" "complete -F _mainwp_completions mainwp"
out="$(run_capture "zsh completion" 0 completion zsh)"
assert_contains "zsh completion header" "$out" "#compdef mainwp"

printf '\n[5b] deps subcommand\n'
out="$(run_capture "deps status" 0 deps status)"
assert_contains "deps status prints Present" "$out" "Present:"
out="$(run_capture "deps status json" 0 deps --json status)"
assert_contains "deps JSON output" "$out" '"present"'
out="$(run_capture "deps help" 0 help deps)"
assert_contains "deps help lists status" "$out" "status"

printf '\n[6] errors point to mainwp init when no profile is set\n'
out="$(run_capture "sites list without config" 1 sites list --no-input)"
assert_contains "init hint" "$out" "mainwp init"
out="$(run_capture "clients list without config" 1 clients list --no-input)"
assert_contains "init hint" "$out" "mainwp init"

printf '\n[7] global flags can appear after the subcommand\n'
# --help after `init` should show init's help, not top-level help.
out="$(run_capture "init --help" 0 init --help)"
assert_contains "init help text" "$out" "Interactive setup"

# --plain after `help` should still work
out="$(run_capture "help --plain sites" 0 --plain help sites)"
assert_contains "sites help under --plain" "$out" "Manage child sites"

# ---- summary ---------------------------------------------------------

printf '\n'
printf '  Passed: \033[32m%d\033[0m\n' "$PASS"
printf '  Failed: \033[31m%d\033[0m\n' "$FAIL"
if [[ $FAIL -gt 0 ]]; then
  printf '\nFailed tests:\n'
  for t in "${FAILED_TESTS[@]}"; do
    printf '  - %s\n' "$t"
  done
  exit 1
fi
exit 0
