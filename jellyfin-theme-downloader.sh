#!/bin/bash
# =============================================================================
# jellyfin-theme-downloader.sh
#
# Automatically downloads theme songs for every movie and TV show in your
# Jellyfin library. Places a theme.mp3 in each media folder, which Jellyfin
# picks up natively. All themes are volume-normalised to EBU R128.
#
# Requirements:
#   apt install ffmpeg -y
#   curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
#     -o /usr/local/bin/yt-dlp && chmod +x /usr/local/bin/yt-dlp
#
# Usage:
#   bash jellyfin-theme-downloader.sh
# =============================================================================

# ── Configure your media folders ─────────────────────────────────────────────
#
# Format: "path/to/folder:search label"
#
# The search label is appended to the title when searching YouTube.
# For example, "movie" produces: "Blade Runner 2049 movie theme song"
#                "tv show"     : "Severance tv show theme song"
#                "anime"       : "Frieren anime theme song"
#
# Add or remove entries to match your setup. The script processes all of them.
#
MEDIA_DIRS=(
  "/media/movies:movie"
  "/media/tv:tv show"
)
#
# ── Other settings ────────────────────────────────────────────────────────────
TRIM_SECONDS=90       # trim downloaded audio to this length (seconds)
TARGET_LUFS="-14"     # loudness target (EBU R128; -14 matches streaming platforms)
SEARCH_DELAY=1        # seconds to wait between YouTube searches (avoids rate limiting)
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# =============================================================================
# Dependency check
# =============================================================================
check_deps() {
  local missing=false
  if ! command -v yt-dlp &>/dev/null; then
    echo -e "${RED}Missing: yt-dlp${NC}"
    echo "  Install: curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && chmod +x /usr/local/bin/yt-dlp"
    missing=true
  fi
  if ! command -v ffmpeg &>/dev/null; then
    echo -e "${RED}Missing: ffmpeg${NC}"
    echo "  Install: apt install ffmpeg -y"
    missing=true
  fi
  if ! command -v python3 &>/dev/null; then
    echo -e "${RED}Missing: python3${NC}"
    echo "  Install: apt install python3 -y"
    missing=true
  fi
  $missing && exit 1
}

# =============================================================================
# Strip release/codec tags from folder name, return clean title
# =============================================================================
clean_title() {
  local raw="$1"
  local t
  t=$(echo "$raw" | tr '_' ' ' | sed 's/\.\([A-Za-z]\)/ \1/g')
  t=$(echo "$t" | sed 's/\[[^]]*\]//g')
  t=$(echo "$t" | sed -E 's/\([A-Z][a-z]+ [A-Z][a-z]+\)//g')
  t=$(echo "$t" | sed -E 's/\([^)]*[0-9][^)]*\)//g')
  t=$(echo "$t" | sed -E 's/\( *[a-z .]+ *\)//g')
  t=$(echo "$t" | sed -E 's/\( *\)//g')
  t=$(echo "$t" | sed -E 's/ S[0-9]{1,2}(-S[0-9]{1,2})?( |$)/ /g')
  t=$(echo "$t" | sed -E 's/\b[Ss]easons? [0-9][-and 0-9]*//g')
  t=$(echo "$t" | sed -E 's/\b[0-9]+ - [0-9]+\b//g')
  t=$(echo "$t" | sed -E 's/\b(2160p|1080p|720p|480p|4K|UHD|HDR|SDR|BluRay|BDRip|BRRip|WEB|WEBRip|WEB-DL|WEBDL|HDTV|DVDRip|x264|x265|HEVC|AVC|H\.?264|H\.?265|AAC|EAC3|DDP|DTS|FLAC|10bit|8bit|REPACK|PROPER|EXTENDED|THEATRICAL|UNRATED|MULTI|DUBBED|SUBBED|YTS|YIFY|RARBG|NTb|NTG|PSA|AMZN|DSNP|HMAX|ATVP|t3nzin|Lootera|Vyndros|moviesbyrizzo|WebRip|Complete|Extras|TV[- ]?series|Mixed|conv)\b//gI')
  t=$(echo "$t" | sed -E 's/\b[0-9]+[MGT]B\b//gI')
  t=$(echo "$t" | sed -E 's/\b[0-9]\.[0-9]\b//g')
  t=$(echo "$t" | sed -E ':loop; s/(^| )([0-9] ){2,}/\1/g; t loop')
  t=$(echo "$t" | sed 's/+//g')
  t=$(echo "$t" | sed 's/^[ ,;:.[-]*//;s/[ ,;:.\]-]*$//')
  t=$(echo "$t" | sed 's/ - $//;s/^- //')
  t=$(echo "$t" | tr -s ' ' | sed 's/^ //;s/ $//')
  echo "$t"
}

fmt_duration() {
  local secs="$1"
  if [[ "$secs" =~ ^[0-9]+$ ]] && [[ "$secs" -gt 0 ]]; then
    printf "%d:%02d" $((secs/60)) $((secs%60))
  else
    echo "?:??"
  fi
}

# =============================================================================
# Normalise a single theme.mp3 in place using ffmpeg loudnorm
# =============================================================================
normalize_file() {
  local theme_file="$1"
  local tmp="${theme_file%.mp3}.tmp.mp3"

  ffmpeg -nostdin -hide_banner \
    -i "$theme_file" \
    -af "loudnorm=I=${TARGET_LUFS}:TP=-1.5:LRA=11" \
    -ar 44100 \
    -b:a 192k \
    "$tmp" \
    -y -loglevel quiet 2>&1 | cat

  if [[ -f "$tmp" ]]; then
    mv "$tmp" "$theme_file"
    return 0
  else
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
}

# =============================================================================
# Phase 1: search YouTube for every folder missing a theme.mp3
# =============================================================================
declare -a FOLDER_PATHS
declare -a FOLDER_TITLES
declare -a FOLDER_TYPES
declare -a YT_TITLES
declare -a YT_DURATIONS

idx=0

search_folder() {
  local folder_path="$1"
  local search_label="$2"
  local folder_name title search_query json vid_title vid_dur

  folder_name=$(basename "$folder_path")

  [[ -f "$folder_path/theme.mp3" ]] && return

  title=$(clean_title "$folder_name")
  [[ -z "$title" ]] && return

  # Final query: "<title> <label> theme song"
  # e.g. "Blade Runner 2049 movie theme song"
  #      "Severance tv show theme song"
  search_query="${title} ${search_label} theme song"

  json=$(yt-dlp \
    --default-search "ytsearch1" \
    --no-playlist \
    --dump-json \
    --quiet \
    --no-warnings \
    "$search_query" 2>/dev/null | head -1)

  vid_title=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))" 2>/dev/null)
  vid_dur=$(echo "$json"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(int(d.get('duration') or 0))" 2>/dev/null)

  FOLDER_PATHS[$idx]="$folder_path"
  FOLDER_TITLES[$idx]="$title"
  FOLDER_TYPES[$idx]="$search_label"
  YT_TITLES[$idx]="${vid_title:-[no result]}"
  YT_DURATIONS[$idx]=$(fmt_duration "$vid_dur")

  ((idx++))
  printf "." >&2

  sleep "$SEARCH_DELAY"
}

# =============================================================================
# Main
# =============================================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║      Jellyfin Theme Song Downloader          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

check_deps

# Process each configured media directory
valid=false
for entry in "${MEDIA_DIRS[@]}"; do
  dir="${entry%%:*}"
  label="${entry##*:}"
  if [[ ! -d "$dir" ]]; then
    echo -e "${YELLOW}Warning: folder not found, skipping: $dir${NC}"
    continue
  fi
  valid=true
done
$valid || { echo -e "${RED}No valid media folders found. Check MEDIA_DIRS in the script.${NC}"; exit 1; }

echo -e "  Searching YouTube for all titles — this may take a few minutes..."
echo -e "  ${DIM}(${SEARCH_DELAY}s delay between searches to avoid rate limiting)${NC}"
echo ""

for entry in "${MEDIA_DIRS[@]}"; do
  dir="${entry%%:*}"
  label="${entry##*:}"
  [[ ! -d "$dir" ]] && continue
  while IFS= read -r -d '' folder; do
    search_folder "$folder" "$label"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
done

echo ""
echo ""

total=${#FOLDER_PATHS[@]}

if [[ $total -eq 0 ]]; then
  echo -e "  ${GREEN}Nothing to do — all folders already have theme.mp3${NC}"
  echo ""
  exit 0
fi

# =============================================================================
# Phase 2: print numbered results table
# =============================================================================
printf "${BOLD}%-4s  %-35s  %-50s  %s${NC}\n" "#" "YOUR TITLE" "YOUTUBE RESULT" "DUR"
printf '%0.s─' {1..100}; echo ""

for ((i=0; i<total; i++)); do
  num=$((i+1))
  yt="${YT_TITLES[$i]}"
  dur="${YT_DURATIONS[$i]}"

  flag=""
  if [[ "$dur" =~ ^([0-9]+): ]]; then
    [[ ${BASH_REMATCH[1]} -ge 10 ]] && flag=" ${RED}⚠ long${NC}"
  fi
  [[ "$yt" == "[no result]" ]] && flag=" ${YELLOW}⚠ no result${NC}"

  printf "${CYAN}%-4s${NC}  ${BOLD}%-35s${NC}  %-50s  ${DIM}%s${NC}%b\n" \
    "$num" \
    "${FOLDER_TITLES[$i]:0:35}" \
    "${yt:0:50}" \
    "$dur" \
    "$flag"
done

echo ""

# =============================================================================
# Phase 3: ask which to skip
# =============================================================================
echo -e "  ${RED}⚠ long${NC}      = probably a full score or documentary rather than a theme"
echo -e "  ${YELLOW}⚠ no result${NC} = nothing found on YouTube, will be skipped automatically"
echo ""
echo -e "  Enter ${BOLD}numbers to skip${NC}, space-separated (or press Enter to download all):"
echo -ne "  > "
read -r skip_input

declare -A SKIP_SET
for n in $skip_input; do
  if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= total )); then
    SKIP_SET[$((n-1))]=1
  fi
done

echo ""

# =============================================================================
# Phase 4: download + normalise
# =============================================================================
echo -e "${BOLD}── Downloading & Normalising ───────────────────────${NC}"
echo ""

ok=0; skipped=0; failed=0

for ((i=0; i<total; i++)); do
  title="${FOLDER_TITLES[$i]}"
  folder_path="${FOLDER_PATHS[$i]}"
  search_label="${FOLDER_TYPES[$i]}"
  theme_file="$folder_path/theme.mp3"
  tmp_file="$folder_path/.theme_tmp"
  search_query="${title} ${search_label} theme song"

  if [[ -n "${SKIP_SET[$i]}" ]]; then
    echo -e "  ${YELLOW}[SKIP]${NC}  $title"
    ((skipped++))
    continue
  fi

  if [[ "${YT_TITLES[$i]}" == "[no result]" ]]; then
    echo -e "  ${YELLOW}[SKIP]${NC}  $title — no result found"
    ((skipped++))
    continue
  fi

  # Try twice with duration filter (<10 min), then once without as fallback
  success=false
  for attempt in 1 2; do
    rm -f "${tmp_file}"* 2>/dev/null
    yt-dlp \
      --default-search "ytsearch5" \
      --match-filter "duration < 600" \
      --format "bestaudio/best" \
      --extract-audio \
      --audio-format mp3 \
      --audio-quality 0 \
      --postprocessor-args "ffmpeg:-t ${TRIM_SECONDS}" \
      --output "${tmp_file}.%(ext)s" \
      --no-playlist \
      --quiet \
      --no-warnings \
      "$search_query" 2>/dev/null
    [[ -f "${tmp_file}.mp3" ]] && { success=true; break; }
  done

  if ! $success; then
    rm -f "${tmp_file}"* 2>/dev/null
    yt-dlp \
      --default-search "ytsearch1" \
      --format "bestaudio/best" \
      --extract-audio \
      --audio-format mp3 \
      --audio-quality 0 \
      --postprocessor-args "ffmpeg:-t ${TRIM_SECONDS}" \
      --output "${tmp_file}.%(ext)s" \
      --no-playlist \
      --quiet \
      --no-warnings \
      "$search_query" 2>/dev/null
    [[ -f "${tmp_file}.mp3" ]] && success=true
  fi

  if ! $success; then
    rm -f "${tmp_file}"* 2>/dev/null
    echo -e "  ${RED}[FAIL]${NC}  $title"
    ((failed++))
    continue
  fi

  mv "${tmp_file}.mp3" "$theme_file"

  if normalize_file "$theme_file"; then
    echo -e "  ${GREEN}[OK]${NC}    $title"
    ((ok++))
  else
    echo -e "  ${YELLOW}[WARN]${NC}  $title — downloaded but normalisation failed"
    ((ok++))
  fi
done

echo ""
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Downloaded:${NC} $ok"
echo -e "  ${YELLOW}Skipped:${NC}    $skipped"
echo -e "  ${RED}Failed:${NC}     $failed"
echo ""
echo -e "  ${DIM}Re-run anytime — folders with an existing theme.mp3 are skipped.${NC}"
echo ""