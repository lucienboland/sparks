#!/usr/bin/env bash
# =============================================================================
# plugins/sparks/adapters/copilot.bash — .github/copilot-instructions.md adapter
# =============================================================================

_sparks_adapter_copilot_file() {
  echo ".github/copilot-instructions.md"
}

_sparks_adapter_copilot_apply() {
  local target_dir="${1:-$PWD}"
  local target_file="${target_dir}/.github/copilot-instructions.md"
  mkdir -p "${target_dir}/.github"
  _sparks_render_to_file "${target_file}" "${target_dir}"
}

_sparks_adapter_copilot_remove() {
  local target_dir="${1:-$PWD}"
  local target_file="${target_dir}/.github/copilot-instructions.md"
  _sparks_remove_sentinel "${target_file}"
}
