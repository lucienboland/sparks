#!/usr/bin/env bash
# =============================================================================
# plugins/sparks/core.bash — Persona resolution, merging, and inheritance
# =============================================================================
#
# What this module does:
#   Implements the directory walk-up inheritance model for Sparks personas.
#   Resolves which personas are active for a given directory by walking
#   upward from $PWD to $HOME collecting .sparks files, processing
#   exclusions (lines prefixed with -), and merging persona content.
#
# Dependencies:
#   SPARKS_CONFIG_DIR    (from plugins/sparks.bash)
#   SPARKS_PERSONAS_DIR  (from plugins/sparks.bash)
#
# Exports (functions):
#   _sparks_resolve_personas   Walk-up from a dir, return active persona names
#   _sparks_list_available     List all personas in the central store
#   _sparks_persona_exists     Check if a persona exists in the central store
#   _sparks_read_persona_body  Read the markdown body (after frontmatter) of a persona
#   _sparks_read_persona_meta  Read a frontmatter field from a persona file
#   _sparks_merge_content      Merge all active personas into a single markdown block
#   _sparks_inheritance_chain  Return the list of .sparks files in the walk-up chain
#   _sparks_hash_content       Compute a short hash of a string (for staleness check)
#
# =============================================================================

# ---------------------------------------------------------------------------
# _sparks_resolve_personas — Walk up from a directory, collect active personas
#
# Usage:
#   local personas
#   personas=$(_sparks_resolve_personas "/path/to/dir")
#   # Returns newline-separated persona names, base always first
#
# Walk-up logic:
#   Starting from the given directory (or $PWD), walk upward to $HOME.
#   At each level, if a .sparks file exists, read its entries.
#   Lines prefixed with - remove a persona from the set.
#   base is always prepended and cannot be excluded.
#
# The result is a unique, ordered list: base first, then personas in the
# order they were first encountered (deepest ancestor first, child last).
# ---------------------------------------------------------------------------

_sparks_resolve_personas() {
  local start_dir="${1:-$PWD}"
  local -a chain_files=()
  local -a result_personas=()
  local -A seen=()
  local -A excluded=()

  # Collect .sparks files from start_dir up to $HOME (inclusive)
  local dir="${start_dir}"
  while true; do
    if [[ -f "${dir}/.sparks" ]]; then
      chain_files+=("${dir}/.sparks")
    fi
    # Stop at $HOME
    [[ "${dir}" == "${HOME}" ]] && break
    # Move up
    local parent
    parent="$(dirname "${dir}")"
    # Safety: stop if we can't go higher
    [[ "${parent}" == "${dir}" ]] && break
    dir="${parent}"
  done

  # Process files in reverse order (root/ancestor first, child last)
  # so child .sparks can override/exclude ancestor personas
  local i
  for (( i = ${#chain_files[@]} - 1; i >= 0; i-- )); do
    local sparks_file="${chain_files[i]}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
      # Strip leading/trailing whitespace
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      # Skip empty lines and comments
      [[ -z "${line}" || "${line}" == \#* ]] && continue

      if [[ "${line}" == -* ]]; then
        # Exclusion: remove from result
        local exclude_name="${line#-}"
        exclude_name="${exclude_name#"${exclude_name%%[![:space:]]*}"}"
        excluded["${exclude_name}"]=1
      else
        # Addition: add if not already seen and not excluded
        if [[ -z "${seen[${line}]+_}" ]]; then
          seen["${line}"]=1
          result_personas+=("${line}")
        fi
        # If previously excluded, un-exclude (child can re-add)
        unset 'excluded[${line}]'
      fi
    done < "${sparks_file}"
  done

  # Apply exclusions
  local -a final=()
  for name in "${result_personas[@]}"; do
    if [[ -z "${excluded[${name}]+_}" ]]; then
      final+=("${name}")
    fi
  done

  # Prepend base unless disabled globally or excluded via -base in a .sparks file
  if [[ "${SPARKS_BASE_ENABLED:-true}" == "true" && -z "${excluded[base]+_}" ]]; then
    local has_base=false
    for name in "${final[@]}"; do
      [[ "${name}" == "base" ]] && has_base=true
    done

    if [[ "${has_base}" == true ]]; then
      # Move base to front
      local -a ordered=("base")
      for name in "${final[@]}"; do
        [[ "${name}" != "base" ]] && ordered+=("${name}")
      done
      final=("${ordered[@]}")
    else
      final=("base" "${final[@]}")
    fi
  fi

  # Output
  printf '%s\n' "${final[@]}"
}

# ---------------------------------------------------------------------------
# _sparks_inheritance_chain — Return the .sparks files in the walk-up chain
#
# Usage:
#   _sparks_inheritance_chain "/path/to/dir"
#   # Returns newline-separated absolute paths, deepest first
# ---------------------------------------------------------------------------

_sparks_inheritance_chain() {
  local start_dir="${1:-$PWD}"
  local dir="${start_dir}"
  while true; do
    if [[ -f "${dir}/.sparks" ]]; then
      echo "${dir}/.sparks"
    fi
    [[ "${dir}" == "${HOME}" ]] && break
    local parent
    parent="$(dirname "${dir}")"
    [[ "${parent}" == "${dir}" ]] && break
    dir="${parent}"
  done
}

# ---------------------------------------------------------------------------
# _sparks_list_available — List all persona names in the central store
#
# Usage:
#   _sparks_list_available
#   # Returns newline-separated persona names (without .md extension)
# ---------------------------------------------------------------------------

_sparks_list_available() {
  local persona_file
  for persona_file in "${SPARKS_PERSONAS_DIR}"/*.md; do
    [[ -f "${persona_file}" ]] || continue
    local name="${persona_file##*/}"
    name="${name%.md}"
    echo "${name}"
  done
}

# ---------------------------------------------------------------------------
# _sparks_persona_exists — Check if a persona file exists
#
# Usage:
#   _sparks_persona_exists "sysadmin" && echo "yes"
# ---------------------------------------------------------------------------

_sparks_persona_exists() {
  [[ -f "${SPARKS_PERSONAS_DIR}/${1}.md" ]]
}

# ---------------------------------------------------------------------------
# _sparks_read_persona_body — Read the markdown body after YAML frontmatter
#
# Frontmatter is delimited by --- on its own line.  Everything after the
# closing --- is the body.  If there's no frontmatter, the whole file is body.
#
# Usage:
#   local body
#   body=$(_sparks_read_persona_body "sysadmin")
# ---------------------------------------------------------------------------

_sparks_read_persona_body() {
  local name="$1"
  local file="${SPARKS_PERSONAS_DIR}/${name}.md"
  [[ -f "${file}" ]] || return 1

  local in_frontmatter=false
  local frontmatter_closed=false
  local body=""
  local first_line=true

  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${first_line}" == true && "${line}" == "---" ]]; then
      in_frontmatter=true
      first_line=false
      continue
    fi
    first_line=false

    if [[ "${in_frontmatter}" == true ]]; then
      if [[ "${line}" == "---" ]]; then
        in_frontmatter=false
        frontmatter_closed=true
        continue
      fi
      continue
    fi

    # Skip leading blank lines after frontmatter
    if [[ "${frontmatter_closed}" == true && -z "${body}" && -z "${line}" ]]; then
      continue
    fi

    if [[ -n "${body}" ]]; then
      body+=$'\n'"${line}"
    else
      body="${line}"
    fi
  done < "${file}"

  echo "${body}"
}

# ---------------------------------------------------------------------------
# _sparks_read_persona_meta — Read a YAML frontmatter field value
#
# Simple line-based parser: looks for "key: value" in frontmatter.
# Does not handle multi-line YAML values or arrays.
#
# Usage:
#   local desc
#   desc=$(_sparks_read_persona_meta "sysadmin" "description")
# ---------------------------------------------------------------------------

_sparks_read_persona_meta() {
  local name="$1"
  local field="$2"
  local file="${SPARKS_PERSONAS_DIR}/${name}.md"
  [[ -f "${file}" ]] || return 1

  local in_frontmatter=false
  local first_line=true

  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${first_line}" == true && "${line}" == "---" ]]; then
      in_frontmatter=true
      first_line=false
      continue
    fi
    first_line=false

    if [[ "${in_frontmatter}" == true ]]; then
      [[ "${line}" == "---" ]] && return 1  # field not found
      # Match "field: value"
      if [[ "${line}" == "${field}:"* ]]; then
        local value="${line#"${field}:"}"
        # Trim leading whitespace
        value="${value#"${value%%[![:space:]]*}"}"
        echo "${value}"
        return 0
      fi
    fi
  done < "${file}"

  return 1
}

# ---------------------------------------------------------------------------
# _sparks_merge_content — Merge active personas into a single markdown block
#
# Usage:
#   local content
#   content=$(_sparks_merge_content "/path/to/dir")
#
# Returns the merged markdown that goes between sentinel markers.
# Includes a header comment listing active personas and their sources.
# ---------------------------------------------------------------------------

_sparks_merge_content() {
  local dir="${1:-$PWD}"
  local -a persona_names=()
  local content=""

  # Read persona names into array
  while IFS= read -r name; do
    [[ -n "${name}" ]] && persona_names+=("${name}")
  done < <(_sparks_resolve_personas "${dir}")

  # Build header comment
  local active_list=""
  for name in "${persona_names[@]}"; do
    [[ -n "${active_list}" ]] && active_list+=", "
    active_list+="${name}"
  done

  content="<!-- active: ${active_list} -->"
  content+=$'\n'"<!-- generated: $(date -u +%Y-%m-%dT%H:%M:%SZ) -->"
  content+=$'\n'

  # Persona management instructions for AI tools
  content+=$'\n'"## Sparks persona management"
  content+=$'\n'
  content+=$'\n'"Personas are managed by Sparks. Central store: ~/.config/sparks/personas/"
  content+=$'\n'"To update a persona from this session:"
  content+=$'\n'"1. Edit ~/.config/sparks/personas/<name>.md directly"
  content+=$'\n'"2. Run \`sparks apply\` in the terminal to regenerate this section"
  content+=$'\n'"Do NOT edit content between the sparks sentinel markers manually."
  content+=$'\n'

  # Merge each persona body
  for name in "${persona_names[@]}"; do
    if ! _sparks_persona_exists "${name}"; then
      content+=$'\n'"<!-- WARNING: persona '${name}' not found in central store -->"
      continue
    fi

    local desc
    desc=$(_sparks_read_persona_meta "${name}" "description") || desc=""

    local body
    body=$(_sparks_read_persona_body "${name}") || body=""

    content+=$'\n'"## Persona: ${name}"
    local persona_version
    persona_version=$(_sparks_read_persona_meta "${name}" "version" 2>/dev/null) \
      || persona_version=""
    if [[ -n "${persona_version}" ]]; then
      content+=$'\n'"<!-- persona-version: ${persona_version} -->"
    fi
    [[ -n "${desc}" ]] && content+=$'\n'"<!-- ${desc} -->"
    content+=$'\n'
    if [[ -n "${body}" ]]; then
      content+=$'\n'"${body}"
    fi
    content+=$'\n'
  done

  echo "${content}"
}

# ---------------------------------------------------------------------------
# _sparks_hash_content — Compute a short hash of a string
#
# Used for staleness detection: hash the merged content and compare with
# what's currently in the sentinel section.
#
# Usage:
#   local hash
#   hash=$(_sparks_hash_content "some string")
# ---------------------------------------------------------------------------

_sparks_hash_content() {
  local input="$1"
  if command -v md5sum &>/dev/null; then
    echo -n "${input}" | md5sum | cut -c1-8
  elif command -v md5 &>/dev/null; then
    echo -n "${input}" | md5 -q | cut -c1-8
  else
    echo -n "${input}" | cksum | cut -d' ' -f1
  fi
}

# ---------------------------------------------------------------------------
# _sparks_read_sparks_file — Read persona names from a .sparks file
#
# Usage:
#   local -a names
#   mapfile -t names < <(_sparks_read_sparks_file "/path/.sparks")
# ---------------------------------------------------------------------------

_sparks_read_sparks_file() {
  local file="$1"
  [[ -f "${file}" ]] || return 1

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    echo "${line}"
  done < "${file}"
}

# ---------------------------------------------------------------------------
# _sparks_write_sparks_file — Write persona names to a .sparks file
#
# Usage:
#   _sparks_write_sparks_file "/path/.sparks" "sysadmin" "homelab"
# ---------------------------------------------------------------------------

_sparks_write_sparks_file() {
  local file="$1"
  shift
  local -a names=("$@")

  {
    echo "# Sparks active personas"
    echo "# Managed by: sparks on/off"
    echo "#"
    for name in "${names[@]}"; do
      echo "${name}"
    done
  } > "${file}"
}
