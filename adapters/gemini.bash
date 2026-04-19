#!/usr/bin/env bash
# =============================================================================
# adapters/gemini.bash — Gemini CLI adapter
#
# Gemini CLI integration — two approaches:
#
# RECOMMENDED — settings.json (for users who also use OpenCode):
#   Configure ~/.gemini/settings.json so Gemini picks up AGENTS.md (written
#   by the opencode adapter) natively in every project. No per-project
#   GEMINI.md needed; always in sync without running sparks apply.
#
#   Add to ~/.gemini/settings.json:
#     {
#       "context": {
#         "fileName": ["AGENTS.md", "GEMINI.md"]
#       }
#     }
#
#   See INSTALL.md § "Gemini CLI" for the full one-time setup steps.
#
# FALLBACK — direct sentinel (Gemini-only projects, no AGENTS.md):
#   Add "gemini" to SPARKS_ACTIVE_ADAPTERS in ~/.config/sparks/sparks.conf:
#     SPARKS_ACTIVE_ADAPTERS=(opencode claude gemini)
#
#   Then run:  sparks apply
#   This writes persona content directly into GEMINI.md via the sentinel
#   protocol. Run sparks doctor to check for staleness.
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
