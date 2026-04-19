#!/usr/bin/env bash
# =============================================================================
# plugins/sparks/adapters/opencode.bash — AGENTS.md adapter
# =============================================================================
#
# Manages the sentinel section in AGENTS.md for OpenCode.
# This is the primary adapter (OpenCode-first design).
#
# Exports (functions):
#   _sparks_adapter_opencode_apply   Write sentinel section to AGENTS.md
#   _sparks_adapter_opencode_remove  Remove sentinel section from AGENTS.md
#   _sparks_adapter_opencode_file    Return the target filename
#
# =============================================================================

_sparks_adapter_opencode_file() {
  echo "AGENTS.md"
}

_sparks_adapter_opencode_apply() {
  local target_dir="${1:-$PWD}"
  local target_file="${target_dir}/AGENTS.md"
  _sparks_render_to_file "${target_file}" "${target_dir}"
}

_sparks_adapter_opencode_remove() {
  local target_dir="${1:-$PWD}"
  local target_file="${target_dir}/AGENTS.md"
  _sparks_remove_sentinel "${target_file}"
}
