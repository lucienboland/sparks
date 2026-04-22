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

_should_run "deploy" && {
  _section "deploy - fresh install"
  _make_tmpenv
  output="$(bash "$INSTALLER" 2>&1)"
  exit_code=$?
  _assert_exit "deploy exits 0" "$exit_code" "0"
  _assert_contains "deploy reports source" "$output" "[deploy]"
  _assert_contains "deploy reports done" "$output" "done"
  [[ -f "${SPARKS_INSTALL_DIR}/sparks.bash" ]] \
    && _ok "sparks.bash deployed" \
    || _fail "sparks.bash not found in install dir"
  [[ -d "${SPARKS_INSTALL_DIR}/lib" ]] \
    && _ok "lib/ deployed" \
    || _fail "lib/ not found in install dir"
  [[ -d "${SPARKS_INSTALL_DIR}/adapters" ]] \
    && _ok "adapters/ deployed" \
    || _fail "adapters/ not found in install dir"
  [[ -f "${SPARKS_INSTALL_DIR}/VERSION" ]] \
    && _ok "VERSION stamp written" \
    || _fail "VERSION stamp not found"
  _assert_contains "VERSION has commit=" "$(cat "${SPARKS_INSTALL_DIR}/VERSION")" "commit="
  _assert_contains "VERSION has deployed_at=" "$(cat "${SPARKS_INSTALL_DIR}/VERSION")" "deployed_at="
  _cleanup_tmpenv

  _section "deploy - excluded files not in install dir"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  [[ ! -f "${SPARKS_INSTALL_DIR}/install.sh" ]] \
    && _ok "install.sh not in install dir" \
    || _fail "install.sh should not be in install dir"
  [[ ! -d "${SPARKS_INSTALL_DIR}/.git" ]] \
    && _ok ".git not in install dir" \
    || _fail ".git should not be in install dir"
  [[ ! -d "${SPARKS_INSTALL_DIR}/tests" ]] \
    && _ok "tests/ not in install dir" \
    || _fail "tests/ should not be in install dir"
  [[ ! -d "${SPARKS_INSTALL_DIR}/docs" ]] \
    && _ok "docs/ not in install dir" \
    || _fail "docs/ should not be in install dir"
  _cleanup_tmpenv

  _section "deploy - idempotent"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  output="$(bash "$INSTALLER" 2>&1)"
  exit_code=$?
  _assert_exit "second deploy exits 0" "$exit_code" "0"
  _assert_contains "second deploy reports done" "$output" "done"
  _cleanup_tmpenv

  _section "deploy - deploy-to-self refused"
  _make_tmpenv
  output="$(SPARKS_INSTALL_DIR="$REPO_DIR" bash "$INSTALLER" 2>&1)"
  exit_code=$?
  _assert_exit "deploy-to-self exits non-zero" "$exit_code" "1"
  _assert_contains "deploy-to-self error message" "$output" "Cannot deploy"
  _cleanup_tmpenv

  _section "deploy - suggests config scaffold when missing"
  _make_tmpenv
  output="$(bash "$INSTALLER" 2>&1)"
  _assert_contains "suggests config scaffold" "$output" "[suggest]"
  _assert_contains "suggests mkdir for personas" "$output" "mkdir -p"
  _assert_contains "mentions sparks.conf" "$output" "sparks.conf"
  _cleanup_tmpenv

  _section "deploy - suggests @sparks in plugins.conf"
  _make_tmpenv
  output="$(bash "$INSTALLER" 2>&1)"
  _assert_contains "suggests @sparks" "$output" "@sparks"
  _assert_contains "mentions plugins.conf" "$output" "plugins.conf"
  _cleanup_tmpenv

  _section "deploy - suggests gemini settings"
  _make_tmpenv
  output="$(bash "$INSTALLER" 2>&1)"
  _assert_contains "suggests gemini context block" "$output" "context.fileName"
  _cleanup_tmpenv

  _section "deploy - no config suggestion when config exists"
  _make_tmpenv
  mkdir -p "${SPARKS_CONFIG_DIR}/personas"
  touch "${SPARKS_CONFIG_DIR}/sparks.conf"
  output="$(bash "$INSTALLER" 2>&1)"
  if [[ "$output" != *"mkdir -p ${SPARKS_CONFIG_DIR}"* ]]; then
    _ok "no config scaffold suggestion when config already exists"
  else
    _fail "config scaffold suggested even though config dir exists"
  fi
  _cleanup_tmpenv

  _section "deploy - no plugins.conf suggestion when @sparks present"
  _make_tmpenv
  echo "@sparks" > "${SPARKS_PLUGINS_CONF}"
  output="$(bash "$INSTALLER" 2>&1)"
  if [[ "$output" != *"@sparks not found"* ]]; then
    _ok "no @sparks suggestion when already present"
  else
    _fail "@sparks suggestion shown even though already in plugins.conf"
  fi
  _cleanup_tmpenv

  _section "deploy - no gemini suggestion when context.fileName present"
  _make_tmpenv
  printf '{"context":{"fileName":["AGENTS.md"]}}\n' > "${SPARKS_GEMINI_SETTINGS}"
  output="$(bash "$INSTALLER" 2>&1)"
  if [[ "$output" != *"context.fileName not found"* ]]; then
    _ok "no gemini suggestion when context.fileName present"
  else
    _fail "gemini suggestion shown even though context.fileName is configured"
  fi
  _cleanup_tmpenv
}

_summary
