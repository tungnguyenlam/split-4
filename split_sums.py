import os

def split_sha256sums(input_file="SHA256SUMS.txt"):
    """
    Splits SHA256SUMS.txt into 4 machine-specific files.
    Fixes the single-space bug by ensuring double-space between hash and filename.
    """
    if not os.path.exists(input_file):
        print(f"Error: {input_file} not found.")
        return

    with open(input_file, 'r') as f:
        lines = f.readlines()

    # First 3 lines go to macbook
    macbook_lines = [l.replace(' ', '  ', 1) for l in lines[:3]]
    school_lines = []
    macmini_lines = []
    windows_lines = []

    for line in lines[3:]:
        # Ensure double space for shasum compatibility
        line_fixed = line.replace(' ', '  ', 1)
        
        if "files/p10/" in line:
            macbook_lines.append(line_fixed)
        elif any(f"files/p{i}/" in line for i in range(11, 14)):
            school_lines.append(line_fixed)
        elif any(f"files/p{i}/" in line for i in range(14, 17)):
            macmini_lines.append(line_fixed)
        elif any(f"files/p{i}/" in line for i in range(17, 20)):
            windows_lines.append(line_fixed)

    # Write files
    targets = {
        "SHA256SUMS_macbook.txt": macbook_lines,
        "SHA256SUMS_school.txt": school_lines,
        "SHA256SUMS_macmini.txt": macmini_lines,
        "SHA256SUMS_windows.txt": windows_lines
    }

    for filename, content in targets.items():
        with open(filename, "w") as f:
            f.writelines(content)
        print(f"Created {filename} ({len(content)} lines)")

if __name__ == "__main__":
    split_sha256sums()
