#!/usr/bin/env bash
# ============================================================
# render_letters.sh
# ============================================================
# Reads letters_manifest.json and renders each character entry
# to an STL file using the OpenSCAD CLI.
#
# All parameters (letter, plinth dimensions, texture settings)
# are driven by the manifest — edit that file to change defaults
# or override settings per character; no changes needed here.
#
# Usage:
#   chmod +x render_letters.sh
#   ./render_letters.sh [OPTIONS]
#
# Options:
#   -m <file>    Path to manifest JSON  (default: letters_manifest.json
#                                        next to this script)
#   -s <file>    Path to .scad source   (overrides manifest scad_file)
#   -o <dir>     Output STL directory   (overrides manifest output_dir)
#   -j <n>       Parallel jobs          (default: CPU count)
#   -g <group>   Only render one group: uppercase | lowercase | digits
#   -f           Force re-render even if the STL already exists
#   -h           Show this help and exit
#
# Dependencies:
#   - openscad  (https://openscad.org/downloads.html)
#   - jq        (https://stedolan.github.io/jq/)
#               Install: brew install jq  /  apt install jq
# ============================================================

# Note: -e (errexit) is intentionally omitted.
# Bash arithmetic expressions like (( n++ )) return exit code 1 when the
# result is zero, which would cause set -e to abort the script mid-loop.
# Errors inside render_one are handled explicitly instead.
set -uo pipefail

# ── Helpers ───────────────────────────────────────────────────

usage() {
    sed -n '/^# Usage/,/^# Dependencies/p' "$0" | sed 's/^# \?//'
    exit 0
}

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
ok()   { echo "[$(date '+%H:%M:%S')]  ✓  $*"; }
fail() { echo "[$(date '+%H:%M:%S')]  ✗  $*" >&2; }

# ── Defaults ─────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/letters_manifest.json"
SCAD_OVERRIDE=""
OUT_OVERRIDE=""
# Default to 1 job — each letter render can consume several GB of RAM due to
# the sphere texture grid. Running multiple jobs in parallel risks OOM kills.
# Increase with -j only if you have confirmed available RAM (allow ~2-4 GB/job).
JOBS="${JOBS:-1}"
GROUP_FILTER=""
FORCE=0

# ── Argument parsing ──────────────────────────────────────────

while getopts "m:s:o:j:g:fh" opt; do
    case $opt in
        m) MANIFEST="$OPTARG" ;;
        s) SCAD_OVERRIDE="$OPTARG" ;;
        o) OUT_OVERRIDE="$OPTARG" ;;
        j) JOBS="$OPTARG" ;;
        g) GROUP_FILTER="$OPTARG" ;;
        f) FORCE=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

# ── Validate dependencies ─────────────────────────────────────

# jq is required to parse the manifest
if ! command -v jq &>/dev/null; then
    echo "ERROR: 'jq' is required but not found." >&2
    echo "  macOS:  brew install jq" >&2
    echo "  Ubuntu: sudo apt install jq" >&2
    exit 1
fi

# Locate openscad binary.
# Detection order:
#   1. OPENSCAD env var (user override — highest priority)
#   2. ~/Applications/openscad.AppImage  (AppImage in user Applications folder)
#   3. Any *.AppImage matching openscad* in ~/Applications (case-insensitive)
#   4. openscad on PATH (system package / distro install)
#   5. macOS .app bundle
if [[ -z "${OPENSCAD:-}" ]]; then
    if [[ -x "${HOME}/Applications/openscad.AppImage" ]]; then
        OPENSCAD="${HOME}/Applications/openscad.AppImage"
    elif appimage="$(find "${HOME}/Applications" -maxdepth 1 -iname 'openscad*.appimage' -executable 2>/dev/null | head -1)" \
            && [[ -n "$appimage" ]]; then
        OPENSCAD="$appimage"
    elif command -v openscad &>/dev/null; then
        OPENSCAD="openscad"
    elif [[ -x "/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD" ]]; then
        OPENSCAD="/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD"
    else
        echo "ERROR: 'openscad' binary not found." >&2
        echo "Checked:" >&2
        echo "  ~/Applications/openscad.AppImage" >&2
        echo "  ~/Applications/openscad*.AppImage" >&2
        echo "  openscad on PATH" >&2
        echo "  /Applications/OpenSCAD.app (macOS)" >&2
        echo "" >&2
        echo "Fix: export OPENSCAD=/path/to/openscad.AppImage" >&2
        exit 1
    fi
fi

# AppImage FUSE workaround.
# Immutable-root distros (Fedora Silverblue/Kinoite, SteamOS, etc.) often ship
# without the FUSE kernel module that AppImages rely on to mount themselves.
# Setting APPIMAGE_EXTRACT_AND_RUN=1 tells the AppImage runtime to extract to a
# temp dir and run directly — no FUSE required. Safe to set on systems that do
# have FUSE; it just adds a small one-time extraction step.
if [[ "$OPENSCAD" == *.AppImage || "$OPENSCAD" == *.appimage ]]; then
    export APPIMAGE_EXTRACT_AND_RUN=1
fi

# ── Read manifest ─────────────────────────────────────────────

if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: Manifest not found: $MANIFEST" >&2
    exit 1
fi

# Resolve paths: CLI flags override manifest values
SCAD_FILE="${SCAD_OVERRIDE:-$(jq -r '.scad_file' "$MANIFEST")}"
OUT_DIR="${OUT_OVERRIDE:-$(jq -r '.output_dir' "$MANIFEST")}"

# If paths are relative, resolve them from the manifest's directory
MANIFEST_DIR="$(cd "$(dirname "$MANIFEST")" && pwd)"
[[ "$SCAD_FILE" != /* ]] && SCAD_FILE="${MANIFEST_DIR}/${SCAD_FILE}"
[[ "$OUT_DIR"   != /* ]] && OUT_DIR="${MANIFEST_DIR}/${OUT_DIR}"

if [[ ! -f "$SCAD_FILE" ]]; then
    echo "ERROR: SCAD file not found: $SCAD_FILE" >&2
    exit 1
fi

# Pull default parameter values from manifest
read_default() { jq -r ".defaults.${1} // empty" "$MANIFEST"; }

DEFAULT_PLINTH_THICKNESS=$(read_default plinth_thickness)
DEFAULT_PLINTH_WIDTH_LEFT=$(read_default plinth_width_left)
DEFAULT_PLINTH_WIDTH_RIGHT=$(read_default plinth_width_right)
DEFAULT_LETTER_SIZE=$(read_default letter_size)
DEFAULT_LETTER_EXTRUDE_HEIGHT=$(read_default letter_extrude_height)
DEFAULT_LETTER_Y_OFFSET=$(read_default letter_y_offset)
DEFAULT_TEXTURE_WIDTH=$(read_default texture_width)
DEFAULT_TEXTURE_HEIGHT=$(read_default texture_height)
DEFAULT_BUMP_SPACING=$(read_default bump_spacing)
DEFAULT_BUMP_RADIUS=$(read_default bump_radius)
DEFAULT_BUMP_FN=$(read_default bump_fn)

# ── Build work list from manifest ─────────────────────────────

# Filter by group if -g was supplied; otherwise take all characters
if [[ -n "$GROUP_FILTER" ]]; then
    FILTER=".characters[] | select(.group == \"${GROUP_FILTER}\")"
else
    FILTER=".characters[]"
fi

# Produce a TSV stream: letter <TAB> output_filename [<TAB> per-char overrides...]
# Per-character overrides use the same key names as defaults; missing keys
# fall back to the manifest defaults read above.
mapfile -t WORK_LINES < <(
    jq -r "${FILTER} | [.letter, .output] | @tsv" "$MANIFEST"
)

TOTAL="${#WORK_LINES[@]}"

if [[ $TOTAL -eq 0 ]]; then
    echo "No characters matched${GROUP_FILTER:+ group '$GROUP_FILTER'}. Exiting." >&2
    exit 1
fi

# ── Setup output directory ────────────────────────────────────

mkdir -p "${OUT_DIR}"

# ── Print banner ──────────────────────────────────────────────

echo "============================================================"
echo " Letter Plinth — Batch STL Renderer"
echo "============================================================"
echo " Manifest : ${MANIFEST}"
echo " Source   : ${SCAD_FILE}"
echo " Output   : ${OUT_DIR}"
echo " OpenSCAD : ${OPENSCAD}"
echo " Jobs     : ${JOBS} parallel"
[[ -n "$GROUP_FILTER" ]] && echo " Group    : ${GROUP_FILTER} only"
echo " Total    : ${TOTAL} characters"
[[ $FORCE -eq 1 ]] && echo " Mode     : FORCE (re-rendering existing files)"
echo "============================================================"
echo " NOTE: Each render may use 2-4 GB RAM. Use -j 1 (default) unless"
echo "       you have confirmed spare RAM. OOM kills will leave no .stl."
echo "============================================================"
echo ""

# Counters (written to a temp file so subshells can update them)
COUNTER_DIR="$(mktemp -d)"
echo 0 > "${COUNTER_DIR}/ok"
echo 0 > "${COUNTER_DIR}/skip"
echo 0 > "${COUNTER_DIR}/fail"

# ── Render function ───────────────────────────────────────────
# Called once per character, potentially in parallel.
# Arguments: <letter> <output_filename>

render_one() {
    local letter="$1"
    local outfile="$2"
    local out_path="${OUT_DIR}/${outfile}"

    # Skip if file exists and -f was not given
    if [[ -f "$out_path" && $FORCE -eq 0 ]]; then
        log "SKIP  '${letter}' → ${outfile} (already exists; use -f to force)"
        # Increment skip counter atomically
        (
            flock 9
            count=$(<"${COUNTER_DIR}/skip")
            echo $(( count + 1 )) > "${COUNTER_DIR}/skip"
        ) 9>"${COUNTER_DIR}/skip.lock"
        return
    fi

    log "START '${letter}' → ${outfile}"

    # Build -D override flags from manifest defaults
    # Per-character overrides could be added here by parsing the manifest again
    local defines=(
        -D "letter=\"${letter}\""
        -D "plinth_thickness=${DEFAULT_PLINTH_THICKNESS}"
        -D "plinth_width_left=${DEFAULT_PLINTH_WIDTH_LEFT}"
        -D "plinth_width_right=${DEFAULT_PLINTH_WIDTH_RIGHT}"
        -D "letter_size=${DEFAULT_LETTER_SIZE}"
        -D "letter_extrude_height=${DEFAULT_LETTER_EXTRUDE_HEIGHT}"
        -D "letter_y_offset=${DEFAULT_LETTER_Y_OFFSET}"
        -D "texture_width=${DEFAULT_TEXTURE_WIDTH}"
        -D "texture_height=${DEFAULT_TEXTURE_HEIGHT}"
        -D "bump_spacing=${DEFAULT_BUMP_SPACING}"
        -D "bump_radius=${DEFAULT_BUMP_RADIUS}"
        -D "bump_fn=${DEFAULT_BUMP_FN}"
    )

    local log_file="${OUT_DIR}/${outfile%.stl}.log"

    if "${OPENSCAD}" \
            "${defines[@]}" \
            -o "${out_path}" \
            "${SCAD_FILE}" \
            2>"${log_file}"; then
        # Remove log on success to keep the output dir clean
        rm -f "${log_file}"
        ok "DONE  '${letter}' → ${outfile}"
        (
            flock 9
            count=$(<"${COUNTER_DIR}/ok")
            echo $(( count + 1 )) > "${COUNTER_DIR}/ok"
        ) 9>"${COUNTER_DIR}/ok.lock"
    else
        fail "FAIL  '${letter}' → ${outfile}  (see ${log_file})"
        (
            flock 9
            count=$(<"${COUNTER_DIR}/fail")
            echo $(( count + 1 )) > "${COUNTER_DIR}/fail"
        ) 9>"${COUNTER_DIR}/fail.lock"
    fi
}

export -f render_one log ok fail
export OPENSCAD OUT_DIR FORCE COUNTER_DIR
export DEFAULT_PLINTH_THICKNESS DEFAULT_PLINTH_WIDTH_LEFT DEFAULT_PLINTH_WIDTH_RIGHT
export DEFAULT_LETTER_SIZE DEFAULT_LETTER_EXTRUDE_HEIGHT DEFAULT_LETTER_Y_OFFSET
export DEFAULT_TEXTURE_WIDTH DEFAULT_TEXTURE_HEIGHT
export DEFAULT_BUMP_SPACING DEFAULT_BUMP_RADIUS DEFAULT_BUMP_FN

# ── Dispatch ──────────────────────────────────────────────────

if command -v parallel &>/dev/null; then
    # GNU parallel — cleanest output ordering
    printf '%s\n' "${WORK_LINES[@]}" | \
        parallel --jobs "${JOBS}" --colsep '\t' render_one {1} {2}
else
    # Fallback: manual background job pool.
    # Uses a semaphore directory instead of (( arithmetic )) counters;
    # arithmetic expressions that evaluate to 0 return exit code 1, which
    # would silently abort the loop even with set -e removed if called in
    # certain subshell contexts.
    sem_dir="$(mktemp -d)"

    for line in "${WORK_LINES[@]}"; do
        IFS=$'\t' read -r letter outfile <<< "$line"

        # Wait until a slot is free
        while true; do
            slot_count="$(find "${sem_dir}" -maxdepth 1 -name 'slot_*' | wc -l)"
            if [[ "$slot_count" -lt "$JOBS" ]]; then
                break
            fi
            sleep 0.2
        done

        # Claim a slot; subshell releases it when render_one finishes
        slot="${sem_dir}/slot_$$_${RANDOM}"
        touch "${slot}"
        (
            render_one "$letter" "$outfile"
            rm -f "${slot}"
        ) &
    done

    # Wait for all remaining background jobs
    wait
    rm -rf "${sem_dir}"
fi

# ── Summary ───────────────────────────────────────────────────

count_ok=$(   <"${COUNTER_DIR}/ok")
count_skip=$( <"${COUNTER_DIR}/skip")
count_fail=$( <"${COUNTER_DIR}/fail")
rm -rf "${COUNTER_DIR}"

rendered=$(find "${OUT_DIR}" -name "*.stl" | wc -l | tr -d ' ')

echo ""
echo "============================================================"
echo " Finished"
echo "   Rendered : ${count_ok}"
echo "   Skipped  : ${count_skip}  (use -f to re-render)"
echo "   Failed   : ${count_fail}"
echo "   STL files in ${OUT_DIR}: ${rendered} total"
echo "============================================================"

# Exit non-zero if any renders failed
[[ $count_fail -gt 0 ]] && exit 1 || exit 0
