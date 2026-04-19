#!/usr/bin/env bash
# =============================================================================
# plugins/sparks/adapters/gemini.bash — GEMINI.md adapter
# =============================================================================

_sparks_adapter_gemini_file() {
  echo "GEMINI.md"
}

_sparks_adapter_gemini_apply() {
  local target_dir="${1:-$PWD}"
  local target_file="${target_dir}/GEMINI.md"
  _sparks_render_to_file "${target_file}" "${target_dir}"
}

_sparks_adapter_gemini_remove() {
  local target_dir="${1:-$PWD}"
  local target_file="${target_dir}/GEMINI.md"
  _sparks_remove_sentinel "${target_file}"
}
