#!/usr/bin/env bash
# Smoke tests for mainwp. Run with: ./tests/smoke.sh
#
# These tests exercise argument parsing, help output, and error paths
# without making any real network calls. They do not require jq, gum,
# or a configured profile.

set -uo pipefail

ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/mainwp"

# Sandbox HOME so config writes do not pollute the real user config.
# Restored on exit. This makes the test suite safe to run against a
# real MainWP Dashboard without risk of clobbering ~/.config/mainwp.
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT
export HOME="$TEST_HOME"

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
for cmd in init deps skill config sites clients tags updates costs users settings monitoring api-keys posts pages batch; do
  out="$(run_capture "help $cmd" 0 help "$cmd")"
  assert_contains "help $cmd is non-empty" "$out" "$cmd -"
done

printf '\n[3] unknown commands\n'
run_capture "unknown command" 1 no-such-command >/dev/null
run_capture "unknown subcommand on sites" 1 sites no-such >/dev/null

printf '\n[4] config subcommands work without a real profile\n'
out="$(run_capture "config path" 0 config path)"
assert_contains "config path output" "$out" "mainwp-cli/config.json"

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

printf '\n[5c] skill subcommand\n'
out="$(run_capture "skill help" 0 help skill)"
assert_contains "skill help lists install" "$out" "install"
assert_contains "skill help lists all agents" "$out" "claude-code"
assert_contains "skill help lists global" "$out" "global"
out="$(run_capture "skill install --help" 0 skill install --help)"
assert_contains "skill install help" "$out" "--agent"

# Real install into a sandboxed HOME so the test is hermetic.
SKILL_SANDBOX="$(mktemp -d)"
HOME="$SKILL_SANDBOX" "$BIN" skill install --all --no-input >/dev/null 2>&1
for agent in claude-code codex pi opencode global; do
  case "$agent" in
    claude-code) root="$SKILL_SANDBOX/.claude/skills" ;;
    codex)       root="$SKILL_SANDBOX/.codex/skills" ;;
    pi)          root="$SKILL_SANDBOX/.pi/agent/skills" ;;
    opencode)    root="$SKILL_SANDBOX/.config/opencode/skills" ;;
    global)      root="$SKILL_SANDBOX/.agents/skills" ;;
  esac
  if [[ -f "$root/mainwp-cli/SKILL.md" ]]; then
    printf '  \033[32m✓\033[0m installed for %s\n' "$agent"
    PASS=$((PASS+1))
  else
    printf '  \033[31m✗\033[0m missing SKILL.md for %s\n' "$agent"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("skill install for $agent")
  fi
done
rm -rf "$SKILL_SANDBOX"

# --agent filters down to one location.
SKILL_SANDBOX="$(mktemp -d)"
HOME="$SKILL_SANDBOX" "$BIN" skill install --agent opencode --no-input >/dev/null 2>&1
if [[ -f "$SKILL_SANDBOX/.config/opencode/skills/mainwp-cli/SKILL.md" \
   && ! -d "$SKILL_SANDBOX/.agents/skills/mainwp-cli" ]]; then
  printf '  \033[32m✓\033[0m --agent installs only the requested agent\n'
  PASS=$((PASS+1))
else
  printf '  \033[31m✗\033[0m --agent did not filter correctly\n'
  FAIL=$((FAIL+1))
  FAILED_TESTS+=("--agent filter")
fi
rm -rf "$SKILL_SANDBOX"

# --global is exclusive and must not remove unrelated skills.
SKILL_SANDBOX="$(mktemp -d)"
mkdir -p "$SKILL_SANDBOX/.claude/skills/other-skill" \
         "$SKILL_SANDBOX/.codex/skills/other-skill" \
         "$SKILL_SANDBOX/.pi/agent/skills/other-skill" \
         "$SKILL_SANDBOX/.config/opencode/skills/other-skill" \
         "$SKILL_SANDBOX/.agents/skills/other-skill"
HOME="$SKILL_SANDBOX" "$BIN" skill install --global --all --no-input >/dev/null 2>&1
if [[ -f "$SKILL_SANDBOX/.agents/skills/mainwp-cli/SKILL.md" \
   && -d "$SKILL_SANDBOX/.agents/skills/other-skill" \
   && -d "$SKILL_SANDBOX/.claude/skills/other-skill" \
   && -d "$SKILL_SANDBOX/.codex/skills/other-skill" \
   && -d "$SKILL_SANDBOX/.pi/agent/skills/other-skill" \
   && -d "$SKILL_SANDBOX/.config/opencode/skills/other-skill" \
   && ! -d "$SKILL_SANDBOX/.claude/skills/mainwp-cli" \
   && ! -d "$SKILL_SANDBOX/.codex/skills/mainwp-cli" \
   && ! -d "$SKILL_SANDBOX/.pi/agent/skills/mainwp-cli" \
   && ! -d "$SKILL_SANDBOX/.config/opencode/skills/mainwp-cli" ]]; then
  printf '  \033[32m✓\033[0m --global installs only shared skill and preserves existing skills\n'
  PASS=$((PASS+1))
else
  printf '  \033[31m✗\033[0m --global touched non-global skill locations\n'
  FAIL=$((FAIL+1))
  FAILED_TESTS+=("--global exclusive install")
fi
rm -rf "$SKILL_SANDBOX"

# --no-input without --agent/--all must fail.
run_capture "skill install --no-input" 1 skill install --no-input >/dev/null

# Unknown agent must fail.
run_capture "skill install unknown agent" 1 skill install --agent bogus --no-input >/dev/null

printf '\n[5d] every command handles --help\n'
# Regression: bin/mainwp must translate "api-keys" -> "cmd_api_keys"
# (bash function names cannot contain hyphens) and the per-command
# case must include "help" alongside "-h|--help" so that
# "<cmd> --help" reaches the help function.
for cmd in init deps skill config sites clients tags updates costs users settings monitoring api-keys posts pages batch; do
  out="$(run_capture "$cmd --help" 0 "$cmd" --help 2>&1)"
  if echo "$out" | grep -qE 'Unknown subcommand|has no entry point|Unknown command'; then
    printf '  \033[31m✗\033[0m %s --help reached an error path\n' "$cmd"
    printf '    output: %s\n' "$(echo "$out" | head -2)"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("$cmd --help")
  elif [[ -z "$out" ]]; then
    printf '  \033[31m✗\033[0m %s --help produced no output\n' "$cmd"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("$cmd --help empty")
  else
    printf '  \033[32m✓\033[0m %s --help\n' "$cmd"
    PASS=$((PASS+1))
  fi
done

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
