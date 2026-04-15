# Agent Handoff — MIMIC-CXR-JPG Distributed Download

> This document contains critical context for any AI agent assisting with
> combining or troubleshooting the MIMIC-CXR-JPG distributed download.
> Read this fully before taking any action.

## Project Context

We are downloading **MIMIC-CXR-JPG v2.1.0** from PhysioNet across 4 machines
to parallelize a slow download. The dataset is ~4.7GB of chest X-ray JPGs
(377,110 files) organized into 10 top-level patient folders (`p10`–`p19`).

- **PhysioNet URL**: `https://physionet.org/files/mimic-cxr-jpg/2.1.0/`
- **Credentials**: username `tungnl` (PhysioNet account)
- **Rate limiting**: PhysioNet throttles per IP, NOT per account

## Machine Assignment (Folder-Based Split)

Each machine downloads specific patient folders — **no overlap**.

| Machine | Script | Folders | Files | Network | Notes |
|---|---|---|---|---|---|
| School Server | `download_school.sh` | p11, p12, p13 | 113,589 | School LAN | Separate IP |
| MacBook Air | `download_macbook.sh` | p10 | 36,681 | Home WiFi | Low disk, smallest portion |
| Mac Mini | `download_macmini.sh` | p14, p15, p16 | 113,546 | Home WiFi |  |
| Windows | `download_windows.sh` | p17, p18, p19 | 113,294 | Other network | Runs via Git Bash or WSL |

## Critical Technical Details

### 1. SHA256SUMS.txt Format Bug
PhysioNet's `SHA256SUMS.txt` uses **single-space** between hash and filename:
```
a688ad339cb18a877f53dea5d900186a... IMAGE_FILENAMES
```
But `sha256sum -c` (Linux) and `shasum -a 256 -c` (macOS) both require **double-space**.
**Fix**: pipe through `sed 's/ /  /'` before verification:
```bash
sed 's/ /  /' SHA256SUMS.txt | shasum -a 256 -c -
```
This is already fixed in `combine.sh`.

### 2. aria2c Input File Format
The download scripts generate aria2c input files with the `dir` directive to preserve
directory structure:
```
https://physionet.org/files/mimic-cxr-jpg/2.1.0/files/p10/p10000032/s50414267/02aa804e-....jpg
  dir=files/p10/p10000032/s50414267
```
The `dir` value is relative to CWD when aria2c runs. Each script `cd`s into the download dir first.

### 3. Download Directory Structure
Each machine produces this structure in its download directory:
```
<download_dir>/
└── files/
    └── pXX/              ← only the assigned p-folders
        └── pXXXXXXXX/    ← patient ID
            └── sXXXXXXXX/ ← study ID
                └── <hash>.jpg
```

### 4. macOS vs Linux Differences
- macOS: `shasum -a 256` (no `sha256sum`)
- macOS: `stat -f%z <file>` for file size (Linux: `stat --format=%s`)
- macOS: no `cat -A` (use `xxd` to inspect bytes)
- `combine.sh` handles this with auto-detection

### 5. No brew/aria2c on Some Machines
The test machine didn't have `brew` or `aria2c`. If aria2c is unavailable,
`curl` works as a fallback:
```bash
curl -f -u "tungnl:PASSWORD" -A "Wget/1.21.4" -o "$DIR/$FILENAME" "$URL"
```
But aria2c is strongly preferred for 377K files (concurrent downloads).

## Combining the Dataset

### Target Machine
The final combined dataset should live on **ict14** (school infrastructure).

### How to Combine
The `combine.sh` script handles everything:
```bash
./combine.sh <target_dir> <source_1> <source_2> <source_3> <source_4>
```

Sources can be:
- **Local paths**: `/mnt/usb1/mimic-cxr-jpg` (USB drives)
- **Remote SSH**: `user@192.168.1.50:/home/user/mimic-cxr-jpg`

### What combine.sh Does (in order)
1. **Merges** all `files/` directories via `rsync` (local or SSH)
2. **Downloads 8 metadata files** (CSVs, LICENSE, README, IMAGE_FILENAMES) via aria2c
3. **Counts files** per folder and reports mismatches
4. **Optional SHA256 verification** (converts single→double space on the fly)

### Expected Final Structure
```
<target>/
├── files/
│   ├── p10/    ← 36,681 JPGs  (from MacBook Air)
│   ├── p11/    ← 38,535 JPGs  (from School Server)
│   ├── p12/    ← 37,197 JPGs  (from School Server)
│   ├── p13/    ← 37,857 JPGs  (from School Server)
│   ├── p14/    ← 37,468 JPGs  (from Mac Mini)
│   ├── p15/    ← 38,980 JPGs  (from Mac Mini)
│   ├── p16/    ← 37,098 JPGs  (from Mac Mini)
│   ├── p17/    ← 37,688 JPGs  (from Windows)
│   ├── p18/    ← 37,958 JPGs  (from Windows)
│   └── p19/    ← 37,648 JPGs  (from Windows)
├── IMAGE_FILENAMES
├── LICENSE.txt
├── README
├── mimic-cxr-2.0.0-chexpert.csv.gz
├── mimic-cxr-2.0.0-metadata.csv.gz
├── mimic-cxr-2.0.0-negbio.csv.gz
├── mimic-cxr-2.0.0-split.csv.gz
└── mimic-cxr-2.1.0-test-set-labeled.csv
```
**Total: 377,110 JPGs + 8 metadata files**

### Handling Missing Files After Combine
If the file count doesn't match, `combine.sh` generates `missing_files.txt`.
Re-download missing files:
```bash
BASE_URL="https://physionet.org/files/mimic-cxr-jpg/2.1.0"
awk -v base="$BASE_URL" '{
    dir = $0; sub(/\/[^\/]*$/, "", dir)
    print base "/" $0
    print "  dir=" dir
}' missing_files.txt > aria2_redownload.txt

aria2c -i aria2_redownload.txt \
    --http-user='tungnl' --http-passwd='<PASSWORD>' \
    --user-agent="Wget/1.21.4" -j 16 -c
```

## Transfer Methods (Getting Data to ict14)

| Method | When to Use | Command |
|---|---|---|
| rsync+SSH | Machine is on same network or has SSH access | `rsync -avz user@host:/path/files/ /target/files/` |
| USB drive | No network between machines | Copy `files/` dir, use `combine.sh` with mount path |
| tar+scp | Slow link, benefit from compression | `tar czf files_pXX.tar.gz files/ && scp ...` |

## Sandbox Test Results (Verified 2026-04-15)

- Downloaded 1 file per folder (10 total) from PhysioNet ✅
- Merged all 4 simulated machine outputs via rsync ✅
- SHA256 verification passed for all 10 files ✅
- Identified and fixed SHA format bug (single→double space) ✅

## File Inventory

| File | Purpose |
|---|---|
| `SHA256SUMS.txt` | 377,118 lines, checksums for all files (from PhysioNet) |
| `SHA256SUMS_macbook.txt` | 36,681 lines, checksums for p10 (MacBook Air) |
| `SHA256SUMS_school.txt` | 113,589 lines, checksums for p11, p12, p13 (School Server) |
| `SHA256SUMS_macmini.txt` | 113,546 lines, checksums for p14, p15, p16 (Mac Mini) |
| `SHA256SUMS_windows.txt` | 113,294 lines, checksums for p17, p18, p19 (Windows) |
| `download_school.sh` | Download script for school server (p11, p12, p13) |
| `download_macbook.sh` | Download script for MacBook Air (p10 only) |
| `download_macmini.sh` | Download script for Mac Mini (p14, p15, p16) |
| `download_windows.sh` | Download script for Windows machine (p17, p18, p19) |
| `combine.sh` | Merge + verify script for ict14 |
| `guide.txt` | Original download tips from nanachi |
| `README.md` | Full user-facing documentation |
| `agents.md` | This file — agent handoff context |
| `.gitignore` | Excludes downloaded data and generated files |
