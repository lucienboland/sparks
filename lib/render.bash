#!/usr/bin/env bash
# =============================================================================
# plugins/sparks/render.bash — Sentinel section management in config files
# =============================================================================
#
# What this module does:
#   Manages the sparks:begin/sparks:end sentinel sections inside AI tool
#   config files (AGENTS.md, CLAUDE.md, etc.).  The sentinel protocol
#   ensures Sparks only touches its own section, leaving user content and
#   AI-generated content intact.
#
# Dependencies:
#   _sparks_merge_content    (from plugins/sparks/core.bash)
#   _sparks_hash_content     (from plugins/sparks/core.bash)
#
# Exports (functions):
#   _sparks_render_to_file   Write/update the sentinel section in a file
#   _sparks_remove_sentinel  Remove the sentinel section from a file
#   _sparks_read_sentinel    Extract the current sentinel section content
#   _sparks_is_stale         Check if a file's sentinel section is out of date
#
# =============================================================================

# The sentinel markers — use simple ASCII-safe strings for pattern matching
_SPARKS_BEGIN='<!-- sparks:begin -->'
_SPARKS_END='<!-- sparks:end -->'

# Human-readable version of the begin marker (written to files)
_SPARKS_BEGIN_FULL='<!-- sparks:begin -- managed by sparks, do not edit below this line -->'

# ---------------------------------------------------------------------------
# _sparks_render_to_file — Write/update the sentinel section in a target file
#
# If the file doesn't exist, create it with just the sentinel section.
# If the file exists but has no sentinels, append the sentinel section.
# If the file has sentinels, replace only the content between them.
#
# Usage:
#   _sparks_render_to_file "/path/to/AGENTS.md" "/path/to/dir"
#
# Arguments:
#   $1 — target file path
#   $2 — directory to resolve personas for (default: directory of target file)
# ---------------------------------------------------------------------------

_sparks_render_to_file() {
  local target_file="$1"
  local resolve_dir="${2:-$(dirname "${target_file}")}"

  # Generate merged content
  local merged
  merged=$(_sparks_merge_content "${resolve_dir}")

  # Build the sentinel block as a temp file (avoids shell quoting issues)
  local tmpfile
  tmpfile=$(mktemp "${TMPDIR:-/tmp}/sparks-render.XXXXXX")
  {
    echo "${_SPARKS_BEGIN_FULL}"
    echo "${merged}"
    echo "${_SPARKS_END}"
  } > "${tmpfile}"

  if [[ ! -f "${target_file}" ]]; then
    # File doesn't exist — create with sentinel section only
    mv "${tmpfile}" "${target_file}"
    return 0
  fi

  # File exists — check for existing sentinels
  # Use anchored patterns to avoid matching instruction text that mentions the markers
  if grep -q '^<!-- sparks:begin' "${target_file}" 2>/dev/null && \
     grep -q '^<!-- sparks:end' "${target_file}" 2>/dev/null; then
    # Replace existing sentinel section using awk
    local outfile
    outfile=$(mktemp "${TMPDIR:-/tmp}/sparks-out.XXXXXX")

    awk -v sentinel_file="${tmpfile}" '
      /^<!-- sparks:begin/ { skip=1; system("cat " sentinel_file); next }
      /^<!-- sparks:end/   { skip=0; next }
      !skip                { print }
    ' "${target_file}" > "${outfile}"

    mv "${outfile}" "${target_file}"
  else
    # No sentinels found — append with a blank line separator
    {
      echo ""
      cat "${tmpfile}"
    } >> "${target_file}"
  fi

  rm -f "${tmpfile}"
}

# ---------------------------------------------------------------------------
# _sparks_remove_sentinel — Remove the sentinel section from a file
#
# Leaves the rest of the file intact.  If the file becomes empty or
# whitespace-only after removal, deletes the file.
#
# Usage:
#   _sparks_remove_sentinel "/path/to/AGENTS.md"
# ---------------------------------------------------------------------------

_sparks_remove_sentinel() {
  local target_file="$1"
  [[ -f "${target_file}" ]] || return 0

  if ! grep -q '^<!-- sparks:begin' "${target_file}" 2>/dev/null; then
    return 0  # No sentinel to remove
  fi

  local outfile
  outfile=$(mktemp "${TMPDIR:-/tmp}/sparks-out.XXXXXX")

  awk '
    /^<!-- sparks:begin/ { skip=1; next }
    /^<!-- sparks:end/   { skip=0; next }
    !skip                { print }
  ' "${target_file}" > "${outfile}"

  # Check if the result is empty/whitespace-only
  local trimmed
  trimmed=$(tr -d '[:space:]' < "${outfile}")

  if [[ -z "${trimmed}" ]]; then
    rm -f "${target_file}" "${outfile}"
  else
    mv "${outfile}" "${target_file}"
  fi
}

# ---------------------------------------------------------------------------
# _sparks_read_sentinel — Extract the current sentinel section content
#
# Usage:
#   local current
#   current=$(_sparks_read_sentinel "/path/to/AGENTS.md")
# ---------------------------------------------------------------------------

_sparks_read_sentinel() {
  local target_file="$1"
  [[ -f "${target_file}" ]] || return 1

  if ! grep -q '^<!-- sparks:begin' "${target_file}" 2>/dev/null; then
    return 1
  fi

  awk '
    /^<!-- sparks:begin/ { printing=1; next }
    /^<!-- sparks:end/   { printing=0; next }
    printing             { print }
  ' "${target_file}"
}

# ---------------------------------------------------------------------------
# _sparks_is_stale — Check if a file's sentinel section is out of date
#
# Compares the hash of what _sparks_merge_content would produce against
# what's currently between the sentinels.  Returns 0 if stale (needs
# regeneration), 1 if current.
#
# Usage:
#   if _sparks_is_stale "/path/to/AGENTS.md" "/path/to/dir"; then
#     echo "needs sparks apply"
#   fi
# ---------------------------------------------------------------------------

_sparks_is_stale() {
  local target_file="$1"
  local resolve_dir="${2:-$(dirname "${target_file}")}"

  # If the file doesn't exist or has no sentinel, it's stale
  local current
  current=$(_sparks_read_sentinel "${target_file}") || return 0

  # Generate what the content should be
  local expected
  expected=$(_sparks_merge_content "${resolve_dir}")

  # Strip the timestamp line before comparing (it changes every time)
  local current_no_ts expected_no_ts
  current_no_ts=$(echo "${current}" | grep -v '^<!-- generated:')
  expected_no_ts=$(echo "${expected}" | grep -v '^<!-- generated:')

  local hash_current hash_expected
  hash_current=$(_sparks_hash_content "${current_no_ts}")
  hash_expected=$(_sparks_hash_content "${expected_no_ts}")

  [[ "${hash_current}" != "${hash_expected}" ]]
}
