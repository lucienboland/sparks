#!/usr/bin/env bash
# =============================================================================
# sparks.bash — Sparks: AI Persona Manager (standalone external module)
# =============================================================================
#
# What this module does:
#   Sparks manages AI persona context files (AGENTS.md, CLAUDE.md, etc.)
#   across project directories using a directory-inheritance model.
#   Personas are stored centrally in ~/.config/sparks/personas/ and
#   activated per-directory via .sparks files.
#
#   This is the main entry point, loaded as a Shellfire plugin.  It:
#     1. Sets up global variables and paths
#     2. Lazy-loads sub-modules on first use
#     3. Defines the `sparks` command (dispatcher)
#     4. Installs a cd hook for status banners
#     5. Reports status to the Shellfire startup banner
#
# Dependencies:
#   XDG_CONFIG_HOME           (from ~/.bash_profile)
#   _status_set, _log_*       (from shellfire lib/logging.bash)
#   _sc, _sr                  (from shellfire lib/logging.bash)
#
# Exports (environment variables):
#   SPARKS_CONFIG_DIR         Path to ~/.config/sparks
#   SPARKS_PERSONAS_DIR       Path to ~/.config/sparks/personas
#
# Exports (functions):
#   sparks                    Main command
#   sparks_cd                 cd wrapper (cd hook)
#
# =============================================================================

# Idempotent load guard
if [[ -z "${_SPARKS_LOADED:-}" || "${SPARKS_RELOAD:-}" == "1" ]]; then
  unset SPARKS_RELOAD
  _SPARKS_LOADED=1

  # =========================================================================
  # SECTION 1: GLOBALS & PATHS
  # =========================================================================

  SPARKS_VERSION="0.1.0"

  : "${SPARKS_CONFIG_DIR:=${XDG_CONFIG_HOME:-${HOME}/.config}/sparks}"
  : "${SPARKS_PERSONAS_DIR:=${SPARKS_CONFIG_DIR}/personas}"
  export SPARKS_CONFIG_DIR SPARKS_PERSONAS_DIR

  # Detect this file's own location using BASH_SOURCE[0].
  # This makes sparks fully self-contained: no dependency on shellfire's config
  # layer paths.  Works regardless of where the repo is installed.
  _SPARKS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _SPARKS_PLUGIN_DIR="${_SPARKS_HOME}/lib"
  _SPARKS_ADAPTERS_DIR="${_SPARKS_HOME}/adapters"

  # Source global config if it exists
  if [[ -f "${SPARKS_CONFIG_DIR}/sparks.conf" ]]; then
    # shellcheck disable=SC1091
    source "${SPARKS_CONFIG_DIR}/sparks.conf"
  fi

  # Defaults for config values

  # Active adapters: which AI context files sparks apply generates by default.
  # Valid values: opencode, claude, copilot, gemini
  # Override in sparks.conf: SPARKS_ACTIVE_ADAPTERS=(opencode claude copilot)
  # The check on element count handles: unset, empty array, or scalar "".
  if [[ "${#SPARKS_ACTIVE_ADAPTERS[@]}" -eq 0 ]]; then
    declare -ga SPARKS_ACTIVE_ADAPTERS=(opencode claude)
  fi

  # Backward compatibility: honour old single-string SPARKS_DEFAULT_ADAPTER
  # if it was set in sparks.conf but SPARKS_ACTIVE_ADAPTERS was not.
  # Detects this by checking if the array is still the two-element default.
  if [[ -n "${SPARKS_DEFAULT_ADAPTER:-}" && \
        "${#SPARKS_ACTIVE_ADAPTERS[@]}" -eq 2 && \
        "${SPARKS_ACTIVE_ADAPTERS[0]}" == "opencode" && \
        "${SPARKS_ACTIVE_ADAPTERS[1]}" == "claude" ]]; then
    SPARKS_ACTIVE_ADAPTERS=("${SPARKS_DEFAULT_ADAPTER}")
  fi

  : "${SPARKS_CD_BANNER:=true}"
  : "${SPARKS_STALE_HINT:=true}"
  : "${SPARKS_VERBOSE:=1}"
  : "${SPARKS_BASE_ENABLED:=true}"

  # Track loaded sub-modules
  declare -gA _sparks_modules_loaded=()

  # Track the last resolved persona set (for cd change detection)
  _sparks_last_persona_set=""

  # =========================================================================
  # SECTION 2: LAZY MODULE LOADING
  # =========================================================================

  _sparks_load_module() {
    local module="$1"
    if [[ -z "${_sparks_modules_loaded[${module}]+_}" ]]; then
      local module_file="${_SPARKS_PLUGIN_DIR}/${module}.bash"
      if [[ -f "${module_file}" ]]; then
        # shellcheck disable=SC1090
        source "${module_file}"
        _sparks_modules_loaded["${module}"]=1
      else
        _log_error "Sparks: module not found: ${module_file}"
        return 1
      fi
    fi
  }

  _sparks_load_adapter() {
    local adapter="$1"
    local adapter_file="${_SPARKS_ADAPTERS_DIR}/${adapter}.bash"
    if [[ -f "${adapter_file}" ]]; then
      # shellcheck disable=SC1090
      source "${adapter_file}"
    else
      _log_error "Sparks: adapter not found: ${adapter}"
      return 1
    fi
  }

  # Load core module eagerly (needed by cd hook and status)
  _sparks_load_module "core"

  # =========================================================================
  # SECTION 3: ADAPTER DISPATCH
  # =========================================================================

  # _sparks_run_adapters — Run apply or remove on selected adapters
  #
  # Usage:
  #   _sparks_run_adapters apply "/path/to/dir" [--all]
  #   _sparks_run_adapters remove "/path/to/dir" [--all]

  _sparks_run_adapters() {
    local action="$1"
    local target_dir="$2"
    local mode="${3:-}"

    local -a adapters_to_run=()

    if [[ "${mode}" == "--all" ]]; then
      adapters_to_run=(opencode claude copilot gemini)
    else
      adapters_to_run=("${SPARKS_ACTIVE_ADAPTERS[@]}")
    fi

    for adapter in "${adapters_to_run[@]}"; do
      _sparks_load_adapter "${adapter}" || continue
      local fn="_sparks_adapter_${adapter}_${action}"
      if declare -f "${fn}" &>/dev/null; then
        "${fn}" "${target_dir}"
        local target_file
        target_file=$("_sparks_adapter_${adapter}_file")
        if [[ "${action}" == "apply" ]]; then
          _log_ok "Sparks: ${target_file} updated"
        else
          _log_ok "Sparks: ${target_file} sentinel removed"
        fi
      fi
    done
  }

  # _sparks_adapter_check_stale — call adapter's _is_stale if it exists,
  # otherwise fall back to the standard sentinel comparison.
  # Returns 0 if stale / not set up, 1 if current.
  _sparks_adapter_check_stale() {
    local adapter="$1"
    local target_dir="$2"
    local resolve_dir="${3:-$target_dir}"

    local is_stale_fn="_sparks_adapter_${adapter}_is_stale"
    local file_fn="_sparks_adapter_${adapter}_file"

    if declare -f "${is_stale_fn}" &>/dev/null; then
      "${is_stale_fn}" "${target_dir}"
      return $?
    fi

    # Fallback: standard sentinel staleness check
    local filename
    filename=$("${file_fn}")
    local target_file="${target_dir}/${filename}"
    _sparks_is_stale "${target_file}" "${resolve_dir}"
  }

  # =========================================================================
  # SECTION 4: COMMAND DISPATCHER
  # =========================================================================

  sparks() {
    case "${1:-}" in

    # -- sparks (no args) / sparks status ----------------------------------
    "" | status)
      _sparks_load_module "render"
      _sparks_load_module "ui"
      _sparks_status
      ;;

    # -- sparks on <name> [name...] ----------------------------------------
    on)
      shift
      if (( $# == 0 )); then
        _log_error "Usage: sparks on <name> [name...]"
        return 1
      fi

      # Validate all persona names exist
      for name in "$@"; do
        if ! _sparks_persona_exists "${name}"; then
          _log_error "Persona not found: ${name}"
          _log_info "Available: $(_sparks_list_available | tr '\n' ' ')"
          return 1
        fi
      done

      # Read current .sparks file if it exists
      local -a current_personas=()
      if [[ -f "${PWD}/.sparks" ]]; then
        while IFS= read -r p; do
          [[ -n "${p}" && "${p}" != -* ]] && current_personas+=("${p}")
        done < <(_sparks_read_sparks_file "${PWD}/.sparks")
      fi

      # Add new personas (avoid duplicates)
      local -A existing=()
      for p in "${current_personas[@]}"; do
        existing["${p}"]=1
      done

      local -a final_list=("${current_personas[@]}")
      for name in "$@"; do
        if [[ -z "${existing[${name}]+_}" ]]; then
          final_list+=("${name}")
          _log_ok "Activated: ${name}"
        else
          _log_info "Already active: ${name}"
        fi
      done

      _sparks_write_sparks_file "${PWD}/.sparks" "${final_list[@]}"
      _log_info "Run ${_SPARKS_C_BOLD:-}sparks apply${_SPARKS_C_RESET:-} to update AI context files"
      ;;

    # -- sparks off [name...] ----------------------------------------------
    off)
      shift
      if (( $# == 0 )); then
        # Clear all
        if [[ -f "${PWD}/.sparks" ]]; then
          rm -f "${PWD}/.sparks"
          _log_ok "Cleared all personas in ${PWD}"
          _log_info "Run ${_SPARKS_C_BOLD:-}sparks apply${_SPARKS_C_RESET:-} to update AI context files"
        else
          _log_info "No .sparks file in current directory"
        fi
        return 0
      fi

      # Remove specific personas
      if [[ ! -f "${PWD}/.sparks" ]]; then
        _log_info "No .sparks file in current directory"
        return 0
      fi

      local -a current_personas=()
      while IFS= read -r p; do
        [[ -n "${p}" ]] && current_personas+=("${p}")
      done < <(_sparks_read_sparks_file "${PWD}/.sparks")

      local -A remove_set=()
      for name in "$@"; do
        remove_set["${name}"]=1
      done

      local -a remaining=()
      for p in "${current_personas[@]}"; do
        if [[ -z "${remove_set[${p}]+_}" ]]; then
          remaining+=("${p}")
        else
          _log_ok "Deactivated: ${p}"
        fi
      done

      if (( ${#remaining[@]} == 0 )); then
        rm -f "${PWD}/.sparks"
      else
        _sparks_write_sparks_file "${PWD}/.sparks" "${remaining[@]}"
      fi
      _log_info "Run ${_SPARKS_C_BOLD:-}sparks apply${_SPARKS_C_RESET:-} to update AI context files"
      ;;

    # -- sparks apply [--all] ----------------------------------------------
    apply)
      shift
      _sparks_load_module "render"
      _sparks_load_module "ui"

      local target_dir
      target_dir=$(_sparks_find_target_dir "${PWD}")
      local mode="${1:-}"

      _sparks_run_adapters "apply" "${target_dir}" "${mode}"

      # Update the cached persona set
      _sparks_last_persona_set=$(_sparks_resolve_personas "${PWD}" | tr '\n' '+')
      ;;

    # -- sparks menu -------------------------------------------------------
    menu)
      _sparks_load_module "render"
      _sparks_load_module "ui"

      local -a selected=()
      while IFS= read -r name; do
        [[ -n "${name}" ]] && selected+=("${name}")
      done < <(_sparks_menu "${PWD}")

      if (( ${#selected[@]} == 0 )); then
        _log_info "No changes"
        return 0
      fi

      # Write selected personas to .sparks
      _sparks_write_sparks_file "${PWD}/.sparks" "${selected[@]}"
      _log_ok "Updated .sparks: ${selected[*]}"
      _log_info "Run ${_SPARKS_C_BOLD:-}sparks apply${_SPARKS_C_RESET:-} to update AI context files"
      ;;

    # -- sparks list -------------------------------------------------------
    list | ls)
      _sparks_load_module "ui"
      printf '\n  %b\n  %sAvailable Personas%b\n\n' \
        "${_SPARKS_LOGO_LINE:-}" "${_SPARKS_C_BOLD:-}" "${_SPARKS_C_RESET:-}"

      local -a active=()
      while IFS= read -r name; do
        [[ -n "${name}" ]] && active+=("${name}")
      done < <(_sparks_resolve_personas "${PWD}")
      local -A active_set=()
      for name in "${active[@]}"; do
        active_set["${name}"]=1
      done

      while IFS= read -r name; do
        local desc
        desc=$(_sparks_read_persona_meta "${name}" "description" 2>/dev/null) || desc=""
        local version
        version=$(_sparks_read_persona_meta "${name}" "version" 2>/dev/null) \
          || version=""
        local version_str=""
        [[ -n "${version}" ]] && version_str="v${version}"
        if [[ -n "${active_set[${name}]+_}" ]]; then
          printf '    %b●%b  %-16s %b%-6s%b  %s\n' \
            "$(_sc 114)" "$(_sr)" "${name}" \
            "$(_sc 243)" "${version_str}" "$(_sr)" \
            "${desc}"
        else
          printf '    %b○%b  %-16s %b%-6s%b  %s\n' \
            "$(_sc 243)" "$(_sr)" "${name}" \
            "$(_sc 243)" "${version_str}" "$(_sr)" \
            "${desc}"
        fi
      done < <(_sparks_list_available)
      printf '\n'
      ;;

    # -- sparks show [name] ------------------------------------------------
    show)
      shift
      _sparks_load_module "render"
      if (( $# > 0 )); then
        for name in "$@"; do
          if _sparks_persona_exists "${name}"; then
            printf '## Persona: %s\n\n' "${name}"
            _sparks_read_persona_body "${name}"
            printf '\n'
          else
            _log_error "Persona not found: ${name}"
          fi
        done
      else
        _sparks_merge_content "${PWD}"
      fi
      ;;

    # -- sparks edit -------------------------------------------------------
    edit | ed)
      _sparks_load_module "render"
      _sparks_load_module "ui"
      _sparks_session_info
      ;;

    # -- sparks new <name> -------------------------------------------------
    new)
      shift
      local name="${1:-}"
      if [[ -z "${name}" ]]; then
        _log_error "Usage: sparks new <name>"
        return 1
      fi
      if _sparks_persona_exists "${name}"; then
        _log_error "Persona already exists: ${name}"
        _log_info "Edit directly: ${SPARKS_PERSONAS_DIR}/${name}.md"
        return 1
      fi
      local file="${SPARKS_PERSONAS_DIR}/${name}.md"
      cat > "${file}" <<TEMPLATE
---
name: ${name}
description: Describe this persona in one line
version: 1.0
tags: general
---

You are assisting someone in the role of: **${name}**.

## Preferences

-

## Style

-

## Domain knowledge

-
TEMPLATE
      local editor="${EDITOR:-vi}"
      "${editor}" "${file}"
      _log_ok "Created persona: ${name}"
      ;;

    # -- sparks diff [--all] -----------------------------------------------
    diff)
      shift
      _sparks_load_module "render"
      _sparks_load_module "ui"

      local target_dir
      target_dir=$(_sparks_find_target_dir "${PWD}")

      local mode="${1:-}"
      local -a adapters_to_check=()
      if [[ "${mode}" == "--all" ]]; then
        adapters_to_check=(opencode claude copilot gemini)
      else
        adapters_to_check=("${SPARKS_ACTIVE_ADAPTERS[@]}")
      fi

      local any_stale=0

      for adapter in "${adapters_to_check[@]}"; do
        _sparks_load_adapter "${adapter}" || continue

        local file_fn="_sparks_adapter_${adapter}_file"
        local filename
        filename=$("${file_fn}")
        local target_file="${target_dir}/${filename}"

        printf '\n  %b%s%b\n' "${_SPARKS_C_BOLD:-}" "${filename}" "${_SPARKS_C_RESET:-}"

        if _sparks_adapter_check_stale "${adapter}" "${target_dir}" "${PWD}"; then
          any_stale=1

          if [[ ! -f "${target_file}" ]]; then
            printf '    %b○%b  not yet created\n' \
              "${_SPARKS_C_GREY:-}" "${_SPARKS_C_RESET:-}"
            printf '    Fix: sparks apply\n'
          else
            # Bootstrap adapters have their own _is_stale fn (no sentinel diff to show)
            local is_stale_fn="_sparks_adapter_${adapter}_is_stale"
            if declare -f "${is_stale_fn}" &>/dev/null; then
              printf '    %b!%b  not set up correctly\n' \
                "${_SPARKS_C_YELLOW:-}" "${_SPARKS_C_RESET:-}"
              printf '    Fix: sparks apply\n'
            else
              printf '    %b!%b  stale — personas changed since last apply\n' \
                "${_SPARKS_C_YELLOW:-}" "${_SPARKS_C_RESET:-}"
              printf '    Fix: sparks apply\n'
              # Show the sentinel diff
              local current expected
              current=$(_sparks_read_sentinel "${target_file}") \
                || current="(no sentinel section)"
              expected=$(_sparks_merge_content "${PWD}")
              if command -v diff &>/dev/null; then
                printf '\n'
                diff --color=auto \
                  <(echo "${current}") \
                  <(echo "${expected}") || true
                printf '\n'
              fi
            fi
          fi
        else
          printf '    %b✔%b  current\n' \
            "${_SPARKS_C_GREEN:-}" "${_SPARKS_C_RESET:-}"
        fi
      done

      printf '\n'
      return $(( any_stale ))
      ;;

    # -- sparks doctor [fix] -----------------------------------------------
    doctor)
      shift
      _sparks_load_module "render"
      _sparks_load_module "ui"
      _sparks_load_module "doctor"
      _sparks_doctor "${1:-}"
      ;;

    # -- sparks sync push/pull ---------------------------------------------
    sync)
      shift
      _sparks_sync "$@"
      ;;

    # -- sparks help -------------------------------------------------------
    help | --help | -h)
      _sparks_load_module "ui"
      _sparks_show_help
      ;;

    # -- sparks version ----------------------------------------------------
    version | --version)
      echo "sparks ${SPARKS_VERSION}"
      ;;

    # -- unknown -----------------------------------------------------------
    *)
      _log_error "Unknown command: $1"
      _log_info "Run 'sparks help' for usage"
      return 1
      ;;
    esac
  }

  # =========================================================================
  # SECTION 5: CHEZMOI SYNC
  # =========================================================================

  _sparks_sync() {
    case "${1:-}" in
    status | "")
      if ! command -v chezmoi &>/dev/null; then
        _log_warn "chezmoi not installed"
        return 1
      fi
      _log_info "Sparks config dir: ${SPARKS_CONFIG_DIR}"
      if chezmoi managed 2>/dev/null | grep -q "sparks"; then
        _log_ok "Tracked by chezmoi"
        _log_info "Source: $(chezmoi source-path 2>/dev/null)"
      else
        _log_warn "Not tracked by chezmoi"
        _log_info "Run 'sparks sync init' to add"
      fi
      ;;

    init)
      if ! command -v chezmoi &>/dev/null; then
        _log_error "chezmoi not installed"
        return 1
      fi
      chezmoi add "${SPARKS_CONFIG_DIR}"
      _log_ok "Added ${SPARKS_CONFIG_DIR} to chezmoi"
      ;;

    push)
      if ! command -v chezmoi &>/dev/null; then
        _log_error "chezmoi not installed"
        return 1
      fi
      chezmoi re-add "${SPARKS_CONFIG_DIR}" 2>/dev/null || \
        chezmoi add "${SPARKS_CONFIG_DIR}"
      _log_ok "Updated chezmoi source state"

      local source_dir
      source_dir=$(chezmoi source-path 2>/dev/null)
      if [[ -n "${source_dir}" ]] && git -C "${source_dir}" remote -v &>/dev/null; then
        git -C "${source_dir}" add -A
        git -C "${source_dir}" commit -m "sparks: update personas and config" 2>/dev/null
        git -C "${source_dir}" push
        _log_ok "Pushed to remote"
      else
        _log_warn "No git remote configured for chezmoi source"
      fi
      ;;

    pull)
      if ! command -v chezmoi &>/dev/null; then
        _log_error "chezmoi not installed"
        return 1
      fi
      chezmoi git -- pull
      chezmoi apply
      _log_ok "Pulled and applied"
      ;;

    *)
      _log_error "Usage: sparks sync [status|init|push|pull]"
      return 1
      ;;
    esac
  }

  # =========================================================================
  # SECTION 6: CD HOOK
  # =========================================================================

  # Wrap cd to detect persona changes.
  # Only shows a status banner — does NOT auto-apply.
  sparks_cd() {
    builtin cd "$@" || return
    _sparks_cd_hook
  }

  _sparks_cd_hook() {
    # Bail early if banner is disabled
    [[ "${SPARKS_CD_BANNER}" == "true" ]] || return 0
    [[ -t 1 ]] || return 0  # Not a terminal

    # Resolve current persona set
    local current_set
    current_set=$(_sparks_resolve_personas "${PWD}" | tr '\n' '+')

    # Only show banner if the set changed
    if [[ "${current_set}" != "${_sparks_last_persona_set}" ]]; then
      _sparks_last_persona_set="${current_set}"

      # Only show if there are personas beyond just base
      if [[ "${current_set}" != "base+" ]]; then
        _sparks_load_module "render"
        _sparks_load_module "ui"
        _sparks_banner "${PWD}"
      fi
    fi
  }

  alias cd='sparks_cd'

  # =========================================================================
  # SECTION 7: TAB COMPLETION
  # =========================================================================

  _sparks_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Top-level commands
    local commands="on off apply menu list show edit new diff doctor sync help version status"

    case "${prev}" in
    sparks)
      COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
      ;;
    on | show)
      # Complete with available persona names
      local personas
      personas=$(_sparks_list_available 2>/dev/null | tr '\n' ' ')
      COMPREPLY=( $(compgen -W "${personas}" -- "${cur}") )
      ;;
    off)
      # Complete with active persona names (from .sparks in $PWD)
      if [[ -f "${PWD}/.sparks" ]]; then
        local active
        active=$(_sparks_read_sparks_file "${PWD}/.sparks" 2>/dev/null | grep -v '^-' | tr '\n' ' ')
        COMPREPLY=( $(compgen -W "${active}" -- "${cur}") )
      fi
      ;;
    sync)
      COMPREPLY=( $(compgen -W "status init push pull" -- "${cur}") )
      ;;
    doctor)
      COMPREPLY=( $(compgen -W "fix" -- "${cur}") )
      ;;
    apply)
      COMPREPLY=( $(compgen -W "--all" -- "${cur}") )
      ;;
    esac
  }

  complete -F _sparks_completion sparks

fi # ← end of _SPARKS_LOADED guard

# =============================================================================
# SECTION 8: STATUS REPORT (runs outside the load guard for Shellfire banner)
# =============================================================================

if command -v _status_set &>/dev/null; then
  # Resolve personas for current directory
  _sf_sparks_personas=()
  while IFS= read -r _sf_sparks_name; do
    [[ -n "${_sf_sparks_name}" ]] && _sf_sparks_personas+=("${_sf_sparks_name}")
  done < <(_sparks_resolve_personas "${PWD}" 2>/dev/null)

  _sf_sparks_total=$(_sparks_list_available 2>/dev/null | wc -l | tr -d ' ')
  _sf_sparks_active=${#_sf_sparks_personas[@]}

  # Build persona list for status detail
  _sf_sparks_detail="$(_sc 208)${_sf_sparks_active}$(_sr)/${_sf_sparks_total} personas"
  if (( _sf_sparks_active > 0 )); then
    _sf_sparks_names=""
    for _sf_sparks_name in "${_sf_sparks_personas[@]}"; do
      [[ -n "${_sf_sparks_names}" ]] && _sf_sparks_names+=" + "
      if [[ "${_sf_sparks_name}" == "base" ]]; then
        _sf_sparks_names+="$(_sc 243)base$(_sr)"
      else
        _sf_sparks_names+="$(_sc 114)${_sf_sparks_name}$(_sr)"
      fi
    done
    _sf_sparks_detail+=" · ${_sf_sparks_names}"
  fi

  _status_set "sparks" "ok" "${_sf_sparks_detail}"

  unset _sf_sparks_personas _sf_sparks_total _sf_sparks_active
  unset _sf_sparks_detail _sf_sparks_names _sf_sparks_name
fi
