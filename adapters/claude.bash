#!/usr/bin/env bash
# =============================================================================
# plugins/sparks/adapters/claude.bash — CLAUDE.md bootstrap adapter
# =============================================================================
#
# What this adapter does:
#   Ensures CLAUDE.md contains an @AGENTS.md import as its first line.
#   This is a bootstrap adapter — it does NOT use the sentinel protocol.
#   Once set up, CLAUDE.md picks up persona changes automatically via the
#   import whenever AGENTS.md is updated by the opencode adapter.
#
#   On first apply, any existing sparks sentinel in CLAUDE.md is removed
#   (migration from the old approach that duplicated sentinel content).
#
#   Content the user writes below the @AGENTS.md line is never touched.
#
# Adapter contract:
#   _sparks_adapter_claude_file      → "CLAUDE.md"
#   _sparks_adapter_claude_apply     → idempotently write @AGENTS.md import
#   _sparks_adapter_claude_remove    → remove @AGENTS.md line; delete if empty
#   _sparks_adapter_claude_is_stale  → 0=stale (missing/no import), 1=current
#
# =============================================================================

_sparks_adapter_claude_file() {
  echo "CLAUDE.md"
}

_sparks_adapter_claude_apply() {
  local target_dir="${1:-$PWD}"
  local target_file="${target_dir}/CLAUDE.md"

  # Step 1: remove any existing sparks sentinel (migration from old approach).
  # _sparks_remove_sentinel is safe to call on a file with no sentinel.
  if [[ -f "${target_file}" ]]; then
    _sparks_remove_sentinel "${target_file}"
  fi

  # Step 2: idempotent — if @AGENTS.md already present anywhere, no-op.
  if [[ -f "${target_file}" ]] && grep -q '^@AGENTS\.md' "${target_file}"; then
    return 0
  fi

  # Step 3: prepend @AGENTS.md import, preserving any existing content below.
  local tmpfile
  tmpfile=$(mktemp)
  printf '@AGENTS.md\n\n' > "${tmpfile}"
  if [[ -f "${target_file}" && -s "${target_file}" ]]; then
    cat "${target_file}" >> "${tmpfile}"
  fi
  mv "${tmpfile}" "${target_file}"
}

_sparks_adapter_claude_remove() {
  local target_dir="${1:-$PWD}"
  local target_file="${target_dir}/CLAUDE.md"
  [[ -f "${target_file}" ]] || return 0

  # Remove the @AGENTS.md import line and any immediately-following blank line.
  local tmpfile
  tmpfile=$(mktemp)
  # Strip @AGENTS.md line; also strip a single blank line immediately after it.
  awk '
    /^@AGENTS\.md$/ { skip_blank=1; next }
    skip_blank && /^[[:space:]]*$/ { skip_blank=0; next }
    { skip_blank=0; print }
  ' "${target_file}" > "${tmpfile}"

  # If file is now empty or whitespace-only, delete it entirely.
  if [[ -z "$(tr -d '[:space:]' < "${tmpfile}")" ]]; then
    rm -f "${target_file}" "${tmpfile}"
  else
    mv "${tmpfile}" "${target_file}"
  fi
}

_sparks_adapter_claude_is_stale() {
  # Returns 0 (stale/needs action) if CLAUDE.md is missing or lacks @AGENTS.md.
  # Returns 1 (current) if @AGENTS.md import is present.
  local target_dir="${1:-$PWD}"
  local target_file="${target_dir}/CLAUDE.md"
  [[ ! -f "${target_file}" ]] && return 0
  grep -q '^@AGENTS\.md' "${target_file}" && return 1 || return 0
}
