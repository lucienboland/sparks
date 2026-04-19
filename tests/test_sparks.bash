#!/usr/bin/env bash
# =============================================================================
# tests/test_sparks.bash -- Sparks plugin test suite
# =============================================================================
#
# Comprehensive tests for the Sparks AI Persona Manager plugin.
# Uses the same test framework conventions as test_shellfire.bash.
#
# Usage:
#   bash ~/code/sparks/tests/test_sparks.bash          # run all tests
#   bash ~/code/sparks/tests/test_sparks.bash -v        # verbose
#   bash ~/code/sparks/tests/test_sparks.bash -s NAME   # run only section NAME
#
# Sections:
#   syntax          Syntax-check all sparks .bash files
#   core            Walk-up resolution, merge, exclude logic
#   render          Sentinel patching in AGENTS.md
#   adapters        Adapter dispatch and file generation
#   commands        Command dispatcher (sparks on/off/apply/etc.)
#   inheritance     Directory hierarchy inheritance
#   session         Session command and OpenCode agent/command validation
#   integration     Full plugin load and status reporting
#
# =============================================================================

set -uo pipefail

# =============================================================================
# TEST FRAMEWORK (identical to test_shellfire.bash)
# =============================================================================

_T_RESET=$'\033[0m'
_T_BOLD=$'\033[1m'
_T_DIM=$'\033[2m'
_T_CMD=$'\033[1;37;44m'
_T_OUT=$'\033[0;37m'
_T_PASS=$'\033[1;32m'
_T_FAIL=$'\033[1;37;41m'
_T_SEC=$'\033[1;36m'
_T_INFO=$'\033[2;37m'
_T_SKIP=$'\033[0;33m'
_T_WARN=$'\033[1;33m'

_T_TOTAL=0
_T_PASSED=0
_T_FAILED=0
_T_SKIPPED=0
_T_VERBOSE=0
_T_SECTION=""
_T_LAST_OUTPUT=""
_T_LAST_RC=0

# Self-relocating: repo root is one level up from tests/
_T_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_T_FRAMEWORK_DIR="${SHELLFIRE_HOME:-${HOME}/.local/share/shellfire}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) _T_VERBOSE=1; shift ;;
    -s|--section) _T_SECTION="$2"; shift 2 ;;
    -h|--help)
      printf "Usage: %s [-v|--verbose] [-s|--section NAME]\n" "$0"
      exit 0
      ;;
    *) printf "Unknown option: %s\n" "$1"; exit 1 ;;
  esac
done

_t_section() {
  local name="$1" desc="${2:-}"
  if [[ -n "${_T_SECTION}" && "${_T_SECTION}" != "${name}" ]]; then
    return 1
  fi
  printf '\n%b══════════════════════════════════════════════════════════════%b\n' "${_T_SEC}" "${_T_RESET}"
  printf '%b  %-20s%b %s\n' "${_T_SEC}" "${name}" "${_T_RESET}" "${desc}"
  printf '%b══════════════════════════════════════════════════════════════%b\n' "${_T_SEC}" "${_T_RESET}"
  return 0
}

_t_cmd() {
  local desc="$1" cmd="$2"
  printf '\n%b  ▸ %s %b\n' "${_T_INFO}" "${desc}" "${_T_RESET}"
  printf '  %b $ %s %b\n' "${_T_CMD}" "${cmd}" "${_T_RESET}"
}

_t_output() {
  while IFS= read -r line; do
    printf '  %b│ %s%b\n' "${_T_OUT}" "${line}" "${_T_RESET}"
  done
}

_t_pass() {
  (( _T_TOTAL++ )); (( _T_PASSED++ ))
  printf '  %b ✓ PASS %b %s\n' "${_T_PASS}" "${_T_RESET}" "$1"
}

_t_fail() {
  (( _T_TOTAL++ )); (( _T_FAILED++ ))
  printf '  %b ✗ FAIL %b %s\n' "${_T_FAIL}" "${_T_RESET}" "$1"
  [[ -n "${2:-}" ]] && printf '  %b         → %s%b\n' "${_T_WARN}" "$2" "${_T_RESET}"
}

_t_skip() {
  (( _T_TOTAL++ )); (( _T_SKIPPED++ ))
  printf '  %b ○ SKIP %b %s — %s\n' "${_T_SKIP}" "${_T_RESET}" "$1" "${2:-}"
}

_t_run() {
  local cmd="$1" output rc
  output=$(eval "${cmd}" 2>&1) && rc=0 || rc=$?
  if (( _T_VERBOSE )) || (( rc != 0 )); then
    [[ -n "${output}" ]] && echo "${output}" | _t_output
  fi
  _T_LAST_OUTPUT="${output}"
  _T_LAST_RC="${rc}"
  return "${rc}"
}

_t_assert_rc() {
  local desc="$1" cmd="$2" expected="${3:-0}"
  _t_cmd "${desc}" "${cmd}"
  _t_run "${cmd}" || true
  if (( _T_LAST_RC == expected )); then _t_pass "${desc}"
  else _t_fail "${desc}" "expected exit code ${expected}, got ${_T_LAST_RC}"; fi
}

_t_assert_contains() {
  local desc="$1" cmd="$2" expected="$3"
  _t_cmd "${desc}" "${cmd}"
  _t_run "${cmd}" || true
  if [[ "${_T_LAST_OUTPUT}" == *"${expected}"* ]]; then _t_pass "${desc}"
  else _t_fail "${desc}" "output does not contain: ${expected}"; fi
}

_t_assert_not_contains() {
  local desc="$1" cmd="$2" unwanted="$3"
  _t_cmd "${desc}" "${cmd}"
  _t_run "${cmd}" || true
  if [[ "${_T_LAST_OUTPUT}" != *"${unwanted}"* ]]; then _t_pass "${desc}"
  else _t_fail "${desc}" "output unexpectedly contains: ${unwanted}"; fi
}

# =============================================================================
# TEST SANDBOX
#
# All tests run inside a temporary directory tree to avoid polluting real files.
# We create a fake central store and project hierarchy.
# =============================================================================

_SPARKS_TEST_DIR=""

_t_setup_sandbox() {
  _SPARKS_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sparks-test.XXXXXX")

  # Create a fake central store
  mkdir -p "${_SPARKS_TEST_DIR}/config/sparks/personas"
  mkdir -p "${_SPARKS_TEST_DIR}/config/sparks/skills"

  # Create test personas
  cat > "${_SPARKS_TEST_DIR}/config/sparks/personas/base.md" <<'EOF'
---
name: base
description: Core preferences always loaded
version: 1.0
tags: base
---

## Core preferences

- Be concise and direct.
EOF

  cat > "${_SPARKS_TEST_DIR}/config/sparks/personas/sysadmin.md" <<'EOF'
---
name: sysadmin
description: System administration context
version: 1.0
tags: ops
---

You are assisting a sysadmin.

## Domain knowledge

- Linux and macOS
EOF

  cat > "${_SPARKS_TEST_DIR}/config/sparks/personas/homelab.md" <<'EOF'
---
name: homelab
description: Homelab infrastructure
version: 1.0
tags: homelab
---

You are assisting with homelab work.
EOF

  cat > "${_SPARKS_TEST_DIR}/config/sparks/personas/principal.md" <<'EOF'
---
name: principal
description: Principal consultant
version: 1.0
tags: work
---

You are assisting a principal consultant.
EOF

  # Create sparks.conf
  cat > "${_SPARKS_TEST_DIR}/config/sparks/sparks.conf" <<'EOF'
SPARKS_ACTIVE_ADAPTERS=(opencode claude)
SPARKS_CD_BANNER="true"
SPARKS_STALE_HINT="true"
SPARKS_VERBOSE="1"
EOF

  # Create a fake project hierarchy
  mkdir -p "${_SPARKS_TEST_DIR}/projects/work/project-a"
  mkdir -p "${_SPARKS_TEST_DIR}/projects/work/project-b"
  mkdir -p "${_SPARKS_TEST_DIR}/projects/personal/homelab"
  mkdir -p "${_SPARKS_TEST_DIR}/projects/personal/homelab/subdir"

  # Override the env vars so Sparks uses our sandbox
  export SPARKS_CONFIG_DIR="${_SPARKS_TEST_DIR}/config/sparks"
  export SPARKS_PERSONAS_DIR="${_SPARKS_TEST_DIR}/config/sparks/personas"
  export HOME="${_SPARKS_TEST_DIR}"

  # Source the modules (not the full plugin, since we don't have Shellfire loaded)
  # We need to provide stubs for Shellfire functions
  # Stub out logging functions if not already loaded
  if ! declare -f _log_info &>/dev/null; then
    _log_info() { printf "  ▸ %s\n" "$*"; }
    _log_ok() { printf "  ✔ %s\n" "$*"; }
    _log_warn() { printf "  ⚠ %s\n" "$*" >&2; }
    _log_error() { printf "  ✘ %s\n" "$*" >&2; }
    _sc() { printf '\033[38;5;%sm' "$1"; }
    _sr() { printf '\033[0m'; }
    _status_set() { :; }
  fi

  # Source core module
  source "${_T_DIR}/lib/core.bash"
  source "${_T_DIR}/lib/render.bash"
}

_t_teardown_sandbox() {
  if [[ -n "${_SPARKS_TEST_DIR}" && -d "${_SPARKS_TEST_DIR}" ]]; then
    rm -rf "${_SPARKS_TEST_DIR}"
  fi
}

# Store real HOME so we can restore it
_REAL_HOME="${HOME}"

# Cleanup on exit
trap '_t_teardown_sandbox; export HOME="${_REAL_HOME}"' EXIT

# =============================================================================
# BANNER
# =============================================================================

printf '\n'
printf '  %b✦%b %bSparks Test Suite%b\n' \
  $'\033[38;5;208m' "${_T_RESET}" "${_T_BOLD}" "${_T_RESET}"
printf '  %b─────────────────────────────────────────%b\n' \
  "${_T_DIM}" "${_T_RESET}"

# =============================================================================
# SECTION: config — SPARKS_ACTIVE_ADAPTERS variable and dispatch
# =============================================================================

if _t_section "config" "SPARKS_ACTIVE_ADAPTERS variable and dispatch"; then

  _t_setup_sandbox

  # Source the full plugin so SPARKS_ACTIVE_ADAPTERS is set
  _SPARKS_LOADED=""
  source "${_T_DIR}/sparks.bash"

  # -- Test: SPARKS_ACTIVE_ADAPTERS defaults to (opencode claude) --
  _t_cmd "SPARKS_ACTIVE_ADAPTERS defaults" "echo \${SPARKS_ACTIVE_ADAPTERS[*]}"
  _t_run "echo \${SPARKS_ACTIVE_ADAPTERS[*]}" || true
  if [[ "${_T_LAST_OUTPUT}" == "opencode claude" ]]; then
    _t_pass "SPARKS_ACTIVE_ADAPTERS defaults to (opencode claude)"
  else
    _t_fail "SPARKS_ACTIVE_ADAPTERS defaults to (opencode claude)" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: backward compat — SPARKS_DEFAULT_ADAPTER converts to array --
  _SPARKS_LOADED=""
  unset SPARKS_ACTIVE_ADAPTERS
  SPARKS_DEFAULT_ADAPTER="opencode"
  source "${_T_DIR}/sparks.bash"
  _t_cmd "Backward compat: SPARKS_DEFAULT_ADAPTER converts" "echo \${SPARKS_ACTIVE_ADAPTERS[*]}"
  _t_run "echo \${SPARKS_ACTIVE_ADAPTERS[*]}" || true
  if [[ "${_T_LAST_OUTPUT}" == "opencode" ]]; then
    _t_pass "SPARKS_DEFAULT_ADAPTER=opencode converts to array"
  else
    _t_fail "SPARKS_DEFAULT_ADAPTER=opencode converts to array" "got: ${_T_LAST_OUTPUT}"
  fi
  unset SPARKS_DEFAULT_ADAPTER

  # -- Test: sparks apply without --all runs only active adapters --
  _SPARKS_LOADED=""
  unset SPARKS_ACTIVE_ADAPTERS
  source "${_T_DIR}/sparks.bash"
  _st_test_project="${_SPARKS_TEST_DIR}/projects/work/project-a"
  echo "sysadmin" > "${_st_test_project}/.sparks"

  _t_cmd "sparks apply runs opencode and claude by default" \
    "cd '${_st_test_project}' && sparks apply"
  ( cd "${_st_test_project}" && sparks apply ) 2>&1 | _t_output

  if [[ -f "${_st_test_project}/AGENTS.md" ]]; then
    _t_pass "sparks apply creates AGENTS.md (opencode adapter)"
  else
    _t_fail "sparks apply creates AGENTS.md (opencode adapter)"
  fi

  if [[ -f "${_st_test_project}/CLAUDE.md" ]]; then
    _t_pass "sparks apply creates CLAUDE.md (claude adapter)"
  else
    _t_fail "sparks apply creates CLAUDE.md (claude adapter)"
  fi

  # Copilot should NOT run (not in active list)
  if [[ ! -f "${_st_test_project}/.github/copilot-instructions.md" ]]; then
    _t_pass "sparks apply does NOT run copilot adapter by default"
  else
    _t_fail "sparks apply does NOT run copilot adapter by default"
  fi

  _t_teardown_sandbox

fi

# =============================================================================
# SECTION: syntax
# =============================================================================

if _t_section "syntax" "Syntax-check all sparks files"; then

  for f in "${_T_DIR}/sparks.bash" \
           "${_T_DIR}/lib/"*.bash \
           "${_T_DIR}/adapters/"*.bash; do
    local_name="${f#"${_T_DIR}/"}"
    _t_assert_rc "bash -n ${local_name}" "bash -n '${f}'"
  done

fi

# =============================================================================
# SECTION: core — Walk-up resolution, merge, exclude
# =============================================================================

if _t_section "core" "Walk-up resolution, merge, exclude logic"; then

  _t_setup_sandbox

  # -- Test: base is always included even with no .sparks files --
  _t_cmd "Base always present (no .sparks files)" "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/work/project-a'"
  _t_run "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/work/project-a'" || true
  if [[ "${_T_LAST_OUTPUT}" == "base" ]]; then
    _t_pass "Base is the only persona when no .sparks files exist"
  else
    _t_fail "Base is the only persona when no .sparks files exist" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: single .sparks file picks up personas --
  echo "sysadmin" > "${_SPARKS_TEST_DIR}/projects/work/.sparks"
  _t_cmd "Single .sparks file" "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/work/project-a'"
  _t_run "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/work/project-a'" || true
  expected=$'base\nsysadmin'
  if [[ "${_T_LAST_OUTPUT}" == "${expected}" ]]; then
    _t_pass "Inherits sysadmin from parent .sparks"
  else
    _t_fail "Inherits sysadmin from parent .sparks" "expected: base+sysadmin, got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: child .sparks adds to parent --
  echo "homelab" > "${_SPARKS_TEST_DIR}/projects/work/project-a/.sparks"
  _t_cmd "Child adds to parent" "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/work/project-a'"
  _t_run "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/work/project-a'" || true
  expected=$'base\nsysadmin\nhomelab'
  if [[ "${_T_LAST_OUTPUT}" == "${expected}" ]]; then
    _t_pass "Child .sparks adds homelab to inherited sysadmin"
  else
    _t_fail "Child .sparks adds homelab to inherited sysadmin" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: exclude with - prefix --
  printf '%s\n' "-sysadmin" "principal" > "${_SPARKS_TEST_DIR}/projects/work/project-b/.sparks"
  _t_cmd "Exclude with - prefix" "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/work/project-b'"
  _t_run "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/work/project-b'" || true
  expected=$'base\nprincipal'
  if [[ "${_T_LAST_OUTPUT}" == "${expected}" ]]; then
    _t_pass "Exclusion removes sysadmin, adds principal"
  else
    _t_fail "Exclusion removes sysadmin, adds principal" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: base can be suppressed with -base --
  printf '%s\n' "-base" "sysadmin" > "${_SPARKS_TEST_DIR}/projects/personal/.sparks"
  _t_cmd "Base suppressed by -base in .sparks" "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/personal/homelab'"
  _t_run "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/personal/homelab'" || true
  if [[ "${_T_LAST_OUTPUT}" != *"base"* ]]; then
    _t_pass "Base is absent when -base is in .sparks"
  else
    _t_fail "Base is absent when -base is in .sparks" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: inheritance chain --
  _t_cmd "Inheritance chain" "_sparks_inheritance_chain '${_SPARKS_TEST_DIR}/projects/work/project-a'"
  _t_run "_sparks_inheritance_chain '${_SPARKS_TEST_DIR}/projects/work/project-a'" || true
  if [[ "${_T_LAST_OUTPUT}" == *"project-a/.sparks"* && "${_T_LAST_OUTPUT}" == *"work/.sparks"* ]]; then
    _t_pass "Chain includes both project-a and work .sparks files"
  else
    _t_fail "Chain includes both .sparks files" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: list available personas --
  _t_cmd "List available" "_sparks_list_available"
  _t_run "_sparks_list_available" || true
  if [[ "${_T_LAST_OUTPUT}" == *"base"* && "${_T_LAST_OUTPUT}" == *"sysadmin"* && \
        "${_T_LAST_OUTPUT}" == *"homelab"* && "${_T_LAST_OUTPUT}" == *"principal"* ]]; then
    _t_pass "All 4 personas listed"
  else
    _t_fail "All 4 personas listed" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: persona exists --
  _t_cmd "Persona exists check" "_sparks_persona_exists sysadmin"
  if _sparks_persona_exists "sysadmin"; then
    _t_pass "sysadmin exists"
  else
    _t_fail "sysadmin exists"
  fi

  if ! _sparks_persona_exists "nonexistent"; then
    _t_pass "nonexistent does not exist"
  else
    _t_fail "nonexistent does not exist"
  fi

  # -- Test: read persona body --
  _t_cmd "Read persona body" "_sparks_read_persona_body sysadmin"
  _t_run "_sparks_read_persona_body sysadmin" || true
  if [[ "${_T_LAST_OUTPUT}" == *"assisting a sysadmin"* ]]; then
    _t_pass "Body contains expected content"
  else
    _t_fail "Body contains expected content" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: read persona meta --
  _t_cmd "Read persona meta" "_sparks_read_persona_meta sysadmin description"
  _t_run "_sparks_read_persona_meta sysadmin description" || true
  if [[ "${_T_LAST_OUTPUT}" == "System administration context" ]]; then
    _t_pass "Description field reads correctly"
  else
    _t_fail "Description field reads correctly" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: merge content --
  _t_cmd "Merge content" "_sparks_merge_content '${_SPARKS_TEST_DIR}/projects/work/project-a'"
  _t_run "_sparks_merge_content '${_SPARKS_TEST_DIR}/projects/work/project-a'" || true
  if [[ "${_T_LAST_OUTPUT}" == *"Persona: base"* && \
        "${_T_LAST_OUTPUT}" == *"Persona: sysadmin"* && \
        "${_T_LAST_OUTPUT}" == *"Persona: homelab"* ]]; then
    _t_pass "Merged content includes all active personas"
  else
    _t_fail "Merged content includes all active personas" "got first 5 lines: $(echo "${_T_LAST_OUTPUT}" | head -5)"
  fi

  # -- Test: hash content --
  _t_cmd "Hash content" "_sparks_hash_content 'test string'"
  _t_run "_sparks_hash_content 'test string'" || true
  if [[ "${#_T_LAST_OUTPUT}" -ge 6 ]]; then
    _t_pass "Hash produces non-trivial output"
  else
    _t_fail "Hash produces non-trivial output" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: hash is deterministic --
  hash1=$(_sparks_hash_content "deterministic test")
  hash2=$(_sparks_hash_content "deterministic test")
  if [[ "${hash1}" == "${hash2}" ]]; then
    _t_pass "Hash is deterministic"
  else
    _t_fail "Hash is deterministic" "${hash1} != ${hash2}"
  fi

  # -- Test: write and read .sparks file --
  _t_cmd "Write .sparks file" "_sparks_write_sparks_file '${_SPARKS_TEST_DIR}/test.sparks' sysadmin homelab"
  _sparks_write_sparks_file "${_SPARKS_TEST_DIR}/test.sparks" "sysadmin" "homelab"
  _t_run "_sparks_read_sparks_file '${_SPARKS_TEST_DIR}/test.sparks'" || true
  expected=$'sysadmin\nhomelab'
  if [[ "${_T_LAST_OUTPUT}" == "${expected}" ]]; then
    _t_pass "Write and read .sparks file roundtrips correctly"
  else
    _t_fail "Write and read .sparks file roundtrips correctly" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: generated content embeds persona version comments --
  echo "sysadmin" > "${_SPARKS_TEST_DIR}/projects/work/project-a/.sparks"
  _t_cmd "Version comment in merged content" \
    "_sparks_merge_content '${_SPARKS_TEST_DIR}/projects/work/project-a'"
  _t_run "_sparks_merge_content '${_SPARKS_TEST_DIR}/projects/work/project-a'" || true
  if [[ "${_T_LAST_OUTPUT}" == *"<!-- persona-version:"* ]]; then
    _t_pass "Merged content contains persona-version comments"
  else
    _t_fail "Merged content contains persona-version comments" \
      "first 10 lines: $(echo "${_T_LAST_OUTPUT}" | head -10)"
  fi

  if [[ "${_T_LAST_OUTPUT}" == *"<!-- persona-version: 1.0 -->"* ]]; then
    _t_pass "Version comment matches frontmatter version (1.0)"
  else
    _t_fail "Version comment matches frontmatter version (1.0)" \
      "output: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: version-only bump in frontmatter triggers staleness --
  # Generate the file first
  _sparks_render_to_file \
    "${_SPARKS_TEST_DIR}/projects/work/project-a/AGENTS.md" \
    "${_SPARKS_TEST_DIR}/projects/work/project-a"

  if ! _sparks_is_stale \
      "${_SPARKS_TEST_DIR}/projects/work/project-a/AGENTS.md" \
      "${_SPARKS_TEST_DIR}/projects/work/project-a"; then
    _t_pass "File not stale immediately after render"
  else
    _t_fail "File not stale immediately after render"
  fi

  # Bump version in sysadmin frontmatter without changing body
  sed -i.bak 's/^version: 1\.0$/version: 1.1/' \
    "${_SPARKS_TEST_DIR}/config/sparks/personas/sysadmin.md"

  if _sparks_is_stale \
      "${_SPARKS_TEST_DIR}/projects/work/project-a/AGENTS.md" \
      "${_SPARKS_TEST_DIR}/projects/work/project-a"; then
    _t_pass "Staleness detected on version-only bump"
  else
    _t_fail "Staleness detected on version-only bump"
  fi

  # Restore original version
  mv "${_SPARKS_TEST_DIR}/config/sparks/personas/sysadmin.md.bak" \
     "${_SPARKS_TEST_DIR}/config/sparks/personas/sysadmin.md"

  # -- Test: missing persona emits warning, does not abort --
  echo "nonexistent" >> "${_SPARKS_TEST_DIR}/projects/work/project-a/.sparks"
  _t_cmd "Missing persona warns, does not abort" \
    "_sparks_merge_content '${_SPARKS_TEST_DIR}/projects/work/project-a'"
  _t_run "_sparks_merge_content '${_SPARKS_TEST_DIR}/projects/work/project-a'" || true
  # Should still output content for the valid personas
  if [[ "${_T_LAST_OUTPUT}" == *"Persona: base"* && \
        "${_T_LAST_OUTPUT}" == *"Persona: sysadmin"* ]]; then
    _t_pass "Merge continues with valid personas when one is missing"
  else
    _t_fail "Merge continues with valid personas when one is missing"
  fi
  # Restore .sparks
  echo "sysadmin" > "${_SPARKS_TEST_DIR}/projects/work/project-a/.sparks"

  _t_teardown_sandbox

fi

# =============================================================================
# SECTION: render — Sentinel patching
# =============================================================================

if _t_section "render" "Sentinel section management"; then

  _t_setup_sandbox

  _st_target_dir="${_SPARKS_TEST_DIR}/projects/work/project-a"
  _st_target_file="${_st_target_dir}/AGENTS.md"
  echo "sysadmin" > "${_st_target_dir}/.sparks"

  # -- Test: create new file with sentinel --
  _t_cmd "Create AGENTS.md from scratch" "_sparks_render_to_file '${_st_target_file}' '${_st_target_dir}'"
  _sparks_render_to_file "${_st_target_file}" "${_st_target_dir}"
  if [[ -f "${_st_target_file}" ]]; then
    _t_pass "AGENTS.md was created"
  else
    _t_fail "AGENTS.md was created"
  fi

  _st_content=$(<"${_st_target_file}")
  if [[ "${_st_content}" == *"sparks:begin"* && "${_st_content}" == *"sparks:end"* ]]; then
    _t_pass "File contains sentinel markers"
  else
    _t_fail "File contains sentinel markers"
  fi

  if [[ "${_st_content}" == *"Persona: base"* && "${_st_content}" == *"Persona: sysadmin"* ]]; then
    _t_pass "File contains persona content"
  else
    _t_fail "File contains persona content"
  fi

  # -- Test: preserve existing content above sentinel --
  cat > "${_st_target_file}" <<'EOF'
# Project AGENTS.md

This is hand-written project context that should NOT be touched.

## Architecture

- This project uses React and TypeScript
EOF

  _t_cmd "Append sentinel to existing file" "_sparks_render_to_file '${_st_target_file}' '${_st_target_dir}'"
  _sparks_render_to_file "${_st_target_file}" "${_st_target_dir}"
  _st_content=$(<"${_st_target_file}")
  if [[ "${_st_content}" == *"hand-written project context"* ]]; then
    _t_pass "Existing content preserved above sentinel"
  else
    _t_fail "Existing content preserved above sentinel"
  fi

  if [[ "${_st_content}" == *"sparks:begin"* && "${_st_content}" == *"Persona: sysadmin"* ]]; then
    _t_pass "Sentinel section appended"
  else
    _t_fail "Sentinel section appended"
  fi

  # -- Test: update sentinel without touching content above --
  # Change the .sparks to include homelab
  printf '%s\n' "sysadmin" "homelab" > "${_st_target_dir}/.sparks"
  _t_cmd "Update sentinel section (add homelab)" "_sparks_render_to_file '${_st_target_file}' '${_st_target_dir}'"
  _sparks_render_to_file "${_st_target_file}" "${_st_target_dir}"
  _st_content=$(<"${_st_target_file}")

  if [[ "${_st_content}" == *"hand-written project context"* ]]; then
    _t_pass "Existing content still preserved after update"
  else
    _t_fail "Existing content still preserved after update"
  fi

  if [[ "${_st_content}" == *"Persona: homelab"* ]]; then
    _t_pass "New persona (homelab) appears in updated sentinel"
  else
    _t_fail "New persona (homelab) appears in updated sentinel"
  fi

  # Count sentinel markers — should be exactly one pair
  begin_count=$(grep -c "sparks:begin" "${_st_target_file}")
  end_count=$(grep -c "sparks:end" "${_st_target_file}")
  if (( begin_count == 1 && end_count == 1 )); then
    _t_pass "Exactly one pair of sentinel markers"
  else
    _t_fail "Exactly one pair of sentinel markers" "begin=${begin_count}, end=${end_count}"
  fi

  # -- Test: remove sentinel --
  _t_cmd "Remove sentinel section" "_sparks_remove_sentinel '${_st_target_file}'"
  _sparks_remove_sentinel "${_st_target_file}"
  if [[ -f "${_st_target_file}" ]]; then
    _st_content=$(<"${_st_target_file}")
  else
    _st_content=""
  fi
  if [[ "${_st_content}" != *"sparks:begin"* && "${_st_content}" != *"sparks:end"* ]]; then
    _t_pass "Sentinel markers removed"
  else
    _t_fail "Sentinel markers removed"
  fi

  if [[ "${_st_content}" == *"hand-written project context"* ]]; then
    _t_pass "Content above sentinel preserved after removal"
  else
    _t_fail "Content above sentinel preserved after removal"
  fi

  # -- Test: read sentinel --
  _sparks_render_to_file "${_st_target_file}" "${_st_target_dir}"
  _t_cmd "Read sentinel section" "_sparks_read_sentinel '${_st_target_file}'"
  _t_run "_sparks_read_sentinel '${_st_target_file}'" || true
  if [[ "${_T_LAST_OUTPUT}" == *"Persona: sysadmin"* ]]; then
    _t_pass "Read sentinel returns persona content"
  else
    _t_fail "Read sentinel returns persona content"
  fi

  # -- Test: staleness detection --
  _t_cmd "Staleness: file is current right after apply" "_sparks_is_stale '${_st_target_file}' '${_st_target_dir}'"
  if ! _sparks_is_stale "${_st_target_file}" "${_st_target_dir}"; then
    _t_pass "File is not stale right after apply"
  else
    _t_fail "File is not stale right after apply"
  fi

  # Change .sparks to make it stale
  echo "principal" >> "${_st_target_dir}/.sparks"
  if _sparks_is_stale "${_st_target_file}" "${_st_target_dir}"; then
    _t_pass "File is stale after .sparks change"
  else
    _t_fail "File is stale after .sparks change"
  fi

  _t_teardown_sandbox

fi

# =============================================================================
# SECTION: adapters — Adapter dispatch
# =============================================================================

if _t_section "adapters" "Adapter file generation"; then

  _t_setup_sandbox

  # Source adapters
  source "${_T_DIR}/adapters/opencode.bash"
  source "${_T_DIR}/adapters/claude.bash"
  source "${_T_DIR}/adapters/copilot.bash"
  source "${_T_DIR}/adapters/gemini.bash"

  _st_target_dir="${_SPARKS_TEST_DIR}/projects/work/project-a"
  echo "sysadmin" > "${_st_target_dir}/.sparks"

  # -- Test: OpenCode adapter --
  _t_cmd "OpenCode adapter filename" "_sparks_adapter_opencode_file"
  _t_run "_sparks_adapter_opencode_file" || true
  if [[ "${_T_LAST_OUTPUT}" == "AGENTS.md" ]]; then
    _t_pass "OpenCode adapter targets AGENTS.md"
  else
    _t_fail "OpenCode adapter targets AGENTS.md" "got: ${_T_LAST_OUTPUT}"
  fi

  _sparks_adapter_opencode_apply "${_st_target_dir}"
  if [[ -f "${_st_target_dir}/AGENTS.md" ]]; then
    _t_pass "OpenCode adapter creates AGENTS.md"
  else
    _t_fail "OpenCode adapter creates AGENTS.md"
  fi

  # -- Test: Claude adapter (bootstrap — @AGENTS.md import) --
  _t_cmd "Claude adapter filename" "_sparks_adapter_claude_file"
  _t_run "_sparks_adapter_claude_file" || true
  if [[ "${_T_LAST_OUTPUT}" == "CLAUDE.md" ]]; then
    _t_pass "Claude adapter targets CLAUDE.md"
  else
    _t_fail "Claude adapter targets CLAUDE.md" "got: ${_T_LAST_OUTPUT}"
  fi

  # Apply: creates CLAUDE.md with @AGENTS.md
  _sparks_adapter_claude_apply "${_st_target_dir}"
  if [[ -f "${_st_target_dir}/CLAUDE.md" ]]; then
    _t_pass "Claude adapter creates CLAUDE.md"
  else
    _t_fail "Claude adapter creates CLAUDE.md"
  fi

  _st_claude_content=$(<"${_st_target_dir}/CLAUDE.md")
  if [[ "${_st_claude_content}" == *"@AGENTS.md"* ]]; then
    _t_pass "CLAUDE.md contains @AGENTS.md import"
  else
    _t_fail "CLAUDE.md contains @AGENTS.md import" "content: ${_st_claude_content}"
  fi

  if [[ "${_st_claude_content}" != *"sparks:begin"* ]]; then
    _t_pass "CLAUDE.md does NOT contain sparks sentinel (bootstrap adapter)"
  else
    _t_fail "CLAUDE.md does NOT contain sparks sentinel (bootstrap adapter)"
  fi

  # Apply is idempotent
  _sparks_adapter_claude_apply "${_st_target_dir}"
  _st_import_count=$(grep -c '^@AGENTS\.md' "${_st_target_dir}/CLAUDE.md")
  if (( _st_import_count == 1 )); then
    _t_pass "Claude adapter apply is idempotent (import not duplicated)"
  else
    _t_fail "Claude adapter apply is idempotent" "found ${_st_import_count} import lines"
  fi

  # Apply migrates old sentinel-based CLAUDE.md
  cat > "${_st_target_dir}/CLAUDE.md" <<'OLDCLAUDE'
<!-- sparks:begin -- managed by sparks, do not edit below this line -->
<!-- active: base -->
## Persona: base
Old sentinel content here.
<!-- sparks:end -->
OLDCLAUDE
  _sparks_adapter_claude_apply "${_st_target_dir}"
  _st_claude_content=$(<"${_st_target_dir}/CLAUDE.md")
  if [[ "${_st_claude_content}" == *"@AGENTS.md"* && \
        "${_st_claude_content}" != *"sparks:begin"* ]]; then
    _t_pass "Claude adapter migrates old sentinel to @AGENTS.md import"
  else
    _t_fail "Claude adapter migrates old sentinel" "content: ${_st_claude_content}"
  fi

  # _is_stale returns stale (0) when CLAUDE.md missing
  rm -f "${_st_target_dir}/CLAUDE.md"
  if _sparks_adapter_claude_is_stale "${_st_target_dir}"; then
    _t_pass "claude _is_stale returns stale when CLAUDE.md missing"
  else
    _t_fail "claude _is_stale returns stale when CLAUDE.md missing"
  fi

  # _is_stale returns current (1) when @AGENTS.md present
  _sparks_adapter_claude_apply "${_st_target_dir}"
  if ! _sparks_adapter_claude_is_stale "${_st_target_dir}"; then
    _t_pass "claude _is_stale returns current after apply"
  else
    _t_fail "claude _is_stale returns current after apply"
  fi

  # Remove strips @AGENTS.md line but preserves user content
  cat >> "${_st_target_dir}/CLAUDE.md" <<'EXTRA'

## Claude Code specifics

Use plan mode for billing changes.
EXTRA
  _sparks_adapter_claude_remove "${_st_target_dir}"
  if [[ -f "${_st_target_dir}/CLAUDE.md" ]]; then
    _st_claude_content=$(<"${_st_target_dir}/CLAUDE.md")
    if [[ "${_st_claude_content}" != *"@AGENTS.md"* && \
          "${_st_claude_content}" == *"Claude Code specifics"* ]]; then
      _t_pass "Claude adapter remove strips import, preserves user content"
    else
      _t_fail "Claude adapter remove strips import, preserves user content" \
        "content: ${_st_claude_content}"
    fi
  else
    _t_fail "Claude adapter remove preserves file with user content (should not delete)"
  fi

  # Remove deletes file if only import was present
  printf '@AGENTS.md\n' > "${_st_target_dir}/CLAUDE.md"
  _sparks_adapter_claude_remove "${_st_target_dir}"
  if [[ ! -f "${_st_target_dir}/CLAUDE.md" ]]; then
    _t_pass "Claude adapter remove deletes file when only import remains"
  else
    _t_fail "Claude adapter remove deletes file when only import remains"
  fi

  # -- Test: opencode, copilot, gemini produce identical sentinel content --
  # (Claude is now a bootstrap adapter — no sentinel — excluded from this check)
  _sparks_adapter_opencode_apply "${_st_target_dir}"
  _sparks_adapter_copilot_apply "${_st_target_dir}"
  _sparks_adapter_gemini_apply "${_st_target_dir}"

  _st_agents_sentinel=$(_sparks_read_sentinel "${_st_target_dir}/AGENTS.md")
  _st_gemini_sentinel=$(_sparks_read_sentinel "${_st_target_dir}/GEMINI.md")
  _st_copilot_sentinel=$(_sparks_read_sentinel \
    "${_st_target_dir}/.github/copilot-instructions.md")

  _st_a_no_ts=$(echo "${_st_agents_sentinel}" | grep -v '^<!-- generated:')
  _st_g_no_ts=$(echo "${_st_gemini_sentinel}" | grep -v '^<!-- generated:')
  _st_p_no_ts=$(echo "${_st_copilot_sentinel}" | grep -v '^<!-- generated:')

  if [[ "${_st_a_no_ts}" == "${_st_g_no_ts}" && \
        "${_st_g_no_ts}" == "${_st_p_no_ts}" ]]; then
    _t_pass "opencode, gemini, copilot adapters produce identical sentinel content"
  else
    _t_fail "opencode, gemini, copilot adapters produce identical sentinel content"
  fi

  # -- Test: opencode adapter remove --
  _sparks_adapter_opencode_remove "${_st_target_dir}"
  if [[ -f "${_st_target_dir}/AGENTS.md" ]]; then
    _st_agents_content=$(<"${_st_target_dir}/AGENTS.md")
  else
    _st_agents_content=""
  fi
  if [[ "${_st_agents_content}" != *"sparks:begin"* ]]; then
    _t_pass "OpenCode adapter remove cleans sentinel"
  else
    _t_fail "OpenCode adapter remove cleans sentinel"
  fi

  _t_teardown_sandbox

fi

# =============================================================================
# SECTION: inheritance — Directory hierarchy tests
# =============================================================================

if _t_section "inheritance" "Directory hierarchy inheritance"; then

  _t_setup_sandbox

  # Set up a 3-level hierarchy:
  #   ~/projects/.sparks              → sysadmin
  #   ~/projects/personal/.sparks     → homelab
  #   ~/projects/personal/homelab/    → (no .sparks — inherits both)
  echo "sysadmin" > "${_SPARKS_TEST_DIR}/projects/.sparks"
  echo "homelab" > "${_SPARKS_TEST_DIR}/projects/personal/.sparks"

  # -- Test: deep dir inherits from all ancestors --
  _t_cmd "3-level inheritance" "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/personal/homelab'"
  _t_run "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/personal/homelab'" || true
  expected=$'base\nsysadmin\nhomelab'
  if [[ "${_T_LAST_OUTPUT}" == "${expected}" ]]; then
    _t_pass "Deep dir inherits base + sysadmin + homelab"
  else
    _t_fail "Deep dir inherits base + sysadmin + homelab" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: subdir inherits parent's parents too --
  _t_cmd "Subdir of subdir" "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/personal/homelab/subdir'"
  _t_run "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/personal/homelab/subdir'" || true
  if [[ "${_T_LAST_OUTPUT}" == "${expected}" ]]; then
    _t_pass "Subdirectory inherits full chain"
  else
    _t_fail "Subdirectory inherits full chain" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: sibling dir at same level only gets parent --
  _t_cmd "Sibling isolation" "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/work/project-a'"
  _t_run "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/work/project-a'" || true
  expected=$'base\nsysadmin'
  if [[ "${_T_LAST_OUTPUT}" == "${expected}" ]]; then
    _t_pass "Work project only inherits sysadmin (not homelab)"
  else
    _t_fail "Work project only inherits sysadmin (not homelab)" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: child override with exclusion --
  printf '%s\n' "-sysadmin" "principal" > "${_SPARKS_TEST_DIR}/projects/personal/homelab/.sparks"
  _t_cmd "Child excludes parent persona" "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/personal/homelab'"
  _t_run "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/personal/homelab'" || true
  expected=$'base\nhomelab\nprincipal'
  if [[ "${_T_LAST_OUTPUT}" == "${expected}" ]]; then
    _t_pass "Child excludes sysadmin, adds principal"
  else
    _t_fail "Child excludes sysadmin, adds principal" "got: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: no duplicate personas --
  echo "sysadmin" > "${_SPARKS_TEST_DIR}/projects/personal/homelab/.sparks"
  _t_cmd "No duplicates when same persona in parent and child" \
    "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/personal/homelab'"
  _t_run "_sparks_resolve_personas '${_SPARKS_TEST_DIR}/projects/personal/homelab'" || true
  _st_sysadmin_count=$(echo "${_T_LAST_OUTPUT}" | grep -c "^sysadmin$")
  if (( _st_sysadmin_count == 1 )); then
    _t_pass "Sysadmin appears exactly once"
  else
    _t_fail "Sysadmin appears exactly once" "appeared ${_st_sysadmin_count} times"
  fi

  _t_teardown_sandbox

fi

# =============================================================================
# SECTION: commands — Command dispatcher (using real plugin)
# =============================================================================

if _t_section "commands" "Command dispatcher"; then

  _t_setup_sandbox

  # Source the full plugin (with stubs for missing Shellfire parts)
  _SPARKS_LOADED=""
  source "${_T_DIR}/sparks.bash"

  _st_test_project="${_SPARKS_TEST_DIR}/projects/work/project-a"

  # -- Test: sparks help --
  _t_assert_contains "sparks help shows usage" "sparks help 2>&1" "USAGE"
  _t_assert_contains "sparks version" "sparks version 2>&1" "sparks"

  # -- Test: sparks list --
  _t_assert_contains "sparks list shows personas" "sparks list 2>&1" "sysadmin"

  # -- Test: sparks list shows version numbers --
  _t_cmd "sparks list shows version numbers" "sparks list 2>&1"
  _t_run "sparks list 2>&1" || true
  if [[ "${_T_LAST_OUTPUT}" == *"v1."* ]]; then
    _t_pass "sparks list shows version numbers"
  else
    _t_fail "sparks list shows version numbers" "output: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: sparks on --
  _t_cmd "sparks on sysadmin" "cd '${_st_test_project}' && sparks on sysadmin"
  ( cd "${_st_test_project}" && sparks on sysadmin ) 2>&1 | _t_output
  if [[ -f "${_st_test_project}/.sparks" ]]; then
    _st_sparks_content=$(<"${_st_test_project}/.sparks")
    if [[ "${_st_sparks_content}" == *"sysadmin"* ]]; then
      _t_pass "sparks on creates .sparks with sysadmin"
    else
      _t_fail "sparks on creates .sparks with sysadmin" "content: ${_st_sparks_content}"
    fi
  else
    _t_fail "sparks on creates .sparks file"
  fi

  # -- Test: sparks on (add another) --
  ( cd "${_st_test_project}" && sparks on homelab ) 2>&1 | _t_output
  _st_sparks_content=$(<"${_st_test_project}/.sparks")
  if [[ "${_st_sparks_content}" == *"sysadmin"* && "${_st_sparks_content}" == *"homelab"* ]]; then
    _t_pass "sparks on adds to existing .sparks"
  else
    _t_fail "sparks on adds to existing .sparks" "content: ${_st_sparks_content}"
  fi

  # -- Test: sparks on (invalid persona) --
  _t_cmd "sparks on nonexistent" "cd '${_st_test_project}' && sparks on nonexistent"
  _t_run "cd '${_st_test_project}' && sparks on nonexistent" || true
  if (( _T_LAST_RC != 0 )); then
    _t_pass "sparks on rejects unknown persona"
  else
    _t_fail "sparks on rejects unknown persona"
  fi

  # -- Test: sparks apply --
  _t_cmd "sparks apply" "cd '${_st_test_project}' && sparks apply"
  ( cd "${_st_test_project}" && sparks apply ) 2>&1 | _t_output
  if [[ -f "${_st_test_project}/AGENTS.md" ]]; then
    _st_agents_content=$(<"${_st_test_project}/AGENTS.md")
    if [[ "${_st_agents_content}" == *"sparks:begin"* && \
          "${_st_agents_content}" == *"Persona: sysadmin"* ]]; then
      _t_pass "sparks apply generates AGENTS.md with sentinel"
    else
      _t_fail "sparks apply generates AGENTS.md with sentinel"
    fi
  else
    _t_fail "sparks apply creates AGENTS.md"
  fi

  # -- Test: sparks off (specific persona) --
  ( cd "${_st_test_project}" && sparks off homelab ) 2>&1 | _t_output
  _st_sparks_content=$(<"${_st_test_project}/.sparks")
  if [[ "${_st_sparks_content}" == *"sysadmin"* && "${_st_sparks_content}" != *"homelab"* ]]; then
    _t_pass "sparks off removes specific persona"
  else
    _t_fail "sparks off removes specific persona" "content: ${_st_sparks_content}"
  fi

  # -- Test: sparks off (clear all) --
  ( cd "${_st_test_project}" && sparks off ) 2>&1 | _t_output
  if [[ ! -f "${_st_test_project}/.sparks" ]]; then
    _t_pass "sparks off (no args) removes .sparks file"
  else
    _t_fail "sparks off (no args) removes .sparks file"
  fi

  # -- Test: sparks show --
  echo "sysadmin" > "${_st_test_project}/.sparks"
  _t_cmd "sparks show sysadmin" "cd '${_st_test_project}' && sparks show sysadmin"
  _t_run "cd '${_st_test_project}' && sparks show sysadmin" || true
  if [[ "${_T_LAST_OUTPUT}" == *"assisting a sysadmin"* ]]; then
    _t_pass "sparks show displays persona body"
  else
    _t_fail "sparks show displays persona body"
  fi

  # -- Test: sparks diff (stale) --
  echo "principal" >> "${_st_test_project}/.sparks"
  _t_cmd "sparks diff detects staleness" "cd '${_st_test_project}' && sparks diff"
  _t_run "cd '${_st_test_project}' && sparks diff" || true
  if [[ "${_T_LAST_OUTPUT}" == *"stale"* ]]; then
    _t_pass "sparks diff reports staleness"
  else
    _t_fail "sparks diff reports staleness"
  fi

  # -- Test: sparks diff exit code + multi-adapter output --
  # Re-apply so AGENTS.md is current (includes sysadmin + principal now)
  ( cd "${_st_test_project}" && sparks apply ) 2>&1 | _t_output

  # diff should be clean right after apply
  _t_cmd "sparks diff clean after apply" "cd '${_st_test_project}' && sparks diff"
  _t_run "cd '${_st_test_project}' && sparks diff" || true
  if (( _T_LAST_RC == 0 )); then
    _t_pass "sparks diff exits 0 when all files current"
  else
    _t_fail "sparks diff exits 0 when all files current" "rc=${_T_LAST_RC}, output: ${_T_LAST_OUTPUT}"
  fi

  # Make AGENTS.md stale by adding another persona
  echo "homelab" >> "${_st_test_project}/.sparks"
  _t_cmd "sparks diff exits 1 when stale" "cd '${_st_test_project}' && sparks diff"
  _t_run "cd '${_st_test_project}' && sparks diff" || true
  if (( _T_LAST_RC == 1 )); then
    _t_pass "sparks diff exits 1 when any file stale"
  else
    _t_fail "sparks diff exits 1 when any file stale" "rc=${_T_LAST_RC}"
  fi

  # Output should mention AGENTS.md
  if [[ "${_T_LAST_OUTPUT}" == *"AGENTS.md"* ]]; then
    _t_pass "sparks diff output names the stale file"
  else
    _t_fail "sparks diff output names the stale file" "output: ${_T_LAST_OUTPUT}"
  fi

  # Restore .sparks
  echo "sysadmin" > "${_st_test_project}/.sparks"

  # -- Test: sparks status shows "Context files:" section --
  ( cd "${_st_test_project}" && sparks apply ) 2>&1 | _t_output

  _t_cmd "sparks status shows Context files section" \
    "cd '${_st_test_project}' && sparks status 2>&1"
  _t_run "cd '${_st_test_project}' && sparks status 2>&1" || true
  if [[ "${_T_LAST_OUTPUT}" == *"Context files"* ]]; then
    _t_pass "sparks status shows Context files section"
  else
    _t_fail "sparks status shows Context files section" \
      "output: ${_T_LAST_OUTPUT}"
  fi

  # AGENTS.md should show as current
  if [[ "${_T_LAST_OUTPUT}" == *"AGENTS.md"* && \
        "${_T_LAST_OUTPUT}" == *"current"* ]]; then
    _t_pass "sparks status shows AGENTS.md as current"
  else
    _t_fail "sparks status shows AGENTS.md as current"
  fi

  # CLAUDE.md should show status
  if [[ "${_T_LAST_OUTPUT}" == *"CLAUDE.md"* ]]; then
    _t_pass "sparks status shows CLAUDE.md status"
  else
    _t_fail "sparks status shows CLAUDE.md status"
  fi

  # -- Test: unknown command --
  _t_cmd "Unknown command fails" "sparks nonexistent"
  _t_run "sparks nonexistent" || true
  if (( _T_LAST_RC != 0 )); then
    _t_pass "Unknown command returns non-zero"
  else
    _t_fail "Unknown command returns non-zero"
  fi

  _t_teardown_sandbox

fi

# =============================================================================
# SECTION: edit — sparks edit command and OpenCode integration
# =============================================================================

if _t_section "edit" "sparks edit command and OpenCode integration"; then

  _t_setup_sandbox

  # Source the full plugin (with stubs for missing Shellfire parts)
  _SPARKS_LOADED=""
  source "${_T_DIR}/sparks.bash"

  _st_test_project="${_SPARKS_TEST_DIR}/projects/work/project-a"

  # -- Set up fake OpenCode agent and command files --
  _st_opencode_dir="${_SPARKS_TEST_DIR}/opencode"
  mkdir -p "${_st_opencode_dir}/agents" "${_st_opencode_dir}/commands"

  # Create minimal agent file
  cat > "${_st_opencode_dir}/agents/sparks.md" <<'AGENT'
---
description: Sparks persona manager
mode: primary
---
You are the Sparks persona manager.
AGENT

  # Create minimal command file
  cat > "${_st_opencode_dir}/commands/sparks.md" <<'CMD'
---
description: Manage Sparks AI personas
agent: sparks
---
$ARGUMENTS
CMD

  # Override XDG so _sparks_session_info finds the test files
  export XDG_CONFIG_HOME="${_SPARKS_TEST_DIR}"

  # -- Test: sparks edit exits 0 --
  _t_cmd "sparks edit exits 0" "cd '${_st_test_project}' && sparks edit"
  _t_run "cd '${_st_test_project}' && sparks edit" || true
  if (( _T_LAST_RC == 0 )); then
    _t_pass "sparks edit exits 0"
  else
    _t_fail "sparks edit exits 0" "rc=${_T_LAST_RC}"
  fi

  # -- Test: edit output contains instructions --
  _t_cmd "edit shows OpenCode instructions" "sparks edit output"
  if [[ "${_T_LAST_OUTPUT}" == *"opencode"* || "${_T_LAST_OUTPUT}" == *"OpenCode"* || "${_T_LAST_OUTPUT}" == *"/sparks"* ]]; then
    _t_pass "edit output contains OpenCode instructions"
  else
    _t_fail "edit output contains OpenCode instructions" "output: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: edit output mentions agent launch steps --
  if [[ "${_T_LAST_OUTPUT}" == *"Launch"* || "${_T_LAST_OUTPUT}" == *"Tab"* || "${_T_LAST_OUTPUT}" == *"/sparks"* ]]; then
    _t_pass "edit output contains launch steps"
  else
    _t_fail "edit output contains launch steps" "output: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: edit in help text --
  _t_assert_contains "sparks help includes edit" "sparks help 2>&1" "edit"

  # -- Test: missing agent file warns --
  rm -f "${_st_opencode_dir}/agents/sparks.md"
  _t_run "cd '${_st_test_project}' && sparks edit" || true
  if [[ "${_T_LAST_OUTPUT}" == *"not found"* || "${_T_LAST_OUTPUT}" == *"Expected"* ]]; then
    _t_pass "edit warns when agent file missing"
  else
    _t_fail "edit warns when agent file missing" "output: ${_T_LAST_OUTPUT}"
  fi

  _t_teardown_sandbox

fi

# =============================================================================
# SECTION: integration — Full plugin load
# =============================================================================

if _t_section "integration" "Full plugin load and status"; then

  # Test that the plugin can be sourced without errors in a subshell
  # that mimics a Shellfire environment
  _t_cmd "Plugin sources cleanly" "bash -c '...source sparks.bash...'"

  (
    export XDG_CONFIG_HOME="${_REAL_HOME}/.config"
    export HOME="${_REAL_HOME}"

    # Minimal Shellfire stubs
    declare -gA __shellfire_status_state=()
    declare -gA __shellfire_status_detail=()
    declare -gA __shellfire_status_file=()
    declare -ga __shellfire_status_order=()

    # Source logging lib from framework (lib/ lives in ~/.local/share/shellfire/, not config layer)
    source "${_T_FRAMEWORK_DIR}/lib/colours.bash"
    source "${_T_FRAMEWORK_DIR}/lib/logging.bash"

    # Source the plugin
    _SPARKS_LOADED=""
    source "${_T_DIR}/sparks.bash"

    # Verify the sparks function exists
    declare -f sparks &>/dev/null || exit 1

    # Verify status was set
    [[ -n "${__shellfire_status_state[sparks]:-}" ]] || exit 2

    # Verify cd alias was set
    alias cd &>/dev/null || exit 3

    # Verify completion was registered
    complete -p sparks &>/dev/null || exit 4

    exit 0
  ) 2>/dev/null && _st_rc=0 || _st_rc=$?

  case "${_st_rc}" in
    0) _t_pass "Plugin loads cleanly and sets up all hooks" ;;
    1) _t_fail "Plugin loads cleanly" "sparks function not defined" ;;
    2) _t_fail "Plugin loads cleanly" "_status_set was not called" ;;
    3) _t_fail "Plugin loads cleanly" "cd alias not set" ;;
    4) _t_fail "Plugin loads cleanly" "completion not registered" ;;
    *) _t_fail "Plugin loads cleanly" "exit code ${_st_rc}" ;;
  esac

  # Test that syntax check passes on all files
  _t_assert_rc "All sparks files pass bash -n" \
    "for f in '${_T_DIR}'/sparks.bash '${_T_DIR}'/lib/*.bash '${_T_DIR}'/adapters/*.bash; do bash -n \"\$f\" || exit 1; done"

fi

# =============================================================================
# SECTION: doctor — System health checks
# =============================================================================

if _t_section "doctor" "sparks doctor health checks"; then

  _t_setup_sandbox

  _SPARKS_LOADED=""
  source "${_T_DIR}/sparks.bash"

  _st_test_project="${_SPARKS_TEST_DIR}/projects/work/project-a"
  echo "sysadmin" > "${_st_test_project}/.sparks"

  # -- Test: doctor command exists --
  if declare -f sparks &>/dev/null; then
    _t_pass "sparks function is defined"
  else
    _t_fail "sparks function is defined"
  fi

  # -- Test: doctor exits 0 on clean sandbox --
  ( cd "${_st_test_project}" && sparks apply ) 2>&1 | _t_output
  _t_cmd "sparks doctor exits 0 on clean config" \
    "cd '${_st_test_project}' && sparks doctor"
  _t_run "cd '${_st_test_project}' && sparks doctor" || true
  if (( _T_LAST_RC == 0 )); then
    _t_pass "sparks doctor exits 0 on clean system"
  else
    _t_fail "sparks doctor exits 0 on clean system" \
      "rc=${_T_LAST_RC} output: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: doctor output contains all check sections --
  if [[ "${_T_LAST_OUTPUT}" == *"Core configuration"* ]]; then
    _t_pass "doctor output has Core configuration section"
  else
    _t_fail "doctor output has Core configuration section"
  fi
  if [[ "${_T_LAST_OUTPUT}" == *"Persona store"* ]]; then
    _t_pass "doctor output has Persona store section"
  else
    _t_fail "doctor output has Persona store section"
  fi
  if [[ "${_T_LAST_OUTPUT}" == *"sparks files"* ]]; then
    _t_pass "doctor output has .sparks files section"
  else
    _t_fail "doctor output has .sparks files section"
  fi
  if [[ "${_T_LAST_OUTPUT}" == *"Output files"* ]]; then
    _t_pass "doctor output has Output files section"
  else
    _t_fail "doctor output has Output files section"
  fi

  # -- Test: missing personas dir flagged as error --
  mv "${_SPARKS_TEST_DIR}/config/sparks/personas" \
     "${_SPARKS_TEST_DIR}/config/sparks/personas.bak"
  _t_cmd "Missing personas dir is an error" \
    "cd '${_st_test_project}' && sparks doctor"
  _t_run "cd '${_st_test_project}' && sparks doctor" || true
  if (( _T_LAST_RC != 0 )); then
    _t_pass "sparks doctor exits non-zero when personas dir missing"
  else
    _t_fail "sparks doctor exits non-zero when personas dir missing"
  fi
  if [[ "${_T_LAST_OUTPUT}" == *"personas"* && \
        ( "${_T_LAST_OUTPUT}" == *"not found"* || \
          "${_T_LAST_OUTPUT}" == *"missing"* ) ]]; then
    _t_pass "doctor reports missing personas dir"
  else
    _t_fail "doctor reports missing personas dir" "output: ${_T_LAST_OUTPUT}"
  fi
  mv "${_SPARKS_TEST_DIR}/config/sparks/personas.bak" \
     "${_SPARKS_TEST_DIR}/config/sparks/personas"

  # -- Test: unknown persona in .sparks is an error --
  echo "nonexistent_persona" >> "${_st_test_project}/.sparks"
  _t_cmd "Unknown persona in .sparks is an error" \
    "cd '${_st_test_project}' && sparks doctor"
  _t_run "cd '${_st_test_project}' && sparks doctor" || true
  if (( _T_LAST_RC != 0 )); then
    _t_pass "sparks doctor exits non-zero for unknown persona in .sparks"
  else
    _t_fail "sparks doctor exits non-zero for unknown persona in .sparks"
  fi
  if [[ "${_T_LAST_OUTPUT}" == *"nonexistent_persona"* ]]; then
    _t_pass "doctor names the unknown persona"
  else
    _t_fail "doctor names the unknown persona" "output: ${_T_LAST_OUTPUT}"
  fi
  # Report includes fix command
  if [[ "${_T_LAST_OUTPUT}" == *"sparks new"* || \
        "${_T_LAST_OUTPUT}" == *"remove"* ]]; then
    _t_pass "doctor suggests fix for unknown persona"
  else
    _t_fail "doctor suggests fix for unknown persona"
  fi
  echo "sysadmin" > "${_st_test_project}/.sparks"
  ( cd "${_st_test_project}" && sparks apply ) 2>&1 | _t_output

  # -- Test: stale AGENTS.md flagged --
  echo "principal" >> "${_st_test_project}/.sparks"
  _t_cmd "Stale AGENTS.md is flagged" \
    "cd '${_st_test_project}' && sparks doctor"
  _t_run "cd '${_st_test_project}' && sparks doctor" || true
  if [[ "${_T_LAST_OUTPUT}" == *"stale"* || "${_T_LAST_OUTPUT}" == *"AGENTS.md"* ]]; then
    _t_pass "doctor reports stale AGENTS.md"
  else
    _t_fail "doctor reports stale AGENTS.md" "output: ${_T_LAST_OUTPUT}"
  fi
  if [[ "${_T_LAST_OUTPUT}" == *"sparks apply"* ]]; then
    _t_pass "doctor suggests sparks apply for stale file"
  else
    _t_fail "doctor suggests sparks apply for stale file"
  fi
  echo "sysadmin" > "${_st_test_project}/.sparks"
  ( cd "${_st_test_project}" && sparks apply ) 2>&1 | _t_output

  # -- Test: CLAUDE.md not set up flagged --
  rm -f "${_st_test_project}/CLAUDE.md"
  _t_cmd "Missing CLAUDE.md setup flagged" \
    "cd '${_st_test_project}' && sparks doctor"
  _t_run "cd '${_st_test_project}' && sparks doctor" || true
  if [[ "${_T_LAST_OUTPUT}" == *"CLAUDE.md"* && \
        ( "${_T_LAST_OUTPUT}" == *"not set up"* || \
          "${_T_LAST_OUTPUT}" == *"not yet created"* ) ]]; then
    _t_pass "doctor reports CLAUDE.md not set up"
  else
    _t_fail "doctor reports CLAUDE.md not set up" "output: ${_T_LAST_OUTPUT}"
  fi

  # -- Test: doctor fix applies sparks apply for safe issues --
  _t_cmd "sparks doctor fix resolves CLAUDE.md setup" \
    "cd '${_st_test_project}' && sparks doctor fix"
  ( cd "${_st_test_project}" && sparks doctor fix ) 2>&1 | _t_output
  if [[ -f "${_st_test_project}/CLAUDE.md" ]] && \
     grep -q '^@AGENTS\.md' "${_st_test_project}/CLAUDE.md"; then
    _t_pass "sparks doctor fix sets up CLAUDE.md"
  else
    _t_fail "sparks doctor fix sets up CLAUDE.md"
  fi

  _t_teardown_sandbox

fi

# =============================================================================
# SUMMARY
# =============================================================================

printf '\n'
printf '  %b──────────────────────────────────────────────────────%b\n' "${_T_DIM}" "${_T_RESET}"

if (( _T_FAILED == 0 )); then
  printf '  %b ✓ ALL TESTS PASSED %b' "${_T_PASS}" "${_T_RESET}"
else
  printf '  %b ✗ SOME TESTS FAILED %b' "${_T_FAIL}" "${_T_RESET}"
fi

printf '  %b%d total, %d passed, %d failed, %d skipped%b\n' \
  "${_T_DIM}" "${_T_TOTAL}" "${_T_PASSED}" "${_T_FAILED}" "${_T_SKIPPED}" "${_T_RESET}"
printf '\n'

exit $(( _T_FAILED > 0 ? 1 : 0 ))
