#!/usr/bin/env bash
set -euo pipefail

# Generic Download Script for MIMIC-CXR-JPG
# Retains logic from original machine-specific scripts but adds parameter support.

# Default values
PHYSIONET_USER=""
PHYSIONET_PASS=""
SHA256_FILE=""
DOWNLOAD_DIR="."
USER_AGENT="Wget/1.21.4"
BASE_URL="https://physionet.org/files/mimic-cxr-jpg/2.1.0"

usage() {
    echo "Usage: $0 --user-name <name> --password <pass> --file <checksum_file> [--dir <download_dir>]"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --user-name) PHYSIONET_USER="$2"; shift 2 ;;
        --password)  PHYSIONET_PASS="$2"; shift 2 ;;
        --file)      SHA256_FILE="$2"; shift 2 ;;
        --dir)       DOWNLOAD_DIR="$2"; shift 2 ;;
        *) usage ;;
    esac
done

if [[ -z "$PHYSIONET_USER" || -z "$PHYSIONET_PASS" || -z "$SHA256_FILE" ]]; then
    usage
fi

if [[ ! -f "$SHA256_FILE" ]]; then
    echo "ERROR: $SHA256_FILE not found."
    exit 1
fi

# Execution Tracking Setup
LOG_FILE="download_$(basename "$SHA256_FILE" .txt).log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

log() {
    local msg="[$(date "+%Y-%m-%d %H:%M:%S")] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

log "Execution started with file: $SHA256_FILE"
log "Target directory: $DOWNLOAD_DIR"

ARIA2_INPUT="aria2_input_$(basename "$SHA256_FILE" .txt).txt"
mkdir -p "$DOWNLOAD_DIR"

log "Generating aria2c input file: $ARIA2_INPUT ..."
awk -v base="$BASE_URL" '{
    path = $2
    dir = path; sub(/\/[^\/]*$/, "", dir)
    print base "/" path
    print "  dir=" dir
}' "$SHA256_FILE" > "$ARIA2_INPUT"
ARIA2_INPUT_ABS="$(cd "$(dirname "$ARIA2_INPUT")" && pwd)/$(basename "$ARIA2_INPUT")"

download_with_aria2c() {
    log "Starting download with aria2c..."
    (
        cd "$DOWNLOAD_DIR"
        aria2c -i "$ARIA2_INPUT_ABS" \
            --http-user="$PHYSIONET_USER" \
            --http-passwd="$PHYSIONET_PASS" \
            --user-agent="$USER_AGENT" \
            --min-split-size=1M \
            -j 16 -x 1 -s 1 \
            --connect-timeout=60 \
            --max-connection-per-server=16 \
            -c
    )
}

download_with_curl() {
    log "aria2c not found; falling back to curl. This will be much slower."
    (
        cd "$DOWNLOAD_DIR"
        local current_url=""
        local dir=""
        local file_name=""

        while IFS= read -r line; do
            case "$line" in
                http*://*)
                    current_url="$line"
                    ;;
                "  dir="*)
                    dir="${line#  dir=}"
                    file_name="${current_url##*/}"
                    mkdir -p "$dir"
                    if curl -f \
                        -u "$PHYSIONET_USER:$PHYSIONET_PASS" \
                        -A "$USER_AGENT" \
                        --retry 5 \
                        --retry-delay 2 \
                        -C - \
                        -o "$dir/$file_name" \
                        "$current_url"; then
                        :
                    else
                        status=$?
                        [ "$status" -eq 33 ] || { log "Curl error: $status"; exit "$status"; }
                    fi
                    ;;
            esac
        done < "$ARIA2_INPUT_ABS"
    )
}

if command -v aria2c >/dev/null 2>&1; then
    download_with_aria2c
elif command -v curl >/dev/null 2>&1; then
    download_with_curl
else
    log "ERROR: Neither aria2c nor curl is installed."
    exit 1
fi

# Verification logic
log "Download attempt finished. Verifying file counts ..."
EXPECTED=$(wc -l < "$SHA256_FILE" | tr -d ' ')

# Detect folder suffix for verification (e.g. SHA256SUMS_p10.txt -> files/p10)
FOLDER_SUFFIX=$(basename "$SHA256_FILE" .txt | sed 's/SHA256SUMS_//')
if [[ "$FOLDER_SUFFIX" == "meta" ]]; then
    ACTUAL=$(find "$DOWNLOAD_DIR" -maxdepth 1 -type f | grep -E "LICENSE.txt|README|IMAGE_FILENAMES" | wc -l | tr -d ' ')
else
    ACTUAL=$(find "$DOWNLOAD_DIR/files/$FOLDER_SUFFIX" -name '*.jpg' 2>/dev/null | wc -l | tr -d ' ')
fi

log "Summary: Expected $EXPECTED | Found $ACTUAL"

if [ "$EXPECTED" -eq "$ACTUAL" ]; then
    log "Status: SUCCESS - File count matches."
else
    log "Status: WARNING - File count mismatch!"
fi
