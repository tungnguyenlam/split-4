import os
from datetime import datetime

def split_sha256sums(input_file="SHA256SUMS.txt"):
    """
    Splits SHA256SUMS.txt into 11 files (meta + p10-p19).
    Fixes the single-space bug by ensuring double-space between hash and filename.
    Logs execution to split_sums.log.
    """
    log_file = "split_sums.log"
    start_time = datetime.now()
    
    def log(message):
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        msg = f"[{timestamp}] {message}"
        print(msg)
        with open(log_file, "a") as f:
            f.write(msg + "\n")

    log(f"Starting split of {input_file} ...")

    if not os.path.exists(input_file):
        log(f"ERROR: {input_file} not found.")
        return

    try:
        with open(input_file, 'r') as f:
            lines = f.readlines()
    except Exception as e:
        log(f"ERROR reading {input_file}: {e}")
        return

    # 1. Meta file (first 3 lines)
    meta_lines = [l.replace(' ', '  ', 1) for l in lines[:3]]
    
    # 2. Patient folder files (p10-p19)
    folder_map = {f"p{i}": [] for i in range(10, 20)}
    
    for line in lines[3:]:
        # Ensure double space for shasum compatibility
        line_fixed = line.replace(' ', '  ', 1)
        
        # Identify folder (e.g., from files/p10/...)
        parts = line.split(' ')
        if len(parts) < 2: continue
        filename = parts[-1].strip()
        
        # Filename format: files/pXX/pXXXXXXXX/...
        if filename.startswith("files/p"):
            folder_key = filename.split('/')[1] # p10, p11, etc.
            if folder_key in folder_map:
                folder_map[folder_key].append(line_fixed)

    # Write files
    targets = { "SHA256SUMS_meta.txt": meta_lines }
    for folder, folder_lines in folder_map.items():
        targets[f"SHA256SUMS_{folder}.txt"] = folder_lines

    for filename, content in targets.items():
        try:
            with open(filename, "w") as f:
                f.writelines(content)
            log(f"Created {filename} ({len(content)} lines)")
        except Exception as e:
            log(f"ERROR writing {filename}: {e}")

    end_time = datetime.now()
    log(f"Split complete. Total time: {end_time - start_time}")

if __name__ == "__main__":
    split_sha256sums()
