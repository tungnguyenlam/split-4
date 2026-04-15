#!/usr/bin/env bash
set -euo pipefail

# Windows (Git Bash / WSL) — downloads p17, p18, p19 (113,294 files)

BASE_URL="https://physionet.org/files/mimic-cxr-jpg/2.1.0"
SHA256_FILE="SHA256SUMS_windows.txt"
ARIA2_INPUT="aria2_input_windows.txt"
DOWNLOAD_DIR="${1:-.}"

if [ ! -f "$SHA256_FILE" ]; then
    echo "ERROR: $SHA256_FILE not found. Place it in the current directory."
    exit 1
fi

echo "Generating aria2c input file from $SHA256_FILE ..."
awk -v base="$BASE_URL" '{
    path = $2
    dir = path; sub(/\/[^\/]*$/, "", dir)
    print base "/" path
    print "  dir=" dir
}' "$SHA256_FILE" > "$ARIA2_INPUT"

echo "Starting download into $DOWNLOAD_DIR ..."
cd "$DOWNLOAD_DIR"

aria2c -i "$OLDPWD/$ARIA2_INPUT" \
    --http-user='tungnl' \
    --http-passwd='PASSWORD' \
    --user-agent="Wget/1.21.4" \
    --min-split-size=1M \
    -j 16 -x 1 -s 1 \
    --connect-timeout=60 \
    --max-connection-per-server=16 \
    -c

echo ""
echo "Download complete. Verifying file counts ..."
cd "$OLDPWD"

EXPECTED=$(wc -l < "$SHA256_FILE" | tr -d ' ')
ACTUAL=0
for p in p17 p18 p19; do
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
