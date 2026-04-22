#!/usr/bin/env bash
# =============================================================================
# test_installer.bash -- Tests for install.sh (Sparks)
# =============================================================================
# Usage:
#   bash tests/test_installer.bash           # all tests
#   bash tests/test_installer.bash -s deploy # one section
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALLER="${REPO_DIR}/install.sh"

# ---------------------------------------------------------------------------
# Minimal test framework (intentionally simpler than test_sparks.bash)
# ---------------------------------------------------------------------------
_pass_count=0
_fail_count=0
_section_name=""

_section() { _section_name="$1"; echo; echo "=== $1 ==="; }
_ok()      { _pass_count=$(( _pass_count + 1 )); echo "  ok: $*"; }
_fail()    { _fail_count=$(( _fail_count + 1 )); echo "  FAIL: $*"; }
_assert()  { local desc="$1" actual="$2" expected="$3"
             if [[ "$actual" == "$expected" ]]; then _ok "$desc"
             else _fail "$desc — got: '$actual' expected: '$expected'"; fi; }
_assert_contains() { local desc="$1" haystack="$2" needle="$3"
             if [[ "$haystack" == *"$needle"* ]]; then _ok "$desc"
             else _fail "$desc — '$needle' not found in output"; fi; }
_assert_exit() { local desc="$1" actual="$2" expected="$3"
             if [[ "$actual" == "$expected" ]]; then _ok "$desc"
             else _fail "$desc — exit code: got $actual, expected $expected"; fi; }

_summary() {
  echo
  echo "Results: ${_pass_count} passed, ${_fail_count} failed"
  [[ "$_fail_count" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Section filter (-s <name>)
# ---------------------------------------------------------------------------
_run_section=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--section) _run_section="${2-}"; shift 2 ;;
    -h|--help)
      printf "Usage: %s [-s|--section NAME]\n" "$0"
      exit 0
      ;;
    *) printf "Unknown option: %s\n" "$1" >&2; exit 1 ;;
  esac
done

_should_run() { [[ -z "$_run_section" || "$_run_section" == "$1" ]]; }

# ---------------------------------------------------------------------------
# Temp environment helper
# _make_tmpenv: creates isolated dirs, exports override vars, sets _TMPENV_ROOT
# _cleanup_tmpenv: removes temp dir and unsets all override vars
# ---------------------------------------------------------------------------
_TMPENV_ROOT=""

_make_tmpenv() {
  local tmp
  tmp="$(mktemp -d)"
  _TMPENV_ROOT="$tmp"
  export SPARKS_INSTALL_DIR="${tmp}/install"
  export SPARKS_CONFIG_DIR="${tmp}/config"
  export SPARKS_PLUGINS_CONF="${tmp}/plugins.conf"
  export SPARKS_GEMINI_SETTINGS="${tmp}/gemini_settings.json"
}

_cleanup_tmpenv() {
  [[ -n "${_TMPENV_ROOT:-}" ]] && rm -rf "$_TMPENV_ROOT"
  unset SPARKS_INSTALL_DIR SPARKS_CONFIG_DIR SPARKS_PLUGINS_CONF SPARKS_GEMINI_SETTINGS _TMPENV_ROOT
}

_should_run "help" && {
  _section "help"

  _make_tmpenv
  output="$(bash "$INSTALLER" --help 2>&1)"
  exit_code=$?
  _assert_exit "--help exits 0" "$exit_code" "0"
  _assert_contains "--help mentions usage" "$output" "Usage:"
  _assert_contains "--help mentions --status" "$output" "--status"
  _cleanup_tmpenv
}

_should_run "commit" && {
  _section "commit detection"

  _make_tmpenv
  commit="$(
    SPARKS_INSTALL_DIR="${SPARKS_INSTALL_DIR}"
    SPARKS_CONFIG_DIR="${SPARKS_CONFIG_DIR}"
    SPARKS_PLUGINS_CONF="${SPARKS_PLUGINS_CONF}"
    SPARKS_GEMINI_SETTINGS="${SPARKS_GEMINI_SETTINGS}"
    bash -c "source '$INSTALLER' --_source-only 2>/dev/null; _get_dev_commit" 2>/dev/null
  )"
  if [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || [[ "$commit" == "unknown" ]]; then
    _ok "commit is valid hex or unknown: $commit"
  else
    _fail "commit has unexpected format: '$commit'"
  fi
  _cleanup_tmpenv
}

_summary
