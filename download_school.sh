#!/usr/bin/env bash
set -euo pipefail

# School Server — downloads p11, p12, p13 (113,589 files)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="https://physionet.org/files/mimic-cxr-jpg/2.1.0"
SHA256_FILE="$SCRIPT_DIR/SHA256SUMS_school.txt"
ARIA2_INPUT="$SCRIPT_DIR/aria2_input_school.txt"
DOWNLOAD_DIR="${1:-.}"
PHYSIONET_USER="fillin"
PHYSIONET_PASS='fillin'
USER_AGENT="Wget/1.21.4"

if [ ! -f "$SHA256_FILE" ]; then
    echo "ERROR: $SHA256_FILE not found."
    exit 1
fi

mkdir -p "$DOWNLOAD_DIR"

echo "Generating aria2c input file from $(basename "$SHA256_FILE") ..."
awk -v base="$BASE_URL" '{
    path = $2
    dir = path; sub(/\/[^\/]*$/, "", dir)
    print base "/" path
    print "  dir=" dir
}' "$SHA256_FILE" > "$ARIA2_INPUT"

download_with_aria2c() {
    (
        cd "$DOWNLOAD_DIR"
        aria2c -i "$ARIA2_INPUT" \
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
    echo "aria2c not found; falling back to curl. This will be much slower."
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
                        [ "$status" -eq 33 ] || exit "$status"
                    fi
                    ;;
            esac
        done < "$ARIA2_INPUT"
    )
}

echo "Starting download into $DOWNLOAD_DIR ..."
if command -v aria2c >/dev/null 2>&1; then
    download_with_aria2c
elif command -v curl >/dev/null 2>&1; then
    download_with_curl
else
    echo "ERROR: Neither aria2c nor curl is installed."
    exit 1
fi

echo ""
echo "Download complete. Verifying file counts ..."
EXPECTED=$(wc -l < "$SHA256_FILE" | tr -d ' ')
ACTUAL=0
for p in p11 p12 p13; do
    COUNT=$(find "$DOWNLOAD_DIR/files/$p" -name '*.jpg' 2>/dev/null | wc -l | tr -d ' ')
    echo "  $p: $COUNT files"
    ACTUAL=$((ACTUAL + COUNT))
done
echo "Expected: $EXPECTED files | Found: $ACTUAL files"

if [ "$EXPECTED" -eq "$ACTUAL" ]; then
    echo "File count matches."
else
    echo "WARNING: File count mismatch! Run verification."
fi
