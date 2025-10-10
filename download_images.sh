#!/bin/bash
#
# ACF Image Downloader - Improved Version
#
# Key features:
# - URL or HTML file input support
# - Intelligent WordPress size suffix removal (-150x150, -scaled, etc.)
# - Chronological per-run logs stored in ~/Downloads/acf-images/logs
# - Smart filename generation preserving meaningful content and order
# - Optional AVIF conversion via ffmpeg or ImageMagick
# - Automatic ImageOptim CLI integration
# - Summary counts with success/failure indicators
# - Automatic archival of processed HTML inputs
#
# Usage:
#   ./download_images.sh                              # Process HTML file in directory
#   ./download_images.sh https://example.com/page     # Fetch and process URL
#   DEBUG=1 ./download_images.sh                      # Debug mode with verbose output

# Define directories
INPUT_DIR="$HOME/Downloads/acf-images"
OUTPUT_BASE="$HOME/Downloads/acf-images/output"
LOG_DIR="$HOME/Downloads/acf-images/logs"
PROCESSED_DIR="$HOME/Downloads/acf-images/processed"
FETCHED_HTML_DIR="$LOG_DIR/fetched-html"

# Cookie file support (optional, user-provided)
# User can manually export cookies from browser extension and place here
COOKIE_FILE="${ACF_COOKIE_FILE:-$INPUT_DIR/cookies.txt}"

# Create required directories
mkdir -p "$OUTPUT_BASE" "$LOG_DIR" "$PROCESSED_DIR" "$FETCHED_HTML_DIR"

# Helper to append to the current log file when available
log_line() {
  if [ -n "${LOG_FILE:-}" ] && [ -f "$LOG_FILE" ]; then
    echo "$1" >> "$LOG_FILE"
  fi
}

# Function to print to terminal
print() {
  echo "$1"
  log_line "$1"
}

# Function for verbose logging (only when DEBUG=1)
debug() {
  if [ "${DEBUG:-0}" = "1" ]; then
    echo "[DEBUG] $1" >&2
    log_line "[DEBUG] $1"
  fi
}

# Check for required tools
debug "Checking for required tools..."
for tool in grep sed wget; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    print "Error: Required tool '$tool' not found."
    exit 1
  fi
done
if ! command -v ffmpeg > /dev/null 2>&1 && ! command -v magick > /dev/null 2>&1; then
  print "Warning: Neither ffmpeg nor magick found. AVIF conversion will be skipped."
fi

# Check input directory
debug "Checking input directory: $INPUT_DIR"
if [ ! -d "$INPUT_DIR" ]; then
  print "Error: Input directory $INPUT_DIR does not exist."
  exit 1
fi

# Function to generate slug from URL
url_to_slug() {
  local url="$1"

  # Remove protocol (http://, https://)
  url=$(echo "$url" | sed -E 's|^https?://||')

  # Strip query parameters and fragments
  url=$(echo "$url" | sed 's/[?#].*$//')

  # Remove trailing slash
  url=$(echo "$url" | sed 's|/$||')

  echo "$url"
}

# Function to resolve relative URLs to absolute URLs
resolve_url() {
  local url="$1"
  local base_url="$2"

  # Already absolute URL
  if [[ "$url" =~ ^https?:// ]]; then
    echo "$url"
    return
  fi

  # Relative URL starting with /
  if [[ "$url" =~ ^/ ]]; then
    echo "${base_url}${url}"
    return
  fi

  # Relative URL without leading / (treat as path relative)
  echo "${base_url}/${url}"
}

# Determine input source: URL argument or HTML file
HTML_FILE=""
SLUG=""
FETCHED_FROM_URL=false
BASE_URL=""

if [ $# -ge 1 ] && [[ "$1" =~ ^https?:// ]]; then
  # URL provided as argument
  INPUT_URL="$1"

  # Extract base URL (protocol + domain) for relative path resolution
  BASE_URL=$(echo "$INPUT_URL" | sed -E 's|(https?://[^/]+).*|\1|')

  print "Fetching URL: $INPUT_URL"

  # Check if user provided a cookie file
  WGET_COOKIES=""
  if [ -f "$COOKIE_FILE" ]; then
    WGET_COOKIES="--load-cookies $COOKIE_FILE"
    print "  ✓ Using cookie file for authentication"
    debug "Cookie file: $COOKIE_FILE"
  else
    debug "No cookie file found. For authenticated sites, export cookies to: $COOKIE_FILE"
  fi

  SLUG=$(url_to_slug "$INPUT_URL")
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  HTML_FILE="$FETCHED_HTML_DIR/fetched-${TIMESTAMP}-${SLUG}.html"

  debug "Downloading HTML from URL..."
  if ! wget --timeout=30 --tries=3 -q -O "$HTML_FILE" $WGET_COOKIES --user-agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" "$INPUT_URL" 2>/dev/null; then
    print "Error: Failed to fetch URL: $INPUT_URL"
    rm -f "$HTML_FILE"
    exit 1
  fi

  if [ ! -s "$HTML_FILE" ]; then
    print "Error: Fetched HTML file is empty."
    rm -f "$HTML_FILE"
    exit 1
  fi

  print "  ✓ HTML fetched successfully"
  FETCHED_FROM_URL=true
else
  # Look for HTML file in directory
  HTML_FILES=("$INPUT_DIR"/*.html)
  if [ ${#HTML_FILES[@]} -eq 0 ] || [ ! -f "${HTML_FILES[0]}" ]; then
    print "Error: No HTML files found in $INPUT_DIR."
    print ""
    print "Usage:"
    print "  1. Place an HTML file in $INPUT_DIR, or"
    print "  2. Provide a URL as argument: getimage https://example.com/page"
    exit 1
  fi

  HTML_FILE="${HTML_FILES[0]}"
  SLUG=$(basename "$HTML_FILE" .html | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
fi

if [ -z "$SLUG" ]; then
  print "Error: Could not derive slug from input."
  exit 1
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/${TIMESTAMP}_${SLUG}.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

print "Processing $HTML_FILE..."
debug "Processing file: $HTML_FILE"

# Set up output directory
BASE_DIR="$OUTPUT_BASE/$SLUG"
mkdir -p "$BASE_DIR"
debug "Slug: $SLUG"
debug "Base Directory: $BASE_DIR"

SUCCESS_COUNT=0
FAIL_COUNT=0

# Function to intelligently remove WordPress size suffixes
get_original_filename() {
  local filename="$1"
  local basename="${filename%.*}"
  local extension="${filename##*.}"
  local clean_basename="$basename"
  local wp_modified=0

  # Remove WordPress dimension suffixes (e.g., -150x150, -300x200, -1024x768, -2048x1536)
  # This handles dimensions at the end, optionally followed by a duplicate number (e.g., -150x150-2)
  if echo "$clean_basename" | grep -qE '\-[0-9]+x[0-9]+(-[0-9]+)?$'; then
    local original_basename="$clean_basename"

    # Check for duplicate index (e.g., -150x150-2) - preserve the duplicate number
    if echo "$clean_basename" | grep -qE '\-[0-9]+x[0-9]+-[0-9]+$'; then
      local dup_suffix=$(echo "$clean_basename" | sed -E 's/^.*-[0-9]+x[0-9]+-([0-9]+)$/\1/')
      clean_basename=$(echo "$clean_basename" | sed -E 's/-[0-9]+x[0-9]+-[0-9]+$/-'"$dup_suffix"'/')
    else
      # Just remove the dimension suffix
      clean_basename=$(echo "$clean_basename" | sed -E 's/-[0-9]+x[0-9]+$//')
    fi

    if [ "$clean_basename" != "$original_basename" ]; then
      wp_modified=1
      local removed_suffix=$(echo "$original_basename" | sed -E 's/^.*(-[0-9]+x[0-9]+(-[0-9]+)?)$/\1/')
      debug "Removed WordPress dimension suffix: $removed_suffix"
    fi
  fi

  # Remove trailing WordPress size keywords (thumbnail, medium, scaled, etc.)
  if echo "$clean_basename" | grep -qE '\-(thumbnail|medium(_large)?|large|full|scaled|rotated)$'; then
    clean_basename=$(echo "$clean_basename" | sed -E 's/-(thumbnail|medium(_large)?|large|full|scaled|rotated)$//')
    wp_modified=1
    debug "Removed WordPress size keyword"
  fi

  echo "${clean_basename}.${extension}"
}

# Convert arbitrary text into a lowercase slug separated by hyphens
slugify() {
  local input="$1"
  if [ -z "$input" ]; then
    echo ""
    return
  fi
  input=$(echo "$input" | tr '[:upper:]' '[:lower:]')
  input=$(echo "$input" | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//; s/-$//')
  echo "$input"
}

# Function to generate intelligent filename based on context
generate_filename() {
  local original_name="$1"
  local section="$2"
  local index="$3"
  local use_custom_name="$4"
  local label="$5"
  
  local extension="${original_name##*.}"
  local base_name="${original_name%.*}"
  local section_slug=""
  if [ -n "$section" ] && [ "$section" != "unknown" ]; then
    section_slug=$(slugify "$section")
    section_slug=$(echo "$section_slug" | sed 's/-image$//')
  fi

  # Prioritize original filename over alt text for better ordering
  local label_slug=$(slugify "$base_name")

  # Only use alt text if base_name doesn't provide meaningful content
  if [ -z "$label_slug" ] && [ -n "$label" ]; then
    label_slug=$(slugify "$label")
  fi

  local filename="$index"

  if [ -n "$section_slug" ]; then
    filename="${filename}-${section_slug}"
  fi

  if [ -n "$label_slug" ] && [ "$label_slug" != "$section_slug" ]; then
    filename="${filename}-${label_slug}"
  fi

  echo "${filename}.${extension}"
}

# Function to download and process images
download_image() {
  local url=$1
  local dir=$2
  local index=$3
  local label="$4"
  local filename_with_query=$(basename "$url")
  local filename="${filename_with_query%%\?*}"
  local query_string=""
  if [[ "$filename_with_query" == *\?* ]]; then
    query_string="?${filename_with_query#*\?}"
  fi

  local normalized_filename=$(get_original_filename "$filename")
  local normalized_url="$url"
  local attempted_fullsize=false

  if [ "$normalized_filename" != "$filename" ]; then
    local base_path="${url%/*}"
    normalized_url="${base_path}/${normalized_filename}${query_string}"
    attempted_fullsize=true
    debug "Attempting full-size version: $normalized_url"
  else
    debug "No size suffix detected, using original: $url"
  fi

  local naming_source="$normalized_filename"
  if [ "$normalized_filename" = "$filename" ]; then
    naming_source="$filename"
  fi

  local output_filename=$(generate_filename "$naming_source" "unknown" "$index" "false" "$label")
  local output_path="$dir/$output_filename"
  mkdir -p "$dir"

  if [ -f "$output_path" ]; then
    print "  $output_filename: skipped (already exists)"
    return
  fi

  # Use cookies if available (for authenticated image downloads)
  local img_cookies=""
  if [ -f "$COOKIE_FILE" ]; then
    img_cookies="--load-cookies $COOKIE_FILE"
  fi

  # Attempt download with normalized filename first when applicable
  if [ "$attempted_fullsize" = true ]; then
    if wget --timeout=10 --tries=2 -q -O "$output_path" $img_cookies "$normalized_url" 2>/dev/null; then
      print "  $output_filename: ✓"
      convert_avif_if_needed "$output_path"
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      return
    else
      debug "Full-size failed: $normalized_url"
      rm -f "$output_path"
      debug "Falling back to original URL: $url"
    fi
  fi

  if wget --timeout=10 --tries=2 -q -O "$output_path" $img_cookies "$url" 2>/dev/null; then
    local suffix_note=""
    if [ "$attempted_fullsize" = true ]; then
      suffix_note=" (fallback to original file)"
    fi
    print "  $output_filename: ✓$suffix_note"
    convert_avif_if_needed "$output_path"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    debug "Original download failed: $url"
    rm -f "$output_path"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    if [ "$attempted_fullsize" = true ]; then
      print "  $output_filename: ✗ Failed (full-size inaccessible; fallback failed)"
    else
      print "  $output_filename: ✗ Failed (original inaccessible)"
    fi
  fi
}

# Function to convert AVIF files to PNG
convert_avif_if_needed() {
  local filepath="$1"
  if file "$filepath" | grep -q "AVIF"; then
    debug "Converting AVIF: $filepath"
    local new_path="${filepath%.*}.png"
    if command -v ffmpeg > /dev/null 2>&1; then
      ffmpeg -i "$filepath" -pix_fmt rgba "$new_path" -y 2>/dev/null && rm "$filepath"
    elif command -v magick > /dev/null 2>&1; then
      magick "$filepath" "$new_path" 2>/dev/null && rm "$filepath"
    else
      debug "Warning: No ffmpeg/magick. Left as AVIF."
    fi
  fi
}

# Function to download and process images with custom naming for ACF fields
download_image_custom() {
  local url=$1
  local dir=$2
  local prefix=$3
  local index=$4
  local label="$5"
  local filename_with_query=$(basename "$url")
  local filename="${filename_with_query%%\?*}"
  local query_string=""
  if [[ "$filename_with_query" == *\?* ]]; then
    query_string="?${filename_with_query#*\?}"
  fi

  local normalized_filename=$(get_original_filename "$filename")
  local normalized_url="$url"
  local attempted_fullsize=false

  if [ "$normalized_filename" != "$filename" ]; then
    local base_path="${url%/*}"
    normalized_url="${base_path}/${normalized_filename}${query_string}"
    attempted_fullsize=true
    debug "Attempting full-size version: $normalized_url"
  else
    debug "No size suffix detected, using original: $url"
  fi

  # Generate intelligent custom filename
  local naming_source="$normalized_filename"
  if [ "$normalized_filename" = "$filename" ]; then
    naming_source="$filename"
  fi

  local output_filename=$(generate_filename "$naming_source" "$prefix-image" "$index" "true" "$label")
  local output_path="$dir/$output_filename"
  
  mkdir -p "$dir"

  if [ -f "$output_path" ]; then
    print "  $output_filename: skipped (already exists)"
    return
  fi

  # Use cookies if available (for authenticated image downloads)
  local img_cookies=""
  if [ -f "$COOKIE_FILE" ]; then
    img_cookies="--load-cookies $COOKIE_FILE"
  fi

  if [ "$attempted_fullsize" = true ]; then
    if wget --timeout=10 --tries=2 -q -O "$output_path" $img_cookies "$normalized_url" 2>/dev/null; then
      print "  $output_filename: ✓"
      convert_avif_if_needed "$output_path"
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      return
    else
      debug "Full-size failed: $normalized_url"
      rm -f "$output_path"
      debug "Falling back to original URL: $url"
    fi
  fi

  if wget --timeout=10 --tries=2 -q -O "$output_path" $img_cookies "$url" 2>/dev/null; then
    local suffix_note=""
    if [ "$attempted_fullsize" = true ]; then
      suffix_note=" (fallback to original file)"
    fi
    print "  $output_filename: ✓$suffix_note"
    convert_avif_if_needed "$output_path"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    debug "Original download failed: $url"
    rm -f "$output_path"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    if [ "$attempted_fullsize" = true ]; then
      print "  $output_filename: ✗ Failed (full-size inaccessible; fallback failed)"
    else
      print "  $output_filename: ✗ Failed (original inaccessible)"
    fi
  fi
}

# Extract all lines with data-name or image URLs, preserving order
TEMP_FILE=$(mktemp)
debug "Extracting lines with data-name or image URLs from $HTML_FILE"
grep -n -i 'data-name="\|src="[^"]*\.\(png\|jpg\|jpeg\|gif\|svg\|webp\|avif\|bmp\)"' "$HTML_FILE" > "$TEMP_FILE"

if [ ! -s "$TEMP_FILE" ]; then
  print "Error: No images found in $HTML_FILE"
  rm "$TEMP_FILE"
  exit 1
fi

IMAGE_COUNT=$(grep -i 'src="[^"]*\.\(png\|jpg\|jpeg\|gif\|svg\|webp\|avif\|bmp\)"' "$TEMP_FILE" | grep -v 'acf-icon' | wc -l)
print "Found $IMAGE_COUNT images."
print "Log file: $LOG_FILE"

# Track current section and indices
CURRENT_SECTION="unknown"
PREV_DIR=""
GLOBAL_INDEX=0

# Process the extracted lines
while IFS= read -r line; do
  LINE_NUM=$(echo "$line" | cut -d: -f1)
  CONTENT=$(echo "$line" | cut -d: -f2-)
  
  if echo "$CONTENT" | grep -q 'data-name="'; then
    SECTION_NAME=$(echo "$CONTENT" | sed 's/.*data-name="\([^"]*\)".*/\1/')
    # Only update section if it's a meaningful ACF field name (ends with _image or contains image)
    if [ "$SECTION_NAME" != "image" ] && echo "$SECTION_NAME" | grep -q -E "(image|_image)$" && ! echo "$SECTION_NAME" | grep -q -E "^(edit|remove|add)$"; then
      CURRENT_SECTION=$(echo "$SECTION_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g')
      debug "Set current section to: $CURRENT_SECTION"
    fi
  elif echo "$CONTENT" | grep -q -i 'src="[^"]*\.\(png\|jpg\|jpeg\|gif\|svg\|webp\|avif\|bmp\)"'; then
    if ! echo "$CONTENT" | grep -q 'acf-icon'; then
      IMAGE_URL=$(echo "$CONTENT" | sed 's/.*src="\([^"]*\)".*/\1/')
      if [ -z "$IMAGE_URL" ]; then
        debug "Warning: Empty image URL at line $LINE_NUM, skipping."
        continue
      fi

      # Resolve relative URLs to absolute URLs when fetched from web
      if [ "$FETCHED_FROM_URL" = true ] && [ -n "$BASE_URL" ]; then
        IMAGE_URL=$(resolve_url "$IMAGE_URL" "$BASE_URL")
        debug "Resolved URL: $IMAGE_URL"
      fi

      ALT_TEXT=$(echo "$CONTENT" | sed -n 's/.*alt="\([^"]*\)".*/\1/p')
      if [ -z "$ALT_TEXT" ]; then
        for offset in 1 2 3; do
          ALT_TEXT=$(sed -n "$((LINE_NUM + offset))p" "$HTML_FILE" | sed -n 's/.*alt="\([^"]*\)".*/\1/p')
          if [ -n "$ALT_TEXT" ]; then
            break
          fi
        done
      fi
      INDEX=$GLOBAL_INDEX
      GLOBAL_INDEX=$((GLOBAL_INDEX + 1))

      # Determine filename and directory structure
      if [ "$CURRENT_SECTION" != "unknown" ] && echo "$CURRENT_SECTION" | grep -q "image"; then
        # Use ACF field name with incremental numbering
        SECTION_DIR="$BASE_DIR/$CURRENT_SECTION"
        FILENAME_PREFIX=$(echo "$CURRENT_SECTION" | sed 's/-image$//')
        USE_CUSTOM_NAME=true
        debug "Using ACF section: $CURRENT_SECTION, prefix: $FILENAME_PREFIX, index: $INDEX"
      else
        # No ACF structure found, use images directory
        SECTION_DIR="$BASE_DIR/images"
        USE_CUSTOM_NAME=false
        FILENAME_PREFIX="general"
        debug "No ACF section, using images/ with index: $INDEX"
      fi
      
      if [ "$SECTION_DIR" != "$PREV_DIR" ]; then
        print "Downloading to $(basename "$SECTION_DIR")/:"
        PREV_DIR="$SECTION_DIR"
      fi
      
      if [ "$USE_CUSTOM_NAME" = true ]; then
        download_image_custom "$IMAGE_URL" "$SECTION_DIR" "$FILENAME_PREFIX" "$INDEX" "$ALT_TEXT"
      else
        download_image "$IMAGE_URL" "$SECTION_DIR" "$INDEX" "$ALT_TEXT"
      fi
    fi
  fi
done < "$TEMP_FILE"

rm "$TEMP_FILE"

# Final cleanup of any remaining AVIF files
AVIF_FILES=$(find "$BASE_DIR" -type f -name "*.avif" 2>/dev/null)
if [ -n "$AVIF_FILES" ]; then
  print "Converting remaining AVIF files..."
  find "$BASE_DIR" -name "*.avif" | while read -r avif_file; do
    convert_avif_if_needed "$avif_file"
  done
fi

# Optimize images with ImageOptim CLI if available
if command -v imageoptim > /dev/null 2>&1; then
  print ""
  print "Optimizing images with ImageOptim (entire output directory)..."
  if imageoptim "$OUTPUT_BASE" 2>/dev/null; then
    print "  ✓ Image optimization complete"
  else
    print "  ⚠ ImageOptim encountered issues (images still downloaded successfully)"
  fi
else
  debug "ImageOptim CLI not installed. Install with: brew install imageoptim-cli"
fi

# Open the output directory if on macOS
if command -v open > /dev/null 2>&1; then
  open "$BASE_DIR"
fi

# Archive processed input
PROCESSED_COPY="$PROCESSED_DIR/$(basename "$HTML_FILE")"
cp -f "$HTML_FILE" "$PROCESSED_COPY"
print ""
print "Processed input copied to $PROCESSED_COPY"

if [ -t 0 ]; then
  while true; do
    read -r -p "Keep original input file? (y/n): " KEEP_INPUT
    case "$KEEP_INPUT" in
      [Yy]*)
        print "Original input retained."
        break
        ;;
      [Nn]*)
        rm -f "$HTML_FILE"
        print "Original input removed. Archived copy remains in $PROCESSED_DIR"
        break
        ;;
      *)
        print "Please answer y or n."
        ;;
    esac
  done
else
  print "Non-interactive session detected; original input retained."
fi

print "All processed inputs are archived in $PROCESSED_DIR"

# Final summary
print ""
print "✓ Processing complete!"
print "  Files downloaded: $SUCCESS_COUNT"
print "  Failures: $FAIL_COUNT"
print "  Output directory: $BASE_DIR"
print "  Log file: $LOG_FILE"

if [ "$DEBUG" = "1" ]; then
  print "  (Debug mode was enabled)"
fi
